extends Node2D
## 第五关引导光点：
##  玩家到达 x=trigger_x → 光点出现，沿它自己的 Path 曲线走；
##  走完整条曲线后停住等玩家；
##  玩家到达光点下方 → 以同样的速度直线走到 end_x 停住。

@export var trigger_x := 257500.0
@export var end_x := 320000.0
@export var drift_speed := 2250.0      # 走 path 的速度，也是之后直线前进的速度
@export var follow_gap := 320.0        # 玩家离光点多近算"到达"
@export var hover_height := 900.0      # 光点比玩家高多少

enum State { HIDDEN, DRIFT, WAIT, FOLLOW, DONE }

var _state := State.HIDDEN
var _player: Node2D
var _dot: Node2D
var _path: Curve2D
var _dist := 0.0
var _origin := Vector2.ZERO
var _curve_len := 0.0

func _ready() -> void:
	visible = false
	_dot = get_node_or_null("LightDot") as Node2D
	if _dot != null:
		_dot.visible = false
		var p := _dot.get_node_or_null("Path") as Path2D
		if p != null and p.curve != null:
			_path = p.curve
			_curve_len = _path.get_baked_length()
	await get_tree().process_frame
	_player = _find_player()

func _find_player() -> Node2D:
	var level := get_parent()
	return level.get_node_or_null("Player") as Node2D if level != null else null

func _process(delta: float) -> void:
	if _player == null:
		return
	var px := _player.global_position.x
	match _state:
		State.HIDDEN:
			if px >= trigger_x:
				_origin = Vector2(trigger_x, _player.global_position.y - hover_height)
				global_position = _origin
				_dist = 0.0
				visible = true
				if _dot != null:
					_dot.visible = true
					_set_dot_offset(Vector2.ZERO)
				_state = State.DRIFT
		State.DRIFT:
			_dist += drift_speed * delta
			if _curve_len <= 1.0 or _dist >= _curve_len:
				_dist = _curve_len
				_set_dot_offset(_sample(_dist))
				_state = State.WAIT
			else:
				_set_dot_offset(_sample(_dist))
		State.WAIT:
			if absf(px - _dot_x()) <= follow_gap:
				_state = State.FOLLOW
		State.FOLLOW:
			if _dot != null:
				_dot.global_position.x += drift_speed * delta
			if _dot_x() >= end_x:
				if _dot != null:
					_dot.global_position.x = end_x
				_state = State.DONE

## path 采样（没曲线就原地）
func _sample(d: float) -> Vector2:
	if _path == null or _curve_len <= 1.0:
		return Vector2.ZERO
	return _path.sample_baked(clampf(d, 0.0, _curve_len))

func _set_dot_offset(offset: Vector2) -> void:
	if _dot != null:
		_dot.position = offset

func _dot_x() -> float:
	return _dot.global_position.x if _dot != null else global_position.x
