extends CharacterBody2D
## 熊：简单状态机（IDLE / WALK）。
## IDLE：平时停在 idle 第一帧；每隔随机时间完整播一次 idle 动画，播完回到第一帧。
## 碰水 → 发 DIE 信号（关卡据此让玩家死亡并回检查点）。

signal DIE

enum State { IDLE, WALK }

const SPEED := 3600.0          # 速度
const ACCELERATION := 24000.0  # 加速度
const DECELERATION := 36000.0  # 减速度
const GRAVITY := 24000.0       # 重力
const WATER_MASK := 1 << 7     # 物理层 8 = water（和玩家同一层）

@export var idle_play_min := 6.0   # 两次 idle 动画之间的随机最短间隔（秒）
@export var idle_play_max := 12.0  # 最长间隔

var can_be_controlled := false
var state := State.IDLE

var _idle_wait := 0.0
var _water_query := PhysicsShapeQueryParameters2D.new()
var _water_dead := false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# idle 只播一次：关掉循环，靠 animation_finished 回到第一帧
	animated_sprite_2d.sprite_frames.set_animation_loop("idle", false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	_water_query.shape = collision_shape_2d.shape
	_water_query.collision_mask = WATER_MASK
	_enter_state()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var dir := 0.0
	if can_be_controlled:
		dir = Input.get_axis("left", "right")

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCELERATION * delta)
		animated_sprite_2d.flip_h = dir < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)

	move_and_slide()
	_push_rigid_bodies(dir, delta)
	_update_state(dir, delta)
	_update_water()

## 熊碰水 → 发一次 DIE（离开水后再重新武装）
func _update_water() -> void:
	if not can_be_controlled:
		_water_dead = false
		return
	_water_query.transform = collision_shape_2d.global_transform
	var hits := get_world_2d().direct_space_state.intersect_shape(_water_query, 1)
	var now := not hits.is_empty()
	if not now:
		_water_dead = false
	elif not _water_dead:
		_water_dead = true
		emit_signal("DIE")

# ==================== 状态机 ====================

func _update_state(dir: float, delta: float) -> void:
	var want := State.WALK if (dir != 0.0 or absf(velocity.x) > 1.0) else State.IDLE
	if want != state:
		state = want
		_enter_state()
	if state == State.IDLE:
		_tick_idle(delta)

func _enter_state() -> void:
	match state:
		State.IDLE:
			_idle_wait = randf_range(idle_play_min, idle_play_max)
			_show_idle_first_frame()
		State.WALK:
			animated_sprite_2d.play("walk")

## IDLE：计时到点就完整播一次 idle 动画
func _tick_idle(delta: float) -> void:
	if animated_sprite_2d.is_playing():
		return                     # 正在播 idle，等 animation_finished
	_idle_wait -= delta
	if _idle_wait <= 0.0:
		_idle_wait = randf_range(idle_play_min, idle_play_max)
		animated_sprite_2d.play("idle")

func _on_animation_finished() -> void:
	if state == State.IDLE and animated_sprite_2d.animation == &"idle":
		_idle_wait = randf_range(idle_play_min, idle_play_max)
		_show_idle_first_frame()

## 停在 idle 第一帧（不播）
func _show_idle_first_frame() -> void:
	animated_sprite_2d.play("idle")
	animated_sprite_2d.stop()
	animated_sprite_2d.frame = 0

## 推 barrier：和熊同速平移，速度清零（推完不会继续滑，也不会来回抖）
func _push_rigid_bodies(dir: float, delta: float) -> void:
	if dir == 0.0:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody2D
		if body == null or signf(collision.get_normal().x) != -signf(dir):
			continue
		var step := dir * SPEED * delta
		body.sleeping = false
		body.linear_velocity = Vector2(0.0, body.linear_velocity.y)   # 不留水平速度 → 松手立即停
		body.angular_velocity = 0.0
		# ponytail: 直接平移，推到墙里会插进去；需要时加位置回退/碰撞检测
		body.global_position.x += step
		global_position.x += step      # 熊跟着走，始终保持贴住
		return                          # 一次只推一个
