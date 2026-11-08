extends CharacterBody2D

signal DIE
signal REVIVEPOINTSET
signal EATABILITY(ability_point)   # 碰到能力点（交给 manager 判定/处理）
signal USEABILITY(property)        # 用掉了某个能力（manager 据此让能力点重生）
signal ability_changed(new_ability)  # 当前形态变了（UI/特效用）
signal USEBEAR
signal EXITBEAR
signal water_changed(inside: bool)   # 进入/离开水（tilemap 的 water 层）

const WATER_MASK := 1 << 7   # 物理层 8 = water（TileSet 的 physics_layer_1，collision_layer=128）

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var ability_choose: Control = $AbilityChoose
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

# ---------------- 一般状态 ----------------
enum State { IDLE, MOVE, JUMP, DEAD, CHOOSE }

# ---------------- 能力状态 ----------------
enum Ability { NONE, BIRD, BEAR, FISH }

# 世界尺度：1 格 = 600px（TileSet.tile_size）
const SPEED := 3600.0          # 速度
const ACCELERATION := 24000.0  # 加速度
const DECELERATION := 36000.0  # 减速度
const JUMP_VELOCITY := -9400.0 # 跳跃速度
const GRAVITY := 24000.0       # 重力
const JUMP_CUT := 0.66         # 松手截断剩余上升速度
const ABILITY_JUMP_VELOCITY := -8800.0  # 鸟形态的空中补跳
const SWIM_SPEED := 4200.0              # 鱼在水中上下左右游的速度
const BUOYANCY := 350.0                 # 水里的浮力：不按上下时向上飘的速度
const WATER_SINK_SPEED := 1000.0         # 狐狸掉进水里：慢速下沉
const WATER_MOVE_SPEED := 2200.0        # 水里左右移动速度
const WATER_ACCEL := 12000.0            # 水里水平加速度
const FISH_SCENE := preload("res://scene/fish.tscn")   # 鱼形态外观（动画在鱼场景里）

@export var coyote_time := 0.1  # 土狼时间

var can_be_controlled := true

var state := State.IDLE
var ability := Ability.NONE
var in_water := false

var _coyote := 0.0
var _water_query := PhysicsShapeQueryParameters2D.new()
var _fish: Node2D = null          # 鱼形态的外观实例（fish.tscn）
var _fish_anim: AnimatedSprite2D = null
var _fish_exited_water := false   # 出水后保持鱼形态，直到重新接触陆地
var _was_floor := false            # 上一帧是否贴地（落地音效用）
var _foot_t := 0.0                 # 草丛脚步声间隔
var _push_t := 0.0                 # 推石头音效间隔

func _sfx(cat: String, db := 0.0, pitch := 0.05) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(cat, db, pitch)

func _ready() -> void:
	_water_query.shape = collision_shape_2d.shape
	_water_query.collision_mask = WATER_MASK
	# 鱼形态直接复用 fish.tscn（swim / idle 动画都在里面）
	_fish = FISH_SCENE.instantiate() as Node2D
	_fish.position = animated_sprite_2d.position
	_fish.visible = false
	add_child(_fish)
	_fish_anim = _fish.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

func _physics_process(delta: float) -> void:
	var was_floor := _was_floor
	_was_floor = is_on_floor()
	if _was_floor and not was_floor and velocity.y > 1500.0:
		_sfx("落地", -3.0, 0.08)
	_footstep(delta)
	_push_stone(delta)
	_update_water()   # 先看水：决定鱼外观 / 出水失能

	if ability == Ability.FISH and in_water:
		_update_swim()      # 鱼在水里：无重力，上下左右自由游
	elif in_water:
		_update_water_sink(delta)   # 不是鱼：不死了，慢慢下沉 + 左右移动
	else:
		_update_locomotion(delta)

		# use_ability 只在这里读一次、只交给 use_ability() 消费，别处不再读
		if Input.is_action_just_pressed("use_ability"):
			use_ability()

		move_and_slide()
		_update_state()
		_update_fish_landing()

	_update_fish_visible()
	_update_fish_anim()

## 鱼形态外观：水里和空中都显示鱼；站在陆地上显示玩家精灵
func _update_fish_visible() -> void:
	if _fish == null:
		return
	var want := ability == Ability.FISH and (in_water or not is_on_floor())
	if _fish.visible == want:
		return
	_fish.visible = want
	animated_sprite_2d.visible = not want
	if want and _fish_anim != null:
		_fish_anim.play("idle")

## 出水后保持鱼形态，直到碰到陆地才失去鱼能力
func _update_fish_landing() -> void:
	if not _fish_exited_water or ability != Ability.FISH:
		return
	if is_on_floor():
		_fish_exited_water = false
		_consume_ability()

## 鱼在水里：上下左右自由游，水有浮力（不按上下就慢慢往上飘）
func _update_swim() -> void:
	var dir := Vector2.ZERO
	if can_be_controlled:
		dir = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	velocity.x = dir.x * SWIM_SPEED
	velocity.y = dir.y * SWIM_SPEED - BUOYANCY   # 往下游会被浮力抵掉一点，往上/悬停会加速上浮
	move_and_slide()

## 按输入方向转身（0 保持当前朝向）
func _face(dir: float) -> void:
	if dir > 0.0:
		animated_sprite_2d.flip_h = false
	elif dir < 0.0:
		animated_sprite_2d.flip_h = true

## 非鱼形态在水里：不死了，缓慢下沉，可以左右移动（不能跳）
func _update_water_sink(delta: float) -> void:
	var dir := _input_axis()
	_face(dir)
	velocity.x = move_toward(velocity.x, dir * WATER_MOVE_SPEED, WATER_ACCEL * delta)
	velocity.y = move_toward(velocity.y, WATER_SINK_SPEED, GRAVITY * delta)
	move_and_slide()
	_update_state()

## 鱼形态：在动就播 swim，待机播 idle（动画来自 fish.tscn）
func _update_fish_anim() -> void:
	if _fish_anim == null or ability != Ability.FISH or not _fish.visible:
		return
	var moving := velocity.length() > 1.0
	if absf(velocity.x) > 1.0:
		_fish_anim.flip_h = velocity.x < 0.0   # 鱼原图朝右
	var want: StringName = &"swim" if moving else &"idle"
	if _fish_anim.animation != want or not _fish_anim.is_playing():
		_fish_anim.play(want)

## 鱼形态外观：只有在水里才显示鱼、播鱼动画；陆地上用玩家自己的精灵
func _set_fish_visible(on: bool) -> void:
	if _fish != null:
		_fish.visible = on
	animated_sprite_2d.visible = not on
	if on and _fish_anim != null:
		_fish_anim.play("idle")

## 每帧查：玩家碰撞体是否和 water 层（layer 8）的 tile 碰撞体重叠
func _update_water() -> void:
	_water_query.transform = collision_shape_2d.global_transform
	var hits := get_world_2d().direct_space_state.intersect_shape(_water_query, 1)
	var now := not hits.is_empty()
	if now != in_water:
		in_water = now
		if now:
			_sfx("泡泡", -3.0, 0.1)
		water_changed.emit(now)
		if ability == Ability.FISH:
			_fish_exited_water = not now   # 出水标记；重新入水就清掉
	# 碰水不再死亡：非鱼形态在水里走 _update_water_sink（慢速下沉 + 左右移动）

# ==================== 一般状态机 ====================

func _update_locomotion(delta: float) -> void:
	match state:
		State.IDLE:
			_update_idle(delta)
		State.MOVE:
			_update_move(delta)
		State.JUMP:
			_update_jump(delta)
		State.DEAD:
			velocity = Vector2.ZERO
		State.CHOOSE:
			velocity = Vector2.ZERO   # 选能力时站住不动

func _update_idle(delta: float) -> void:
	_ground_tick()
	_handle_jump()

	var dir := _input_axis()
	if dir == 0.0:
		velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCELERATION * delta)

func _update_move(delta: float) -> void:
	_ground_tick()
	_handle_jump()

	var dir := _input_axis()
	_face(dir)
	var rate := DECELERATION if dir == 0.0 else ACCELERATION
	velocity.x = move_toward(velocity.x, dir * SPEED, rate * delta)

func _update_jump(delta: float) -> void:
	velocity.y += GRAVITY * delta
	_coyote = maxf(_coyote - delta, 0.0)
	_handle_jump()

	if velocity.y > 0:
		animated_sprite_2d.play("down")

	var dir := _input_axis()
	_face(dir)   # 空中按左右也转身
	var rate := DECELERATION if dir == 0.0 else ACCELERATION
	velocity.x = move_toward(velocity.x, dir * SPEED, rate * delta)

## 走路时按间隔播草丛脚步
func _footstep(delta: float) -> void:
	_foot_t = maxf(_foot_t - delta, 0.0)
	if state != State.MOVE or not is_on_floor() or not can_be_controlled:
		return
	if _foot_t <= 0.0:
		_sfx("走在草丛", -8.0, 0.12)
		_foot_t = 0.34

## 熊形态推动挡路的石头/障碍
func _push_stone(delta: float) -> void:
	_push_t = maxf(_push_t - delta, 0.0)
	if ability != Ability.BEAR or absf(velocity.x) < 200.0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body != null and String(body.name).begins_with("Barrier"):
			if _push_t <= 0.0:
				_sfx("推动石头", -4.0, 0.1)
				_push_t = 0.4
			return

## 贴地时刷新土狼时间
func _ground_tick() -> void:
	_coyote = coyote_time

## 跳跃输入 + 松手截断
func _handle_jump() -> void:
	if not can_be_controlled:
		return
	if Input.is_action_just_pressed("jump"):
		try_jump()
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

## 水平输入（不可控时为 0）
func _input_axis() -> float:
	return Input.get_axis("left", "right") if can_be_controlled else 0.0

func try_jump() -> void:
	if is_on_floor() or _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_sfx("跳跃", -4.0, 0.06)

func _update_state() -> void:
	if state == State.CHOOSE:
		if Input.is_action_just_pressed("choose_ability"):
			ability_choose.confirm()   # X = 确认光标选中的能力（不用上键）
		return
	if Input.is_action_just_pressed("choose_ability") and is_on_floor():
		# 不可控时不弹能力选择：操控熊、对话中、菜单/设置、死亡、切关都算
		if not can_be_controlled:
			return
		# 对话中不弹能力选择面板，避免确认键被对话吃掉
		var dlg := get_node_or_null("/root/Dialogue")
		if dlg != null and dlg.is_playing():
			return
		set_state(State.CHOOSE)
		return
	if state == State.DEAD:
		return
	if not is_on_floor():
		set_state(State.JUMP)
	elif absf(velocity.x) > 1.0:
		set_state(State.MOVE)
	else:
		set_state(State.IDLE)

func set_state(next: State) -> void:
	if next == state:
		return
	var prev := state
	state = next
	_enter_state(prev)

func _enter_state(_prev: State) -> void:
	match state:
		State.IDLE:
			animated_sprite_2d.play("idle")
		State.MOVE:
			animated_sprite_2d.play("run")
		State.JUMP:
			animated_sprite_2d.play("jump")
		State.DEAD:
			velocity = Vector2.ZERO
			set_ability(Ability.NONE)
		State.CHOOSE:
			velocity = Vector2.ZERO
			animated_sprite_2d.play("idle")   # 选能力时播待机
			ability_choose.visible = true
			can_be_controlled = false

## 关闭能力选择面板，恢复操作（UI 确认选择 / 再按一次选择键时调用）
func close_choose() -> void:
	if state != State.CHOOSE:
		return
	can_be_controlled = true
	ability_choose.visible = false
	set_state(State.IDLE)

## 死亡：由 DIE 信号的使用方（level）决定何时复活
func die() -> void:
	_sfx("掉落", -2.0, 0.06)
	set_state(State.DEAD)

## 复活到指定位置
func revive(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	set_ability(Ability.NONE)
	set_state(State.IDLE)

# ==================== 能力 ====================

## 在已持有的能力之间切换形态（UI 选中后调用，不消耗能力）
func switch_ability(prop: int) -> void:
	var next := ability_from_property(prop)
	if next != Ability.NONE:
		set_ability(next)

## 使用当前能力：唯一的输入消费点（每帧最多执行一次，别处不要再读 use_ability）
func use_ability() -> void:
	if ability == Ability.NONE:
		return

	if not can_be_controlled:
		# 正在操控熊：再按一次 = 退出熊形态（消耗能力 → EXITBEAR → 能力点重生）
		if ability == Ability.BEAR:
			_consume_ability()
		return

	match ability:
		Ability.BIRD:
			if is_on_floor():
				return  # 鸟是空中补跳，地面上不消耗
			velocity.y = ABILITY_JUMP_VELOCITY
			animated_sprite_2d.play("bird")
			_sfx("飞行", -4.0, 0.12)
		Ability.BEAR:
			emit_signal("USEBEAR")   # 进入熊形态：能力先留着，退出时再消耗
			return                   # ← 不往下走，否则同一次按键又发 EXITBEAR 变回来
		Ability.FISH:
			return  # 鱼没有主动技能；出水时才失去能力

	_consume_ability()

## 消耗当前能力：形态清空（会触发 EXITBEAR 等）→ 通知 manager 让能力点重生
func _consume_ability() -> void:
	var used := property_from_ability(ability)
	set_ability(Ability.NONE)
	emit_signal("USEABILITY", used)

func set_ability(next: Ability) -> void:
	if next == ability:
		return
	_leave_ability()

	var prev := ability
	ability = next
	_enter_ability(prev)
	emit_signal("ability_changed", ability)

func _enter_ability(_prev: Ability) -> void:
	match ability:
		Ability.NONE:
			pass
		Ability.BIRD:
			pass
		Ability.BEAR:
			pass
		Ability.FISH:
			_set_fish_visible(in_water or not is_on_floor())   # 水里/空中都是鱼

func _leave_ability() -> void:
	match ability:
		Ability.NONE:
			pass
		Ability.BIRD:
			pass
		Ability.BEAR:
			emit_signal("EXITBEAR")
		Ability.FISH:
			_fish_exited_water = false
			_set_fish_visible(false)

static func ability_from_property(prop: int) -> Ability:
	match prop:
		AbilityPoint.Property.bird:
			return Ability.BIRD
		AbilityPoint.Property.bear:
			return Ability.BEAR
		AbilityPoint.Property.fish:
			return Ability.FISH
	return Ability.NONE

static func property_from_ability(a: Ability) -> int:
	match a:
		Ability.BIRD:
			return AbilityPoint.Property.bird
		Ability.BEAR:
			return AbilityPoint.Property.bear
		Ability.FISH:
			return AbilityPoint.Property.fish
	return AbilityPoint.Property.none

# ==================== 区域检测（陷阱 / 复活点 / 能力点） ====================

func _on_area_2d_area_entered(area: Area2D) -> void:
	var source := area.get_parent()
	if source is AbilityPoint:
		emit_signal("EATABILITY", source)
	elif String(source.name).begins_with("Trap"):
		emit_signal("DIE")
	elif String(source.name).begins_with("RebirthPoint"):
		emit_signal("REVIVEPOINTSET", source.global_position)
