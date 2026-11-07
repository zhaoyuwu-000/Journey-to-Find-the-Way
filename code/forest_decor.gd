@tool
extends Node2D
## 装饰分近/中/远三层：
##   DecorTile/Markers 里画三种 tile（0=近景 1=中景 2=远景），每种 tile 在该格随机长一个对应层的素材。
##   中景略淡、远景更淡，最后一层背景用淡黄色铺满。

const TILE := 600.0
const SURFACE := 506.0          # 地面 tile 顶面相对格子顶部的偏移

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

## 每层的 z / 透明度 / 高度范围(px)
const LAYER_Z := [40, -20, -60]
const LAYER_ALPHA := [1.0, 0.82, 0.6]
const LAYER_TINT := [Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.99, 0.9)]
const LAYER_HEIGHT := [Vector2(260, 540), Vector2(800, 1500), Vector2(1800, 3400)]
const LAYER_WIDTH_CAP := [700.0, 1200.0, 1500.0]

const BG_COLOR := Color(0.99, 0.96, 0.82)   # 最后一层背景：淡黄

var _markers: TileMapLayer
var _tm: TileMapLayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20261107
	_markers = get_node_or_null("Markers") as TileMapLayer
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if Engine.is_editor_hint() and _markers != null:
		_markers.changed.connect(_rebuild, CONNECT_DEFERRED)
	_rebuild()

func _rebuild() -> void:
	for c in get_children(true):
		remove_child(c)
	if _markers == null:
		return
	_add_background()
	for cell in _markers.get_used_cells():
		var layer := _markers.get_cell_source_id(cell)
		if layer < 0 or layer > 2:
			continue
		_spawn(cell, layer)

## 淡黄色背景，铺在整个关卡后面
func _add_background() -> void:
	var rect := ColorRect.new()
	rect.color = BG_COLOR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1000
	var center := Vector2.ZERO
	if _tm != null:
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

func _spawn(cell: Vector2i, layer: int) -> void:
	var pool: Array = [NEAR, MID, FAR][layer]
	var tex: Texture2D = pool[_rng.randi() % pool.size()]
	var content := _content_rect(tex)
	var h: float = _rng.randf_range(LAYER_HEIGHT[layer].x, LAYER_HEIGHT[layer].y)
	var s: float = h / maxf(content.size.y, 1.0)
	s = minf(s, LAYER_WIDTH_CAP[layer] / maxf(content.size.x, 1.0))

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = true
	sp.offset = Vector2(0, -content.size.y * 0.5 - content.position.y)
	sp.scale = Vector2(s, s)
	sp.flip_h = _rng.randf() < 0.5
	sp.z_index = LAYER_Z[layer]
	sp.modulate = Color(LAYER_TINT[layer].r, LAYER_TINT[layer].g, LAYER_TINT[layer].b, LAYER_ALPHA[layer])
	var ground := _ground_y(cell)
	var jitter: float = _rng.randf_range(-0.3, 0.3) * TILE
	sp.position = Vector2(float(cell.x) * TILE + TILE * 0.5 + jitter, ground)
	add_child(sp, false, Node.INTERNAL_MODE_FRONT)

## 素材可见区域（去掉透明边），没有就整张
func _content_rect(tex: Texture2D) -> Rect2:
	return Rect2(Vector2.ZERO, tex.get_size())

## 这一列的落地高度（该列最上面的实心 tile 顶面）
func _ground_y(cell: Vector2i) -> float:
	if _tm == null:
		return float(cell.y) * TILE + SURFACE
	for row in range(cell.y - 12, cell.y + 8):
		if _is_solid(Vector2i(cell.x, row)):
			return float(row) * TILE + SURFACE
	return float(cell.y) * TILE + SURFACE

func _is_solid(cell: Vector2i) -> bool:
	if _tm == null or _tm.tile_set == null:
		return false
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
