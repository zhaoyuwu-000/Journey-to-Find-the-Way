extends Control
## 主菜单：寻路之旅 + 开始/设置/退出，用 sprite/ui 里的字体图，左半屏竖向均匀分布。

signal start_requested
signal settings_requested
signal continue_requested

const TINT_HOVER := Color(1.0, 0.94, 0.72)   # 悬停略微偏暖，不改原色

@onready var btn_start: TextureButton = $Left/VBox/StartWrap/BtnStart
@onready var btn_continue: Button = $Left/VBox/ContinueWrap/BtnContinue
@onready var btn_settings: TextureButton = $Left/VBox/SettingsWrap/BtnSettings
@onready var btn_quit: TextureButton = $Left/VBox/QuitWrap/BtnQuit
@onready var title: TextureRect = $Left/VBox/TitleWrap/Title

func _ready() -> void:
	_setup_continue_button()
	btn_start.pressed.connect(func() -> void: start_requested.emit())
	btn_continue.pressed.connect(func() -> void: continue_requested.emit())
	btn_settings.pressed.connect(func() -> void: settings_requested.emit())
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	# 用字体图本来的颜色，不做染色；悬停只做一点点提亮
	title.modulate = Color.WHITE
	for b in [btn_start, btn_settings, btn_quit]:
		b.modulate = Color.WHITE
		b.mouse_entered.connect(func() -> void: b.modulate = TINT_HOVER)
		b.mouse_exited.connect(func() -> void: b.modulate = Color.WHITE)
	btn_start.grab_focus()

## "继续游戏"没有对应字体图，用系统中文字体做成同款白字
func _setup_continue_button() -> void:
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		btn_continue.add_theme_stylebox_override(st, empty)
	btn_continue.add_theme_font_size_override("font_size", 31)
	btn_continue.add_theme_color_override("font_color", Color.WHITE)
	btn_continue.add_theme_color_override("font_hover_color", TINT_HOVER)
	btn_continue.add_theme_color_override("font_pressed_color", TINT_HOVER)
	btn_continue.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	for path in ["C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simsun.ttc"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(path) == OK:
			btn_continue.add_theme_font_override("font", f)
			break

## 有没有存档：没有就把"继续游戏"置灰
func set_continue_available(available: bool) -> void:
	btn_continue.disabled = not available
