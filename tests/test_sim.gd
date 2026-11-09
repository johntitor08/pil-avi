extends Node
## Kural ve fizik testleri. `--fixed-fps 60` ile gerçek zamandan hızlı çalışır.

var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await _test_movement()
	await _test_goals()
	await _test_deaths()
	await _test_wall_jump()
	await _test_climb()
	await _test_placement_rules()
	await _test_bolts()
	await _test_balloon_and_spring()
	await _test_ramp()
	await _test_step_up()
	await _test_round_flow()
	await _test_snapshot()
	await _test_maps_solvable()
	print("SONUÇ: %s" % ("tüm kural testleri geçti" if _fails == 0 else "%d test başarısız" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _ok(condition: bool, label: String) -> void:
	if condition:
		print("OK   ", label)
	else:
		_fails += 1
		print("HATA ", label)


func _steps(a: Arena, n: int) -> void:
	for i in n:
		a.step()
		await get_tree().physics_frame


func _make(map_index: int, players: int, engineer_slot := -1) -> Arena:
	var a := Arena.new()
	a.fixed_map = map_index
	a.no_engineer = engineer_slot < 0
	var first := 0
	for i in players:
		var pid := a.add_player("T%d" % i, i, 0)
		if i == engineer_slot:
			first = pid
	if engineer_slot >= 0:
		a.force_engineer = first
	a.start_round(map_index)
	a.skip_countdown()
	return a


func _tp(r: Arena.Robot, pos: Vector2, vel := Vector2.ZERO) -> void:
	PhysicsServer2D.body_set_state(r.body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, pos))
	PhysicsServer2D.body_set_state(r.body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, vel)
	r.pos = pos
	r.vel = vel


func _press(a: Arena, r: Arena.Robot, mask: int) -> void:
	a.set_input(r.pid, mask, Vector2.ZERO, 0, 0)


func _first(a: Arena, life: int) -> Arena.Robot:
	for r: Arena.Robot in a.robots.values():
		if r.life == life:
			return r
	return null


func _test_movement() -> void:
	var a := _make(0, 1)
	var r := _first(a, Arena.Life.RACING)
	await _steps(a, 70)
	_ok(r.on_ground, "robot zeminde duruyor")
	_ok(absf(r.pos.y - 538.0) < 4.0, "robot zeminin üstünde (y=%.1f)" % r.pos.y)
	var x0 := r.pos.x
	_press(a, r, Arena.RIGHT)
	await _steps(a, 40)
	_ok(r.pos.x > x0 + 100.0, "sağa koşuyor (%.0f px)" % (r.pos.x - x0))
	_ok(r.vel.x > 300.0, "hız üst sınıra yaklaşıyor (%.0f)" % r.vel.x)
	_press(a, r, 0)
	await _steps(a, 12)
	_ok(r.vel.x > 60.0, "tuş bırakılınca momentum sürüyor (%.0f)" % r.vel.x)
	await _steps(a, 50)
	_ok(absf(r.vel.x) < 5.0, "sonunda duruyor")
	var y0 := r.pos.y
	var top := y0
	_press(a, r, Arena.JUMP)
	for i in 50:
		await _steps(a, 1)
		top = minf(top, r.pos.y)
	_ok(y0 - top > 105.0 and y0 - top < 150.0, "zıplama yüksekliği (%.0f px)" % (y0 - top))
	a.dispose()


func _test_goals() -> void:
	var a := _make(0, 2)
	var r := _first(a, Arena.Life.RACING)
	await _steps(a, 5)
	_tp(r, a.map["station"])
	await _steps(a, 3)
	_ok(r.life == Arena.Life.RACING, "pilsiz istasyon bitirmiyor")
	_tp(r, a.map["battery"])
	await _steps(a, 3)
	_ok(r.has_battery, "pil alındı")
	_tp(r, a.map["station"])
	await _steps(a, 3)
	_ok(r.life == Arena.Life.DONE, "pille istasyona ulaşınca bitiyor")
	_ok(r.score == 10, "birinciye 10 puan (%d)" % r.score)
	var second := _first(a, Arena.Life.RACING)
	_tp(second, a.map["battery"])
	await _steps(a, 3)
	_tp(second, a.map["station"])
	await _steps(a, 3)
	_ok(second.score == 7, "ikinciye 7 puan (%d)" % second.score)
	a.dispose()


func _test_deaths() -> void:
	var a := _make(0, 2)
	var r := _first(a, Arena.Life.RACING)
	await _steps(a, 3)
	_tp(r, Vector2(540, 700))
	await _steps(a, 30)
	_ok(r.life == Arena.Life.DEAD, "boşluğa düşünce ölüyor")
	a.dispose()
	var b := _make(1, 2)
	var s := _first(b, Arena.Life.RACING)
	await _steps(b, 3)
	_tp(s, Vector2(700, 580))
	await _steps(b, 30)
	_ok(s.life == Arena.Life.DEAD, "dikene değince ölüyor")
	var other := _first(b, Arena.Life.RACING)
	_press(b, other, Arena.SELF_DESTRUCT)
	await _steps(b, 2)
	_ok(other.life == Arena.Life.DEAD, "R ile pes ediyor")
	await _steps(b, 2)
	_ok(b.phase == Arena.Phase.RESULT, "kimse kalmayınca tur bitiyor")
	b.dispose()


func _test_wall_jump() -> void:
	var a := _make(1, 1)
	var r := _first(a, Arena.Life.RACING)
	await _steps(a, 3)
	_tp(r, Vector2(1092, 480))
	_press(a, r, Arena.RIGHT)
	await _steps(a, 6)
	_ok(not r.on_ground, "duvar yanında havada")
	_press(a, r, Arena.RIGHT | Arena.JUMP)
	await _steps(a, 2)
	_ok(r.vel.y < -300.0 and r.vel.x < -100.0, "duvardan sekiyor (%.0f, %.0f)" % [r.vel.x, r.vel.y])
	a.dispose()


func _test_climb() -> void:
	var a := _make(1, 1)
	var r := _first(a, Arena.Life.RACING)
	await _steps(a, 3)
	_tp(r, Vector2(1168, 610))
	await _steps(a, 15)
	var start_y := r.pos.y
	_press(a, r, Arena.CLIMB)
	await _steps(a, 20)
	_ok(r.climbing and r.pos.y < start_y - 40.0, "duvara tırmanıyor (%.0f px)" % (start_y - r.pos.y))
	await _steps(a, 75)
	_press(a, r, 0)
	await _steps(a, 30)
	_ok(r.on_ground and absf(r.pos.y - 408.0) < 5.0 and r.pos.x > 1105.0 and r.pos.x < 1158.0, "çıkıntıya atlayıp duvarın üstüne çıkıyor (%s)" % str(r.pos))
	_ok(r.stamina == Arena.CLIMB_TICKS, "yere inince güç doluyor")
	_tp(r, Vector2(1262, 610))
	await _steps(a, 15)
	var floor_y := r.pos.y
	_press(a, r, Arena.CLIMB)
	var highest := floor_y
	for i in Arena.CLIMB_TICKS + 40:
		await _steps(a, 1)
		highest = minf(highest, r.pos.y)
	_ok(r.stamina == 0 or r.on_ground, "tırmanma gücü bitiyor")
	_ok(floor_y - highest < Arena.CLIMB_SPEED * Arena.CLIMB_TICKS / 60.0 + 30.0, "güç bitince tırmanış duruyor (%.0f px)" % (floor_y - highest))
	_press(a, r, 0)
	var snap := Arena.parse_snapshot(a.snapshot())
	_ok(snap["robots"][r.pid].has("stamina"), "snapshot güç seviyesini taşıyor")
	a.dispose()


func _test_placement_rules() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	var racer := _first(a, Arena.Life.RACING)
	await _steps(a, 5)
	_ok(eng != null, "Mühendis atandı")
	_ok(a.try_place(racer.pid, Arena.Kind.BOX, Vector2(540, 300), 0) != "", "yarışçı parça koyamıyor")
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(200, 600), 0) != "", "zeminin içine kutu konmuyor")
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, racer.pos, 0) != "", "robotun üstüne konmuyor")
	_ok(a.try_place(eng.pid, Arena.Kind.BOLT, Vector2(600, 200), 0) != "", "boşluğa cıvata konmuyor")
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(540, 200), 0) == "", "boşluğa kutu konuyor")
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(640, 200), 0) != "", "bekleme süresi uygulanıyor")
	for i in 4:
		await _steps(a, Arena.PLACE_COOLDOWN + 1)
		_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(700.0 + i * 70.0, 120), 0) == "", "kutu %d kondu" % (i + 2))
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(760, 60), 0) != "", "sınır dolunca konmuyor")
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	var ramp_error := a.try_place(eng.pid, Arena.Kind.RAMP, Vector2(300, 530), 0)
	_ok(ramp_error == "", "rampa zemine gömülerek konabiliyor [%s]" % ramp_error)
	a.dispose()


func _test_bolts() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	await _steps(a, 5)
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(540, 300), 0) == "", "kutu kondu")
	var box: Arena.Part = a.parts.values()[0]
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	var y_before := box.pos.y
	_ok(y_before > 305.0, "cıvatasız kutu düşüyor (%.0f)" % y_before)
	_ok(a.try_place(eng.pid, Arena.Kind.BOLT, box.pos, 0) == "", "cıvata kutuya takıldı")
	await _steps(a, 90)
	_ok(absf(box.pos.y - y_before) < 12.0, "tek cıvata kutuyu havada tutuyor (%.0f -> %.0f)" % [y_before, box.pos.y])
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	_ok(a.try_place(eng.pid, Arena.Kind.PLANK, Vector2(800, 200), 0) == "", "tahta kondu")
	var plank: Arena.Part = a.parts.values()[-1]
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	var left := plank.pos + Vector2(-60, 0).rotated(plank.rot)
	_ok(a.try_place(eng.pid, Arena.Kind.BOLT, left, 0) == "", "tahtaya ilk cıvata")
	await _steps(a, 40)
	var swung := absf(wrapf(plank.rot, -PI, PI))
	_ok(swung > 0.3, "tek cıvatada tahta sallanıyor (%.2f rad)" % swung)
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	_ok(a.try_place(eng.pid, Arena.Kind.BOLT, plank.pos, 0) == "", "tahtaya ikinci cıvata")
	await _steps(a, 2)
	var locked_rot := plank.rot
	await _steps(a, 60)
	_ok(absf(plank.rot - locked_rot) < 0.001, "iki cıvata tahtayı sabitliyor")
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	_ok(a.try_place(eng.pid, Arena.Kind.BOLT, plank.pos + Vector2(20, 0).rotated(plank.rot), 0) != "", "üçüncü cıvata reddediliyor")
	a.dispose()


func _test_balloon_and_spring() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	var racer := _first(a, Arena.Life.RACING)
	await _steps(a, 5)
	_ok(a.try_place(eng.pid, Arena.Kind.BOX, Vector2(1100, 400), 0) == "", "yerde kutu")
	var box: Arena.Part = a.parts.values()[0]
	await _steps(a, 60)
	var rest := box.pos.y
	_ok(a.try_place(eng.pid, Arena.Kind.BALLOON, box.pos + Vector2(0, -50), 0) == "", "balon kutunun yanına kondu")
	await _steps(a, 90)
	_ok(box.pos.y < rest - 60.0, "balon kutuyu kaldırıyor (%.0f -> %.0f)" % [rest, box.pos.y])
	await _steps(a, Arena.PLACE_COOLDOWN + 1)
	_ok(a.try_place(eng.pid, Arena.Kind.SPRING, Vector2(800, 551), 0) == "", "yay kondu")
	_tp(racer, Vector2(800, 505))
	var fastest := 0.0
	for i in 12:
		await _steps(a, 1)
		fastest = minf(fastest, racer.vel.y)
	_ok(fastest < -900.0, "yay robotu fırlatıyor (%.0f)" % fastest)
	a.dispose()


func _test_ramp() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	var racer := _first(a, Arena.Life.RACING)
	await _steps(a, 5)
	_tp(racer, Vector2(120, 530))
	await _steps(a, 20)
	_ok(a.try_place(eng.pid, Arena.Kind.RAMP, Vector2(320, 525), 0) == "", "rampa kondu")
	_press(a, racer, Arena.RIGHT)
	var highest := racer.pos.y
	for i in 70:
		await _steps(a, 1)
		highest = minf(highest, racer.pos.y)
	_ok(highest < 495.0, "robot rampayı tırmanıyor (en yüksek y=%.0f)" % highest)
	a.dispose()


func _test_step_up() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	var racer := _first(a, Arena.Life.RACING)
	await _steps(a, 5)
	_tp(racer, Vector2(60, 530))
	_ok(a.try_place(eng.pid, Arena.Kind.PLANK, Vector2(250, 550), 0) == "", "yerde tahta kondu")
	var plank: Arena.Part = a.parts.values()[0]
	await _steps(a, 30)
	var plank_x := plank.pos.x
	_press(a, racer, Arena.RIGHT)
	await _steps(a, 90)
	_ok(racer.pos.x > plank.pos.x + 75.0, "robot tahta ucuna takılmadan geçiyor (x=%.0f)" % racer.pos.x)
	_ok(absf(plank.pos.x - plank_x) < 25.0, "robot tahtayı itmiyor (%.0f px)" % absf(plank.pos.x - plank_x))
	a.dispose()


func _test_round_flow() -> void:
	var a := Arena.new()
	a.fixed_map = 0
	for i in 4:
		a.add_player("T%d" % i, i, 0)
	a.start_round(0)
	_ok(a.phase == Arena.Phase.COUNTDOWN, "tur geri sayımla başlıyor")
	_ok(a.engineer_pid != 0, "ilk tur Mühendis seçildi")
	var racer := _first(a, Arena.Life.RACING)
	var x0 := racer.pos.x
	_press(a, racer, Arena.RIGHT)
	await _steps(a, 30)
	_ok(absf(racer.pos.x - x0) < 3.0, "geri sayımda hareket yok")
	a.skip_countdown()
	var eng: Arena.Robot = a.robots[a.engineer_pid]
	var eng_before := eng.score
	await _steps(a, 2)
	_tp(racer, a.map["battery"])
	await _steps(a, 3)
	_tp(racer, a.map["station"])
	await _steps(a, 3)
	_ok(eng.score == eng_before + Arena.ENGINEER_POINTS, "Mühendis kurtarılan robottan puan aldı")
	for r: Arena.Robot in a.robots.values():
		if r.life == Arena.Life.RACING:
			_press(a, r, Arena.SELF_DESTRUCT)
	await _steps(a, 4)
	_ok(a.phase == Arena.Phase.RESULT, "herkes bitince sonuç ekranı")
	var winner := racer.pid
	await _steps(a, Arena.RESULT_TICKS + 2)
	_ok(a.phase == Arena.Phase.COUNTDOWN, "sonuçtan sonra yeni tur")
	_ok(a.engineer_pid == winner, "önceki birinci Mühendis oldu")
	a.remove_player(winner)
	_ok(a.engineer_pid == 0, "Mühendis çıkınca odada kalmıyor")
	a.dispose()


func _test_snapshot() -> void:
	var a := _make(0, 2, 0)
	var eng := _first(a, Arena.Life.ENGINEER)
	var racer := _first(a, Arena.Life.RACING)
	await _steps(a, 10)
	a.try_place(eng.pid, Arena.Kind.BOX, Vector2(540, 200), 30)
	await _steps(a, 2)
	var bytes := a.snapshot()
	var snap := Arena.parse_snapshot(bytes)
	_ok(int(snap["tick"]) == a.tick, "snapshot tick")
	var row: Dictionary = snap["robots"][racer.pid]
	_ok((row["pos"] as Vector2).distance_to(racer.pos) < 1.0, "snapshot robot konumu")
	_ok((snap["parts"] as Dictionary).size() == 1, "snapshot parça sayısı")
	_ok(int(snap["eng"]["pid"]) == eng.pid, "snapshot Mühendis")
	_ok(int(snap["eng"]["left"][Arena.Kind.BOX]) == 4, "snapshot kalan parça")
	_ok(bytes.size() < 1200, "snapshot MTU altında (%d bayt)" % bytes.size())
	a.dispose()


## Botlar haritayı bitirebiliyorsa harita yardımsız da, Mühendisle de geçilebilir demektir.
## Botlar rastgele hız alır ve birbirine çarpar; bir tur şanssız geçebilir, üç deneme verilir.
func _test_maps_solvable() -> void:
	for index in Maps.all().size():
		for with_engineer: bool in [false, true]:
			var label := "%s %s" % [str(Maps.get_map(index)["name"]), "Mühendisli" if with_engineer else "yardımsız"]
			var best := 0
			for attempt in 3:
				best = maxi(best, await _bot_round(index, with_engineer, label))
				if best > 0:
					break
			_ok(best >= 1, "%s bitirilebiliyor" % label)


func _bot_round(index: int, with_engineer: bool, label: String) -> int:
	var a := Arena.new()
	a.min_robots = 5
	a.fixed_map = index
	a.no_engineer = not with_engineer
	a.start_round(index)
	a.skip_countdown()
	var guard := 0
	while a.phase == Arena.Phase.RUN and guard < Arena.ROUND_TICKS:
		await _steps(a, 1)
		guard += 1
		for ev in a.drain_events():
			if str(ev["t"]) == "death":
				var dead: Arena.Robot = a.robots[int(ev["pid"])]
				print("[yz]   %s öldü: %s rota=%d t=%.1f" % [dead.name, str(ev["pos"]), dead.wp, guard / 60.0])
	var racers := a.robots.size() - (1 if with_engineer else 0)
	print("[yz] %s: %d/%d robot bitirdi, %.0f sn" % [label, a.finished_count, racers, guard / 60.0])
	if with_engineer:
		var planned: Array = a.map["help"]
		_ok(a._help_index == planned.size() and a._next_part > planned.size(), "%s planı uygulandı" % label)
	var done := a.finished_count
	a.dispose()
	return done
