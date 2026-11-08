@tool
extends Node2D
## 沿路径移动的金色光点：
##  - 直径 = 玩家高度的一半（默认 182）
##  - 路径用子节点 Path 的 Curve2D 在编辑器里画
##  - 可循环 / 单程，带轻微呼吸闪烁和上下浮动

const PLAYER_HEIGHT := 364.0   # 狐狸精灵高度

@export var diameter := PLAYER_HEIGHT:
	set(v):
		diameter = maxf(v, 40.0)
		_apply_size()
@export var core_ratio := 0.32:      # 中心亮核占直径比例
	set(v):
		core_ratio = clampf(v, 0.05, 1.0)
		_apply_size()
@export var speed := 4000.0           # 路径速度 px/s
@export var manual := false           # 由外部（光点引导）控制位置，不自己沿路径走
## 路线预设（路径曲线为空时按它生成；空 = 用编辑器里画的 Curve2D）
@export_enum("custom", "arc", "zigzag", "wave", "rise", "loop", "circle") var route := "custom"
@export var snap_ground := false        # 按地面自动定高（各关地形高度不同）
@export var ground_offset := 700.0      # 离地高度
@export var route_span := 2600.0       # 路线横向跨度
@export var route_height := 700.0      # 路线高度
@export var loop := false            # 到头后回到起点
@export var bob_height := 8.0        # 上下轻微浮动
@export var pulse := true            # 呼吸闪烁

var _path: Path2D
var _glow: Sprite2D
var _core: Sprite2D
var _dist := 0.0
var _time := 0.0

func _ready() -> void:
	_path = get_node_or_null("Path") as Path2D
	_glow = get_node_or_null("Glow") as Sprite2D
	_core = get_node_or_null("Core") as Sprite2D
	_ensure_curve()
	_apply_size()
	if snap_ground:
		_snap_to_ground()

## 从上方往下打射线，把光点放到地面以上 ground_offset（等一帧让 TileMap 碰撞就绪）
func _snap_to_ground() -> void:
	await get_tree().process_frame
	var px := global_position.x
	var level := get_parent()
	if level != null:
		var player := level.get_node_or_null("Player")
		if player != null:
			px = player.global_position.x + 600.0      # 放在玩家出生点附近
	var q := PhysicsRayQueryParameters2D.create(Vector2(px, -30000.0), Vector2(px, 30000.0), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	global_position = Vector2(px, float(hit["position"].y) - ground_offset)

func _ensure_curve() -> void:
	if _path == null:
		return
	if _path.curve == null:
		_path.curve = Curve2D.new()
	var c := _path.curve
	if route != "custom":
		c.clear_points()
		_build_route(c)
		return
	if c.point_count >= 2:
		return
	if route == "custom":
		# 默认给一条平滑的小弧线，方便直接在编辑器里接着改
		c.add_point(Vector2(0, 0), Vector2(160, 0), Vector2(-160, 0))
		c.add_point(Vector2(520, -180), Vector2(200, 0), Vector2(-200, 0))
		c.add_point(Vector2(1040, 0), Vector2(200, 0), Vector2(-160, 0))
		return
	_build_route(c)

## 每条关卡用不同形状的路线
func _build_route(c: Curve2D) -> void:
	var s := route_span
	var h := route_height
	match route:
		"arc":
			c.add_point(Vector2(0, 0), Vector2(s * 0.4, 0), Vector2(-s * 0.4, 0))
			c.add_point(Vector2(s * 0.5, -h), Vector2(s * 0.4, 0), Vector2(-s * 0.4, 0))
			c.add_point(Vector2(s, 0), Vector2(s * 0.4, 0), Vector2(-s * 0.4, 0))
		"zigzag":
			c.add_point(Vector2(0, 0))
			c.add_point(Vector2(s * 0.25, -h))
			c.add_point(Vector2(s * 0.5, 0))
			c.add_point(Vector2(s * 0.75, -h))
			c.add_point(Vector2(s, 0))
		"wave":
			var n := 6
			for i in n + 1:
				var x := s * float(i) / float(n)
				var y := -h * 0.5 + sin(float(i) / float(n) * TAU) * h * 0.5
				c.add_point(Vector2(x, y))
		"rise":
			c.add_point(Vector2(0, 0), Vector2(0, -h * 0.6), Vector2(0, h * 0.6))
			c.add_point(Vector2(s * 0.35, -h * 0.8), Vector2(s * 0.2, 0), Vector2(-s * 0.2, 0))
			c.add_point(Vector2(s, -h * 1.6), Vector2(s * 0.3, 0), Vector2(-s * 0.3, 0))
		"loop":
			c.add_point(Vector2(0, 0), Vector2(s * 0.3, 0), Vector2(-s * 0.3, 0))
			c.add_point(Vector2(s * 0.45, -h), Vector2(s * 0.3, h * 0.6), Vector2(-s * 0.1, -h * 0.6))
			c.add_point(Vector2(s * 0.75, h * 0.35), Vector2(s * 0.3, -h * 0.4), Vector2(-s * 0.2, h * 0.2))
			c.add_point(Vector2(s, -h * 0.2), Vector2(s * 0.2, 0), Vector2(-s * 0.3, 0))
		"circle":
			var r := minf(s, h) * 0.5
			for i in 8:
				var a := TAU * float(i) / 8.0
				c.add_point(Vector2(cos(a) * r, sin(a) * r))
			c.add_point(Vector2(r, 0))

func _apply_size() -> void:
	if _glow == null or _glow.texture == null:
		return
	var w := float(_glow.texture.get_width())
	var s := diameter / w
	_glow.scale = Vector2(s, s)
	if _core != null and _core.texture != null:
		var cs := diameter * core_ratio / float(_core.texture.get_width())
		_core.scale = Vector2(cs, cs)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_move(delta)

## 主菜单还开着（未点开始游戏 / 已回菜单）就不动
func _menu_open() -> bool:
	var game := get_tree().get_first_node_in_group("game_root")
	if game == null:
		return false
	var menu := game.get_node_or_null("UI/Menu")
	return menu != null and menu.visible

func _move(delta: float) -> void:
	if _menu_open():
		return
	if _path == null or _path.curve == null:
		return
	var curve := _path.curve
	var length := curve.get_baked_length()
	if length <= 0.1:
		return
	_time += delta
	if manual:
		# 位置交给外面的控制器，这里只保留呼吸闪烁
		if pulse and _glow != null:
			_glow.modulate.a = 0.85 + 0.15 * sin(_time * 3.1)
		return
	_dist += speed * delta
	_dist = fmod(_dist, length) if loop else minf(_dist, length)
	var local := curve.sample_baked(_dist, true)
	var pos := _path.to_global(local)
	if bob_height > 0.0:
		pos.y += sin(_time * 2.2) * bob_height
	# 只移动光晕/亮核，根节点本身不动（否则路径跟着走会越跑越远）
	if _glow != null:
		_glow.global_position = pos
	if _core != null:
		_core.global_position = pos
	if pulse:
		var k := 0.92 + 0.08 * sin(_time * 3.1)
		if _glow != null:
			_glow.modulate.a = 0.85 + 0.15 * sin(_time * 3.1)
			_glow.scale = Vector2.ONE * (diameter / float(_glow.texture.get_width())) * k
