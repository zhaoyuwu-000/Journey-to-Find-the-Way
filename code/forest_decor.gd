@tool
extends Node2D
## 关卡装饰 v2：完全由 DecorTile（decortile）驱动。
## 不在 DecorTile 里画格子的地方一点装饰都不生成。
## marker 不区分种类：每有个格子就撒一簇随机的树/草/花/石。
## 根长在 marker 格底部；全部画在 tilemap 后面。
## @tool：编辑器里改参数 / 刷 marker 会立刻重新生成预览（预览节点是 internal，不会被存盘）。

const TILE := 600.0
const SURFACE := 506.0     # 地面 tile 里草地上沿的 y

const FOX := preload("res://sprite/场景图，neva/fox/idle/Scene1_000.png")
const SKY := preload("res://sprite/场景图，neva/场景图/_0016_远天延申.png")
const HILLS := preload("res://sprite/场景图，neva/场景图/_0015_远天.png")
const TREE_BIG := preload("res://sprite/场景图，neva/树1.png")
const TREE_MID := preload("res://sprite/场景图，neva/中树.png")
const FLOWERS := preload("res://sprite/场景图，neva/花1.png")
const FLOWER_BAND := preload("res://sprite/场景图，neva/场景图/_0003_中景花.png")
const ROCK := preload("res://sprite/场景图，neva/石头.png")
const GRASS: Array[Texture2D] = [
	preload("res://sprite/场景图，neva/草1.png"),
	preload("res://sprite/场景图，neva/草2.png"),
	preload("res://sprite/场景图，neva/草3.png"),
	preload("res://sprite/场景图，neva/草4.png"),
	preload("res://sprite/场景图，neva/草5.png"),
	preload("res://sprite/场景图，neva/草6.png"),
]

## 按狐狸身高定的相对大小（狐高 = 364px）
## 地面条 tile 的不透明横向范围（像素）：拼接总览2 的端头块只占半格

## 地面 tile 的不透明横向范围（像素）：端头块/竖墙条只占格子的一部分
const TILE_ART_X := {
	Vector2i(2, 3): Vector2(0, 600),      # 整格地面条
	Vector2i(0, 4): Vector2(0, 134),      # 左下端头块
	Vector2i(1, 4): Vector2(466, 600),    # 右下端头块
	Vector2i(0, 3): Vector2(0, 133),      # 左侧竖墙条
	Vector2i(1, 3): Vector2(466, 600),    # 右侧竖墙条
}

const U_GRASS_MIN := 0.8
const U_GRASS_MAX := 1.5
const U_FLOWER_MIN := 0.55
const U_FLOWER_MAX := 0.9
const U_ROCK_MIN := 0.34
const U_ROCK_MAX := 0.48

## 各贴图的 alpha 内容框：贴地/居中都按这个算，忽略透明边
const CONTENT := {
	"res://sprite/场景图，neva/fox/idle/Scene1_000.png": Rect2(14, 117, 572, 364),
	"res://sprite/场景图，neva/场景图/_0003_中景花.png": Rect2(0, 0, 600, 158),
	"res://sprite/场景图，neva/中树.png": Rect2(25, 12, 543, 353),
	"res://sprite/场景图，neva/树1.png": Rect2(32, 19, 532, 566),
	"res://sprite/场景图，neva/花1.png": Rect2(169, 124, 232, 233),
	"res://sprite/场景图，neva/石头.png": Rect2(245, 314, 89, 100),
	"res://sprite/场景图，neva/草1.png": Rect2(89, 20, 301, 461),
	"res://sprite/场景图，neva/草2.png": Rect2(15, 44, 470, 413),
	"res://sprite/场景图，neva/草3.png": Rect2(125, 44, 238, 410),
	"res://sprite/场景图，neva/草4.png": Rect2(59, 24, 380, 450),
	"res://sprite/场景图，neva/草5.png": Rect2(92, 10, 305, 481),
	"res://sprite/场景图，neva/草6.png": Rect2(41, 94, 487, 344),
}

@export var rng_seed := 20251107:
	set(v):
		rng_seed = v
		_rebuild()
@export var density := 1.0:            # 0~1，整体密度
	set(v):
		density = v
		_rebuild()
@export var scale_mul := 1.0:          # 整体大小倍率
	set(v):
		scale_mul = v
		_rebuild()
@export_group("树")
@export var tree_scale := 1.0:            # 树的额外大小倍率
	set(v):
		tree_scale = v
		_rebuild()
@export var tree_size_min := 4.6:         # 中树高度下限（狐高）
	set(v):
		tree_size_min = v
		_rebuild()
@export var tree_size_max := 7.5:         # 中树高度上限（狐高）
	set(v):
		tree_size_max = v
		_rebuild()
@export var big_tree_size_min := 8.0:     # 大树高度下限（狐高）
	set(v):
		big_tree_size_min = v
		_rebuild()
@export var big_tree_size_max := 12.0:    # 大树高度上限（狐高）
	set(v):
		big_tree_size_max = v
		_rebuild()
@export var big_tree_chance := 0.5:       # 每个 marker 额外长一棵大树的概率
	set(v):
		big_tree_chance = v
		_rebuild()

var _rng := RandomNumberGenerator.new()
var _tm: TileMapLayer = null
var _marker: TileMapLayer = null
var _fox_h := 364.0
var _cols: Dictionary = {}         # 列 -> 该列最高 tile 的行号
var _marker_cells: Dictionary = {} # marker 格集合，判断左右有没有 marker
var _tree_group_cells: Dictionary = {} # 属于“2 个以上相连”组的 marker 格
var _built := false

func _ready() -> void:
	_build()
	# 编辑器里刷 marker 也实时刷新预览
	if Engine.is_editor_hint() and _marker != null:
		_marker.changed.connect(_rebuild, CONNECT_DEFERRED)

## 清掉旧装饰后重新生成（运行时 / 编辑器预览都走这里）
func _build() -> void:
	if not is_inside_tree():
		return
	_clear_generated()
	var editor := Engine.is_editor_hint()
	_rng.seed = rng_seed
	_fox_h = maxf(_content(FOX).size.y, 1.0)
	_cols.clear()
	_marker_cells.clear()
	var parent := get_parent()
	_tm = parent.get_node_or_null("TileMapLayer") as TileMapLayer
	_marker = get_node_or_null("Markers") as TileMapLayer
	if _tm == null:
		return
	_scan_ground()
	_spawn_sky()   # 天空/远山是关卡底色，不属于装饰，跟 decortile 无关
	_built = true
	if _marker == null:
		return
	if not editor:
		_marker.visible = false   # 运行时隐藏 marker
	for cell in _marker.get_used_cells():
		_marker_cells[cell] = true
	_build_tree_groups()   # 哪些 marker 属于"2 个以上相连"的组
	for cell in _marker.get_used_cells():
		if _rng.randf() > density:
			continue
		_spawn_cell(cell)
	if not editor:
		print("[decor] decortile 标记 ", _marker.get_used_cells().size(), " 个 -> 装饰 ", get_child_count(), " 个")

func _rebuild() -> void:
	if _built:
		_build()

## 只删生成的 Sprite2D（含编辑器的 internal 预览），Markers 不动
func _clear_generated() -> void:
	for c in get_children(true):
		if c is Sprite2D:
			remove_child(c)
			c.queue_free()

# ==================== 地形 / 生成 ====================

func _scan_ground() -> void:
	for cell in _tm.get_used_cells():
		if not _cols.has(cell.x) or cell.y < _cols[cell.x]:
			_cols[cell.x] = cell.y

func _ground_y(cx: int) -> float:
	return float(_cols.get(cx, 0)) * TILE + SURFACE

## 天空渐变 + 远处山影：铺满整关，跟 decortile 无关
func _spawn_sky() -> void:
	var keys: Array = _cols.keys()
	if keys.is_empty():
		return
	keys.sort()
	var x0: float = _tm.position.x + float(keys.min()) * TILE
	var x1: float = _tm.position.x + float(keys.max() + 1) * TILE
	var top_y := 99999999.0
	var bot_y := -99999999.0
	for cx in keys:
		var gy := _ground_y(cx)
		top_y = minf(top_y, gy - TILE * 12.0)
		bot_y = maxf(bot_y, gy + TILE * 10.0)
	var sky := _sprite(SKY, Vector2(x0 - TILE * 10.0, top_y), 1.0, -100)
	sky.centered = false
	sky.scale = Vector2((x1 - x0 + TILE * 20.0) / float(SKY.get_width()), (bot_y - top_y) / float(SKY.get_height()))
	for i in 6:
		var scl := _fs(HILLS, _rng.randf_range(7.0, 10.0)) * scale_mul
		var half := HILLS.get_width() * scl * 0.5
		var x := _rng.randf_range(x0 + half, maxf(x0 + half, x1 - half))
		var gy := _ground_y(int((x - _tm.position.x) / TILE))
		var s := _sprite(HILLS, Vector2(x, gy - _rng.randf_range(1400.0, 4200.0)), scl, -95, true)
		s.modulate.a = _rng.randf_range(0.25, 0.4)

## 每个 marker 格生成一簇随机混合的装饰（不区分种类）。
## 根长在 marker 格的底部：feet_y = (cell.y + 1) * TILE + SURFACE，
## 所以 marker 刷在贴地那一格时，正好和地面齐平；刷高一点装饰就跟着往上抬。
func _spawn_cell(cell: Vector2i) -> void:
	if not _cols.has(cell.x):
		return   # 那一列没地面，不放
	var cx := cell.x
	# 这一列顶层 tile 只有半格宽（竖墙条、端头块）时不当"地面"用，不然装饰会站在墙面上
	var seg0 := _opaque_segment(cx)
	if seg0.y - seg0.x < TILE * 0.5:
		return
	var base_x := _tm.position.x + float(cx) * TILE + TILE * 0.5
	# 根长在 marker 格底部；但 marker 刷在地面以下时不能跟着往下沉，最低压到地面
	# 一律贴在该列的地面上（marker 的行号只当编辑位置，不参与高度）
	var g := _ground_y(cx)
	# 草 + 花：随机、稀疏一点，别把背景挡死
	for i in _rng.randi_range(5, 8):
		_clump(GRASS[_rng.randi_range(0, GRASS.size() - 1)], cx, base_x, g, U_GRASS_MIN, U_GRASS_MAX, -5, 40.0, TILE * 0.5)
	if _rng.randf() < 0.9:
		for i in _rng.randi_range(2, 4):
			_clump(FLOWERS, cx, base_x, g, U_FLOWER_MIN, U_FLOWER_MAX, -5, 24.0, TILE * 0.45)
	if _rng.randf() < 0.4:
		# 一条中景花带，彩色更显眼
		var bs := _fs(FLOWER_BAND, 0.6) * scale_mul
		var bseg := _opaque_segment(cx)
		var bx := clampf(base_x + _rng.randf_range(-TILE * 0.4, TILE * 0.4), bseg.x + 6.0, bseg.y - 6.0)
		if _in_pit(cx) or _footprint_ok(_content(FLOWER_BAND), bs, bx):
			_sprite(FLOWER_BAND, _feet(FLOWER_BAND, bx, g + 26.0, bs), bs, -3, _rng.randf() < 0.5)
	if _rng.randf() < 0.1:
		_clump(ROCK, cx, base_x, g, U_ROCK_MIN, U_ROCK_MAX, -4, 30.0, TILE * 0.4)
	# 树：只有相连 ≥2 的 marker 才长；两种树随机落在不同前后层，交错出层次
	if _tree_space_ok(cell):
		for i in _rng.randi_range(2, 3):
			_tree(TREE_MID, cx, base_x, g, _rng.randf_range(tree_size_min, tree_size_max) * tree_scale, _rand_tree_z(false), 110.0, TILE * 0.45)
		if _rng.randf() < big_tree_chance:
			_tree(TREE_BIG, cx, base_x, g, _rng.randf_range(big_tree_size_min, big_tree_size_max) * tree_scale, _rand_tree_z(true), 120.0, TILE * 0.4)

## 树的前后层次（越靠前 z 越大，全部 < 0 所以在 tilemap 后面）
const TREE_Z := [-64, -44, -26, -6]

## 随机取一层：小树/大树都在各层随机出现（小树也可以在最前面），交错出层次
func _rand_tree_z(big: bool) -> int:
	var i := _rng.randi_range(0, TREE_Z.size() - 1)
	if big and _rng.randf() < 0.5:
		i = maxi(i, _rng.randi_range(1, TREE_Z.size() - 1))   # 大树稍微偏前一点，但不强制
	return TREE_Z[i]

## 只有 2 个及以上互相连接的 marker 才长树：
## 四方向连通的 marker 分组，组内格子数 >= 2 才算可长树
func _tree_space_ok(cell: Vector2i) -> bool:
	return _tree_group_cells.has(cell)


func _build_tree_groups() -> void:
	_tree_group_cells.clear()
	var visited := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for start in _marker_cells:
		if visited.has(start):
			continue
		var group := []
		var stack := [start]
		visited[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for d in dirs:
				var nb: Vector2i = c + d
				if _marker_cells.has(nb) and not visited.has(nb):
					visited[nb] = true
					stack.append(nb)
		if group.size() >= 2:
			for c in group:
				_tree_group_cells[c] = true

## 一棵树：x 在格子内随机偏一点，脚贴地；大小由 units（狐高）决定
func _tree(tex: Texture2D, cx: int, base_x: float, g: float, units: float, z: int, sink: float, spread := TILE * 0.3) -> void:
	# 不自动缩放：大小就是你设的范围
	var scl := _fs(tex, units) * scale_mul
	# 坑内不做端头收缩
	var pit := _in_pit(cx)
	# 只把"中树"往里收：按它根部外扩宽度算内缩格数，端头附近不长中树；大树不收缩
	if pit:
		pass
	elif tex == TREE_MID:
		var flare_half: float = _trunk_band(tex).y * scl
		var inset := clampi(int(ceil(flare_half / TILE)) + 1, TREE_INSET, 6)
		if not _inset_ok(cx, inset):
			return
	elif not _inset_ok(cx, 1):
		return
	# 树根中心严格收在 marker 这一列（格子范围）内
	var cell_x: float = _tm.position.x + float(cx) * TILE
	var x := clampf(base_x + _rng.randf_range(-spread, spread), cell_x + TILE * 0.12, cell_x + TILE * 0.88)
	# 树干落地那一段（±0.4 格）必须踩在同高度的地面上
	var row: int = _cols[cx]
	var k0 := int(floor((x - TILE * 0.4 - _tm.position.x) / TILE))
	var k1 := int(floor((x + TILE * 0.4 - _tm.position.x) / TILE))
	for k in range(k0, k1 + 1):
		if not _cols.has(k) or int(_cols[k]) != row:
			return
	# 地面 tile 只有一部分是不透明的（端头块是半格）：树根中心必须落在不透明那段里
	var seg := _opaque_segment(cx)
	x = clampf(x, maxf(seg.x, cell_x) + 4.0, minf(seg.y, cell_x + TILE) - 4.0)
	if x < cell_x or x > cell_x + TILE:
		return
	var r := _content(tex)
	var content_center := x + (r.get_center().x - _trunk_band(tex).x) * scl
	if not pit and not _footprint_ok(r, scl, content_center):
		return
	var s := _sprite_trunk(tex, x, g + sink, scl, z, _rng.randf() < 0.5)
	if z <= -60:
		s.modulate.a = 0.86   # 后面的树淡一点，空气透视，层次更明显

## 用"树干中心"对齐 x 放置树（而不是用整张图的内容中心，树冠是不对称的）
func _sprite_trunk(tex: Texture2D, root_x: float, ground_y: float, scl: float, z: int, flip: bool) -> Sprite2D:
	var r := _content(tex)
	var trunk_cx := _trunk_band(tex).x
	var pos := Vector2(root_x - (trunk_cx - tex.get_width() * 0.5) * scl,
			ground_y - (r.end.y - tex.get_height() * 0.5) * scl)
	return _sprite(tex, pos, scl, z, flip)

## 树干（贴图内容底部 15% 那条）在贴图里的中心像素 x
var _trunk_center_cache: Dictionary = {}

var _trunk_cache: Dictionary = {}

## 树根那圈（内容底部 15%）在贴图里的 (中心 x, 半宽)，缓存
func _trunk_band(tex: Texture2D) -> Vector2:
	var key := tex.resource_path
	if not _trunk_cache.has(key):
		var r := _content(tex)
		var img := tex.get_image()
		var minx := 99999
		var maxx := -1
		for y in range(int(r.position.y + r.size.y * 0.85), int(r.end.y), 2):
			for px in range(int(r.position.x), int(r.end.x), 2):
				if img.get_pixel(px, y).a > 0.5:
					minx = mini(minx, px)
					maxx = maxi(maxx, px)
		if maxx < minx:
			_trunk_cache[key] = Vector2(r.get_center().x, 0.0)
		else:
			_trunk_cache[key] = Vector2(float(minx + maxx) * 0.5, float(maxx - minx) * 0.5)
	return _trunk_cache[key]

## 树的左右两侧都不能更低：
##   旁边是坑底 / 低一级台面（行号更大）→ 不长树
##   旁边是同高 / 更高平台（行号相同或更小）、墙根、上一级台面 → 可以长树
##   旁边完全没有地面（平台边）→ 也不长树
## 树要往里收：左右各 3 格都必须是有画的、同高度的完整地面。
## 这样平台端头（端头块那半格）附近至少 3 格内不会长树。
const TREE_INSET := 3   # 至少往里收 3 格

## 这一列往左右各 n 格都必须是有画的、同高度的完整地面
func _inset_ok(cx: int, n: int) -> bool:
	if not _cols.has(cx):
		return false
	var row: int = _cols[cx]
	for d in range(-n, n + 1):
		var k := cx + d
		if not _cols.has(k) or int(_cols[k]) != row:
			return false
		var seg := _opaque_segment(k)
		if seg.y - seg.x < TILE * 0.5:
			return false
	return true

func _tree_side_ok(cx: int) -> bool:
	if not _cols.has(cx):
		return false
	var row: int = _cols[cx]
	for k in [cx - 1, cx + 1]:
		if not _cols.has(k):
			return false          # 平台边
		if int(_cols[k]) > row:
			return false          # 旁边更低：坑底或低一级台面
	return true                   # 同高 / 更高（墙根、上一级台面）

## 小物件（草/花/石）：一次摆一簇


## 是否在"坑/低洼地"里（附近 4 格内存在更高的地面）。坑内不做收缩/贴边检测，
## 因为坑底四周都是高墙，树贴着墙长才是对的。
func _in_pit(cx: int) -> bool:
	if not _cols.has(cx):
		return false
	var row: int = _cols[cx]
	for k in range(cx - 4, cx + 5):
		if _cols.has(k) and int(_cols[k]) < row:
			return true
	return false

## 严格地面检测：装饰整张图横向覆盖到的每一列，都必须是同高度、有画的完整地面。
## 只要有哪怕一点压到更低/更高的地面、半格端头块、或没地面的地方，就不生成。
func _footprint_ok(content: Rect2, scl: float, center_x: float) -> bool:
	var half: float = content.size.x * scl * 0.5
	var col_c := int(floor((center_x - _tm.position.x) / TILE))
	if not _cols.has(col_c):
		return false
	var row: int = _cols[col_c]
	var k0 := int(floor((center_x - half - _tm.position.x) / TILE))
	var k1 := int(floor((center_x + half - _tm.position.x) / TILE))
	for k in range(k0, k1 + 1):
		if not _cols.has(k) or int(_cols[k]) != row:
			return false
		var sg := _opaque_segment(k)
		if sg.y - sg.x < TILE * 0.5:
			return false
	return true

func _clump(tex: Texture2D, cx: int, base_x: float, g: float, u_min: float, u_max: float, z: int, sink: float, spread: float) -> void:
	var seg := _opaque_segment(cx)
	if seg.y - seg.x < 20.0:
		return   # 这一列几乎没有不透明地面，不放
	var scl := _fs(tex, _rng.randf_range(u_min, u_max)) * scale_mul
	var x := base_x + _rng.randf_range(-spread, spread)
	x = clampf(x, seg.x + 6.0, seg.y - 6.0)
	if not _in_pit(cx) and not _footprint_ok(_content(tex), scl, x):
		return
	var sp := _sprite(tex, _feet(tex, x, g + sink, scl), scl, z, _rng.randf() < 0.5)
	# 草叶本身是很深的墨绿，压在同样深的树林上几乎看不见：稍微提亮让它浮出来
	if tex in GRASS:
		sp.modulate = Color(1.35, 1.35, 1.15, 1.0)

## 别让装饰跑出 marker 所在列，免得悬到相邻的坑/台阶外面
func _clamp_x(x: float, cx: int) -> float:
	var lo := _tm.position.x + float(cx) * TILE + 60.0
	return clampf(x, lo, lo + TILE - 120.0)

## 该列地面 tile 的不透明横向范围（世界坐标 x0, x1）；普通整格 tile 就是整格
func _opaque_segment(cx: int) -> Vector2:
	var cell := Vector2i(cx, _cols.get(cx, 0))
	var cell_x: float = _tm.position.x + float(cx) * TILE
	if _tm.get_cell_source_id(cell) == 5:
		var r: Vector2 = TILE_ART_X.get(_tm.get_cell_atlas_coords(cell), Vector2(0, TILE))
		return Vector2(cell_x + r.x, cell_x + r.y)
	return Vector2(cell_x, cell_x + TILE)


# ==================== 小工具 ====================

func _fs(tex: Texture2D, units: float) -> float:
	return units * _fox_h / maxf(_content(tex).size.y, 1.0)

func _feet(tex: Texture2D, x: float, ground_y: float, scl: float) -> Vector2:
	var r := _content(tex)
	return Vector2(_center_offset(tex, r, x, scl), ground_y - (r.end.y - tex.get_height() * 0.5) * scl)

func _center_offset(tex: Texture2D, r: Rect2, x: float, scl: float) -> float:
	return x - (r.get_center().x - tex.get_width() * 0.5) * scl

func _content(tex: Texture2D) -> Rect2:
	return CONTENT.get(tex.resource_path, Rect2(Vector2.ZERO, tex.get_size()))

func _sprite(tex: Texture2D, pos: Vector2, scl: float, z: int, flip := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2(-scl if flip else scl, scl)
	s.z_index = z
	if Engine.is_editor_hint():
		# 预览节点：internal，不进场景文件
		add_child(s, false, Node.INTERNAL_MODE_FRONT)
	else:
		add_child(s)
	return s
