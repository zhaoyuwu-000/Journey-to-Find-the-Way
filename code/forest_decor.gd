@tool
extends Node2D
## 近/中/远三层装饰：按地面自动、独立、均匀地长，全部贴地。
##   近景：草/前景草，贴地，密
##   中景：树/花，放大、贴地
##   远景：高树，更淡，最后铺淡黄背景

const TILE := 600.0
const SURFACE := 506.0

const NEAR := [
	preload("res://sprite/场景图，neva/场景图/_0001_近景杂草.png"),
	preload("res://sprite/场景图，neva/草1.png"),
	preload("res://sprite/场景图，neva/草2.png"),
	preload("res://sprite/场景图，neva/草3.png"),
	preload("res://sprite/场景图，neva/草4.png"),
	preload("res://sprite/场景图，neva/草5.png"),
	preload("res://sprite/场景图，neva/草6.png"),
	preload("res://sprite/场景图，neva/前景1.png"),
	preload("res://sprite/场景图，neva/前景2.png"),
	preload("res://sprite/场景图，neva/前景3.png"),
	preload("res://sprite/场景图，neva/前景4.png"),
]
const MID := [
	preload("res://sprite/场景图，neva/中树.png"),
	preload("res://sprite/场景图，neva/中树2.png"),
	preload("res://sprite/场景图，neva/场景图/_0003_中景花.png"),
	preload("res://sprite/场景图，neva/远中树2.png"),
]
## 这张统一压到中景最后面
const BACK_TEX := preload("res://sprite/场景图，neva/远中树2.png")

const FAR := [
	preload("res://sprite/场景图，neva/场景图/_0010_远景树4.png"),
	preload("res://sprite/场景图，neva/场景图/_0011_远景树3.png"),
	preload("res://sprite/场景图，neva/场景图/_0012_远景树2.png"),
	preload("res://sprite/场景图，neva/场景图/_0013_远景树1.png"),
	preload("res://sprite/场景图，neva/树1.png"),
]

const LAYER_Z := [40, -20, -60]
const MID_Z := [-48, -36, -24, -12]      # 中景在前后四个深度上均匀分布
const FAR_Z := [-104, -92, -80]          # 远景整体更深
const LAYER_ALPHA := [1.0, 0.82, 0.6]
const LAYER_TINT := [Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.99, 0.9)]
const LAYER_HEIGHT := [Vector2(300, 680), Vector2(1500, 3000), Vector2(2000, 3600)]   # 基准
const LAYER_WIDTH_CAP := [800.0, 1500.0, 1700.0]
const LAYER_PERIOD := [1.1, 1.6, 2.6]      # 每层每隔几格长一个（越小越密）

var _tm: TileMapLayer
# ====== 可编辑参数（Inspector 里改，编辑器里实时预览）======
@export_group("尺寸倍率")
@export var near_scale := 1.0:
	set(v):
		near_scale = v
		_rebuild()
@export var mid_scale := 5.0:
	set(v):
		mid_scale = v
		_rebuild()
@export var far_scale := 5.0:
	set(v):
		far_scale = v
		_rebuild()

@export_group("密度")
@export var near_density := 1.0:
	set(v):
		near_density = maxf(v, 0.05)
		_rebuild()
@export var mid_density := 0.55:
	set(v):
		mid_density = maxf(v, 0.05)
		_rebuild()
@export var far_density := 1.0:
	set(v):
		far_density = maxf(v, 0.05)
		_rebuild()

@export_group("背景")
@export var background_color := Color(0.99, 0.96, 0.82):
	set(v):
		background_color = v
		_rebuild()

var _rng := RandomNumberGenerator.new()
var _sig := 0
var _poll := 0.0

var _bbox_cache := {}

func _ready() -> void:
	_rng.seed = 20261107
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if Engine.is_editor_hint():
		if _tm != null:
			_tm.changed.connect(_on_tm_changed, CONNECT_DEFERRED)
		call_deferred("_rebuild")   # 编辑器里等 tile 数据就绪再生成
		set_process(true)
		return
	set_process(false)
	_rebuild()

## 编辑器里：tilemap 一改就重建（changed 信号 + 轮询兜底）
func _on_tm_changed() -> void:
	_rebuild()
	_sig = _tm_signature()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var sig := _tm_signature()
	if sig != _sig:
		_sig = sig
		_rebuild()

func _tm_signature() -> int:
	if _tm == null:
		return 0
	var h := 17
	for cell in _tm.get_used_cells():
		h = (h * 31 + cell.x * 7 + cell.y * 131 + _tm.get_cell_source_id(cell) * 977) & 0x7fffffff
	return h

func _rebuild() -> void:
	for c in get_children(true):
		remove_child(c)
	if _tm == null or _tm.tile_set == null:
		return
	_add_background()
	var surface := _surface_rows()
	if surface.is_empty():
		return

	var xs := surface.keys()
	xs.sort()
	var acc := [_rng.randf(), _rng.randf(), _rng.randf()]
	var prev_x: int = xs[0] - 2
	for x in xs:
		# 断开的两段地面，重新起相位
		if x - prev_x > 2:
			acc = [_rng.randf(), _rng.randf(), _rng.randf()]
		prev_x = x
		for layer in 3:
			acc[layer] += 1.0 / (LAYER_PERIOD[layer] / _layer_density(layer))
			if acc[layer] >= 1.0:
				acc[layer] -= 1.0
				_spawn(x, layer, surface[x], surface)
	_sig = _tm_signature()

func _layer_scale(layer: int) -> float:
	return [near_scale, mid_scale, far_scale][layer]

func _layer_density(layer: int) -> float:
	return [near_density, mid_density, far_density][layer]

## 每列最上面的实心 tile 行（地面）
func _surface_rows() -> Dictionary:
	var out := {}
	for cell in _tm.get_used_cells():
		if not _is_solid(cell):
			continue
		if not out.has(cell.x) or cell.y < out[cell.x]:
			out[cell.x] = cell.y
	return out

func _add_background() -> void:
	var rect := ColorRect.new()
	rect.color = background_color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1000
	var center := Vector2.ZERO
	var used := _tm.get_used_cells()
	if not used.is_empty():
		var lo := used[0]
		var hi := used[0]
		for c in used:
			lo.x = mini(lo.x, c.x); lo.y = mini(lo.y, c.y)
			hi.x = maxi(hi.x, c.x); hi.y = maxi(hi.y, c.y)
		center = _tm.position + Vector2(float(lo.x + hi.x) * 0.5 * TILE, float(lo.y + hi.y) * 0.5 * TILE)
	rect.position = center - Vector2(60000, 60000)
	rect.size = Vector2(120000, 120000)
	add_child(rect, false, Node.INTERNAL_MODE_FRONT)

func _spawn(cell_x: int, layer: int, surface_row: int, surface: Dictionary) -> void:
	var pool: Array = [NEAR, MID, FAR][layer]
	var tex: Texture2D = pool[_rng.randi() % pool.size()]
	var bbox: Rect2 = _bbox(tex)
	var mul := _layer_scale(layer)
	var h: float = _rng.randf_range(LAYER_HEIGHT[layer].x, LAYER_HEIGHT[layer].y) * mul
	var s: float = h / maxf(bbox.size.y, 1.0)
	s = minf(s, LAYER_WIDTH_CAP[layer] * mul / maxf(bbox.size.x, 1.0))

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.scale = Vector2(s, s)
	# 用可见区域对齐：横向居中、底部刚好压在地面
	sp.offset = Vector2(tex.get_size().x * 0.5 - bbox.get_center().x,
		tex.get_size().y * 0.5 - bbox.end.y)
	sp.flip_h = _rng.randf() < 0.5
	var alpha: float = LAYER_ALPHA[layer]
	if layer == 1:
		if tex == BACK_TEX:
			sp.z_index = MID_Z[0]          # 远中树2 永远在最里面
			alpha = 0.9 - 0.06
		else:
			var k := _rng.randi() % MID_Z.size()
			sp.z_index = MID_Z[k]
			alpha = 0.9 - 0.06 * float(k)      # 越靠后越淡一点
	elif layer == 2:
		sp.z_index = FAR_Z[_rng.randi() % FAR_Z.size()]
	else:
		sp.z_index = LAYER_Z[0]
	sp.modulate = Color(LAYER_TINT[layer].r, LAYER_TINT[layer].g, LAYER_TINT[layer].b, alpha)
	var jitter := _rng.randf_range(-0.35, 0.35) * TILE
	var cx: float = float(cell_x) * TILE + TILE * 0.5 + jitter
	# 悬空检测：按可见宽度看左右两端，落到同一高度的地面才站得住，否则往里收
	var half_w: float = bbox.size.x * s * 0.5          # 素材完整宽度的一半
	var margin: float = TILE                            # 边缘留一格空间
	cx = _pull_inside(cell_x, cx, half_w, margin, surface_row, surface)
	if cx < -1e8:      # 这段地面放不下（宽度 + 左右各一格留白）→ 这个位置不放
		return

	sp.position = Vector2(cx, float(surface_row) * TILE + SURFACE)
	add_child(sp, false, Node.INTERNAL_MODE_FRONT)

## 悬空检测：只在"和锚点同高的连续地面"上放，太靠边就向内收
func _pull_inside(cell_x: int, cx: float, half_w: float, margin: float, surface_row: int, surface: Dictionary) -> float:
	var lo_col := cell_x
	var hi_col := cell_x
	while surface.get(lo_col - 1, -99999) == surface_row:
		lo_col -= 1
	while surface.get(hi_col + 1, -99999) == surface_row:
		hi_col += 1
	var lo := float(lo_col) * TILE + half_w + margin
	var hi := float(hi_col + 1) * TILE - half_w - margin
	if lo > hi:
		return -1e9      # 放不下就跳过，宁可少长也不悬空
	return clampf(cx, lo, hi)

## 素材的可见区域（去透明边），缓存
func _bbox(tex: Texture2D) -> Rect2:
	var key := tex.get_instance_id()
	if _bbox_cache.has(key):
		return _bbox_cache[key]
	var img := tex.get_image()
	var r := Rect2(Vector2.ZERO, tex.get_size())
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			r = Rect2(used)
	_bbox_cache[key] = r
	return r

func _is_solid(cell: Vector2i) -> bool:
	var sid := _tm.get_cell_source_id(cell)
	if sid < 0:
		return false
	var src := _tm.tile_set.get_source(sid) as TileSetAtlasSource
	if src == null:
		return false
	var atlas := _tm.get_cell_atlas_coords(cell)
	if not src.has_tile(atlas):
		return false
	var td := src.get_tile_data(atlas, 0)
	return td != null and td.get_collision_polygons_count(0) > 0
