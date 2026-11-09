extends Node
## Görsel kontrol: menüyü ve her haritayı user:// altına PNG olarak kaydeder.

const OUT := "user://foto_%s.png"


func _ready() -> void:
	_run()


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT % label
	get_viewport().get_texture().get_image().save_png(path)
	print("[foto] ", ProjectSettings.globalize_path(path))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var menu := Menu.new()
	add_child(menu)
	await _wait(0.5)
	await _shot("menu")
	menu.queue_free()
	await get_tree().process_frame
	for index in Maps.all().size():
		await _map_shot(index)
	await _engineer_shot()
	get_tree().quit()


func _map_shot(index: int) -> void:
	var view := GameView.new()
	view.start_offline("Eren", 4, 1)
	add_child(view)
	var a := view.arena()
	a.fixed_map = index
	a.no_engineer = true
	a.start_round(index)
	await _wait(0.4)
	a.skip_countdown()
	await _wait(2.2)
	await _shot("harita%d" % index)
	view.queue_free()
	await get_tree().process_frame


func _engineer_shot() -> void:
	var view := GameView.new()
	view.start_offline("Eren", 6, 3)
	add_child(view)
	var a := view.arena()
	a.fixed_map = 0
	a.force_engineer = view._my_pid
	a.no_engineer = false
	a.start_round(0)
	await _wait(0.3)
	a.skip_countdown()
	await _wait(0.3)
	a.try_place(view._my_pid, Arena.Kind.LONG_PLANK, Vector2(540, 552), 0)
	await _wait(0.4)
	a.try_place(view._my_pid, Arena.Kind.BOX, Vector2(760, 300), 0)
	await _wait(0.4)
	a.try_place(view._my_pid, Arena.Kind.SPRING, Vector2(320, 551), 0)
	await _wait(0.4)
	view._kind = Arena.Kind.PLANK
	view._rot = 30
	get_viewport().warp_mouse(Vector2(640, 330))
	await _wait(0.4)
	await _shot("muhendis")
	var result_view := view
	a.force_engineer = -1
	a.robots.values()[1].score = 17
	for r: Arena.Robot in a.robots.values():
		if r.life == Arena.Life.RACING:
			a._kill(r)
	result_view._show_toast("Örnek uyarı")
	await _wait(0.5)
	await _shot("sonuc")
	view.queue_free()
