@tool
extends ParallaxBackground
## 视差背景：按元素类别分成多层（越远的层 motion_scale.x 越小）。
##
## 竖直方向：
##  1) 静态构图：bottom_y 直接指定"背景底边贴在哪一行屏幕像素"，各层再按
##     nearest_raise / far_raise 做近低远高的斜度，y_offsets 可单层微调
##  2) 跳跃/下落：相机竖直移动时，背景各层跟着上下走，越远幅度越大（near_rise / far_rise）

const BASE_SCALE := 0.8318

@export_group("竖直位置")
## 背景底边所在的屏幕 y（720 = 摄像机底部）
@export var bottom_y := 719.0:
	set(v):
		bottom_y = v
		_refresh()

## 最近一层相对最远层的额外上移像素（形成近低远高的斜度）
@export var raise_spread := 200.0:
	set(v):
		raise_spread = v
		_refresh()

## 按层名再单独微调，例如 {"L03_中天": -20.0}
@export var y_offsets: Dictionary = {}:
	set(v):
		y_offsets = v
		_refresh()

@export_group("缩放")
## 所有层 Frame 的缩放倍率（1.0 对应基准 0.8318）
@export var layer_scale := 1.0:
	set(v):
		layer_scale = maxf(v, 0.05)
		_refresh()

@export_group("跳跃 / 下落")
## 最近层：相机竖直移动 1 像素时，这一层跟着上下移动的像素
@export var near_rise := 0.0005:
	set(v):
		near_rise = v
		_refresh()

## 最远层：相机竖直移动 1 像素时，这一层跟着上下移动的像素
@export var far_rise := 0.04:
	set(v):
		far_rise = v
		_refresh()

## 从基准往下落时，整块背景跟随下移的速度（不分层，所有层同幅度）。
## 单位：相机下落 1 像素 → 背景下移 fall_speed 像素（0.1 相当于与玩家同速，越小越慢）。
@export_range(0.0, 0.5, 0.005) var fall_speed := 0.05:
	set(v):
		fall_speed = maxf(v, 0.0)
		_refresh()

@export_group("上下浮动范围")
## 浮动跟随的平滑时间（秒）：越大越柔
@export var smooth_time := 0.20:
	set(v):
		smooth_time = maxf(v, 0.01)

## 预测落地的最大向下探测距离
@export var predict_distance := 8000.0:
	set(v):
		predict_distance = maxf(v, 100.0)

## 探测不到地面时，按这个距离预测（避免久坑一直浮）
@export var predict_fallback := 1200.0:
	set(v):
		predict_fallback = maxf(v, 0.0)

## 相对静止位置最多往上浮多少像素（负数，例如 -600 表示最多上移 600）
@export var float_up_limit := -240.0:
	set(v):
		float_up_limit = minf(v, 0.0)
## 相对静止位置最多往下沉多少像素
@export var float_down_limit := 240.0:
	set(v):
		float_down_limit = maxf(v, 0.0)

var _frames: Array[Node2D] = []
var _static_y: Array[float] = []
var _rises: Array[float] = []
var _ref_cam_y := NAN     # 平滑后的"狐狸落地点对应的相机高度"
var _cur_off: Array[float] = []   # 平滑后的实际偏移
var _tex_bottom := {}   # 贴图 id -> 可见底边相对贴图中心的偏移（贴图像素）

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	# 属性 setter 可能在脚本成员初始化之前触发（编辑器加载 / 场景实例化），
	# 这时 _tex_bottom 还是 null；而子节点也可能还没建好，所以都先兜一层。
	if _tex_bottom == null:
		_tex_bottom = {}
	_frames.clear()
	_static_y.clear()
	_rises.clear()
	_cur_off.clear()
	var layers: Array = []
	for c in get_children():
		if c is ParallaxLayer:
			layers.append(c)
	if layers.is_empty():
		return
	var n := layers.size()
	for i in n:
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)   # 0 = 最远，1 = 最近
		var layer := layers[i] as ParallaxLayer
		var frame := layer.get_node_or_null("Frame") as Node2D
		if frame == null:
			continue
		_frames.append(frame)
		_static_y.append(-raise_spread * (1.0 - t) + float(y_offsets.get(String(layer.name), 0.0)))
		_cur_off.append(0.0)
		_rises.append(lerpf(far_rise, near_rise, t))
		frame.scale = Vector2(BASE_SCALE, BASE_SCALE) * layer_scale
		frame.position.y = _static_y[-1]

	# 量出当前 art 底边，再把所有层整体平移到 bottom_y
	var delta := bottom_y - _art_bottom()
	for i in _frames.size():
		_static_y[i] += delta
		_frames[i].position.y = _static_y[i]

func _art_bottom() -> float:
	var lowest := -INF
	for f in _frames:
		var local_bottom := -INF
		for c in f.get_children():
			if not (c is Sprite2D):
				continue
			var sp := c as Sprite2D
			var b := sp.position.y + _texture_bottom(sp) * sp.scale.y
			if b > local_bottom:
				local_bottom = b
		if local_bottom == -INF:
			continue
		var screen_bottom := f.position.y + local_bottom * f.scale.y
		if screen_bottom > lowest:
			lowest = screen_bottom
	return lowest

## 贴图"可见底边"相对贴图中心的偏移（贴图像素）：按 alpha 阈值找最后一行不透明像素，
## 避免把底部的渐隐透明带算进去。
func _texture_bottom(sp: Sprite2D) -> float:
	var tex := sp.texture
	if tex == null:
		return 0.0
	if _tex_bottom == null:
		_tex_bottom = {}
	var key := tex.get_instance_id()
	if not _tex_bottom.has(key):
		var size := tex.get_size()
		var offset := size.y * 0.5
		var img := tex.get_image()
		if img != null:
			var w := img.get_width()
			var h := img.get_height()
			var found := -1
			var y := h - 1
			while y >= 0 and found < 0:
				var x := 0
				while x < w:
					if img.get_pixel(x, y).a > 0.5:
						found = y
						break
					x += 8
				y -= 1
			if found >= 0:
				offset = float(found) + 1.0 - size.y * 0.5
		_tex_bottom[key] = offset
	return float(_tex_bottom[key])

## 当前被相机跟随的"狐狸"（关卡里的 cameraowner / Player）
func _camera_owner() -> Node2D:
	var parent := get_parent()
	if parent == null:
		return null
	var owner_node = parent.get("cameraowner")
	if owner_node is Node2D and is_instance_valid(owner_node):
		return owner_node
	return parent.get_node_or_null("Player") as Node2D

## 预测狐狸的落地高度（向下打一条射线）
func _predict_land_y(fox: Node2D) -> float:
	var space := get_viewport().world_2d.direct_space_state
	var from := fox.global_position + Vector2(0, 24.0)
	var to := from + Vector2(0, predict_distance)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)   # 地面图层
	query.exclude = [fox]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fox.global_position.y + predict_fallback
	return float(hit.position.y)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _frames.is_empty():
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cam_y := cam.global_position.y
	var fox := _camera_owner()
	# 目标基准：站地上 = 当前相机高度；空中 = 预测落地点的相机高度
	var target_ref := cam_y
	if fox != null:
		var fox_y := fox.global_position.y
		var grounded := fox is CharacterBody2D and (fox as CharacterBody2D).is_on_floor()
		if not grounded:
			var land_y := _predict_land_y(fox)
			target_ref = cam_y + (land_y - fox_y)   # 相机会跟着狐狸落下这么多
	if is_nan(_ref_cam_y):
		_ref_cam_y = target_ref
	# 基准本身也平滑，落地点算偏了也不会跳
	var kref := 1.0 - exp(-_delta / maxf(smooth_time, 0.001))
	_ref_cam_y = lerpf(_ref_cam_y, target_ref, kref)
	var dy := cam_y - _ref_cam_y
	# 每层目标偏移（含上下限），再平滑逼近
	for i in _frames.size():
		var target: float
		if dy > 0.0:
			target = clampf(fall_speed * dy, float_up_limit, float_down_limit)
		else:
			target = clampf(_rises[i] * dy, float_up_limit, float_down_limit)
		if _cur_off.size() <= i:
			_cur_off.append(0.0)
		_cur_off[i] = lerpf(_cur_off[i], target, kref)
		_frames[i].position.y = _static_y[i] + _cur_off[i]
