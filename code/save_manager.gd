extends Node
## 存档：只记"最后一次复活点"的状态（关卡、复活坐标、能力）。
## 存到 user://save.json；进入游戏时 GameRoot 会读它并把关卡恢复到该状态。

const PATH := "user://save.json"

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func write(data: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save: 无法写入 %s" % PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func read() -> Dictionary:
	if not has_save():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
