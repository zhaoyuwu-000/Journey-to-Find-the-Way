extends CharacterBody2D

# 世界尺度：1 格 = 600px（TileSet.tile_size）
const SPEED := 3600.0          # 速度
const ACCELERATION := 24000.0  # 加速度
const DECELERATION := 36000.0  # 减速度
const JUMP_VELOCITY := -8800.0 # 跳跃速度 起跳约 2.7 格高
const GRAVITY := 24000.0       # 重力
const DOUBLE_JUMP_VELOCITY := -6800.0
const JUMP_CUT := 0.66         # 松手截断剩余上升速度：最短点按约为满跳的 1/2 高

@export var coyote_time := 0.1  # 土狼时间
@export var air_jumps := 1      # 二段跳段数； 0 = 没有二段跳； 1 = 启用二段跳

var _coyote := 0.0
var _air_jumps_left := 0

func _physics_process(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
		_air_jumps_left = air_jumps
	else:
		velocity.y += GRAVITY * delta
		_coyote = maxf(_coyote - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		try_jump()

	# 上升中松手：剩余上升速度打折 → 按住越久跳越高
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	var direction := Input.get_axis("left", "right")
	if direction == 0.0:
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION * delta)

	move_and_slide()

func try_jump() -> void:
	if is_on_floor() or _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_air_jumps_left = air_jumps
	elif _air_jumps_left > 0:
		double_jump()

## 二段跳。
func double_jump() -> void:
	_air_jumps_left -= 1
	velocity.y = DOUBLE_JUMP_VELOCITY
