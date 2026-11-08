@tool
extends Node2D
## 沿路径移动的金色光点：
##  - 直径 = 玩家高度的一半（默认 182）
##  - 路径用子节点 Path 的 Curve2D 在编辑器里画
##  - 可循环 / 单程，带轻微呼吸闪烁和上下浮动

const PLAYER_HEIGHT := 364.0   # 狐狸精灵高度

@export var diameter := PLAYER_HEIGHT * 0.5:
	set(v):
		diameter = maxf(v, 4.0)
		_apply_size()
@export var core_ratio := 0.32:      # 中心亮核占直径比例
	set(v):
		core_ratio = clampf(v, 0.05, 1.0)
		_apply_size()
@export var speed := 160.0           # 路径速度 px/s
@export var loop := true             # 到头后回到起点
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

func _ensure_curve() -> void:
	if _path == null:
		return
	if _path.curve == null:
		_path.curve = Curve2D.new()
	if _path.curve.point_count >= 2:
		return
	# 默认给一条平滑的小弧线，方便直接在编辑器里接着改
	var c := _path.curve
	c.add_point(Vector2(0, 0), Vector2(160, 0), Vector2(-160, 0))
	c.add_point(Vector2(520, -180), Vector2(200, 0), Vector2(-200, 0))
	c.add_point(Vector2(1040, 0), Vector2(200, 0), Vector2(-160, 0))

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

func _move(delta: float) -> void:
	if _path == null or _path.curve == null:
		return
	var curve := _path.curve
	var length := curve.get_baked_length()
	if length <= 0.1:
		return
	_time += delta
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
