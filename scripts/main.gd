extends Node
## Giriş noktası: menü ile oyun ekranı arasında geçiş yapar, sunucu ve test
## kiplerini komut satırından başlatır.

var _current: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--sunucu" in args:
		_run_server(args)
	elif "--test-sim" in args:
		_start_tool("res://tests/test_sim.gd")
	elif "--test-bot" in args:
		_start_tool("res://tests/net_bot.gd")
	elif "--foto" in args:
		_start_tool("res://tests/foto.gd")
	else:
		show_menu()


## Test betiği derlenemezse Godot açık kalıp testi sonsuza dek bekletmesin.
func _start_tool(path: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Betik yüklenemedi: " + path)
		get_tree().quit(1)
		return
	add_child(script.new())


func _run_server(args: PackedStringArray) -> void:
	var port := Net.DEFAULT_PORT
	for a in args:
		if a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()
		elif a == "--botsuz":
			Net.min_robots = 0
		elif a == "--ilk-muhendis":
			Net.first_is_engineer = true
	var err := Net.start_server(port)
	if err != OK:
		push_error("Sunucu port %d üzerinde açılamadı (hata %d)" % [port, err])
		get_tree().quit(1)


func _swap(node: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = node
	add_child(node)


func show_menu(message := "") -> void:
	var menu := Menu.new()
	menu.notice = message
	menu.play_offline.connect(_on_play_offline)
	menu.play_online.connect(_on_play_online)
	_swap(menu)


func _on_play_offline(player_name: String, color: int, acc: int) -> void:
	var view := GameView.new()
	view.finished.connect(show_menu)
	view.start_offline(player_name, color, acc)
	_swap(view)


func _on_play_online(pid: int, code: String) -> void:
	var view := GameView.new()
	view.finished.connect(show_menu)
	view.start_online(pid, code)
	_swap(view)
