extends Control
## 能力选择面板：按 manager.owned 显示/隐藏；左右键移动光标，按 X（choose_ability）确认。

const PS := preload("res://code/player.gd")
const ORDER: Array[int] = [
	AbilityPoint.Property.fish,
	AbilityPoint.Property.bird,
	AbilityPoint.Property.bear,
]
const COLOR_CURRENT := Color(1.0, 1.0, 1.0, 1.0)   # 当前形态
const COLOR_CURSOR := Color(1.0, 0.85, 0.3, 1.0)   # 光标选中
const COLOR_DIM := Color(1.0, 1.0, 1.0, 1.0)    # 持有但没被选中
const HIGHLIGHT := 0.4                             # 有 ShaderMaterial 时的 shader 高亮强度

@onready var fish: TextureRect = $fish
@onready var bird: TextureRect = $bird
@onready var bear: TextureRect = $bear

var chosen: int = AbilityPoint.Property.none   # 光标选中的能力

var _manager: Node

func _ready() -> void:
	visible = false        # 面板默认隐藏，由玩家的 CHOOSE 状态控制显隐
	visibility_changed.connect(_on_visibility_changed)
	_bind.call_deferred()   # 等 AbilityPointManager._ready 把自己加进组

func _bind() -> void:
	_manager = get_tree().get_first_node_in_group("ability_manager")
	if _manager == null:
		push_error("AbilityChoose: 找不到 AbilityPointManager")
		return

	_manager.ability_acquired.connect(func(_p): refresh())
	_manager.ability_consumed.connect(func(_p): refresh())
	_manager.state_restored.connect(func(): refresh())
	var player: CharacterBody2D = _manager.player
	if player != null:
		player.ability_changed.connect(func(_a): refresh())

	refresh()

func _on_visibility_changed() -> void:
	if visible:
		_reset_cursor()
		refresh()

func _process(_delta: float) -> void:
	if not visible or _manager == null:
		return
	if Input.is_action_just_pressed("choose_left_button"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed("choose_right_button"):
		_move_cursor(1)

# ==================== 光标 ====================

func _owned() -> Array[int]:
	var out: Array[int] = []
	for prop in ORDER:
		if _manager.has_ability(prop):
			out.append(prop)
	return out

## 光标回到当前形态（没有就回到第一个持有的能力）
func _reset_cursor() -> void:
	var owned := _owned()
	if owned.is_empty():
		chosen = AbilityPoint.Property.none
		return
	var current := AbilityPoint.Property.none
	if _manager.player != null:
		current = PS.property_from_ability(_manager.player.ability)
	chosen = current if current in owned else owned[0]

func _move_cursor(dir: int) -> void:
	var owned := _owned()
	if owned.is_empty():
		chosen = AbilityPoint.Property.none
		refresh()
		return
	var i := owned.find(chosen)
	i = (i + dir + owned.size()) % owned.size()   # 循环
	chosen = owned[i]
	refresh()

## 确认当前光标选中的能力：切到该形态并关面板（由玩家按 X 时调用）
func confirm() -> void:
	if _manager == null:
		return
	var player: CharacterBody2D = _manager.player
	if chosen == AbilityPoint.Property.none or not _manager.choose_ability(chosen):
		# 没有可选项（一个能力都没拿到）：直接关面板
		if player != null:
			player.close_choose()
		return
	if player != null:
		player.close_choose()

# ==================== 显示 ====================

## 颜色优先级：光标 > 当前形态 > 普通
func refresh() -> void:
	if _manager == null or _manager.player == null:
		return
	var owned := _owned()
	if chosen not in owned:
		_reset_cursor()
	var current_prop: int = PS.property_from_ability(_manager.player.ability)
	_update_button(fish, AbilityPoint.Property.fish, current_prop)
	_update_button(bird, AbilityPoint.Property.bird, current_prop)
	_update_button(bear, AbilityPoint.Property.bear, current_prop)

func _update_button(btn: TextureRect, prop: int, current_prop: int) -> void:
	var owned: bool = _manager.has_ability(prop)
	btn.visible = owned                      # 没这个能力就藏起来
	if not owned:
		return
	if prop == chosen:
		btn.modulate = COLOR_CURSOR
	elif prop == current_prop:
		btn.modulate = COLOR_CURRENT
	else:
		btn.modulate = COLOR_DIM
	set_highlight(btn, prop == chosen or prop == current_prop)

## shader 高亮（按钮没挂材质时自动跳过）
func set_highlight(btn: TextureRect, on: bool) -> void:
	var mat := btn.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("highlight_strength", HIGHLIGHT if on else 0.0)
