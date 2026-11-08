extends Node
## 音效播放：按"音效/分类"目录随机挑一个播放。
## 分类目录：跳跃、落地、走在草丛、掉落、复活、泡泡、飞行、推动石头、变光点、鸟、熊、鱼

const ROOT_DIR := "res://音效"
const POOL_SIZE := 10

var _cats: Dictionary = {}                      # 分类 -> Array[AudioStream]
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last: Dictionary = {}                       # 分类 -> 上次播放时间（节流用）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_scan()

func _scan() -> void:
	var dir := DirAccess.open(ROOT_DIR)
	if dir == null:
		push_warning("Sfx: 找不到目录 %s" % ROOT_DIR)
		return
	for cat in dir.get_directories():
		var sub := DirAccess.open(ROOT_DIR + "/" + cat)
		if sub == null:
			continue
		var list: Array[AudioStream] = []
		for f in sub.get_files():
			var ext := f.get_extension().to_lower()
			if ext != "mp3" and ext != "wav" and ext != "ogg":
				continue
			var stream := load(ROOT_DIR + "/" + cat + "/" + f) as AudioStream
			if stream != null:
				list.append(stream)
		if not list.is_empty():
			_cats[cat] = list

## 播放某分类里的随机音效（volume_db 相对值，pitch_var 音高随机抖动）
func play(cat: String, volume_db := 0.0, pitch_var := 0.05, min_gap := 0.03) -> void:
	if not _cats.has(cat) or _players.is_empty():
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if min_gap > 0.0 and now - float(_last.get(cat, -99.0)) < min_gap:
		return
	_last[cat] = now
	var list: Array = _cats[cat]
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

## 某个分类有几个音效（调试/验证用）
func count(cat: String) -> int:
	return (_cats[cat] as Array).size() if _cats.has(cat) else 0
