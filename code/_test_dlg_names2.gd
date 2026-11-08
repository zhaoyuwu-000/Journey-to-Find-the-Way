extends SceneTree
## temp: 各关能力点 名字→对话 检查。delete after。

func _initialize() -> void:
	_run()

func _check(level_path: String) -> void:
	var level: Node = load(level_path).instantiate()
	root.add_child(level)
	for i in 20:
		await process_frame
	var dlg: Node = root.get_node("Dialogue")
	print("=== ", level_path.get_file(), " ===")
	for c in get_nodes_in_group("abilitypoints"):
		if c.get_parent() != level:
			continue
		var key: String = c.dialogue_id if c.dialogue_id != "" else c._auto_dialogue_id()
		var exists: bool = not dlg._entry(key).is_empty()
		print("  %-16s 类型=%s  ->  %-18s 对话=%s" % [c.name, c.property, key, "有" if exists else "缺"])
	root.remove_child(level)
	level.queue_free()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for i in 8:
		await process_frame
	for lv in ["level1", "level2", "level3", "level4", "level5"]:
		await _check("res://scene/levels/%s.tscn" % lv)
	quit(0)
