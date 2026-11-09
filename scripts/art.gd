class_name Art
extends RefCounted
## Tüm görseller kodla çizilir; dosyadan görsel yüklenmez.

const COLORS := [
	Color("ff6b5e"), Color("ffb347"), Color("ffe066"), Color("5fd38d"),
	Color("4fc3f7"), Color("7e8cff"), Color("d17bff"), Color("eef1f6"),
]
const ACCESSORIES := ["Yok", "Anten", "Silindir", "Pervane", "Kulaklık", "Boynuz"]

const SKY_TOP := Color("0f2233")
const SKY_BOTTOM := Color("23495c")
const GEAR_COLOR := Color(0.55, 0.8, 0.9, 0.07)
const STEEL := Color("4a6275")
const STEEL_DARK := Color("2f4252")
const STEEL_TOP := Color("9fc0d0")
const ICE := Color("9fe6f5")
const ICE_DARK := Color("5fb7d0")
const WOOD := Color("c58f55")
const WOOD_DARK := Color("8c5f33")
const GLOW_GREEN := Color("5dffa0")
const AMBER := Color("ffc94d")


static func rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(radius, radius), PI],
		[rect.position + Vector2(rect.size.x - radius, radius), PI * 1.5],
		[rect.position + rect.size - Vector2(radius, radius), 0.0],
		[rect.position + Vector2(radius, rect.size.y - radius), PI * 0.5],
	]
	for c: Array in corners:
		var center: Vector2 = c[0]
		var start: float = c[1]
		for i in 5:
			pts.append(center + Vector2.RIGHT.rotated(start + PI * 0.5 * i / 4.0) * radius)
	return pts


static func panel(c: CanvasItem, rect: Rect2, radius: float, fill: Color, line := Color.TRANSPARENT, width := 2.0) -> void:
	var pts := rounded(rect, radius)
	c.draw_colored_polygon(pts, fill)
	if line.a > 0.0:
		pts.append(pts[0])
		c.draw_polyline(pts, line, width, true)


static func background(c: CanvasItem, time: float) -> void:
	var bands := 36
	for i in bands:
		var k := float(i) / (bands - 1)
		c.draw_rect(Rect2(0, 720.0 * i / bands, 1280, 720.0 / bands + 1.0), SKY_TOP.lerp(SKY_BOTTOM, k))
	gear(c, Vector2(180, 170), 120.0, 12, time * 0.12, GEAR_COLOR)
	gear(c, Vector2(345, 92), 72.0, 8, -time * 0.2, GEAR_COLOR)
	gear(c, Vector2(1060, 150), 150.0, 14, -time * 0.09, GEAR_COLOR)
	gear(c, Vector2(830, 420), 90.0, 10, time * 0.15, GEAR_COLOR)
	gear(c, Vector2(480, 470), 64.0, 8, -time * 0.22, GEAR_COLOR)
	for y: float in [262.0, 610.0]:
		c.draw_rect(Rect2(0, y, 1280, 12), Color(0.6, 0.85, 0.95, 0.04))


static func gear(c: CanvasItem, center: Vector2, radius: float, teeth: int, angle: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var inner := radius * 0.82
	var slice := TAU / teeth
	for i in teeth:
		var a := angle + slice * i
		pts.append(center + Vector2.RIGHT.rotated(a - slice * 0.28) * inner)
		pts.append(center + Vector2.RIGHT.rotated(a - slice * 0.14) * radius)
		pts.append(center + Vector2.RIGHT.rotated(a + slice * 0.14) * radius)
		pts.append(center + Vector2.RIGHT.rotated(a + slice * 0.28) * inner)
	c.draw_colored_polygon(pts, color)
	c.draw_circle(center, radius * 0.3, Color(SKY_TOP, 0.55))


static func tile(c: CanvasItem, data: Dictionary, time: float) -> void:
	var size: Vector2 = data["s"]
	c.draw_set_transform(data["p"], data["a"], Vector2.ONE)
	var half := size * 0.5
	var rect := Rect2(-half, size)
	match int(data["k"]):
		Maps.Tile.SOLID:
			_solid(c, rect)
		Maps.Tile.ICE:
			_ice_block(c, rect)
		Maps.Tile.SPIKE:
			_spikes(c, rect, time)
		Maps.Tile.SPRING:
			spring_shape(c, size)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _solid(c: CanvasItem, rect: Rect2) -> void:
	c.draw_rect(rect, STEEL_DARK)
	c.draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.y, 34.0))), STEEL)
	c.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), STEEL_TOP)
	var x := rect.position.x + 22.0
	while x < rect.end.x - 10.0:
		if rect.size.y >= 22.0:
			c.draw_circle(Vector2(x, rect.position.y + 16.0), 2.5, STEEL_DARK)
		if rect.size.y > 60.0:
			c.draw_line(Vector2(x + 26.0, rect.position.y + 34.0), Vector2(x + 26.0, rect.end.y), Color(0, 0, 0, 0.14), 2.0)
		x += 52.0


static func _ice_block(c: CanvasItem, rect: Rect2) -> void:
	c.draw_rect(rect, ICE_DARK)
	c.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6.0)), Color.WHITE)
	var x := rect.position.x + 10.0
	while x < rect.end.x - 12.0:
		c.draw_line(Vector2(x, rect.end.y - 3.0), Vector2(x + 10.0, rect.position.y + 8.0), ICE, 2.0)
		x += 24.0


static func _spikes(c: CanvasItem, rect: Rect2, time: float) -> void:
	var width := 22.0
	var count := maxi(int(rect.size.x / width), 1)
	var step := rect.size.x / count
	var glow := 0.75 + 0.25 * sin(time * 4.0)
	for i in count:
		var x := rect.position.x + step * i
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(x, rect.end.y), Vector2(x + step * 0.5, rect.position.y), Vector2(x + step, rect.end.y)
		]), Color("6d7a88"))
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(x + step * 0.36, rect.position.y + rect.size.y * 0.42),
			Vector2(x + step * 0.5, rect.position.y),
			Vector2(x + step * 0.64, rect.position.y + rect.size.y * 0.42),
		]), Color(1.0, 0.33, 0.28, glow))


static func spring_shape(c: CanvasItem, size: Vector2, alpha := 1.0) -> void:
	var half := size * 0.5
	c.draw_rect(Rect2(-half.x, half.y - 5.0, size.x, 5.0), Color(STEEL_DARK, alpha))
	var coil := PackedVector2Array()
	var n := 8
	for i in n + 1:
		var x := lerpf(-half.x + 12.0, half.x - 12.0, float(i) / n)
		coil.append(Vector2(x, half.y - 5.0 if i % 2 == 0 else -half.y + 5.0))
	c.draw_polyline(coil, Color(AMBER, alpha), 3.0, true)
	c.draw_rect(Rect2(-half.x, -half.y, size.x, 6.0), Color(1.0, 0.45, 0.3, alpha))


static func part(c: CanvasItem, kind: int, pos: Vector2, rot: float, alpha := 1.0) -> void:
	var size: Vector2 = Arena.PART_INFO[kind]["size"]
	var half := size * 0.5
	c.draw_set_transform(pos, rot, Vector2.ONE)
	match kind:
		Arena.Kind.PLANK, Arena.Kind.LONG_PLANK:
			c.draw_rect(Rect2(-half, size), Color(WOOD, alpha))
			c.draw_rect(Rect2(-half, Vector2(size.x, 3.0)), Color(WOOD.lightened(0.3), alpha))
			c.draw_rect(Rect2(-half.x, half.y - 3.0, size.x, 3.0), Color(WOOD_DARK, alpha))
			var x := -half.x + 34.0
			while x < half.x:
				c.draw_line(Vector2(x, -half.y + 3.0), Vector2(x, half.y - 3.0), Color(WOOD_DARK, alpha * 0.6), 1.5)
				x += 46.0
		Arena.Kind.BOX:
			c.draw_rect(Rect2(-half, size), Color(WOOD, alpha))
			c.draw_rect(Rect2(-half, size), Color(WOOD_DARK, alpha), false, 4.0)
			c.draw_line(-half + Vector2(4, 4), half - Vector2(4, 4), Color(WOOD_DARK, alpha), 4.0)
			c.draw_line(Vector2(half.x - 4.0, -half.y + 4.0), Vector2(-half.x + 4.0, half.y - 4.0), Color(WOOD_DARK, alpha), 4.0)
		Arena.Kind.BALLOON:
			c.draw_line(Vector2(0, half.y - 2.0), Vector2(3, half.y + 24.0), Color(1, 1, 1, alpha * 0.7), 1.5)
			c.draw_circle(Vector2.ZERO, half.x, Color(1.0, 0.36, 0.42, alpha))
			c.draw_circle(Vector2(-6, -7), 6.0, Color(1, 1, 1, alpha * 0.5))
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(-5, half.y + 5.0), Vector2(0, half.y - 3.0), Vector2(5, half.y + 5.0)
			]), Color(0.8, 0.2, 0.3, alpha))
		Arena.Kind.RAMP:
			var pts := PackedVector2Array()
			for p: Vector2 in Arena.part_local_points(kind):
				pts.append(p)
			c.draw_colored_polygon(pts, Color(STEEL, alpha))
			c.draw_line(pts[0], pts[1], Color(STEEL_TOP, alpha), 4.0, true)
		Arena.Kind.SPRING:
			spring_shape(c, size, alpha)
		Arena.Kind.BOLT:
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(Vector2.RIGHT.rotated(TAU * i / 6.0) * 9.0)
			c.draw_colored_polygon(hex, Color("c9d3dc", alpha))
			c.draw_line(Vector2(-5, 0), Vector2(5, 0), Color(0.2, 0.25, 0.3, alpha), 2.5)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func robot(c: CanvasItem, p: Vector2, color_index: int, acc: int, facing: int, spin: float, battery: bool, time: float, climbing := false) -> void:
	var base: Color = COLORS[posmod(color_index, COLORS.size())]
	var dark := base.darkened(0.42)
	for dx: float in [-10.0, 10.0]:
		var wheel := p + Vector2(dx, 16.0)
		c.draw_circle(wheel, 6.5, Color("232a35"))
		c.draw_circle(wheel, 2.5, Color("9aa8b5"))
		c.draw_line(wheel, wheel + Vector2.RIGHT.rotated(spin) * 5.5, Color("9aa8b5"), 1.5)
	panel(c, Rect2(p + Vector2(-16, -20), Vector2(32, 34)), 9.0, base, dark, 2.0)
	panel(c, Rect2(p + Vector2(-12, -15), Vector2(24, 15)), 5.0, Color("12202e"))
	var look := Vector2(facing * 2.5, 0)
	var blink := fmod(time + p.x * 0.01, 3.2) < 0.1
	var eye := Color("7df2ff")
	for dx: float in [-5.0, 5.0]:
		var e := p + Vector2(dx, -8) + look
		if blink:
			c.draw_line(e - Vector2(3, 0), e + Vector2(3, 0), eye, 2.0)
		else:
			c.draw_circle(e, 3.0, eye)
	c.draw_rect(Rect2(p + Vector2(-8, 5), Vector2(16, 3)), dark)
	_accessory(c, p, acc, time)
	if climbing:
		var reach := sin(time * 16.0) * 6.0
		for sign_y: float in [-1.0, 1.0]:
			var hand := p + Vector2(facing * 17.0, sign_y * (7.0 + sign_y * reach))
			c.draw_line(p + Vector2(facing * 12.0, sign_y * 4.0), hand, Color("cfd8e0"), 3.0)
			c.draw_circle(hand, 3.0, Art.AMBER)
	if battery:
		battery_icon(c, p + Vector2(0, -44), 0.72, time)


static func _accessory(c: CanvasItem, p: Vector2, acc: int, time: float) -> void:
	var top := p + Vector2(0, -20)
	match acc:
		1:
			c.draw_line(top, top + Vector2(0, -14), Color("cfd8e0"), 2.0)
			c.draw_circle(top + Vector2(0, -16), 3.5, Color(1.0, 0.35, 0.3, 0.7 + 0.3 * sin(time * 6.0)))
		2:
			c.draw_rect(Rect2(top + Vector2(-14, -3), Vector2(28, 4)), Color("1c1f26"))
			c.draw_rect(Rect2(top + Vector2(-9, -20), Vector2(18, 18)), Color("1c1f26"))
			c.draw_rect(Rect2(top + Vector2(-9, -7), Vector2(18, 4)), Color("d63c4b"))
		3:
			c.draw_line(top, top + Vector2(0, -8), Color("cfd8e0"), 2.0)
			var w := cos(time * 22.0) * 16.0
			c.draw_line(top + Vector2(-w, -9), top + Vector2(w, -9), Color("ffd166"), 3.0)
		4:
			c.draw_arc(p + Vector2(0, -9), 18.0, PI, TAU, 16, Color("1c1f26"), 3.0, true)
			for side: float in [-1.0, 1.0]:
				c.draw_rect(Rect2(p + Vector2(side * 18.0 - 3.0, -14), Vector2(6, 12)), Color("e0475b"))
		5:
			for side: float in [-1.0, 1.0]:
				c.draw_colored_polygon(PackedVector2Array([
					top + Vector2(side * 12.0, 2), top + Vector2(side * 16.0, -13), top + Vector2(side * 5.0, 2)
				]), Color("f0e6d2"))


static func drone(c: CanvasItem, p: Vector2, color_index: int, time: float) -> void:
	var base: Color = COLORS[posmod(color_index, COLORS.size())]
	var bob := p + Vector2(0, sin(time * 3.0) * 3.0)
	c.draw_arc(bob, 34.0, time, time + TAU * 0.8, 32, Color(AMBER, 0.65), 2.0, true)
	for side: float in [-1.0, 1.0]:
		var arm := bob + Vector2(side * 22.0, -6.0)
		c.draw_line(bob, arm, Color("cfd8e0"), 3.0)
		var w := cos(time * 28.0 + side) * 13.0
		c.draw_line(arm + Vector2(-w, -3), arm + Vector2(w, -3), Color(1, 1, 1, 0.75), 2.5)
	c.draw_circle(bob, 15.0, base)
	c.draw_circle(bob, 15.0, base.darkened(0.42), false, 2.0, true)
	c.draw_circle(bob + Vector2(0, 1), 7.5, Color("12202e"))
	c.draw_circle(bob + Vector2(0, 1), 3.5, Color("7df2ff"))


static func battery_icon(c: CanvasItem, p: Vector2, scale_factor: float, time: float) -> void:
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	c.draw_circle(p, 30.0 * scale_factor, Color(GLOW_GREEN, 0.1 + 0.1 * pulse))
	c.draw_set_transform(p, 0.0, Vector2.ONE * scale_factor)
	c.draw_rect(Rect2(-7, -24, 14, 7), Color("b9f6ca"))
	panel(c, Rect2(-14, -18, 28, 40), 5.0, Color("35b869"), Color("176b3c"), 2.0)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(3, -13), Vector2(-8, 3), Vector2(-1, 3), Vector2(-3, 17), Vector2(8, -1), Vector2(1, -1)
	]), Color.WHITE)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func station(c: CanvasItem, p: Vector2, time: float) -> void:
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	c.draw_circle(p, 62.0, Color(AMBER, 0.05 + 0.07 * pulse))
	var base := p + Vector2(0, 42)
	c.draw_rect(Rect2(base + Vector2(-46, -8), Vector2(92, 10)), STEEL_DARK)
	c.draw_rect(Rect2(base + Vector2(-46, -8), Vector2(92, 3)), AMBER)
	c.draw_rect(Rect2(p + Vector2(-44, -40), Vector2(10, 74)), STEEL)
	c.draw_rect(Rect2(p + Vector2(34, -40), Vector2(10, 74)), STEEL)
	panel(c, Rect2(p + Vector2(-44, -56), Vector2(88, 22)), 7.0, STEEL, STEEL_DARK, 2.0)
	c.draw_colored_polygon(PackedVector2Array([
		p + Vector2(4, -53), p + Vector2(-8, -44), p + Vector2(-1, -44),
		p + Vector2(-5, -37), p + Vector2(8, -47), p + Vector2(1, -47)
	]), AMBER)
	var beam := Color(AMBER, 0.08 + 0.1 * pulse)
	c.draw_rect(Rect2(p + Vector2(-34, -34), Vector2(68, 68)), beam)
