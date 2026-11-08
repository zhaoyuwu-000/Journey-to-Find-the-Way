extends Node2D
## 第六关结尾：玩家向前走时，用原来的对话框匀速播放文字。
## 向前移动时匀速换句（每 sec_per_line 秒一句），停下文字就停。
## 内容默认取 data/dialogues.json 的 ending.goldball.first；可用 custom_lines 覆盖（每行一句）。

@export_multiline var custom_lines := ""
@export var sec_per_line := 1.6       # 每句停留秒数（只在向前移动时计时）
@export var require_right_move := true
@export var first_delay := 0.6        # 进关后第一句延迟

var _lines: Array[String] = []
var _i := -1
var _t := 0.0
var _done := false
var _player: Node2D
var _last_x := 0.0
var _dlg: Node

func _ready() -> void:
	_dlg = get_node_or_null("/root/Dialogue")
	_lines = _read_lines()
	await get_tree().process_frame
	_player = _find_player()
	if _player != null:
		_last_x = _player.global_position.x
	await get_tree().create_timer(first_delay).timeout
	_show_next()

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
	return parent.get_node_or_null("Player") as Node2D

func _show_next() -> void:
	_i += 1
	if _i >= _lines.size():
		_done = true
		if _dlg != null and _dlg.has_method("fade_out_manual"):
			_dlg.fade_out_manual()
		return
	if _dlg != null and _dlg.has_method("show_line_manual"):
		_dlg.show_line_manual(_lines[_i])

func _process(delta: float) -> void:
	if _done or _player == null:
		return
	var x := _player.global_position.x
	var dx := x - _last_x
	_last_x = x
	if require_right_move and dx <= 0.2:
		return
	_t += delta
	while _t >= sec_per_line and not _done:
		_t -= sec_per_line
		_show_next()
