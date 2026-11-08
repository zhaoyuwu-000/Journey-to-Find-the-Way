extends Node
## 背景音乐管理：
##  - 进入游戏/关卡：循环播放 character
##  - 拿到能力点：播放对应曲（bird/bear/fish）一遍
##  - 任何切换都要等当前曲播满 MIN_SECONDS 秒
##  - 一次性曲子播完（且已满一分钟）后淡出切回 character
## 切换用双播放器交叉淡入淡出。

const CHARACTER := preload("res://music/character.wav")
const TRACKS := {
	0: preload("res://music/bird.mp3"),
	1: preload("res://music/bear.mp3"),
	2: preload("res://music/fish.wav"),
}
const NAMES := ["bird", "bear", "fish"]

const MIN_SECONDS := 60.0      # 一首至少播这么久才允许切
const FADE := 1.2              # 交叉淡入淡出时长
const SILENT_DB := -60.0

var _players: Array[AudioStreamPlayer] = []
var _active: AudioStreamPlayer = null
var _current := ""             # character / bird / bear / fish
var _started := 0.0
var _pending := ""
var _busy_fade := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		p.finished.connect(_on_finished.bind(p))
		_players.append(p)
	_set_loop(CHARACTER, true)
	for k in TRACKS:
		_set_loop(TRACKS[k], false)

func _set_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			# loop_end 必须显式给帧数，默认 0 会导致播放卡在起点（没声音）
			w.loop_end = maxi(int(round(w.get_length() * float(w.mix_rate))), 1)
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

## 请求切到 character（受"至少一分钟"限制）
func play_character() -> void:
	_request("character")

## 强制立刻切到 character（进新关卡/新游戏时用）
func restart_character() -> void:
	_pending = ""
	_switch_now("character")

## 拿到能力点后调用：prop 是 AbilityPoint.Property（bird=0/bear=1/fish=2）
func play_ability(prop: int) -> void:
	if prop < 0 or prop >= NAMES.size():
		return
	_request(NAMES[prop])

func _request(name: String) -> void:
	if name == _current and _active != null and _active.playing:
		return
	_pending = name
	if _current == "":
		_switch_now(_pending)
		_pending = ""

func _process(_delta: float) -> void:
	if _pending == "" or _current == "":
		return
	if _now() - _started >= MIN_SECONDS and not _busy_fade:
		var target := _pending
		_pending = ""
		_switch_now(target)

func _switch_now(name: String) -> void:
	var stream: AudioStream
	if name == "character":
		stream = CHARACTER
	elif TRACKS.has(NAMES.find(name)):
		stream = TRACKS[NAMES.find(name)]
	else:
		return
	if stream == null:
		return

	var from := _active
	var to: AudioStreamPlayer
	if from == null:
		to = _players[0]
	else:
		to = _players[1] if from == _players[0] else _players[0]

	to.stream = stream
	to.volume_db = SILENT_DB
	to.play()
	_active = to
	_current = name
	_started = _now()

	_busy_fade = true
	var tw := create_tween()
	tw.set_parallel(true)
	if from != null and from.playing:
		tw.tween_property(from, "volume_db", SILENT_DB, FADE)
	tw.tween_property(to, "volume_db", 0.0, FADE)
	tw.chain().tween_callback(func() -> void:
		_busy_fade = false
		if from != null and from != to and not from.playing:
			from.stop())

func _on_finished(p: AudioStreamPlayer) -> void:
	if p != _active:
		return
	if _current == "character":
		p.play()          # 循环兜底
		return
	# 一次性曲子播完：没满一分钟就续播，满一分钟回 character
	if _now() - _started < MIN_SECONDS:
		p.play()
		return
	_pending = ""
	_switch_now("character")
