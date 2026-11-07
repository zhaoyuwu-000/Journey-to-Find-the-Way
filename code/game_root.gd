extends Node
## 常驻流程根

const SETTINGS_PANEL := preload("res://code/settings_panel.gd")

const LEVELS := [
	"res://scene/levels/level1.tscn",
	"res://scene/levels/level2.tscn",
	"res://scene/levels/level3.tscn",
	"res://scene/levels/level4.tscn",
	"res://scene/levels/level5.tscn",
]

@onready var level_container: Node2D = $LevelContainer

@export var player_can_be_controlled : bool = false

var _settings_panel: Control = null
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _transitioning := false
var _settings_locked := false
var current_level := -1
var current_level_node: Node2D

func _ready() -> void:
	_setup_fade()
	goto_level(0)      # 进来先进第一关，读档由菜单的"继续游戏"负责
	init_menu()

## 全屏黑幕：切关时淡出/淡入
func _setup_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vp := get_viewport().get_visible_rect().size
	_fade_rect.size = vp
	get_viewport().size_changed.connect(func() -> void: _fade_rect.size = get_viewport().get_visible_rect().size)
	_fade_layer.add_child(_fade_rect)

func _fade_to(alpha: float, sec: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", alpha, sec)
	await tw.finished

## 带淡入淡出的切关（淡出→换关→淡入）
func _goto_level_faded(index: int, save_data: Dictionary = {}) -> void:
	if _transitioning:
		return
	_transitioning = true
	var player := _get_player()
	if player != null:
		player.can_be_controlled = false
	await _fade_to(1.0, 0.25)
	goto_level(index)
	if not save_data.is_empty() and current_level_node != null and current_level_node.has_method("apply_save"):
		current_level_node.apply_save(save_data)
	await get_tree().process_frame
	var player2 := _get_player()
	if player2 != null:
		player2.can_be_controlled = true
	await _fade_to(0.0, 0.35)
	_transitioning = false

## 有存档就从上次复活点继续，否则从头开始
func _restore_or_start() -> void:
	var save_node := get_node_or_null("/root/Save")
	var data: Dictionary = save_node.read() if save_node != null else {}
	if data.is_empty():
		goto_level(0)
		return
	goto_level(int(data.get("level", 0)))
	if current_level_node != null and current_level_node.has_method("apply_save"):
		current_level_node.apply_save(data)

func _process(delta: float) -> void:
	pass

##主菜单
func init_menu() -> void:
	var menu := get_node_or_null("UI/Menu")
	if menu == null:
		return
	# 菜单显示期间玩家不能操作
	var player := _get_player()
	if player != null:
		player.can_be_controlled = false
	menu.start_requested.connect(_on_menu_start)
	menu.settings_requested.connect(_on_menu_settings)
	menu.continue_requested.connect(_on_menu_continue)
	var sv := get_node_or_null("/root/Save")
	menu.set_continue_available(sv != null and sv.has_save())
	# 设置面板挂在 UI 层，默认隐藏
	var ui := get_node_or_null("UI")
	if ui != null and _settings_panel == null:
		_settings_panel = SETTINGS_PANEL.new()
		ui.add_child(_settings_panel)
		_settings_panel.closed.connect(_on_settings_closed)

func _on_settings_closed() -> void:
	if _settings_locked:
		_settings_locked = false
		var menu := get_node_or_null("UI/Menu")
		var menu_open: bool = menu != null and menu.visible
		var player := _get_player()
		if player != null and not menu_open:
			player.can_be_controlled = true

func _on_menu_start() -> void:
	_new_game()

## 新开一局：清存档、清对话记录、从第一关重新开始
func _new_game() -> void:
	var sv := get_node_or_null("/root/Save")
	if sv != null:
		sv.clear()
	var dlg := get_node_or_null("/root/Dialogue")
	if dlg != null:
		dlg.restore({})
	_hide_menu_and_play()
	goto_level(0)      # 开始游戏不淡入淡出
	var p := _get_player()
	if p != null:
		p.can_be_controlled = true

## 继续游戏：读档回到上次复活点；没有存档就当新开
func _on_menu_continue() -> void:
	var sv := get_node_or_null("/root/Save")
	var data: Dictionary = sv.read() if sv != null else {}
	if data.is_empty():
		_new_game()
		return
	_hide_menu_and_play()
	await _goto_level_faded(int(data.get("level", 0)), data)

func _hide_menu_and_play() -> void:
	var menu := get_node_or_null("UI/Menu")
	if menu != null:
		menu.hide()
	var player := _get_player()
	if player != null:
		player.can_be_controlled = true

func _on_menu_settings() -> void:
	if _settings_panel != null:
		_settings_panel.open()

## Esc 回到主菜单
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_settings()

## Esc / 菜单按钮：打开设置面板并把玩家停下来；再按一次收起
func toggle_settings() -> void:
	if _settings_panel == null:
		return
	if _settings_panel.visible:
		_close_settings()
	else:
		_settings_panel.open()
		var player := _get_player()
		if player != null:
			player.can_be_controlled = false
		_settings_locked = true

func _close_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false
	if _settings_locked:
		_settings_locked = false
		var menu := get_node_or_null("UI/Menu")
		var menu_open: bool = menu != null and menu.visible
		var player := _get_player()
		if player != null and not menu_open:
			player.can_be_controlled = true

func show_menu() -> void:
	var menu := get_node_or_null("UI/Menu")
	if menu == null:
		return
	menu.show()
	var player := _get_player()
	if player != null:
		player.can_be_controlled = false

func _get_player() -> CharacterBody2D:
	if current_level_node == null:
		return null
	return current_level_node.get_node_or_null("Player") as CharacterBody2D

## 切到第 index 关：清掉旧关卡，实例化新关卡放进 LevelContainer。
func goto_level(index: int) -> void:
	index = clampi(index, 0, LEVELS.size() - 1)
	_clear_level()
	current_level = index
	current_level_node = load(LEVELS[index]).instantiate()
	level_container.add_child(current_level_node)

func next_level() -> void:
	if current_level + 1 < LEVELS.size():
		await _goto_level_faded(current_level + 1)

func restart_level() -> void:
	await _goto_level_faded(current_level)

func _clear_level() -> void:
	if current_level_node == null:
		return
	level_container.remove_child(current_level_node)
	current_level_node.queue_free()
	current_level_node = null
