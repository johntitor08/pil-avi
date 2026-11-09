class_name Arena
extends RefCounted
## Bir odanın oyun dünyası ve kuralları. Fizik kendi PhysicsServer2D alanında döner,
## düğüm kullanmaz; böylece sunucuda her oda birbirinden bağımsızdır.
## step() her fizik karesinde çağrılır, motor adımı hemen ardından gelir.

enum Phase { COUNTDOWN, RUN, RESULT }
enum Life { RACING, DEAD, DONE, ENGINEER }
enum Kind { PLANK, LONG_PLANK, BOX, BALLOON, RAMP, SPRING, BOLT }

const LEFT := 1
const RIGHT := 2
const JUMP := 4
const SELF_DESTRUCT := 8
const CLIMB := 16

const DT := 1.0 / 60.0
const GRAVITY := 1500.0
const MAX_SPEED := 340.0
const GROUND_ACCEL := 1500.0
const GROUND_BRAKE := 950.0
const AIR_ACCEL := 1100.0
const ICE_FACTOR := 0.22
const JUMP_SPEED := 640.0
const WALL_JUMP_Y := 520.0
const WALL_JUMP_X := 330.0
const WALL_LOCK_TICKS := 16
const WALL_SLIDE_SPEED := 240.0
const MAX_FALL := 1100.0
const CLIMB_SPEED := 190.0
const CLIMB_TICKS := 90
const CLIMB_WALL_PRESS := 60.0
const CLIMB_VAULT_Y := 300.0
const CLIMB_VAULT_X := 110.0
const CLIMB_VAULT_TICKS := 20
const STAMINA_LEVELS := 7
const STEP_UP_HEIGHT := 24.0
const STEP_UP_SPEED := 280.0
const COYOTE_TICKS := 6
const JUMP_BUFFER_TICKS := 8
const SPRING_SPEED := 1050.0
const LIFT_ACCEL := GRAVITY * 1.35
const LIFT_MAX_SPEED := 260.0
const ROBOT_SIZE := Vector2(34, 44)
const PICKUP_RADIUS := 44.0
const STATION_RADIUS := 56.0
const KILL_Y := 800.0
const PART_KILL_Y := 900.0

const COUNTDOWN_TICKS := 180
const ROUND_TICKS := 7200
const RESULT_TICKS := 360
const PLACE_COOLDOWN := 15
const MAX_PARTS := 40
const MAX_ROBOTS := 12
const BALLOON_ATTACH_RANGE := 70.0
const BALLOON_ATTACHED_TICKS := 480
const BALLOON_FREE_TICKS := 600
const RANK_POINTS := [10, 7, 5]
const FINISH_POINTS := 3
const ENGINEER_POINTS := 3

const LAYER_WORLD := 1
const LAYER_ROBOT := 2
const LAYER_PART := 4

const PART_INFO := [
	{"name": "Tahta", "limit": 8, "size": Vector2(150, 14), "mass": 6.0},
	{"name": "Uzun Tahta", "limit": 4, "size": Vector2(280, 14), "mass": 9.0},
	{"name": "Kutu", "limit": 5, "size": Vector2(46, 46), "mass": 5.0},
	{"name": "Balon", "limit": 4, "size": Vector2(40, 40), "mass": 0.4},
	{"name": "Rampa", "limit": 3, "size": Vector2(150, 70), "mass": 0.0},
	{"name": "Yay", "limit": 3, "size": Vector2(96, 18), "mass": 0.0},
	{"name": "Cıvata", "limit": 10, "size": Vector2(16, 16), "mass": 0.0},
]

const BOT_NAMES := ["Paslı", "Vızvız", "Somun", "Dişli", "Tekerlek", "Kablo", "Sigorta", "Yağdanlık"]


class Robot:
	var pid := 0
	var name := ""
	var color := 0
	var acc := 0
	var is_bot := false
	var life: int = Life.DEAD
	var body := RID()
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var mask := 0
	var prev_mask := 0
	var facing := 1
	var on_ground := false
	var on_ice := false
	var ground_normal := Vector2.UP
	var coyote := 0
	var jump_buffer := 0
	var jump_lock := 0
	var rising := false
	var wall_lock := 0
	var climbing := false
	var climb_side := 0
	var vault_ticks := 0
	var stamina := CLIMB_TICKS
	var pad_cooldown := 0
	var fx_jump := false
	var has_battery := false
	var score := 0
	var round_points := 0
	var engineer_count := 0
	var aim := Vector2(640, 300)
	var aim_kind := 0
	var aim_rot := 0
	var placed: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var place_cooldown := 0
	# Bot beyni
	var wp := 0
	var wp_age := 0
	var start_delay := 0
	var speed_mul := 1.0
	var stuck_timer := 0
	var stuck_count := 0
	var stuck_pos := Vector2.ZERO


class Part:
	var id := 0
	var kind := 0
	var body := RID()
	var joint := RID()
	var pos := Vector2.ZERO
	var rot := 0.0
	var ttl := -1
	var bolts := 0
	var host_part := 0
	var host_robot := 0
	var offset := Vector2.ZERO


var tick := 0
var phase: int = Phase.COUNTDOWN
var timer := COUNTDOWN_TICKS
var map: Dictionary = {}
var map_index := -1
var robots: Dictionary = {}
var parts: Dictionary = {}
var engineer_pid := 0
var finished_count := 0
var last_winner := 0
var last_engineer := 0
var min_robots := 0
var fixed_map := -1
var force_engineer := -1
var no_engineer := false

var _space: RID
var _anchor: RID
var _world_bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _ice: Dictionary = {}
var _spikes: Array[Dictionary] = []
var _pads: Array[Dictionary] = []
var _terrain_polys: Array = []
var _next_pid := 1
var _next_part := 1
var _events: Array[Dictionary] = []
var _help_index := 0
var _round_ticks := 0
var _disposed := false
var _ray := PhysicsRayQueryParameters2D.new()


func _init() -> void:
	_space = PhysicsServer2D.space_create()
	PhysicsServer2D.space_set_active(_space, true)
	PhysicsServer2D.area_set_param(_space, PhysicsServer2D.AREA_PARAM_GRAVITY, GRAVITY)
	PhysicsServer2D.area_set_param(_space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2.DOWN)
	PhysicsServer2D.area_set_param(_space, PhysicsServer2D.AREA_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer2D.area_set_param(_space, PhysicsServer2D.AREA_PARAM_ANGULAR_DAMP, 1.5)
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_clear_world()
	PhysicsServer2D.free_rid(_space)


# --- Oyuncular ---

func add_player(player_name: String, color: int, acc: int, is_bot := false) -> int:
	var r := Robot.new()
	r.pid = _next_pid
	_next_pid = _next_pid % 250 + 1
	while robots.has(_next_pid):
		_next_pid = _next_pid % 250 + 1
	r.name = player_name
	r.color = color
	r.acc = acc
	r.is_bot = is_bot
	if is_bot:
		r.speed_mul = randf_range(0.92, 0.98)
	robots[r.pid] = r
	if not map.is_empty() and phase != Phase.RESULT:
		_spawn_robot(r, robots.size() - 1)
	_emit_roster()
	return r.pid


func remove_player(pid: int) -> void:
	var r: Robot = robots.get(pid)
	if r == null:
		return
	_remove_robot_body(r)
	robots.erase(pid)
	if engineer_pid == pid:
		engineer_pid = 0
	_emit_roster()


func human_count() -> int:
	var n := 0
	for r: Robot in robots.values():
		if not r.is_bot:
			n += 1
	return n


func set_input(pid: int, mask: int, aim: Vector2, kind: int, rot_deg: int) -> void:
	var r: Robot = robots.get(pid)
	if r == null:
		return
	r.mask = mask
	r.aim = Vector2(clampf(aim.x, 0.0, Maps.WIDTH), clampf(aim.y, 0.0, Maps.HEIGHT))
	r.aim_kind = clampi(kind, 0, PART_INFO.size() - 1)
	r.aim_rot = rot_deg


func say(pid: int, text: String) -> void:
	var r: Robot = robots.get(pid)
	if r != null:
		_event({"t": "chat", "name": r.name, "text": text})


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


# --- Tur akışı ---

func next_round() -> void:
	start_round(fixed_map if fixed_map >= 0 else map_index + 1)


func start_round(index: int) -> void:
	_sync_bots()
	_clear_world()
	map_index = posmod(index, Maps.all().size())
	map = Maps.get_map(map_index)
	_build_map()
	phase = Phase.COUNTDOWN
	timer = COUNTDOWN_TICKS
	finished_count = 0
	_help_index = 0
	_round_ticks = 0
	engineer_pid = _pick_engineer()
	last_engineer = engineer_pid
	var slot := 0
	for r: Robot in robots.values():
		r.round_points = 0
		r.has_battery = false
		r.placed = [0, 0, 0, 0, 0, 0, 0]
		r.place_cooldown = 0
		if r.pid == engineer_pid:
			r.life = Life.ENGINEER
			r.engineer_count += 1
			r.aim = Vector2(640, 260)
			r.wp = 0
		else:
			_spawn_robot(r, slot)
			slot += 1
	_event({"t": "round", "map": map_index, "engineer": engineer_pid})
	_emit_roster()


## Testler için: geri sayımı atlar.
func skip_countdown() -> void:
	if phase == Phase.COUNTDOWN:
		phase = Phase.RUN
		timer = ROUND_TICKS
		_event({"t": "go"})


func _sync_bots() -> void:
	while robots.size() < min_robots:
		var used := robots.size()
		add_player(BOT_NAMES[used % BOT_NAMES.size()], randi() % Art.COLORS.size(), randi() % Art.ACCESSORIES.size(), true)
	if robots.size() > min_robots:
		for r: Robot in robots.values():
			if r.is_bot and robots.size() > min_robots:
				remove_player(r.pid)


## Kural: önceki turun birincisi Mühendis olur. Birinci yoksa en az Mühendis olan seçilir.
func _pick_engineer() -> int:
	if no_engineer:
		return 0
	if force_engineer >= 0 and robots.has(force_engineer):
		return force_engineer
	if robots.size() < 2:
		return 0
	if last_winner != 0 and robots.has(last_winner):
		var winner := last_winner
		last_winner = 0
		return winner
	last_winner = 0
	var fewest := 1 << 30
	var picks: Array[int] = []
	for r: Robot in robots.values():
		if r.pid == last_engineer:
			continue
		if r.engineer_count < fewest:
			fewest = r.engineer_count
			picks = [r.pid]
		elif r.engineer_count == fewest:
			picks.append(r.pid)
	return 0 if picks.is_empty() else picks[randi() % picks.size()]


func _end_round() -> void:
	phase = Phase.RESULT
	timer = RESULT_TICKS
	var rows: Array = []
	for r: Robot in robots.values():
		rows.append({"pid": r.pid, "points": r.round_points, "done": r.life == Life.DONE, "engineer": r.pid == engineer_pid})
	_event({"t": "result", "rows": rows})
	_emit_roster()


func step() -> void:
	tick += 1
	timer -= 1
	_round_ticks += 1
	match phase:
		Phase.COUNTDOWN:
			if timer <= 0:
				phase = Phase.RUN
				timer = ROUND_TICKS
				_event({"t": "go"})
		Phase.RUN:
			if timer <= 0 or not _anyone_racing():
				_end_round()
		Phase.RESULT:
			if timer <= 0:
				next_round()
				return
	_read_bodies()
	for r: Robot in robots.values():
		if r.place_cooldown > 0:
			r.place_cooldown -= 1
		if r.life == Life.ENGINEER and r.is_bot:
			_bot_engineer(r)
		if r.life == Life.RACING:
			_update_robot(r)
		r.prev_mask = r.mask
	_update_parts()


func _anyone_racing() -> bool:
	for r: Robot in robots.values():
		if r.life == Life.RACING:
			return true
	return false


func _bot_engineer(r: Robot) -> void:
	var plan: Array = map["help"]
	if _help_index >= plan.size():
		return
	var entry: Dictionary = plan[_help_index]
	var at: int = entry["t"]
	var pos: Vector2 = entry["p"]
	if int(entry["k"]) == Kind.BOLT:
		# Cıvata planındaki konum, son konan parçaya göredir; parça oturmuş olabilir.
		var host: Part = _last_dynamic_part()
		if host == null:
			_help_index += 1
			return
		pos = host.pos + pos.rotated(host.rot)
	r.aim = r.aim.move_toward(pos, 14.0)
	r.aim_kind = entry["k"]
	r.aim_rot = entry["r"]
	if _round_ticks >= at and r.place_cooldown == 0:
		try_place(r.pid, entry["k"], pos, entry["r"])
		_help_index += 1


func _last_dynamic_part() -> Part:
	var found: Part = null
	for p: Part in parts.values():
		if is_dynamic(p.kind):
			found = p
	return found


# --- Dünya ---

func _clear_world() -> void:
	for p: Part in parts.values():
		_free_part_rids(p)
	parts.clear()
	for r: Robot in robots.values():
		_remove_robot_body(r)
	for b in _world_bodies:
		PhysicsServer2D.free_rid(b)
	_world_bodies.clear()
	for s in _shapes:
		PhysicsServer2D.free_rid(s)
	_shapes.clear()
	_ice.clear()
	_spikes.clear()
	_pads.clear()
	_terrain_polys.clear()


func _build_map() -> void:
	_terrain_polys = Maps.polygons(map)
	for tile: Dictionary in map["tiles"]:
		var kind: int = tile["k"]
		var size: Vector2 = tile["s"]
		var center: Vector2 = tile["p"]
		var angle: float = tile["a"]
		var half := size * 0.5
		var body := _new_body(PhysicsServer2D.BODY_MODE_STATIC, [
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
		], center, angle, LAYER_WORLD, 0.9, 1.0)
		_world_bodies.append(body)
		match kind:
			Maps.Tile.ICE:
				_ice[body] = true
			Maps.Tile.SPIKE:
				_spikes.append({"p": center, "s": size, "a": angle})
			Maps.Tile.SPRING:
				_pads.append({"p": center, "s": size, "a": angle})
	# Cıvatalar bu şekilsiz sabit cisme bağlanır; pin ekleminde ikinci cisim boş olursa
	# Godot fizik iş parçacığı çöküyor.
	_anchor = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(_anchor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_space(_anchor, _space)
	_world_bodies.append(_anchor)
	for x: float in [-20.0, Maps.WIDTH + 20.0]:
		_world_bodies.append(_new_body(PhysicsServer2D.BODY_MODE_STATIC, [
			Vector2(-20, -700), Vector2(20, -700), Vector2(20, 700), Vector2(-20, 700)
		], Vector2(x, 200), 0.0, LAYER_WORLD, 0.0, 1.0))


func _new_body(mode: int, points: Array, pos: Vector2, rot: float, layer: int, friction: float, mass: float) -> RID:
	var shape := PhysicsServer2D.convex_polygon_shape_create()
	PhysicsServer2D.shape_set_data(shape, _clockwise(points))
	_shapes.append(shape)
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, mode as PhysicsServer2D.BodyMode)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_space(body, _space)
	PhysicsServer2D.body_set_collision_layer(body, layer)
	PhysicsServer2D.body_set_collision_mask(body, LAYER_WORLD | LAYER_ROBOT | LAYER_PART)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, friction)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.0)
	if mode != PhysicsServer2D.BODY_MODE_STATIC:
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_MASS, mass)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(rot, pos))
	return body


## GodotPhysics dışbükey çokgende ekranda saat yönünü bekler; ters verilirse çarpışma bozulur.
func _clockwise(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	var area := 0.0
	for i in out.size():
		var a := out[i]
		var b := out[(i + 1) % out.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		out.reverse()
	return out


func _spawn_robot(r: Robot, slot: int) -> void:
	_remove_robot_body(r)
	var spawn: Vector2 = map["spawn"]
	var row := slot / 5
	var column := slot % 5
	var pos := spawn + Vector2((column - 2) * 40.0, row * -50.0)
	var hw := ROBOT_SIZE.x * 0.5
	var hh := ROBOT_SIZE.y * 0.5
	var c := 8.0
	r.body = _new_body(PhysicsServer2D.BODY_MODE_RIGID_LINEAR, [
		Vector2(-hw + c, -hh), Vector2(hw - c, -hh), Vector2(hw, -hh + c), Vector2(hw, hh - c),
		Vector2(hw - c, hh), Vector2(-hw + c, hh), Vector2(-hw, hh - c), Vector2(-hw, -hh + c)
	], pos, 0.0, LAYER_ROBOT, 0.0, 3.0)
	PhysicsServer2D.body_set_continuous_collision_detection_mode(r.body, PhysicsServer2D.CCD_MODE_CAST_SHAPE)
	r.life = Life.RACING
	r.pos = pos
	r.vel = Vector2.ZERO
	r.has_battery = false
	r.wp = 0
	r.wp_age = 0
	r.start_delay = slot * 35 + randi_range(0, 20)
	r.stuck_timer = 0
	r.stuck_count = 0
	r.stuck_pos = pos
	r.on_ground = false
	r.coyote = 0
	r.jump_buffer = 0
	r.jump_lock = 0
	r.climbing = false
	r.vault_ticks = 0
	r.stamina = CLIMB_TICKS


func _remove_robot_body(r: Robot) -> void:
	if r.body.is_valid():
		PhysicsServer2D.free_rid(r.body)
		r.body = RID()


func _read_bodies() -> void:
	for r: Robot in robots.values():
		if r.body.is_valid():
			var t: Transform2D = PhysicsServer2D.body_get_state(r.body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			r.pos = t.origin
			r.vel = PhysicsServer2D.body_get_state(r.body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	for p: Part in parts.values():
		if p.body.is_valid():
			var t: Transform2D = PhysicsServer2D.body_get_state(p.body, PhysicsServer2D.BODY_STATE_TRANSFORM)
			p.pos = t.origin
			p.rot = t.get_rotation()


# --- Robot hareketi ---

func _update_robot(r: Robot) -> void:
	var mask := r.mask if phase == Phase.RUN else 0
	var pressed_jump := (mask & JUMP) != 0 and (r.prev_mask & JUMP) == 0
	var dir := int((mask & RIGHT) != 0) - int((mask & LEFT) != 0)
	if r.is_bot and phase == Phase.RUN:
		mask = BotBrain.think(self, r)
		pressed_jump = (mask & JUMP) != 0 and (r.prev_mask & JUMP) == 0
		dir = int((mask & RIGHT) != 0) - int((mask & LEFT) != 0)
		r.mask = mask
	if (mask & SELF_DESTRUCT) != 0:
		_kill(r)
		return
	if dir != 0:
		r.facing = dir
	r.jump_lock = maxi(r.jump_lock - 1, 0)
	r.wall_lock = maxi(r.wall_lock - 1, 0)
	r.pad_cooldown = maxi(r.pad_cooldown - 1, 0)
	r.jump_buffer = JUMP_BUFFER_TICKS if pressed_jump else maxi(r.jump_buffer - 1, 0)
	_probe_ground(r)
	r.coyote = COYOTE_TICKS if r.on_ground else maxi(r.coyote - 1, 0)

	var v := r.vel
	var top := MAX_SPEED * r.speed_mul
	if r.on_ground:
		v = _ground_motion(r, v, dir, top)
		if dir != 0 and low_step_ahead(r, dir):
			v.y = minf(v.y, -STEP_UP_SPEED)
	else:
		if dir != 0 and v.x * dir < top and not (r.wall_lock > 0 and dir != signi(int(v.x))):
			v.x = move_toward(v.x, dir * top, AIR_ACCEL * DT)
	v = _climb(r, v, mask)
	v = _jumps(r, v, dir, mask, pressed_jump)
	v.y = minf(v.y, MAX_FALL)
	r.vel = v
	PhysicsServer2D.body_set_state(r.body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, v)
	_apply_pads(r)
	_check_goals(r)


func _ground_motion(r: Robot, v: Vector2, dir: int, top: float) -> Vector2:
	var n := r.ground_normal
	var t := Vector2(-n.y, n.x)
	var along := v.dot(t)
	var normal_part := v.dot(n)
	var grip := ICE_FACTOR if r.on_ice else 1.0
	if dir != 0:
		if along * dir < top:
			along = move_toward(along, dir * top, GROUND_ACCEL * grip * DT)
	else:
		along = move_toward(along, 0.0, GROUND_BRAKE * grip * DT)
	# Motor bir sonraki adımda yerçekimi ekleyecek; eğimde kaymasın diye teğet payı çıkarılır.
	return t * (along - GRAVITY * DT * t.y) + n * normal_part


## Shift basılıyken duvara tırmanır; güç yere inince dolar. Duvar bitince çıkıntıya atlar.
func _climb(r: Robot, v: Vector2, mask: int) -> Vector2:
	var was_climbing := r.climbing
	r.climbing = false
	if r.on_ground:
		r.stamina = CLIMB_TICKS
		r.vault_ticks = 0
	if r.vault_ticks > 0:
		# Üst kenarda gövde hâlâ duvara değer; tek itiş sıfırlanır, birkaç kare sürmeli.
		r.vault_ticks -= 1
		v.x = r.climb_side * CLIMB_VAULT_X
		return v
	if (mask & CLIMB) == 0 or r.jump_lock > 0:
		return v
	var wall := _wall_side(r)
	if wall == 0:
		if was_climbing:
			v.y = minf(v.y, -CLIMB_VAULT_Y)
			v.x = r.climb_side * CLIMB_VAULT_X
			r.vault_ticks = CLIMB_VAULT_TICKS
		return v
	if r.stamina <= 0:
		return v
	r.stamina -= 1
	r.climbing = true
	r.climb_side = wall
	r.facing = wall
	v.y = -CLIMB_SPEED
	v.x = wall * CLIMB_WALL_PRESS
	return v


func _jumps(r: Robot, v: Vector2, dir: int, mask: int, pressed: bool) -> Vector2:
	if pressed:
		_pop_balloons_on(r)
	var wall := 0 if r.on_ground else _wall_side(r)
	if r.jump_buffer > 0 and r.coyote > 0 and r.jump_lock == 0:
		v.y = -JUMP_SPEED
		r.coyote = 0
		r.jump_buffer = 0
		r.jump_lock = 10
		r.rising = true
		r.on_ground = false
		r.fx_jump = true
	elif r.jump_buffer > 0 and wall != 0 and r.jump_lock == 0:
		v.y = -WALL_JUMP_Y
		v.x = -wall * WALL_JUMP_X
		r.facing = -wall
		r.jump_buffer = 0
		r.jump_lock = 8
		r.wall_lock = WALL_LOCK_TICKS
		r.rising = true
		r.fx_jump = true
	elif wall != 0 and dir == wall and v.y > WALL_SLIDE_SPEED:
		v.y = WALL_SLIDE_SPEED
	if r.rising:
		if v.y >= 0.0:
			r.rising = false
		elif (mask & JUMP) == 0:
			v.y *= 0.55
			r.rising = false
	return v


func _probe_ground(r: Robot) -> void:
	r.on_ground = false
	r.on_ice = false
	if r.jump_lock > 0:
		return
	var state := PhysicsServer2D.space_get_direct_state(_space)
	var hh := ROBOT_SIZE.y * 0.5
	var best := -0.35
	_ray.exclude = [r.body]
	_ray.collision_mask = LAYER_WORLD | LAYER_ROBOT | LAYER_PART
	for dx: float in [-13.0, 0.0, 13.0]:
		_ray.from = r.pos + Vector2(dx, hh - 6.0)
		_ray.to = r.pos + Vector2(dx, hh + 7.0)
		var hit := state.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var n: Vector2 = hit["normal"]
		if n.y < best:
			best = n.y
			r.on_ground = true
			r.ground_normal = n
			r.on_ice = _ice.has(hit["rid"])
	if r.on_ground and r.vel.dot(r.ground_normal) > 120.0:
		r.on_ground = false


## Alçak basamakta (tahta ucu, yay) durmasın ve tahtayı boşluğa itmesin diye robot hafifçe sıçrar.
func low_step_ahead(r: Robot, dir: int) -> bool:
	var state := PhysicsServer2D.space_get_direct_state(_space)
	_ray.exclude = [r.body]
	_ray.collision_mask = LAYER_WORLD | LAYER_PART
	var hw := ROBOT_SIZE.x * 0.5
	var hh := ROBOT_SIZE.y * 0.5
	_ray.from = r.pos + Vector2(dir * (hw - 4.0), hh - 4.0)
	_ray.to = r.pos + Vector2(dir * (hw + 7.0), hh - 4.0)
	var low := state.intersect_ray(_ray)
	if low.is_empty() or absf((low["normal"] as Vector2).x) < 0.7:
		return false
	_ray.from = r.pos + Vector2(dir * (hw - 4.0), hh - STEP_UP_HEIGHT)
	_ray.to = r.pos + Vector2(dir * (hw + 7.0), hh - STEP_UP_HEIGHT)
	return state.intersect_ray(_ray).is_empty()


func _wall_side(r: Robot) -> int:
	var state := PhysicsServer2D.space_get_direct_state(_space)
	_ray.exclude = [r.body]
	_ray.collision_mask = LAYER_WORLD | LAYER_PART
	var hw := ROBOT_SIZE.x * 0.5
	for side: int in [-1, 1]:
		for dy: float in [-10.0, 8.0]:
			_ray.from = r.pos + Vector2(side * (hw - 5.0), dy)
			_ray.to = r.pos + Vector2(side * (hw + 5.0), dy)
			var hit := state.intersect_ray(_ray)
			if not hit.is_empty() and absf((hit["normal"] as Vector2).x) > 0.8:
				return side
	return 0


func _apply_pads(r: Robot) -> void:
	if r.pad_cooldown > 0:
		return
	for pad in _pads:
		var size: Vector2 = pad["s"]
		var center: Vector2 = pad["p"]
		var angle: float = pad["a"]
		var local := (r.pos - center).rotated(-angle)
		var above := -local.y - size.y * 0.5
		if absf(local.x) < size.x * 0.5 + 10.0 and above > -6.0 and above < ROBOT_SIZE.y * 0.5 + 8.0:
			var up := Vector2.UP.rotated(angle)
			var side := r.vel - up * r.vel.dot(up)
			var launched := side + up * SPRING_SPEED
			r.vel = launched
			r.pad_cooldown = 12
			r.jump_lock = 10
			r.rising = false
			PhysicsServer2D.body_set_state(r.body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, launched)
			_event({"t": "spring", "pos": center})
			return


func _check_goals(r: Robot) -> void:
	if r.pos.y > KILL_Y or _touching_spike(r):
		_kill(r)
		return
	var battery: Vector2 = map["battery"]
	var station: Vector2 = map["station"]
	if not r.has_battery and r.pos.distance_to(battery) < PICKUP_RADIUS:
		r.has_battery = true
		r.wp = 0
		r.wp_age = 0
		_event({"t": "pickup", "pid": r.pid})
	elif r.has_battery and r.pos.distance_to(station) < STATION_RADIUS:
		_finish(r)


func _touching_spike(r: Robot) -> bool:
	for spike in _spikes:
		var size: Vector2 = spike["s"]
		var center: Vector2 = spike["p"]
		var angle: float = spike["a"]
		var local := (r.pos - center).rotated(-angle)
		if absf(local.x) < size.x * 0.5 + ROBOT_SIZE.x * 0.4 and absf(local.y) < size.y * 0.5 + ROBOT_SIZE.y * 0.5 - 1.0:
			return true
	return false


func _kill(r: Robot) -> void:
	_event({"t": "death", "pid": r.pid, "pos": r.pos})
	r.life = Life.DEAD
	r.has_battery = false
	_remove_robot_body(r)
	_remove_balloons_on(r.pid)


func _finish(r: Robot) -> void:
	finished_count += 1
	var points: int = RANK_POINTS[finished_count - 1] if finished_count <= RANK_POINTS.size() else FINISH_POINTS
	r.score += points
	r.round_points += points
	if finished_count == 1:
		last_winner = r.pid
	r.life = Life.DONE
	r.has_battery = false
	_remove_robot_body(r)
	_remove_balloons_on(r.pid)
	var eng: Robot = robots.get(engineer_pid)
	if eng != null:
		eng.score += ENGINEER_POINTS
		eng.round_points += ENGINEER_POINTS
	_event({"t": "finish", "pid": r.pid, "rank": finished_count, "points": points})
	_emit_roster()


# --- Bot yardımcıları ---

func has_floor(x: float, y: float, depth: float) -> bool:
	var state := PhysicsServer2D.space_get_direct_state(_space)
	_ray.exclude = []
	_ray.collision_mask = LAYER_WORLD | LAYER_PART
	_ray.from = Vector2(x, y)
	_ray.to = Vector2(x, y + depth)
	return not state.intersect_ray(_ray).is_empty()


func wall_ahead(r: Robot, dir: int) -> bool:
	var state := PhysicsServer2D.space_get_direct_state(_space)
	_ray.exclude = [r.body]
	_ray.collision_mask = LAYER_WORLD | LAYER_PART
	_ray.from = r.pos + Vector2(0, 8)
	_ray.to = r.pos + Vector2(dir * (ROBOT_SIZE.x * 0.5 + 10.0), 8)
	return not state.intersect_ray(_ray).is_empty()


func spike_below(x: float, y: float) -> bool:
	for spike in _spikes:
		var size: Vector2 = spike["s"]
		var center: Vector2 = spike["p"]
		if absf(x - center.x) < size.x * 0.5 and center.y > y and center.y - y < 90.0:
			return true
	return false


# --- Mühendis parçaları ---

## Dönüş değeri boşsa parça kondu, doluysa neden konamadığıdır.
func try_place(pid: int, kind: int, pos: Vector2, rot_deg: int) -> String:
	var r: Robot = robots.get(pid)
	if r == null or r.life != Life.ENGINEER:
		return "Parçayı yalnızca Mühendis koyabilir."
	if phase == Phase.RESULT:
		return "Tur bitti."
	if kind < 0 or kind >= PART_INFO.size():
		return "Bilinmeyen parça."
	if r.place_cooldown > 0:
		return "Biraz bekle."
	if r.placed[kind] >= int(PART_INFO[kind]["limit"]):
		return "%s kalmadı." % str(PART_INFO[kind]["name"])
	if parts.size() >= MAX_PARTS:
		return "Haritada çok fazla parça var."
	var rot := deg_to_rad(float(posmod(rot_deg, 360)))
	var error := placement_error(kind, pos, rot, _terrain_polys, part_list(), robot_positions())
	if error != "":
		return error
	if kind == Kind.BOLT:
		error = _bolt_error(pos)
		if error != "":
			return error
	_create_part(kind, pos, rot)
	r.placed[kind] += 1
	r.place_cooldown = PLACE_COOLDOWN
	return ""


func part_list() -> Array:
	var out: Array = []
	for p: Part in parts.values():
		out.append({"id": p.id, "kind": p.kind, "pos": p.pos, "rot": p.rot})
	return out


func robot_positions() -> Array:
	var out: Array = []
	for r: Robot in robots.values():
		if r.body.is_valid():
			out.append(r.pos)
	return out


static func is_dynamic(kind: int) -> bool:
	return kind == Kind.PLANK or kind == Kind.LONG_PLANK or kind == Kind.BOX


static func part_local_points(kind: int) -> Array:
	var size: Vector2 = PART_INFO[kind]["size"]
	var half := size * 0.5
	match kind:
		Kind.RAMP:
			return [Vector2(-half.x, half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y)]
		Kind.BALLOON:
			var circle: Array = []
			for i in 8:
				circle.append(Vector2.RIGHT.rotated(TAU * i / 8.0) * half.x)
			return circle
	return [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]


static func part_polygon(kind: int, pos: Vector2, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in part_local_points(kind):
		out.append(pos + p.rotated(rot))
	return out


static func robot_polygon(pos: Vector2) -> PackedVector2Array:
	var half := ROBOT_SIZE * 0.5
	return PackedVector2Array([pos + Vector2(-half.x, -half.y), pos + Vector2(half.x, -half.y), pos + Vector2(half.x, half.y), pos + Vector2(-half.x, half.y)])


## İstemci hayalet parçayı aynı denetimle renklendirir; sunucuyla anlaşmazlık olmasın.
static func placement_error(kind: int, pos: Vector2, rot: float, terrain: Array, part_rows: Array, robot_rows: Array) -> String:
	if pos.x < 0.0 or pos.x > Maps.WIDTH or pos.y < 0.0 or pos.y > Maps.HEIGHT:
		return "Harita dışına koyamazsın."
	if kind == Kind.BOLT:
		return "" if find_part_at(pos, part_rows) != 0 else "Cıvata bir tahtaya ya da kutuya takılır."
	var poly := part_polygon(kind, pos, rot)
	if kind == Kind.BALLOON:
		for t: PackedVector2Array in terrain:
			if _overlaps(poly, t):
				return "Balon zemine giremez."
		return ""
	for rp: Vector2 in robot_rows:
		if _overlaps(poly, robot_polygon(rp)):
			return "Robotun üstüne koyamazsın."
	for row: Dictionary in part_rows:
		var other: int = row["kind"]
		if other == Kind.BOLT or other == Kind.BALLOON:
			continue
		if _overlaps(poly, part_polygon(other, row["pos"], row["rot"])):
			return "Başka bir parçanın içine koyamazsın."
	if is_dynamic(kind):
		for t: PackedVector2Array in terrain:
			if _overlaps(poly, t):
				return "Zeminin içine koyamazsın."
	return ""


static func find_part_at(pos: Vector2, part_rows: Array) -> int:
	for row: Dictionary in part_rows:
		var kind: int = row["kind"]
		if is_dynamic(kind) and Geometry2D.is_point_in_polygon(pos, part_polygon(kind, row["pos"], row["rot"])):
			return row["id"]
	return 0


static func _overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()


func _bolt_error(pos: Vector2) -> String:
	var host: Part = parts.get(find_part_at(pos, part_list()))
	if host == null:
		return "Cıvata bir tahtaya ya da kutuya takılır."
	if host.bolts >= 2:
		return "Bu parça zaten sabit."
	return ""


func _create_part(kind: int, pos: Vector2, rot: float) -> void:
	var p := Part.new()
	p.id = _next_part
	_next_part += 1
	p.kind = kind
	p.pos = pos
	p.rot = rot
	var mass: float = PART_INFO[kind]["mass"]
	match kind:
		Kind.BALLOON:
			_setup_balloon(p)
		Kind.BOLT:
			_setup_bolt(p)
		Kind.RAMP, Kind.SPRING:
			p.body = _new_body(PhysicsServer2D.BODY_MODE_STATIC, part_local_points(kind), pos, rot, LAYER_PART, 0.9, 1.0)
			if kind == Kind.SPRING:
				_pads.append({"p": pos, "s": PART_INFO[kind]["size"], "a": rot})
		_:
			p.body = _new_body(PhysicsServer2D.BODY_MODE_RIGID, part_local_points(kind), pos, rot, LAYER_PART, 0.9, mass)
	parts[p.id] = p


func _setup_balloon(p: Part) -> void:
	var nearest := BALLOON_ATTACH_RANGE
	for q: Part in parts.values():
		if is_dynamic(q.kind) and q.pos.distance_to(p.pos) < nearest:
			nearest = q.pos.distance_to(p.pos)
			p.host_part = q.id
			p.offset = Vector2(0, -44)
	for r: Robot in robots.values():
		if r.body.is_valid() and r.pos.distance_to(p.pos) < nearest:
			nearest = r.pos.distance_to(p.pos)
			p.host_robot = r.pid
			p.host_part = 0
			p.offset = Vector2(0, -62)
	if p.host_part != 0 or p.host_robot != 0:
		p.ttl = BALLOON_ATTACHED_TICKS
	else:
		p.ttl = BALLOON_FREE_TICKS
		p.body = _new_body(PhysicsServer2D.BODY_MODE_RIGID, part_local_points(Kind.BALLOON), p.pos, 0.0, LAYER_PART, 0.3, 0.4)
		PhysicsServer2D.body_set_param(p.body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -0.3)


## İlk cıvata mil olur; ikincisi parçayı tamamen sabitler.
func _setup_bolt(p: Part) -> void:
	var host: Part = parts.get(find_part_at(p.pos, part_list()))
	p.host_part = host.id
	host.bolts += 1
	if host.bolts == 1:
		host.joint = PhysicsServer2D.joint_create()
		PhysicsServer2D.joint_make_pin(host.joint, p.pos, host.body, _anchor)
	else:
		PhysicsServer2D.free_rid(host.joint)
		host.joint = RID()
		PhysicsServer2D.body_set_mode(host.body, PhysicsServer2D.BODY_MODE_STATIC)


func _update_parts() -> void:
	for p: Part in parts.values():
		if p.ttl > 0:
			p.ttl -= 1
			if p.ttl == 0:
				_remove_part(p)
				continue
		if p.kind == Kind.BALLOON:
			if not _update_balloon(p):
				continue
		if p.pos.y > PART_KILL_Y or p.pos.y < -200.0:
			_remove_part(p)


func _update_balloon(p: Part) -> bool:
	var host_body := RID()
	var host_pos := Vector2.ZERO
	if p.host_robot != 0:
		var r: Robot = robots.get(p.host_robot)
		if r == null or not r.body.is_valid():
			_remove_part(p)
			return false
		host_body = r.body
		host_pos = r.pos
	elif p.host_part != 0:
		var q: Part = parts.get(p.host_part)
		if q == null:
			_remove_part(p)
			return false
		if q.bolts >= 2:
			return true
		host_body = q.body
		host_pos = q.pos
	else:
		return true
	p.pos = host_pos + p.offset
	var v: Vector2 = PhysicsServer2D.body_get_state(host_body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	if v.y > -LIFT_MAX_SPEED:
		v.y -= LIFT_ACCEL * DT
		PhysicsServer2D.body_set_state(host_body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, v)
	return true


func _pop_balloons_on(r: Robot) -> void:
	if not r.on_ground:
		_remove_balloons_on(r.pid)


func _remove_balloons_on(pid: int) -> void:
	for p: Part in parts.values():
		if p.kind == Kind.BALLOON and p.host_robot == pid:
			_remove_part(p)


func _remove_part(p: Part) -> void:
	if not parts.has(p.id):
		return
	parts.erase(p.id)
	_free_part_rids(p)
	for other: Part in parts.values():
		if other.host_part == p.id:
			_remove_part(other)


func _free_part_rids(p: Part) -> void:
	if p.joint.is_valid():
		PhysicsServer2D.free_rid(p.joint)
		p.joint = RID()
	if p.body.is_valid():
		PhysicsServer2D.free_rid(p.body)
		p.body = RID()


# --- Durum yayını ---

func _event(ev: Dictionary) -> void:
	_events.append(ev)


func _emit_roster() -> void:
	var rows: Array = []
	for r: Robot in robots.values():
		rows.append({"pid": r.pid, "name": r.name, "color": r.color, "acc": r.acc, "score": r.score, "rp": r.round_points, "bot": r.is_bot})
	_event({"t": "roster", "rows": rows})


## Sonradan katılan oyuncuya gönderilecek başlangıç olayı.
func round_info() -> Dictionary:
	return {"t": "round", "map": map_index, "engineer": engineer_pid}


func snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u8(phase)
	b.put_u16(clampi(timer, 0, 65535))
	var active: Array[Robot] = []
	for r: Robot in robots.values():
		if r.body.is_valid():
			active.append(r)
	b.put_u8(active.size())
	for r in active:
		var level := ceili(float(r.stamina) * STAMINA_LEVELS / CLIMB_TICKS)
		var flags := int(r.has_battery) | (int(r.facing > 0) << 1) | (int(r.on_ground) << 2) | (int(r.fx_jump) << 3) | (int(r.climbing) << 4) | (level << 5)
		r.fx_jump = false
		b.put_u8(r.pid)
		b.put_u8(flags)
		_put_pos(b, r.pos)
		_put_pos(b, r.vel)
	b.put_u8(parts.size())
	for p: Part in parts.values():
		b.put_u16(p.id)
		b.put_u8(p.kind)
		_put_pos(b, p.pos)
		b.put_16(int(wrapf(p.rot, -PI, PI) * 1000.0))
	var eng: Robot = robots.get(engineer_pid)
	if eng != null and eng.life == Life.ENGINEER:
		b.put_u8(eng.pid)
		_put_pos(b, eng.aim)
		b.put_u8(eng.aim_kind)
		b.put_16(eng.aim_rot)
		for k in PART_INFO.size():
			b.put_u8(int(PART_INFO[k]["limit"]) - eng.placed[k])
	else:
		b.put_u8(0)
	return b.data_array


static func _put_pos(b: StreamPeerBuffer, p: Vector2) -> void:
	b.put_16(clampi(int(p.x * 2.0), -32000, 32000))
	b.put_16(clampi(int(p.y * 2.0), -32000, 32000))


static func _get_pos(b: StreamPeerBuffer) -> Vector2:
	var x := b.get_16() * 0.5
	var y := b.get_16() * 0.5
	return Vector2(x, y)


static func parse_snapshot(bytes: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var out := {"tick": b.get_u32(), "phase": b.get_u8(), "timer": b.get_u16()}
	var bots: Dictionary = {}
	for i in b.get_u8():
		var pid := b.get_u8()
		var flags := b.get_u8()
		var pos := _get_pos(b)
		var vel := _get_pos(b)
		bots[pid] = {
			"pos": pos, "vel": vel, "battery": (flags & 1) != 0, "facing": 1 if (flags & 2) != 0 else -1,
			"ground": (flags & 4) != 0, "jump": (flags & 8) != 0,
			"climb": (flags & 16) != 0, "stamina": (flags >> 5) & 7,
		}
	out["robots"] = bots
	var part_rows: Dictionary = {}
	for i in b.get_u8():
		var id := b.get_u16()
		var kind := b.get_u8()
		var pos := _get_pos(b)
		var rot := b.get_16() / 1000.0
		part_rows[id] = {"id": id, "kind": kind, "pos": pos, "rot": rot}
	out["parts"] = part_rows
	var eng_pid := b.get_u8()
	out["eng"] = {}
	if eng_pid != 0:
		var aim := _get_pos(b)
		var aim_kind := b.get_u8()
		var aim_rot := b.get_16()
		var left: Array[int] = []
		for k in PART_INFO.size():
			left.append(b.get_u8())
		out["eng"] = {"pid": eng_pid, "aim": aim, "kind": aim_kind, "rot": aim_rot, "left": left}
	return out
