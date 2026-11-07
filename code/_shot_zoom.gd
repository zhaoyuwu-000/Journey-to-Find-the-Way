extends SceneTree
## temp: 摄像机 zoom=0.4 画面截图。delete after。

func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	for i in 8:
		await process_frame
	root.get_node("Save").clear()
	var game: Node = load("res://scene/game_root.tscn").instantiate()
	root.add_child(game)
	for i in 40:
		await process_frame
	game._on_menu_start()
	await create_timer(0.6).timeout
	var cam: Camera2D = game.current_level_node.get_node("Camera2D")
	print("level1 camera zoom=", cam.zoom)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/project/demo/screenshots/zoom_04.png")
	print("saved")
	quit(0)
