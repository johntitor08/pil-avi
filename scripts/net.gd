extends Node
## ENet katmanı. Sunucu yetkilidir: istemciler tuş, nişan ve parça isteği gönderir;
## fizik ve kurallar sunucudaki Arena'da döner, durum istemcilere yayılır.

signal connect_failed(message: String)
signal rejected(message: String)
signal joined(pid: int, code: String)
signal snap_received(bytes: PackedByteArray)
signal event_received(ev: Dictionary)
signal disconnected

const VERSION := 1
const DualPeer := preload("res://scripts/dual_peer.gd")
const WS_PORT_OFFSET := 1
const DEFAULT_PORT := 7810
const DEFAULT_ADDRESS := "chords-amarillo.tun.ply.gg:19552"
const MAX_PEERS := 256
const CHANNELS := 5
const CH_INPUT := 1
const CH_SNAP := 2
const CH_EVENT := 3
const CH_PING := 4
const HELLO_TIMEOUT_MSEC := 10000
const THROTTLE_INTERVAL_MSEC := 5000
const INPUT_HEARTBEAT_TICKS := 3
const SNAPSHOT_EVERY_TICKS := 3
const MAX_NAME := 16
const MAX_CODE := 12
const MAX_CHAT := 120
const CHAT_GAP_MSEC := 700


class Room:
	var arena := Arena.new()
	var code := ""
	var peer_of: Dictionary = {}


var is_server := false
var ping_ms := -1
var client_version := VERSION
## Testler botsuz oda ister; normalde oda en az bu kadar robotla dolar.
var min_robots := 4
## Ağ testi Mühendisi bilmek ister: odayı açan ilk tur Mühendis olur.
var first_is_engineer := false

var _rooms: Array[Room] = []
var _peer_room: Dictionary = {}
var _peer_pid: Dictionary = {}
var _pending: Dictionary = {}
var _last_chat: Dictionary = {}

var _hello: Array = []
var _ping_accum := 0.0
var _last_mask := -1
var _input_age := 0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_server(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS, CHANNELS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	# Tarayıcılar UDP kullanamaz: aynı odalara WebSocket ile (port + 1, TCP) bağlanırlar.
	var ws := WebSocketMultiplayerPeer.new()
	var ws_err := ws.create_server(port + WS_PORT_OFFSET)
	if ws_err == OK:
		var dual := DualPeer.new()
		dual.setup(peer, ws)
		multiplayer.multiplayer_peer = dual
		print("[sunucu] tarayıcılar için WebSocket: %d" % (port + WS_PORT_OFFSET))
	else:
		push_warning("WebSocket portu açılamadı (hata %d), yalnızca UDP" % ws_err)
		multiplayer.multiplayer_peer = peer
	is_server = true
	print("[sunucu] port %d dinleniyor, sürüm %d" % [port, VERSION])
	return OK


func connect_to(address: String, port: int, player_name: String, code: String, color: int, acc: int) -> Error:
	leave()
	_hello = [player_name, code, color, acc]
	_last_mask = -1
	if OS.has_feature("web") or address.begins_with("ws://") or address.begins_with("wss://"):
		var ws := WebSocketMultiplayerPeer.new()
		var ws_err := ws.create_client(address)
		if ws_err != OK:
			return ws_err
		multiplayer.multiplayer_peer = ws
		return OK
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	ping_ms = -1
	var peer := multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Tuş değişince hemen, değişmese de 3 karede bir gönderilir (playit tünelinde
## saniyede 60 paket kuyruk biriktiriyor).
func send_input(mask: int, aim: Vector2, kind: int, rot_deg: int) -> void:
	if not is_online():
		return
	_input_age += 1
	if mask != _last_mask or _input_age >= INPUT_HEARTBEAT_TICKS:
		_last_mask = mask
		_input_age = 0
		_c_input.rpc_id(1, mask, int(aim.x), int(aim.y), kind, rot_deg)


func send_place(kind: int, pos: Vector2, rot_deg: int) -> void:
	if is_online():
		_c_place.rpc_id(1, kind, int(pos.x), int(pos.y), rot_deg)


func send_chat(text: String) -> void:
	if is_online():
		_c_chat.rpc_id(1, text)


func _process(delta: float) -> void:
	if is_server or not is_online():
		return
	_ping_accum += delta
	if _ping_accum >= 1.0:
		_ping_accum = 0.0
		_c_ping.rpc_id(1, Time.get_ticks_msec())


func _physics_process(_delta: float) -> void:
	if is_server:
		_server_tick()


# --- İstemci olayları ---

func _on_connected() -> void:
	# ENet gecikme dalgalanmasında güvenilmez paketleri kısıyor; tünelde tuşlar kayboluyordu.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		enet.get_peer(1).throttle_configure(THROTTLE_INTERVAL_MSEC, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)
	_c_hello.rpc_id(1, client_version, str(_hello[0]), str(_hello[1]), int(_hello[2]), int(_hello[3]))


func _on_connection_failed() -> void:
	leave()
	connect_failed.emit("Sunucuya bağlanılamadı.")


func _on_server_gone() -> void:
	leave()
	disconnected.emit()


# --- Sunucu ---

func _on_peer_connected(id: int) -> void:
	if is_server:
		_pending[id] = Time.get_ticks_msec()


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_pending.erase(id)
	_last_chat.erase(id)
	var room: Room = _peer_room.get(id)
	if room == null:
		return
	var pid: int = _peer_pid[id]
	_peer_room.erase(id)
	_peer_pid.erase(id)
	room.peer_of.erase(pid)
	room.arena.remove_player(pid)
	if room.peer_of.is_empty():
		room.arena.dispose()
		_rooms.erase(room)
		print("[sunucu] oda kapandı: '%s'" % room.code)


func _server_tick() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _pending.keys():
		if now - int(_pending[id]) > HELLO_TIMEOUT_MSEC:
			_pending.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for room in _rooms:
		_tick_room(room)


func _tick_room(room: Room) -> void:
	room.arena.step()
	for ev in room.arena.drain_events():
		for peer: int in room.peer_of.values():
			_s_event.rpc_id(peer, ev)
	if room.arena.tick % SNAPSHOT_EVERY_TICKS == 0:
		var bytes := room.arena.snapshot()
		for peer: int in room.peer_of.values():
			_s_snap.rpc_id(peer, bytes)


func _clean_text(text: String, limit: int) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.left(limit)


func _find_room(code: String) -> Room:
	for room in _rooms:
		if room.code == code and room.arena.human_count() < Arena.MAX_ROBOTS:
			return room
	return null


func _open_room(code: String) -> Room:
	var room := Room.new()
	room.code = code
	room.arena.min_robots = min_robots
	_rooms.append(room)
	print("[sunucu] oda açıldı: '%s'" % code)
	return room


func _peer_slot() -> Array:
	var id := multiplayer.get_remote_sender_id()
	var room: Room = _peer_room.get(id)
	if room == null:
		return []
	return [room, int(_peer_pid[id])]


# --- RPC'ler ---

@rpc("any_peer", "call_remote", "reliable", CH_EVENT)
func _c_hello(version: int, player_name: String, code: String, color: int, acc: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id):
		return
	_pending.erase(id)
	if version != VERSION:
		_s_reject.rpc_id(id, "Oyun sürümün eski. Lütfen güncelle.")
		return
	var clean_name := _clean_text(player_name, MAX_NAME)
	if clean_name == "":
		clean_name = "Robot%d" % (randi() % 900 + 100)
	var clean_code := _clean_text(code, MAX_CODE).to_upper()
	var room := _find_room(clean_code)
	var is_new := room == null
	if is_new:
		for existing in _rooms:
			if existing.code == clean_code and clean_code != "":
				_s_reject.rpc_id(id, "Bu oda dolu.")
				return
		room = _open_room(clean_code)
	var pid := room.arena.add_player(clean_name, posmod(color, Art.COLORS.size()), posmod(acc, Art.ACCESSORIES.size()))
	room.peer_of[pid] = id
	_peer_room[id] = room
	_peer_pid[id] = pid
	_s_joined.rpc_id(id, pid, clean_code)
	if is_new:
		if first_is_engineer:
			room.arena.force_engineer = pid
		room.arena.start_round(0)
	else:
		_s_event.rpc_id(id, room.arena.round_info())


@rpc("any_peer", "call_remote", "unreliable_ordered", CH_INPUT)
func _c_input(mask: int, ax: int, ay: int, kind: int, rot_deg: int) -> void:
	var slot := _peer_slot()
	if not slot.is_empty():
		(slot[0] as Room).arena.set_input(slot[1], mask & 31, Vector2(ax, ay), kind, rot_deg)


@rpc("any_peer", "call_remote", "reliable", CH_EVENT)
func _c_place(kind: int, x: int, y: int, rot_deg: int) -> void:
	var slot := _peer_slot()
	if slot.is_empty():
		return
	var error := (slot[0] as Room).arena.try_place(slot[1], kind, Vector2(x, y), rot_deg)
	if error != "":
		_s_event.rpc_id(multiplayer.get_remote_sender_id(), {"t": "toast", "text": error})


@rpc("any_peer", "call_remote", "reliable", CH_EVENT)
func _c_chat(text: String) -> void:
	var slot := _peer_slot()
	if slot.is_empty():
		return
	var id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if now - int(_last_chat.get(id, -CHAT_GAP_MSEC)) < CHAT_GAP_MSEC:
		return
	var clean := _clean_text(text, MAX_CHAT)
	if clean != "":
		_last_chat[id] = now
		(slot[0] as Room).arena.say(slot[1], clean)


@rpc("any_peer", "call_remote", "unreliable", CH_PING)
func _c_ping(sent: int) -> void:
	if is_server:
		_s_pong.rpc_id(multiplayer.get_remote_sender_id(), sent)


@rpc("authority", "call_remote", "unreliable", CH_PING)
func _s_pong(sent: int) -> void:
	ping_ms = Time.get_ticks_msec() - sent


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_joined(pid: int, code: String) -> void:
	joined.emit(pid, code)


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_reject(message: String) -> void:
	leave()
	rejected.emit(message)


@rpc("authority", "call_remote", "unreliable_ordered", CH_SNAP)
func _s_snap(bytes: PackedByteArray) -> void:
	snap_received.emit(bytes)


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_event(ev: Dictionary) -> void:
	event_received.emit(ev)
