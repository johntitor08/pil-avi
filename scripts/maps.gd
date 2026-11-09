class_name Maps
extends RefCounted
## Haritalar. Dünya tek ekrandır (1280x720), kamera yoktur; Mühendis her yeri görür.
## "out" pile, "back" istasyona giden bot rotalarıdır; "help" bot Mühendisin planıdır.

enum Tile { SOLID, ICE, SPIKE, SPRING }

const WIDTH := 1280.0
const HEIGHT := 720.0

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = [_bridge(), _ice_towers(), _valley()]
	return _cache


static func get_map(index: int) -> Dictionary:
	var list := all()
	return list[posmod(index, list.size())]


## Her karonun köşeleri; yerleştirme denetimi sunucuda ve istemcide aynı olsun diye.
static func polygons(map: Dictionary) -> Array:
	var out: Array = []
	for tile: Dictionary in map["tiles"]:
		out.append(tile_polygon(tile))
	return out


static func tile_polygon(tile: Dictionary) -> PackedVector2Array:
	var size: Vector2 = tile["s"]
	var center: Vector2 = tile["p"]
	var angle: float = tile["a"]
	var half := size * 0.5
	var pts := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		pts.append(center + corner.rotated(angle))
	return pts


static func _box(x0: float, y0: float, x1: float, y1: float, kind: int = Tile.SOLID) -> Dictionary:
	return {"p": Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5), "s": Vector2(x1 - x0, y1 - y0), "a": 0.0, "k": kind}


## Bot rota noktası: _on yere inince, _over havadan geçerken de sayılır.
static func _on(x: float, y: float) -> Vector3:
	return Vector3(x, y, 0.0)


static func _over(x: float, y: float) -> Vector3:
	return Vector3(x, y, 1.0)


static func _help(at_tick: int, kind: int, pos: Vector2, degrees: int = 0) -> Dictionary:
	return {"t": at_tick, "k": kind, "p": pos, "r": degrees}


## Ortada bir boşluk, uzak uçta bir basamak: ilk harita, öğretici.
static func _bridge() -> Dictionary:
	return {
		"name": "Köprü Başı",
		"spawn": Vector2(220, 510),
		"battery": Vector2(1190, 395),
		"station": Vector2(70, 516),
		"tiles": [
			_box(0, 560, 430, 720),
			_box(650, 560, 900, 720),
			_box(900, 440, 1280, 720),
		],
		"out": [_on(790, 515), _on(960, 395), _on(1190, 395)],
		"back": [_on(790, 515), _on(320, 515), _on(70, 515)],
		"help": [
			_help(30, Arena.Kind.LONG_PLANK, Vector2(540, 552)),
			_help(50, Arena.Kind.BOLT, Vector2(-115, 0)),
			_help(70, Arena.Kind.BOLT, Vector2(115, 0)),
		],
	}


## Dikenli zemin üstünde basamaklar; inişteki platformlar buz.
static func _ice_towers() -> Dictionary:
	return {
		"name": "Buz Kuleleri",
		"spawn": Vector2(100, 596),
		"battery": Vector2(640, 288),
		"station": Vector2(1215, 596),
		"tiles": [
			_box(0, 640, 1280, 720),
			_box(350, 622, 1100, 640, Tile.SPIKE),
			_box(180, 540, 340, 566),
			_box(400, 440, 540, 466),
			_box(560, 330, 720, 356),
			_box(770, 430, 880, 450, Tile.ICE),
			_box(930, 530, 1060, 550, Tile.ICE),
			_box(1110, 430, 1150, 640),
		],
		"out": [_on(130, 596), _on(260, 495), _on(470, 395), _on(640, 288)],
		"back": [_on(825, 385), _on(995, 485), _over(1130, 385), _on(1215, 596)],
		"help": [_help(40, Arena.Kind.RAMP, Vector2(1010, 495))],
	}


## Boşlukta adacıklar; yukarı çıkmanın yolu ortadaki yay.
static func _valley() -> Dictionary:
	return {
		"name": "Yaylı Vadi",
		"spawn": Vector2(110, 436),
		"battery": Vector2(1200, 218),
		"station": Vector2(222, 436),
		"tiles": [
			_box(0, 480, 260, 720),
			_box(330, 540, 540, 720),
			_box(430, 522, 520, 540, Tile.SPRING),
			_box(600, 300, 770, 330),
			_box(860, 340, 1020, 370),
			_box(1100, 260, 1280, 290),
		],
		"out": [_over(425, 495), _on(685, 256), _on(940, 296), _on(1200, 218)],
		"back": [_on(940, 296), _on(685, 256), _on(375, 495), _on(222, 436)],
		"help": [
			_help(30, Arena.Kind.PLANK, Vector2(815, 282)),
			_help(90, Arena.Kind.BOLT, Vector2(-50, 0)),
			_help(115, Arena.Kind.BOLT, Vector2(50, 0)),
		],
	}
