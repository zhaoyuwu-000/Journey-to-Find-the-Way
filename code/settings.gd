extends Node
## 设置：只有音乐音量和音效音量两项。存到 user://settings.json，启动时套到音频总线上。

const PATH := "user://settings.json"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var music := 1.0
var sfx := 1.0

func _ready() -> void:
	load_settings()
	apply()

func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		music = clampf(float(parsed.get("music", music)), 0.0, 1.0)
		sfx = clampf(float(parsed.get("sfx", sfx)), 0.0, 1.0)

func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Settings: 无法写入 %s" % PATH)
		return
	f.store_string(JSON.stringify({"music": music, "sfx": sfx}, "\t"))
	f.close()

func set_music(v: float) -> void:
	music = clampf(v, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, music)
	save_settings()

func set_sfx(v: float) -> void:
	sfx = clampf(v, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx)
	save_settings()

func apply() -> void:
	_apply_bus(MUSIC_BUS, music)
	_apply_bus(SFX_BUS, sfx)

func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
