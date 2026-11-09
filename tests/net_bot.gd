extends Node
## Gerçek ENet üzerinden istemci testi. Roller: eski, ilk (Mühendis), ikinci (yarışçı).

var _role := ""
var _pid := 0
var _engineer := 0
var _placed := false
var _chatted := false
var _start_x := -1.0
var _members := 0
var _got_chat := false
var _part_seen := false
var _moved := false
var _ending := false


func _ready() -> void:
	var port := Net.DEFAULT_PORT
	var host := "127.0.0.1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rol="):
			_role = a.trim_prefix("--rol=")
		elif a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()
		elif a.begins_with("--adres="):
			host = a.trim_prefix("--adres=")
	if _role == "eski":
		Net.client_version = 0
	Net.joined.connect(func(pid: int, _code: String) -> void: _pid = pid; print("[%s] katıldı pid=%d" % [_role, pid]))
	Net.rejected.connect(_on_rejected)
	Net.connect_failed.connect(func(m: String) -> void: _finish(false, "bağlantı: " + m))
	Net.snap_received.connect(_on_snap)
	Net.event_received.connect(_on_event)
	Net.connect_to(host, port, "Bot_" + _role, "TEST", 2, 3)


func _on_rejected(message: String) -> void:
	_finish(_role == "eski", "eski sürüm reddedildi: " + message)


func _on_event(ev: Dictionary) -> void:
	match str(ev["t"]):
		"round":
			_engineer = ev["engineer"]
		"roster":
			_members = (ev["rows"] as Array).size()
			if _members >= 2 and not _chatted and _pid != 0:
				_chatted = true
				Net.send_chat("merhaba " + _role)
		"chat":
			if str(ev["name"]) != "Bot_" + _role:
				_got_chat = true
				print("OK   [%s] sohbet alındı: %s" % [_role, str(ev["text"])])
				_check_done()


func _on_snap(bytes: PackedByteArray) -> void:
	var snap := Arena.parse_snapshot(bytes)
	var eng: Dictionary = snap["eng"]
	if not eng.is_empty():
		_engineer = eng["pid"]
	if _engineer == _pid and _pid != 0:
		_engineer_turn(snap)
	else:
		_racer_turn(snap)


func _engineer_turn(snap: Dictionary) -> void:
	Net.send_input(0, Vector2(540, 200), Arena.Kind.BOX, 0)
	if not _placed:
		_placed = true
		Net.send_place(Arena.Kind.BOX, Vector2(540, 200), 0)
		Net.send_place(Arena.Kind.BOX, Vector2(200, 650), 0)
	if not _part_seen and not (snap["parts"] as Dictionary).is_empty():
		_part_seen = true
		print("OK   [%s] Mühendisin parçası snapshot'ta görüldü" % _role)
		_check_done()


func _racer_turn(snap: Dictionary) -> void:
	Net.send_input(Arena.RIGHT, Vector2.ZERO, 0, 0)
	var bots: Dictionary = snap["robots"]
	if not bots.has(_pid):
		return
	var x: float = bots[_pid]["pos"].x
	if _start_x < 0.0:
		_start_x = x
	if not _moved and x > _start_x + 40.0:
		_moved = true
		print("OK   [%s] sunucu tuşları işliyor, robot %.0f px ilerledi" % [_role, x - _start_x])
		_check_done()


func _check_done() -> void:
	var role_done := _part_seen if _role == "ilk" else _moved
	if role_done and _got_chat:
		_finish(true, "tamam")


func _finish(ok: bool, message: String) -> void:
	if _ending:
		return
	_ending = true
	print("%s [%s] %s" % ["OK  " if ok else "HATA", _role, message])
	# Karşı taraf kendi denetimini bitirene kadar bağlı kal.
	await get_tree().create_timer(1.5).timeout
	Net.leave()
	get_tree().quit(0 if ok else 1)
