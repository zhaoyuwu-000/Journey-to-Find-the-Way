extends Node
## 对话系统（autoload "Dialogue"）：JSON 记录台词，只有 NPC 说话。
## 第一次进入某个对话：播 first 整段流程；之后进入：从 pool 随机一句。
## 播放期间锁住玩家控制。

signal started
signal finished

const DATA_PATH := "res://data/dialogues.json"
const BOX := preload("res://code/dialogue_box.gd")

var _data: Dictionary = {}
var _seen: Dictionary = {}      # 对话 key -> 已经播过 first
var _box: Control = null
var _player: Node = null
var _playing := false
var _locked := false
var _voice_cat := ""              # 对话对应的动物音效分类（鸟/熊/鱼）
var _voice_t := 0.0

func _ready() -> void:
	_data = _read_json(DATA_PATH)
	var layer := CanvasLayer.new()
	layer.layer = 40               # 盖在关卡 UI 上面
	add_child(layer)
	_box = BOX.new()
	layer.add_child(_box)
	_box.visible = false
	_box.finished.connect(_on_finished)

func is_playing() -> bool:
	return _playing

## 已经播过 first 的对话 key（给关卡检查点/存档用）
func snapshot() -> Dictionary:
	return _seen.duplicate()

## 恢复"哪些对话已经播过"
func restore(state: Dictionary) -> void:
	_seen.clear()
	for k in state:
		_seen[str(k)] = true

## 播一段对话；key 形如 "level1.bird"。返回是否真的开始播。
func play(key: String, player: Node = null) -> bool:
	if _playing:
		return false
	# 玩家已经被别的系统锁着（能力选择面板、菜单等）时别插话，否则确认键会被对话吃掉
	if player != null and player.get("can_be_controlled") == false:
		return false
	var entry := _entry(key)
	if entry.is_empty():
		return false
	var lines: Array = []
	var first: Array = entry.get("first", [])
	var is_first := first.size() > 0 and not _seen.has(key)
	if is_first:
		_seen[key] = true
		lines = first
	else:
		var pool: Array = entry.get("pool", [])
		if pool.is_empty():
			return false
		lines = [pool[randi() % pool.size()]]
	_playing = true
	_player = player
	_locked = is_first          # 只有第一次的整段流程才锁玩家，之后照样能走
	if _locked:
		_set_player_control(false)
	_box.show_lines(str(entry.get("speaker", "")), lines, not is_first)
	# 对话属于哪种动物：key 形如 level1.bird / level2.bear / level3.fish
	_voice_cat = ""
	for suffix in [["bird", "鸟"], ["bear", "熊"], ["fish", "鱼"]]:
		if key.to_lower().ends_with("." + suffix[0]):
			_voice_cat = suffix[1]
			break
	_voice_t = 0.0
	started.emit()
	return true

func _process(delta: float) -> void:
	# 对话持续期间隔一会儿叫一声（鸟/熊/鱼）
	if not _playing or _voice_cat == "":
		return
	_voice_t -= delta
	if _voice_t > 0.0:
		return
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(_voice_cat, -4.0, 0.12)
	_voice_t = 1.6

func _on_finished() -> void:
	_playing = false
	_voice_cat = ""
	# 结束就一定解除本次锁定，避免出现"对话完了人不能动"
	if _player != null and is_instance_valid(_player):
		if _player.get("can_be_controlled") != null:
			_player.can_be_controlled = true
		# 万一还卡在能力选择面板里，一并关掉（close_choose 只在 CHOOSE 状态生效）
		if _player.has_method("close_choose"):
			_player.close_choose()
	_locked = false
	_player = null
	finished.emit()

func _set_player_control(on: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("can_be_controlled") != null:
		_player.can_be_controlled = on

func _entry(key: String) -> Dictionary:
	var node: Variant = _data
	for part in key.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return {}
		node = (node as Dictionary)[part]
	return node if node is Dictionary else {}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Dialogue: 找不到 %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Dialogue: %s 解析失败" % path)
		return {}
	return parsed
