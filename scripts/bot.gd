class_name BotBrain
extends RefCounted
## Basit bot: haritadaki rota noktalarını izler; duvarda, boşlukta ve dikende zıplar.

const STUCK_CHECK_TICKS := 45
const WAYPOINT_PATIENCE_TICKS := 360
const MAX_RETRIES := 4


static func think(a: Arena, r: Arena.Robot) -> int:
	# Botlar aynı anda çıkarsa yayda üst üste binip birbirini boşluğa savuruyor.
	if r.start_delay > 0:
		r.start_delay -= 1
		return 0
	var route: Array = a.map["back"] if r.has_battery else a.map["out"]
	r.wp = mini(r.wp, route.size() - 1)
	var point: Vector3 = route[r.wp]
	var near := absf(point.x - r.pos.x) < 30.0 and absf(point.y - r.pos.y) < 80.0
	if near and (r.on_ground or point.z > 0.0) and r.wp < route.size() - 1:
		r.wp += 1
		r.wp_age = 0
		point = route[r.wp]
	r.wp_age += 1
	if r.wp_age > WAYPOINT_PATIENCE_TICKS:
		r.wp_age = 0
		r.wp = maxi(r.wp - 1, 0)
		r.stuck_count += 1
		if r.stuck_count >= MAX_RETRIES:
			return Arena.SELF_DESTRUCT
		point = route[r.wp]
	var target := Vector2(point.x, point.y)
	var dx := target.x - r.pos.x
	var dir := 0
	if absf(dx) > 8.0:
		dir = 1 if dx > 0.0 else -1
	if not r.on_ground and dir != 0 and r.vel.x * dir > 0.0:
		# Havada duruş mesafesi hedefe yetmiyorsa ters tuşla frenler, kenardan aşmaz.
		var stopping := r.vel.x * r.vel.x / (2.0 * Arena.AIR_ACCEL)
		if absf(dx) < stopping + 12.0:
			dir = -dir
	var mask := 0
	if dir > 0:
		mask |= Arena.RIGHT
	elif dir < 0:
		mask |= Arena.LEFT
	if r.on_ground:
		if _should_jump(a, r, dir, target, dx):
			mask |= Arena.JUMP
	elif r.vel.y < 0.0:
		mask |= Arena.JUMP
	return _unstick(r, mask)


static func _should_jump(a: Arena, r: Arena.Robot, dir: int, target: Vector2, dx: float) -> bool:
	if (r.prev_mask & Arena.JUMP) != 0:
		return false
	if dir != 0:
		var ahead := r.pos.x + dir * 44.0
		if a.wall_ahead(r, dir) and not a.low_step_ahead(r, dir):
			return true
		if absf(dx) > 40.0 and (not a.has_floor(ahead, r.pos.y, 260.0) or a.spike_below(ahead, r.pos.y)):
			return true
	# Ters yönde hızlıyken zıplarsa karşıya yetişemez; önce toparlanır.
	return target.y < r.pos.y - 50.0 and absf(dx) < 190.0 and r.vel.x * dir > 150.0


## Yerinde sayan bot zıplayarak kurtulmayı dener.
static func _unstick(r: Arena.Robot, mask: int) -> int:
	r.stuck_timer += 1
	if r.stuck_timer < STUCK_CHECK_TICKS:
		return mask
	r.stuck_timer = 0
	var moved := r.pos.distance_to(r.stuck_pos) >= 12.0
	r.stuck_pos = r.pos
	return mask if moved else mask | Arena.JUMP
