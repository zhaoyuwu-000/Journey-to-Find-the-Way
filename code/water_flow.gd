@tool
extends Node2D
## 水流：按"每一列里连续的这段水"铺一条满格宽的水流带，UV 自上而下滚动。
## 带子按格重复，所以上下相邻的水 tile 会自然接上；整段水的两端稍微淡出。

const TILE := 600.0
const WATER_LAYER := 1
const SHADER := preload("res://shaders/water_flow.gdshader")
const TEX := preload("res://sprite/水中场景/水流特效.png")

@export var strength := 0.35:
	set(v):
		strength = v
		_rebuild()
@export var speed := 0.45:
	set(v):
		speed = v
		_rebuild()
@export var alpha := 1.0:
	set(v):
		alpha = v
		_rebuild()

var _tm: TileMapLayer

func _ready() -> void:
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if _tm != null and Engine.is_editor_hint():
		_tm.changed.connect(_rebuild, CONNECT_DEFERRED)
	_rebuild()

## 清掉旧带子，按水格重铺
func _rebuild() -> void:
	for c in get_children(true):
		remove_child(c)
	if _tm == null or _tm.tile_set == null:
		return
	var water := _water_cells()
	# 每一列里连续的这段水 → 一条带子
	var by_col := {}
	for cell in water:
		if not by_col.has(cell.x):
			by_col[cell.x] = []
		by_col[cell.x].append(cell.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260203
	for col in by_col:
		var rows: Array = by_col[col]
		rows.sort()
		var start: int = rows[0]
		var prev: int = rows[0]
		for i in range(1, rows.size() + 1):
			var cur: int = rows[i] if i < rows.size() else -99999
			if cur != prev + 1:
				_add_strip(col, start, prev, rng)
				if i < rows.size():
					start = cur
			prev = cur

func _water_cells() -> Array:
	var ts := _tm.tile_set
	var ids := {}
	for idx in ts.get_source_count():
		ids[ts.get_source_id(idx)] = true
	var out := []
	for cell in _tm.get_used_cells():
		var sid := _tm.get_cell_source_id(cell)
		if not ids.has(sid):
			continue
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		var atlas := _tm.get_cell_atlas_coords(cell)
		if not src.has_tile(atlas):
			continue
		var td := src.get_tile_data(atlas, 0)
		if td != null and td.get_collision_polygons_count(WATER_LAYER) > 0:
			out.append(cell)
	return out

## 一条从 row0 到 row1（含）的水流带，铺满整格宽
func _add_strip(col: int, row0: int, row1: int, rng: RandomNumberGenerator) -> void:
	var tiles := float(row1 - row0 + 1)
	var rect := ColorRect.new()
	rect.position = Vector2(_tm.position.x + float(col) * TILE, _tm.position.y + float(row0) * TILE)
	rect.size = Vector2(TILE, tiles * TILE)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("flow_tex", TEX)
	mat.set_shader_parameter("tiles", tiles)
	mat.set_shader_parameter("repeat_scale", 0.5)
	mat.set_shader_parameter("speed", speed)   # 流速统一
	mat.set_shader_parameter("offset", rng.randf())
	mat.set_shader_parameter("strength", strength * alpha)
	rect.material = mat
	add_child(rect, false, Node.INTERNAL_MODE_FRONT)
