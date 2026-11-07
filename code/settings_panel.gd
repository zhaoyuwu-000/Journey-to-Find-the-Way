extends Control
## 设置面板：只有音乐音量 / 音效音量两个滑条。浅色底 + 小字号。

const LABEL_MUSIC := preload("res://sprite/ui/字体（音乐）.png")
const LABEL_SFX := preload("res://sprite/ui/字体（音效）.png")
const FONT_PATHS := ["C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simsun.ttc"]

const PANEL_W := 720.0
const PANEL_H := 400.0
const INK := Color(0.24, 0.34, 0.30)     # 浅底上的深色字

var _dim: ColorRect
var _panel: Panel
var _music_slider: HSlider
var _sfx_slider: HSlider

signal closed

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.96, 0.92, 0.96)
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.70, 0.60, 0.9)
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_music_slider = _make_row(LABEL_MUSIC, Rect2(194, 663, 542, 270), 84.0)
	_sfx_slider = _make_row(LABEL_SFX, Rect2(407, 829, 559, 276), 212.0)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(160, 54)
	back.position = Vector2(PANEL_W * 0.5 - 80, PANEL_H - 84)
	back.add_theme_font_size_override("font_size", 26)
	back.add_theme_color_override("font_color", INK)
	back.add_theme_color_override("font_hover_color", Color(0.12, 0.2, 0.16))

	_panel.add_child(back)
	_apply_light_button(back)
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())

	var quit_btn := Button.new()
	quit_btn.text = "退出游戏"
	quit_btn.custom_minimum_size = Vector2(160, 54)
	quit_btn.position = Vector2(PANEL_W * 0.5 + 92, PANEL_H - 84)
	quit_btn.add_theme_font_size_override("font_size", 26)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	_panel.add_child(quit_btn)
	_apply_light_button(quit_btn)

	_sync_from_settings()
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

## 打开时重新算一次尺寸/居中
func open() -> void:
	_sync_from_settings()
	_layout()
	visible = true

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = vp
	_dim.size = vp
	_dim.position = Vector2.ZERO
	_panel.position = (vp - _panel.size) * 0.5

func _make_row(tex: Texture2D, region: Rect2, y: float) -> HSlider:
	var lab := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	lab.texture = at
	lab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lab.stretch_mode = TextureRect.STRETCH_SCALE
	lab.modulate = INK                      # 白色字压在浅底上要压暗
	lab.position = Vector2(70, y + 6)
	lab.size = Vector2(150, 75)
	_panel.add_child(lab)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.position = Vector2(258, y + 26)
	slider.size = Vector2(330, 36)
	slider.value_changed.connect(func(v: float) -> void:
		var st := get_node_or_null("/root/Settings")
		if st == null:
			return
		if slider == _music_slider:
			st.set_music(v)
		else:
			st.set_sfx(v))
	_panel.add_child(slider)
	return slider

func _sync_from_settings() -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return
	_music_slider.value = st.music
	_sfx_slider.value = st.sfx

func _apply_font(button: Button) -> void:
	for path in FONT_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(path) != OK:
			continue
		button.add_theme_font_override("font", f)
		return

func _apply_light_button(btn: Button) -> void:
	btn.add_theme_color_override("font_color", INK)
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.2, 0.16))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.2, 0.16))
	for state in ["normal", "hover", "pressed", "focus"]:
		var bs := StyleBoxFlat.new()
		var tone := Color(0.90, 0.93, 0.86)
		if state == "hover":
			tone = Color(0.96, 0.98, 0.92)
		elif state == "pressed":
			tone = Color(0.82, 0.87, 0.78)
		bs.bg_color = tone
		bs.set_corner_radius_all(14)
		bs.set_border_width_all(2)
		bs.border_color = Color(0.62, 0.70, 0.60)
		bs.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, bs)
