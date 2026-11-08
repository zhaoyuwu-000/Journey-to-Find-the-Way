extends Node2D
## 第五关引导光点：
##  玩家到达 x=trigger_x → 光点出现，以 drift_speed 前进到 phase1_end_x（尾端）静止；
##  玩家走到光点下方（x 接近）→ 光点以玩家速度继续向前，直到 end_x 停住。
##  位置由本脚本控制，子节点 LightDot 只负责发光外观（manual=true）。

@export var trigger_x := 257500.0
@export var phase1_end_x := 300000.0
@export var end_x := 320000.0
@export var drift_speed := 900.0        # 第一阶段自动前进速度
@export var follow_gap := 320.0         # 玩家离光点多近算"到达下方"
@export var hover_height := 900.0       # 光点比玩家高多少

enum State { HIDDEN, DRIFT, WAIT, FOLLOW, DONE }

var _state := State.HIDDEN
var _player: Node2D

func _ready() -> void:
	visible = false
	_set_dot_visible(false)
	await get_tree().process_frame
	_player = _find_player()

func _find_player() -> Node2D:
	var level := get_parent()
	return level.get_node_or_null("Player") as Node2D if level != null else null

func _set_dot_visible(on: bool) -> void:
	var dot := get_node_or_null("LightDot")
	if dot != null:
		dot.visible = on

func _process(delta: float) -> void:
	if _player == null:
		return
	var px := _player.global_position.x
	match _state:
		State.HIDDEN:
			if px >= trigger_x:
				# 高度按玩家当前 y 来定（关卡地形高低差很大，不能靠固定地面高度）
				global_position = Vector2(trigger_x, _player.global_position.y - hover_height)
				visible = true
				_set_dot_visible(true)
				_state = State.DRIFT
		State.DRIFT:
			global_position.x += drift_speed * delta
			if global_position.x >= phase1_end_x:
				global_position.x = phase1_end_x
				_state = State.WAIT
		State.WAIT:
			if absf(px - global_position.x) <= follow_gap:
				_state = State.FOLLOW
		State.FOLLOW:
			var vx := 0.0
			if _player is CharacterBody2D:
				vx = (_player as CharacterBody2D).velocity.x
			global_position.x += maxf(vx, 0.0) * delta
			if global_position.x >= end_x:
				global_position.x = end_x
				_state = State.DONE
