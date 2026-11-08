extends Node2D
## 不同颜色的水 tile 之间自动加一条渐变过渡（水平/竖直接缝都会处理）。
## 放在 TileMapLayer 的兄弟节点上，运行时和编辑器里都会重建。

const TILE := 600.0
const WATER_LAYER := 1        # TileSet 的 physics_layer_1 = 水（collision_layer 128）
const COLOR_EPS := 10.0       # 两种水色差超过这个值才做过渡

var _tm: TileMapLayer
var _src_color: Dictionary = {}   # source_id -> Color
var _valid_ids: Dictionary = {}   # tileset 里真实存在的 source_id

func _ready() -> void:
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
	if _tm == null or _tm.tile_set == null:
		return
	_src_color.clear()
	_valid_ids.clear()
	for idx in _tm.tile_set.get_source_count():
		_valid_ids[_tm.tile_set.get_source_id(idx)] = true

	# 1) 收集所有水格及其颜色
	var water := {}
	for cell in _tm.get_used_cells():
		var sid := _tm.get_cell_source_id(cell)
		if not _is_water(sid, _tm.get_cell_atlas_coords(cell)):
			continue
		water[cell] = _color_of(sid, _tm.get_cell_atlas_coords(cell))

	# 2) 右邻 / 下邻颜色不同 → 在接缝处放一条渐变
	for cell in water:
		var col: Color = water[cell]
		var right: Vector2i = cell + Vector2i(1, 0)
		if water.has(right) and _diff(col, water[right]) > COLOR_EPS:
			_add_blend_h(cell, col, water[right])
		var down: Vector2i = cell + Vector2i(0, 1)
		if water.has(down) and _diff(col, water[down]) > COLOR_EPS:
			_add_blend_v(cell, col, water[down])

## 这一格是不是水：tile 在 water 物理层上有碰撞
func _is_water(source_id: int, atlas: Vector2i) -> bool:
	if source_id < 0 or not _valid_ids.has(source_id):
		return false
	var src := _tm.tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return false
	if not src.has_tile(atlas):
		return false
	var td := src.get_tile_data(atlas, 0)
	return td != null and td.get_collision_polygons_count(WATER_LAYER) > 0

## 一个 water 源的平均颜色（水格子图都是单格 600×600，直接平均就行）
func _color_of(source_id: int, _atlas: Vector2i) -> Color:
	if _src_color.has(source_id):
		return _src_color[source_id]
	var src := _tm.tile_set.get_source(source_id) as TileSetAtlasSource
	var col := Color(0.3, 0.55, 0.6)
	if src != null and src.texture != null:
		var img := src.texture.get_image()
		if img != null:
			img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			var sum := Color(0, 0, 0, 0)
			var n := 0
			var step := maxi(w / 32, 1)
			for y in range(0, h, step):
				for x in range(0, w, step):
					var c := img.get_pixel(x, y)
					if c.a > 0.2:
						sum += c
						n += 1
			if n > 0:
				col = Color(sum.r / n, sum.g / n, sum.b / n, 1.0)
	_src_color[source_id] = col
	return col

func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) * 255.0 + absf(a.g - b.g) * 255.0 + absf(a.b - b.b) * 255.0

## 左右相邻两色 → 跨接缝 2 格宽的横向渐变
func _add_blend_h(cell: Vector2i, a: Color, b: Color) -> void:
	var x := _tm.position.x + float(cell.x + 1) * TILE - TILE   # 接缝左边一格
	var y := _tm.position.y + float(cell.y) * TILE
	_add_gradient(Vector2(x, y), Vector2(TILE * 2.0, TILE), a, b, true)

## 上下相邻两色 → 竖向渐变
func _add_blend_v(cell: Vector2i, a: Color, b: Color) -> void:
	var x := _tm.position.x + float(cell.x) * TILE
	var y := _tm.position.y + float(cell.y + 1) * TILE - TILE
	_add_gradient(Vector2(x, y), Vector2(TILE, TILE * 2.0), a, b, false)

func _add_gradient(top_left: Vector2, size: Vector2, a: Color, b: Color, horizontal: bool) -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(a.r, a.g, a.b, 0.0), Color(a.r, a.g, a.b, 0.85),
		Color((a.r + b.r) * 0.5, (a.g + b.g) * 0.5, (a.b + b.b) * 0.5, 0.9),
		Color(b.r, b.g, b.b, 0.85), Color(b.r, b.g, b.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 64
	tex.fill_from = Vector2(0.0, 0.5) if horizontal else Vector2(0.5, 0.0)
	tex.fill_to = Vector2(1.0, 0.5) if horizontal else Vector2(0.5, 1.0)

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	sp.position = top_left
	sp.scale = Vector2(size.x / float(tex.width), size.y / float(tex.height))
	add_child(sp, false, Node.INTERNAL_MODE_FRONT)
