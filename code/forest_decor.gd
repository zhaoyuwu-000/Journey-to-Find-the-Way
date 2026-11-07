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
const FAR := [
	preload("res://sprite/场景图，neva/场景图/_0010_远景树4.png"),
	preload("res://sprite/场景图，neva/场景图/_0011_远景树3.png"),
	preload("res://sprite/场景图，neva/场景图/_0012_远景树2.png"),
	preload("res://sprite/场景图，neva/场景图/_0013_远景树1.png"),
	preload("res://sprite/场景图，neva/树1.png"),
]

const LAYER_Z := [40, -20, -60]
const LAYER_ALPHA := [1.0, 0.82, 0.6]
const LAYER_TINT := [Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.99, 0.9)]
const LAYER_HEIGHT := [Vector2(300, 680), Vector2(7500, 15000), Vector2(2000, 3600)]
const LAYER_WIDTH_CAP := [800.0, 7500.0, 1700.0]
const LAYER_PERIOD := [1.1, 1.6, 2.6]      # 每层每隔几格长一个（越小越密）
# 中景：高度范围 7500~15000（相当原来的 5 倍）

const BG_COLOR := Color(0.99, 0.96, 0.82)

var _tm: TileMapLayer
var _rng := RandomNumberGenerator.new()
var _bbox_cache := {}

func _ready() -> void:
	_rng.seed = 20261107
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if Engine.is_editor_hint() and _tm != null:
		_tm.changed.connect(_rebuild, CONNECT_DEFERRED)
	_rebuild()

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
			acc[layer] += 1.0 / LAYER_PERIOD[layer]
			if acc[layer] >= 1.0:
				acc[layer] -= 1.0
				_spawn(x, layer, surface[x])

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
	rect.color = BG_COLOR
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

func _spawn(cell_x: int, layer: int, surface_row: int) -> void:
	var pool: Array = [NEAR, MID, FAR][layer]
	var tex: Texture2D = pool[_rng.randi() % pool.size()]
	var bbox: Rect2 = _bbox(tex)
	var h: float = _rng.randf_range(LAYER_HEIGHT[layer].x, LAYER_HEIGHT[layer].y)
	var s: float = h / maxf(bbox.size.y, 1.0)
	s = minf(s, LAYER_WIDTH_CAP[layer] / maxf(bbox.size.x, 1.0))

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.scale = Vector2(s, s)
	# 用可见区域对齐：横向居中、底部刚好压在地面
	sp.offset = Vector2(tex.get_size().x * 0.5 - bbox.get_center().x,
		tex.get_size().y * 0.5 - bbox.end.y)
	sp.flip_h = _rng.randf() < 0.5
	sp.z_index = LAYER_Z[layer]
	sp.modulate = Color(LAYER_TINT[layer].r, LAYER_TINT[layer].g, LAYER_TINT[layer].b, LAYER_ALPHA[layer])
	var jitter := _rng.randf_range(-0.35, 0.35) * TILE
	sp.position = Vector2(float(cell_x) * TILE + TILE * 0.5 + jitter, float(surface_row) * TILE + SURFACE)
	add_child(sp, false, Node.INTERNAL_MODE_FRONT)

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
