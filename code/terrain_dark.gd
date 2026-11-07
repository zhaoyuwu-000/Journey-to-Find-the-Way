@tool
extends Node2D
## 地面 tile 向内逐渐变黑：按"离空气有多远"算深度，生成一张低分辨率黑色遮罩再放大，
## 线性过滤后就是平滑的由外向内变黑。

const TILE := 600.0
const GROUND_LAYER := 0        # TileSet physics_layer_0 = 地面（collision_layer 1）
const DARK_TILES := 7.0        # 大约多深时到达最深
const MAX_ALPHA := 0.82        # 最深处黑到什么程度

var _tm: TileMapLayer

func _ready() -> void:
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if _tm != null and Engine.is_editor_hint():
		_tm.changed.connect(_rebuild, CONNECT_DEFERRED)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
	if _tm == null or _tm.tile_set == null:
		return
	var solid := _solid_cells()
	if solid.is_empty():
		return

	# 1) 包围盒
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in solid:
		lo.x = mini(lo.x, cell.x)
		lo.y = mini(lo.y, cell.y)
		hi.x = maxi(hi.x, cell.x)
		hi.y = maxi(hi.y, cell.y)
	lo -= Vector2i(2, 2)
	hi += Vector2i(2, 2)
	var w := hi.x - lo.x + 1
	var h := hi.y - lo.y + 1

	# 2) 多源 BFS：从空气出发，记录每个实心格离空气的步数
	var depth := {}
	# 先把空气邻接的实心格设为 1
	var next: Array[Vector2i] = []
	for cell in solid:
		for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not solid.has(cell + off):
				depth[cell] = 1
				next.append(cell)
				break
	var d := 1
	while not next.is_empty():
		d += 1
		var following: Array[Vector2i] = []
		for cell in next:
			for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + off
				if solid.has(n) and not depth.has(n):
					depth[n] = d
					following.append(n)
		next = following

	# 3) 生成遮罩图
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for cell in solid:
		var dd: float = float(depth.get(cell, 1))
		var a: float = clampf((dd - 1.0) / DARK_TILES, 0.0, 1.0) * MAX_ALPHA
		if a <= 0.0:
			continue
		img.set_pixel(cell.x - lo.x, cell.y - lo.y, Color(0, 0, 0, a))
	var tex := ImageTexture.create_from_image(img)

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sp.position = _tm.position + Vector2(float(lo.x) * TILE, float(lo.y) * TILE)
	sp.scale = Vector2(TILE, TILE)
	add_child(sp, false, Node.INTERNAL_MODE_FRONT)

func _solid_cells() -> Dictionary:
	var out := {}
	var ts: TileSet = _tm.tile_set
	var ids := {}
	for idx in ts.get_source_count():
		ids[ts.get_source_id(idx)] = true
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
		if td != null and td.get_collision_polygons_count(GROUND_LAYER) > 0:
			out[cell] = true
	return out
