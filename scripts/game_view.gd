class_name GameView
extends Control
## Oyun ekranı: çizim, tuşlar ve arayüz. Botlu oyunda Arena burada döner,
## online oyunda durum Net üzerinden gelir; ikisi de aynı snapshot yolunu kullanır.

signal finished(message: String)

const ONLINE_DELAY_TICKS := 5.0
const SLOT_SIZE := Vector2(76, 66)
const SLOT_GAP := 6.0
const TOOLBAR_Y := 646.0
const ROTATE_STEP := 15
const CHAT_KEEP := 6

var _arena: Arena
var _online := false
var _room_code := ""
var _my_pid := 0
var _roster: Dictionary = {}
var _map: Dictionary = {}
var _terrain: Array = []
var _engineer := 0
var _latest: Dictionary = {}
var _snaps: Array[Dictionary] = []
var _clock := -1.0
var _robot_frame: Dictionary = {}
var _part_frame: Dictionary = {}
var _own_pos := Vector2.ZERO
var _own_ready := false
var _time := 0.0
var _kind := 0
var _rot := 0
var _particles: Array[Dictionary] = []
var _banner := ""
var _banner_time := 0.0
var _toast := ""
var _toast_time := 0.0
var _chat_lines: Array[String] = []
var _result_rows: Array = []
var _seen_parts: Dictionary = {}
var _last_count := -1
var _sfx: Sfx
var _chat: LineEdit


func start_offline(player_name: String, color: int, acc: int) -> void:
	_arena = Arena.new()
	_arena.min_robots = 4
	_my_pid = _arena.add_player(player_name, color, acc)
	_arena.start_round(0)


func start_online(pid: int, code: String) -> void:
	_online = true
	_my_pid = pid
	_room_code = code
	Net.snap_received.connect(_on_snapshot)
	Net.event_received.connect(_handle_event)
	Net.disconnected.connect(_on_disconnected)


func arena() -> Arena:
	return _arena


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sfx = Sfx.new()
	add_child(_sfx)
	_chat = LineEdit.new()
	_chat.position = Vector2(14, 610)
	_chat.size = Vector2(420, 34)
	_chat.max_length = Net.MAX_CHAT
	_chat.placeholder_text = "Mesajını yaz, Enter ile gönder"
	_chat.visible = false
	_chat.text_submitted.connect(_on_chat_submit)
	add_child(_chat)


func _exit_tree() -> void:
	if _online:
		Net.snap_received.disconnect(_on_snapshot)
		Net.event_received.disconnect(_handle_event)
		Net.disconnected.disconnect(_on_disconnected)
	if _arena != null:
		_arena.dispose()


func _on_disconnected() -> void:
	finished.emit("Sunucuyla bağlantı koptu.")


# --- Girdi ---

func _is_engineer() -> bool:
	return _engineer != 0 and _engineer == _my_pid


func _collect_mask() -> int:
	if _chat.visible:
		return 0
	var mask := 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		mask |= Arena.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		mask |= Arena.RIGHT
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_SPACE):
		mask |= Arena.JUMP
	if Input.is_physical_key_pressed(KEY_R):
		mask |= Arena.SELF_DESTRUCT
	if Input.is_physical_key_pressed(KEY_SHIFT):
		mask |= Arena.CLIMB
	return mask


func _physics_process(_delta: float) -> void:
	var mask := _collect_mask()
	var aim := get_local_mouse_position()
	if _online:
		Net.send_input(mask, aim, _kind, _rot)
		return
	_arena.set_input(_my_pid, mask, aim, _kind, _rot)
	_arena.step()
	for ev in _arena.drain_events():
		_handle_event(ev)
	_on_snapshot(_arena.snapshot())


func _input(event: InputEvent) -> void:
	if _chat.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
	elif event is InputEventMouseButton and event.pressed and _is_engineer():
		_on_mouse(event)


func _on_key(event: InputEventKey) -> void:
	match event.physical_keycode:
		KEY_ESCAPE:
			_leave()
		KEY_ENTER, KEY_KP_ENTER:
			_chat.visible = true
			_chat.grab_focus()
			get_viewport().set_input_as_handled()
		KEY_Q:
			_rot = posmod(_rot - ROTATE_STEP, 360)
		KEY_E:
			_rot = posmod(_rot + ROTATE_STEP, 360)
		_:
			var index: int = event.physical_keycode - KEY_1
			if index >= 0 and index < Arena.PART_INFO.size():
				_kind = index


func _on_mouse(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_rot = posmod(_rot + ROTATE_STEP, 360)
		MOUSE_BUTTON_WHEEL_DOWN:
			_rot = posmod(_rot - ROTATE_STEP, 360)
		MOUSE_BUTTON_LEFT:
			var slot := _slot_at(get_local_mouse_position())
			if slot >= 0:
				_kind = slot
			else:
				_place()


func _place() -> void:
	var pos := get_local_mouse_position()
	if _online:
		Net.send_place(_kind, pos, _rot)
		return
	var error := _arena.try_place(_my_pid, _kind, pos, _rot)
	if error != "":
		_show_toast(error)


func _leave() -> void:
	if _online:
		Net.leave()
	finished.emit("")


func _on_chat_submit(text: String) -> void:
	var clean := text.strip_edges()
	if clean != "":
		if _online:
			Net.send_chat(clean)
		else:
			_arena.say(_my_pid, clean)
	_close_chat()


func _close_chat() -> void:
	_chat.text = ""
	_chat.visible = false
	_chat.release_focus()


# --- Durum ---

func _on_snapshot(bytes: PackedByteArray) -> void:
	var snap := Arena.parse_snapshot(bytes)
	var tick: int = snap["tick"]
	if not _latest.is_empty() and tick <= int(_latest["tick"]):
		return
	_latest = snap
	_snaps.append(snap)
	if _snaps.size() > 24:
		_snaps.pop_front()
	if _clock < 0.0 or absf(tick - _clock) > 30.0:
		_clock = float(tick)
	else:
		_clock += (tick - _clock) * 0.1
	_snapshot_effects(snap)


func _snapshot_effects(snap: Dictionary) -> void:
	var bots: Dictionary = snap["robots"]
	for pid: int in bots:
		var row: Dictionary = bots[pid]
		if row["jump"]:
			_burst(row["pos"] + Vector2(0, 22), 5, Color(0.8, 0.9, 1.0, 0.8), 90.0)
			if pid == _my_pid:
				_sfx.play("jump", -6.0)
	var rows: Dictionary = snap["parts"]
	for id: int in rows:
		if not _seen_parts.has(id):
			_seen_parts[id] = true
			_sfx.play("place", -4.0)
			_burst(rows[id]["pos"], 8, Color(1.0, 0.85, 0.5, 0.9), 130.0)
	var phase: int = snap["phase"]
	var count: int = ceili(int(snap["timer"]) / 60.0)
	if phase == Arena.Phase.COUNTDOWN and count != _last_count:
		_last_count = count
		_sfx.play("tick", -5.0)


func _handle_event(ev: Dictionary) -> void:
	match str(ev["t"]):
		"roster":
			_roster.clear()
			for row: Dictionary in ev["rows"]:
				_roster[int(row["pid"])] = row
		"round":
			_begin_round(ev["map"], ev["engineer"])
		"go":
			_sfx.play("go")
			_last_count = -1
		"pickup":
			var who: Dictionary = _robot_frame.get(int(ev["pid"]), {})
			if not who.is_empty():
				_burst(who["pos"], 16, Art.GLOW_GREEN, 200.0)
			if int(ev["pid"]) == _my_pid:
				_sfx.play("pickup")
				_show_banner("Pil sende! Şimdi istasyona dön.")
		"finish":
			_on_finish(ev)
		"death":
			_burst(ev["pos"], 26, Color(1.0, 0.6, 0.25), 300.0)
			_sfx.play("death", 0.0 if int(ev["pid"]) == _my_pid else -10.0)
		"spring":
			_sfx.play("spring", -5.0)
			_burst(ev["pos"], 10, Art.AMBER, 240.0)
		"toast":
			_show_toast(str(ev["text"]))
		"chat":
			_chat_lines.append("%s: %s" % [str(ev["name"]), str(ev["text"])])
			if _chat_lines.size() > CHAT_KEEP:
				_chat_lines.pop_front()
		"result":
			_result_rows = ev["rows"]


func _begin_round(index: int, engineer: int) -> void:
	_map = Maps.get_map(index)
	_terrain = Maps.polygons(_map)
	_engineer = engineer
	_seen_parts.clear()
	_result_rows = []
	_own_ready = false
	_last_count = -1
	if _is_engineer():
		_show_banner("Mühendis sensin! Parçalarla robotlara yol aç.")
	else:
		_show_banner("Pili al, istasyona dön!")


func _on_finish(ev: Dictionary) -> void:
	var pid: int = ev["pid"]
	var who: Dictionary = _robot_frame.get(pid, {})
	if not who.is_empty():
		_burst(who["pos"], 24, Art.AMBER, 260.0)
	if pid == _my_pid:
		_sfx.play("finish")
		_show_banner("%d. oldun! +%d puan" % [int(ev["rank"]), int(ev["points"])])
	else:
		_sfx.play("pickup", -10.0)


func _show_banner(text: String) -> void:
	_banner = text
	_banner_time = 3.0


func _show_toast(text: String) -> void:
	_toast = text
	_toast_time = 2.2
	_sfx.play("error", -5.0)


func _burst(pos: Vector2, count: int, color: Color, speed: float) -> void:
	for i in count:
		_particles.append({
			"pos": pos, "vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(speed * 0.3, speed),
			"life": randf_range(0.25, 0.6), "color": color,
		})


# --- Kare hazırlığı ---

func _process(delta: float) -> void:
	_time += delta
	_banner_time = maxf(_banner_time - delta, 0.0)
	_toast_time = maxf(_toast_time - delta, 0.0)
	if _clock >= 0.0:
		_clock += delta * 60.0
	_build_frame(delta)
	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_particles.remove_at(i)
			continue
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, 700.0 * delta)
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
	queue_redraw()


func _build_frame(delta: float) -> void:
	if _snaps.is_empty():
		return
	var delay := ONLINE_DELAY_TICKS if _online else 1.0
	var at := _clock - delay
	var newest: Dictionary = _snaps[-1]
	var a: Dictionary = newest
	var b: Dictionary = newest
	for i in range(_snaps.size() - 1):
		if float(_snaps[i]["tick"]) <= at and at < float(_snaps[i + 1]["tick"]):
			a = _snaps[i]
			b = _snaps[i + 1]
			break
	var k := 0.0
	if int(b["tick"]) > int(a["tick"]):
		k = clampf((at - float(a["tick"])) / (int(b["tick"]) - int(a["tick"])), 0.0, 1.0)
	_robot_frame = _blend_robots(a, b, k)
	_part_frame = _blend_parts(a, b, k)
	if _online:
		_predict_own(newest, delta)


func _blend_robots(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = {}
	var from: Dictionary = a["robots"]
	var to: Dictionary = b["robots"]
	for pid: int in to:
		var row: Dictionary = (to[pid] as Dictionary).duplicate()
		if from.has(pid):
			var start: Vector2 = from[pid]["pos"]
			var end: Vector2 = row["pos"]
			if start.distance_to(end) < 160.0:
				row["pos"] = start.lerp(end, k)
		out[pid] = row
	return out


func _blend_parts(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = {}
	var from: Dictionary = a["parts"]
	var to: Dictionary = b["parts"]
	for id: int in to:
		var row: Dictionary = (to[id] as Dictionary).duplicate()
		if from.has(id):
			row["pos"] = (from[id]["pos"] as Vector2).lerp(row["pos"], k)
			row["rot"] = lerp_angle(from[id]["rot"], row["rot"], k)
		out[id] = row
	return out


## Kendi robotun beklemeden çizilir: son durum + hız x (yaşı + yarım ping).
func _predict_own(newest: Dictionary, delta: float) -> void:
	var bots: Dictionary = newest["robots"]
	if not bots.has(_my_pid):
		_own_ready = false
		return
	var row: Dictionary = bots[_my_pid]
	var age := maxf(_clock - float(newest["tick"]), 0.0) / 60.0
	var lead := clampf(age + maxf(Net.ping_ms, 0.0) / 2000.0, 0.0, 0.15)
	var target: Vector2 = row["pos"] + (row["vel"] as Vector2) * lead
	if not _own_ready or _own_pos.distance_to(target) > 150.0:
		_own_pos = target
		_own_ready = true
	else:
		_own_pos = _own_pos.lerp(target, clampf(delta * 25.0, 0.0, 1.0))
	if _robot_frame.has(_my_pid):
		_robot_frame[_my_pid]["pos"] = _own_pos


# --- Çizim ---

func _draw() -> void:
	Art.background(self, _time)
	if _map.is_empty() or _latest.is_empty():
		_text("Harita bekleniyor...", Vector2(0, 360), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1280)
		return
	Art.station(self, _map["station"], _time)
	var mine: Dictionary = _robot_frame.get(_my_pid, {})
	if mine.is_empty() or not mine["battery"]:
		Art.battery_icon(self, _map["battery"] + Vector2(0, sin(_time * 3.0) * 4.0), 1.0, _time)
	for tile: Dictionary in _map["tiles"]:
		Art.tile(self, tile, _time)
	for row: Dictionary in _part_frame.values():
		Art.part(self, row["kind"], row["pos"], row["rot"])
	_draw_robots()
	_draw_engineer()
	for p in _particles:
		var c: Color = p["color"]
		c.a *= clampf(float(p["life"]) * 3.0, 0.0, 1.0)
		draw_circle(p["pos"], 2.6, c)
	_draw_hud()


func _draw_robots() -> void:
	for pid: int in _robot_frame:
		var row: Dictionary = _robot_frame[pid]
		var info: Dictionary = _roster.get(pid, {})
		var pos: Vector2 = row["pos"]
		Art.robot(self, pos, info.get("color", 0), info.get("acc", 0), row["facing"], pos.x / 7.0, row["battery"], _time, row["climb"])
		if pid == _my_pid and int(row["stamina"]) < Arena.STAMINA_LEVELS:
			_draw_stamina(pos, int(row["stamina"]))
		var label := str(info.get("name", "?"))
		var color := Art.AMBER if pid == _my_pid else Color(1, 1, 1, 0.82)
		var name_y := pos.y - (70.0 if row["battery"] else 40.0)
		_text(label, Vector2(pos.x - 90.0, name_y), 14, color, HORIZONTAL_ALIGNMENT_CENTER, 180.0)


func _draw_stamina(pos: Vector2, level: int) -> void:
	var back := Rect2(pos + Vector2(-20, 30), Vector2(40, 5))
	draw_rect(back, Color(0.04, 0.09, 0.14, 0.85))
	var fill := back
	fill.size.x *= float(level) / Arena.STAMINA_LEVELS
	draw_rect(fill, Art.GLOW_GREEN if level > 2 else Color("ff7b6b"))


func _draw_engineer() -> void:
	var eng: Dictionary = _latest["eng"]
	if eng.is_empty():
		return
	var pid: int = eng["pid"]
	var info: Dictionary = _roster.get(pid, {})
	var mine := pid == _my_pid
	var aim: Vector2 = get_local_mouse_position() if mine else eng["aim"]
	var kind: int = _kind if mine else eng["kind"]
	var rot := deg_to_rad(float(_rot if mine else eng["rot"]))
	var over_toolbar := mine and _slot_at(aim) >= 0
	if not over_toolbar:
		_draw_ghost(kind, aim, rot, mine)
	Art.drone(self, aim + Vector2(0, -52), info.get("color", 0), _time)
	_text(str(info.get("name", "?")), Vector2(aim.x - 90.0, aim.y - 92.0), 14, Art.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 180.0)


func _draw_ghost(kind: int, pos: Vector2, rot: float, mine: bool) -> void:
	var valid := true
	if mine:
		var rows: Array = (_latest["parts"] as Dictionary).values()
		var bots: Array = []
		for row: Dictionary in (_latest["robots"] as Dictionary).values():
			bots.append(row["pos"])
		valid = Arena.placement_error(kind, pos, rot, _terrain, rows, bots) == ""
	Art.part(self, kind, pos, rot, 0.55 if mine else 0.3)
	var poly := Arena.part_polygon(kind, pos, rot)
	poly.append(poly[0])
	var edge := Color(0.4, 1.0, 0.6, 0.9) if valid else Color(1.0, 0.3, 0.3, 0.9)
	if not mine:
		edge = Color(1, 1, 1, 0.35)
	draw_polyline(poly, edge, 2.0, true)


func _draw_hud() -> void:
	var phase: int = _latest["phase"]
	var seconds := ceili(int(_latest["timer"]) / 60.0)
	Art.panel(self, Rect2(500, 8, 280, 54), 12.0, Color(0.04, 0.09, 0.14, 0.78))
	_text(str(_map["name"]), Vector2(500, 28), 15, Color("a9c6d4"), HORIZONTAL_ALIGNMENT_CENTER, 280)
	if phase == Arena.Phase.RUN:
		var color := Color("ff7b6b") if seconds <= 15 else Color.WHITE
		_text("%d:%02d" % [seconds / 60, seconds % 60], Vector2(500, 54), 24, color, HORIZONTAL_ALIGNMENT_CENTER, 280)
	elif phase == Arena.Phase.COUNTDOWN:
		_text("Hazırlan", Vector2(500, 54), 22, Art.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 280)
		_text(str(seconds), Vector2(0, 310), 120, Art.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	_draw_scores()
	_draw_chat()
	if _banner_time > 0.0:
		_text(_banner, Vector2(0, 112), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	if _toast_time > 0.0:
		_text(_toast, Vector2(0, 630), 22, Color("ffb0a0"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	if _online:
		var room := _room_code if _room_code != "" else "Genel"
		_text("Oda: %s   Ping: %d ms" % [room, Net.ping_ms], Vector2(14, 26), 15, Color("a9c6d4"))
	if _is_engineer() and phase != Arena.Phase.RESULT:
		_draw_toolbar()
	if phase == Arena.Phase.RESULT:
		_draw_result()


func _sorted_roster() -> Array:
	var rows: Array = _roster.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	return rows


func _draw_scores() -> void:
	var rows := _sorted_roster()
	var shown := mini(rows.size(), 7)
	Art.panel(self, Rect2(1050, 8, 222, 30.0 + shown * 22.0), 10.0, Color(0.04, 0.09, 0.14, 0.72))
	_text("Skor", Vector2(1064, 30), 16, Art.AMBER)
	for i in shown:
		var row: Dictionary = rows[i]
		var y := 54.0 + i * 22.0
		var pid: int = row["pid"]
		draw_circle(Vector2(1070, y - 5.0), 6.0, Art.COLORS[posmod(int(row["color"]), Art.COLORS.size())])
		var color := Art.AMBER if pid == _my_pid else Color.WHITE
		var label := str(row["name"]) + ("  [M]" if pid == _engineer else "")
		_text(label, Vector2(1082, y), 15, color, HORIZONTAL_ALIGNMENT_LEFT, 140.0)
		_text(str(row["score"]), Vector2(1212, y), 15, color, HORIZONTAL_ALIGNMENT_RIGHT, 50.0)


func _draw_chat() -> void:
	var y := 600.0 - (_chat_lines.size() - 1) * 20.0
	for line in _chat_lines:
		_text(line, Vector2(14, y), 15, Color(1, 1, 1, 0.88), HORIZONTAL_ALIGNMENT_LEFT, 520.0)
		y += 20.0


func _slot_rect(index: int) -> Rect2:
	var count := Arena.PART_INFO.size()
	var total := count * SLOT_SIZE.x + (count - 1) * SLOT_GAP
	return Rect2((1280.0 - total) * 0.5 + index * (SLOT_SIZE.x + SLOT_GAP), TOOLBAR_Y, SLOT_SIZE.x, SLOT_SIZE.y)


func _slot_at(pos: Vector2) -> int:
	for i in Arena.PART_INFO.size():
		if _slot_rect(i).has_point(pos):
			return i
	return -1


func _draw_toolbar() -> void:
	var eng: Dictionary = _latest["eng"]
	if eng.is_empty():
		return
	var left: Array = eng["left"]
	for i in Arena.PART_INFO.size():
		var rect := _slot_rect(i)
		var selected := i == _kind
		var fill := Color(0.14, 0.26, 0.36, 0.94) if selected else Color(0.05, 0.1, 0.15, 0.86)
		Art.panel(self, rect, 9.0, fill, Art.AMBER if selected else Color(1, 1, 1, 0.2), 2.0)
		_draw_slot_icon(i, rect.get_center() + Vector2(0, -4))
		_text(str(i + 1), rect.position + Vector2(6, 16), 13, Color("a9c6d4"))
		var count: int = left[i]
		_text("x%d" % count, rect.position + Vector2(0, 16), 14, Color.WHITE if count > 0 else Color("ff7b6b"), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6.0)
		_text(str(Arena.PART_INFO[i]["name"]), rect.position + Vector2(0, rect.size.y - 6.0), 11, Color("cfe4ee"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _draw_slot_icon(kind: int, center: Vector2) -> void:
	var size: Vector2 = Arena.PART_INFO[kind]["size"]
	var fit := minf(0.65, 54.0 / maxf(size.x, size.y))
	draw_set_transform(center, 0.0, Vector2.ONE * fit)
	# Art.part kendi dönüşümünü kurar; küçük önizleme için burada sade biçim çizilir.
	var half := size * 0.5
	match kind:
		Arena.Kind.BALLOON:
			draw_circle(Vector2.ZERO, half.x * 0.7, Color(1.0, 0.36, 0.42))
		Arena.Kind.BOLT:
			draw_circle(Vector2.ZERO, 9.0, Color("c9d3dc"))
			draw_line(Vector2(-5, 0), Vector2(5, 0), Color(0.2, 0.25, 0.3), 2.5)
		Arena.Kind.RAMP:
			var pts := PackedVector2Array()
			for p: Vector2 in Arena.part_local_points(kind):
				pts.append(p)
			draw_colored_polygon(pts, Art.STEEL_TOP)
		Arena.Kind.SPRING:
			Art.spring_shape(self, size)
		_:
			draw_rect(Rect2(-half, size), Art.WOOD)
			draw_rect(Rect2(-half, size), Art.WOOD_DARK, false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_result() -> void:
	var rows := _sorted_roster()
	var shown := mini(rows.size(), 12)
	var height := 96.0 + shown * 28.0
	var rect := Rect2(390, 360.0 - height * 0.5, 500, height)
	Art.panel(self, rect, 16.0, Color(0.04, 0.09, 0.14, 0.92), Color(1, 1, 1, 0.2))
	_text("Tur Bitti", rect.position + Vector2(0, 42), 30, Art.AMBER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	for i in shown:
		var row: Dictionary = rows[i]
		var y := rect.position.y + 80.0 + i * 28.0
		var color := Art.AMBER if int(row["pid"]) == _my_pid else Color.WHITE
		_text("%d. %s" % [i + 1, str(row["name"])], Vector2(rect.position.x + 34.0, y), 19, color, HORIZONTAL_ALIGNMENT_LEFT, 260.0)
		_text("+%d" % int(row["rp"]), Vector2(rect.position.x + 300.0, y), 19, Art.GLOW_GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
		_text(str(row["score"]), Vector2(rect.position.x + 380.0, y), 19, color, HORIZONTAL_ALIGNMENT_RIGHT, 80.0)


func _text(text: String, pos: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, text, align, width, size, maxi(size / 5, 3), Color(0.03, 0.07, 0.11, 0.9))
	draw_string(font, pos, text, align, width, size, color)
