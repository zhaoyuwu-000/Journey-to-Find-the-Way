extends CanvasLayer
## 第六关结尾：玩家向前走时匀速显示文字。
## 内容默认取 data/dialogues.json 的 ending.goldball.first；也可以在 Inspector 里用 custom_lines 覆盖（每行一句）。
## 只有向右前进才推进（speed = 每秒显示几个字），停下来文字就停。

@export_multiline var custom_lines := ""      # 非空则用它，按换行拆行
@export var chars_per_sec := 9.0              # 匀速：每秒显示字数
@export var hold_sec := 1.4                   # 一句显示完后的停顿
@export var require_right_move := true        # 只在前右移动时推进

var _lines: Array[String] = []
var _i := 0
var _shown := 0.0
var _hold := 0.0
var _done := false
var _label: Label
var _player: Node2D
var _last_x := 0.0

func _ready() -> void:
	_label = get_node_or_null("Root/Label") as Label
	if _label == null:
		return
	_label.text = ""
	_label.modulate.a = 0.0
	_lines = _read_lines()
	await get_tree().process_frame
	_player = _find_player()
	if _player != null:
		_last_x = _player.global_position.x
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, 0.8)

func _read_lines() -> Array[String]:
	var out: Array[String] = []
	if custom_lines.strip_edges() != "":
		for s in custom_lines.split("\n", false):
			if s.strip_edges() != "":
				out.append(s.strip_edges())
		return out
	var path := "res://data/dialogues.json"
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var ending: Dictionary = (data as Dictionary).get("ending", {})
	var gold: Dictionary = ending.get("goldball", {})
	for s in gold.get("first", []):
		out.append(str(s))
	return out

func _find_player() -> Node2D:
	var parent := get_parent()
	if parent == null:
		return null
	var p := parent.get_node_or_null("Player")
	return p as Node2D

func _process(delta: float) -> void:
	if _done or _label == null or _player == null or _lines.is_empty():
		return
	var x := _player.global_position.x
	var dx := x - _last_x
	_last_x = x
	if require_right_move and dx <= 0.2:
		return
	if _hold > 0.0:
		_hold = maxf(_hold - delta, 0.0)
		return
	var line := _lines[_i]
	_shown += chars_per_sec * delta
	var n := mini(int(_shown), line.length())
	_label.text = line.substr(0, n)
	if n >= line.length():
		_i += 1
		_shown = 0.0
		_hold = hold_sec
		if _i >= _lines.size():
			_done = true
			var tw := create_tween()
			tw.tween_interval(2.0)
			tw.tween_property(_label, "modulate:a", 0.0, 1.5)
