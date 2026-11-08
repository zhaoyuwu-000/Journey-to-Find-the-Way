extends Control
## 顶部对话框：椭圆渐淡背景 + 居中白字。只有 NPC 说话，点击/空格/回车下一句。

signal finished

const FADE_SHADER := preload("res://shaders/dialogue_fade.gdshader")
const BAND_H := 260.0
## 系统里现成的中文字体（导出的包读不到项目外的字体时再补字体文件进项目）
const FONT_PATHS := [
	"C:/Windows/Fonts/simhei.ttf",
	"C:/Windows/Fonts/msyh.ttc",
	"C:/Windows/Fonts/simsun.ttc",
]

var _text_label: Label
var _hint: Label
var _bg: ColorRect
var _lines: Array = []
var _index := 0
var _fading := false
var _target_alpha := 0.0
var _manual := false      # 手动模式：由外部控制显示/淡出，不响应按键、不自动计时
var _auto := false        # 自动播放（对话池随机一句）：自己淡入淡出，不需要按键
var _auto_timer := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = BAND_H
	custom_minimum_size = Vector2(0, BAND_H)

	# 椭圆软边底：颜色/透明度在 shader 里调
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bg.offset_bottom = BAND_H
	var mat := ShaderMaterial.new()
	mat.shader = FADE_SHADER
	_bg.material = mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.anchor_left = 0.0
	_text_label.anchor_right = 1.0
	_text_label.anchor_bottom = 1.0   # 纵向铺满对话框，靠 vertical_alignment 居中
	_text_label.offset_left = 120
	_text_label.offset_right = -120
	_text_label.offset_top = 0
	_text_label.offset_bottom = 0
	_text_label.add_theme_font_size_override("font_size", 34)
	_text_label.add_theme_color_override("font_color", Color(1, 1, 1))
	# 半透明底上白字加一点阴影，亮背景也能看清
	_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_text_label.add_theme_constant_override("shadow_offset_x", 2)
	_text_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_text_label)

	_hint = Label.new()
	_hint.text = "空格 / 点击 继续"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -46
	_hint.offset_bottom = -14
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hint)

	_apply_font()

## 背景透明度（0~1 里越低越透）
func set_bg_alpha(a: float) -> void:
	if _bg != null and _bg.material is ShaderMaterial:
		(_bg.material as ShaderMaterial).set_shader_parameter("tint", Color(0.04, 0.09, 0.08, a))

func _apply_font() -> void:
	for path in FONT_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(path) != OK:
			continue
		for lb in [_text_label, _hint]:
			lb.add_theme_font_override("font", f)
		return

## 从第一句开始播（淡入）；auto_mode=true 时自己淡出，不等按键
func show_lines(_speaker: String, lines: Array, auto_mode := false) -> void:
	_lines = lines
	_index = 0
	_auto = auto_mode
	_auto_timer = _auto_duration(str(_lines[0]))
	_text_label.text = str(_lines[0]) if _lines.size() > 0 else ""
	visible = true
	_fading = false
	modulate.a = 0.0
	_target_alpha = 1.0

## 自动播放时停留多久（按字数给一点时间，1.8~4.5 秒）
func _auto_duration(text: String) -> float:
	return clampf(1.5 + float(text.length()) * 0.12, 1.8, 4.5)

func _input(event: InputEvent) -> void:
	if not visible or _auto or _manual:
		return
	var advance := false
	if event is InputEventKey:
		advance = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		advance = event.pressed
	elif event is InputEventScreenTouch:
		advance = event.pressed
	if advance:
		_next()
		get_viewport().set_input_as_handled()

func _next() -> void:
	if _fading:
		return
	_index += 1
	if _index >= _lines.size():
		_lines = []
		_fading = true
		_fade_out()
		return
	_text_label.text = str(_lines[_index])

## 淡出（由 _process 推，淡到 0 才隐藏并通知结束）
func _fade_out() -> void:
	_target_alpha = 0.0

## 手动模式：只显示一句，不自动淡出、不响应按键（走路播字用）
func show_line_manual(text: String) -> void:
	_lines = [text]
	_index = 0
	_manual = true
	_auto = false
	_fading = false
	_text_label.text = text
	visible = true
	modulate.a = 0.0
	_target_alpha = 1.0

## 手动模式：淡出并结束
func fade_out_manual() -> void:
	if not _manual:
		return
	_manual = false
	_fading = true
	_target_alpha = 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	modulate.a = move_toward(modulate.a, _target_alpha, delta / 0.18)
	if _auto and not _fading and modulate.a >= 0.99:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_fading = true
			_target_alpha = 0.0
	if _fading and modulate.a <= 0.001:
		visible = false
		_fading = false
		finished.emit()
