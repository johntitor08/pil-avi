class_name Menu
extends Control
## Ana menü: isim, robot görünümü, oda kodu ve sunucu adresi.

signal play_offline(player_name: String, color: int, acc: int)
signal play_online(pid: int, code: String)

const CONFIG_PATH := "user://ayar.cfg"

var notice := ""

var _name: LineEdit
var _code: LineEdit
var _address: LineEdit
var _status: Label
var _online_button: Button
var _offline_button: Button
var _acc_label: Label
var _color := 4
var _acc := 1
var _time := 0.0
var _connecting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_load_settings()
	_status.text = notice
	Net.joined.connect(_on_joined)
	Net.connect_failed.connect(_on_problem)
	Net.rejected.connect(_on_problem)


func _exit_tree() -> void:
	Net.joined.disconnect(_on_joined)
	Net.connect_failed.disconnect(_on_problem)
	Net.rejected.disconnect(_on_problem)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	Art.background(self, _time)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(80, 112), "PİL AVI", HORIZONTAL_ALIGNMENT_LEFT, -1, 76, 12, Color("0b1824"))
	draw_string(font, Vector2(80, 112), "PİL AVI", HORIZONTAL_ALIGNMENT_LEFT, -1, 76, Art.AMBER)
	draw_string(font, Vector2(84, 146), "Pili kap, istasyona dön. Mühendise güven ya da güvenme.", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("cfe4ee"))
	Art.panel(self, Rect2(690, 72, 510, 590), 16.0, Color(0.05, 0.11, 0.16, 0.82), Color(0.6, 0.8, 0.9, 0.2))
	Art.robot(self, Vector2(945, 190), _color, _acc, 1 if fmod(_time, 4.0) < 2.0 else -1, _time * 3.0, false, _time)
	var lines := [
		["Nasıl oynanır", Art.AMBER, 22],
		["A / D ya da oklar: hareket     W / Boşluk: zıpla", Color.WHITE, 17],
		["Duvara değerken zıplarsan duvardan sekersin.", Color.WHITE, 17],
		["Shift: duvara tırman. Güç yere inince dolar.", Color.WHITE, 17],
		["R: pes et     Enter: sohbet     Esc: çık", Color.WHITE, 17],
		["", Color.WHITE, 12],
		["Mühendis", Art.AMBER, 22],
		["Her tur önceki turun birincisi Mühendis olur.", Color.WHITE, 17],
		["1-7: parça seç     Q / E ya da tekerlek: döndür", Color.WHITE, 17],
		["Sol tık: parçayı koy", Color.WHITE, 17],
		["Bir cıvata parçayı mil yapar, iki cıvata sabitler.", Color.WHITE, 17],
		["Balonu parçanın ya da robotun yanına koy, yukarı taşır.", Color.WHITE, 17],
		["Bitiren her robot Mühendise 3 puan kazandırır.", Color.WHITE, 17],
	]
	var y := 310.0
	for row: Array in lines:
		draw_string(font, Vector2(722, y), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, 460, int(row[2]), row[1])
		y += int(row[2]) + 11.0
	var swatch_y := 262.0
	for i in Art.COLORS.size():
		var rect := _swatch_rect(i, swatch_y)
		draw_rect(rect, Art.COLORS[i])
		if i == _color:
			draw_rect(rect.grow(3.0), Color.WHITE, false, 3.0)


func _swatch_rect(index: int, y: float) -> Rect2:
	return Rect2(800.0 + index * 37.0, y, 28, 22)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in Art.COLORS.size():
			if _swatch_rect(i, 262.0).grow(3.0).has_point(event.position):
				_color = i
				queue_redraw()


func _build() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(84, 186)
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_name = _field(box, "Robotunun adı", "Robot adı")
	_name.max_length = Net.MAX_NAME
	_code = _field(box, "Oda kodu (boş bırakırsan genel oda)", "Örn: EREN")
	_code.max_length = Net.MAX_CODE
	_address = _field(box, "Sunucu adresi", "Otomatik" if OS.has_feature("web") else Net.DEFAULT_ADDRESS)
	_online_button = _big_button(box, "ONLINE OYNA", Color("2f9e63"))
	_online_button.pressed.connect(_on_online)
	_offline_button = _big_button(box, "BOTLARLA OYNA", Color("3b6f9e"))
	_offline_button.pressed.connect(_on_offline)
	var quit := _big_button(box, "ÇIKIŞ", Color("5a4050"))
	quit.pressed.connect(func() -> void: get_tree().quit())
	quit.visible = not OS.has_feature("web")
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.position = Vector2(790, 222)
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func() -> void: _cycle_acc(-1))
	row.add_child(prev)
	_acc_label = Label.new()
	_acc_label.custom_minimum_size = Vector2(200, 0)
	_acc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_acc_label)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func() -> void: _cycle_acc(1))
	row.add_child(next)


func _field(parent: Control, title: String, hint: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color("a9c6d4"))
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = hint
	edit.custom_minimum_size = Vector2(0, 40)
	parent.add_child(edit)
	return edit


func _big_button(parent: Control, text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 22)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.bg_color = color.lightened(0.14) if state == "hover" else color.darkened(0.15 if state == "pressed" else 0.0)
		if state == "disabled":
			style.bg_color = Color(0.3, 0.33, 0.37)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color = Color.WHITE
		button.add_theme_stylebox_override(state, style)
	parent.add_child(button)
	return button


func _cycle_acc(step: int) -> void:
	_acc = posmod(_acc + step, Art.ACCESSORIES.size())
	_acc_label.text = "Aksesuar: %s" % str(Art.ACCESSORIES[_acc])


func _player_name() -> String:
	var text := _name.text.strip_edges()
	return text if text != "" else "Robot%d" % (randi() % 900 + 100)


func _on_offline() -> void:
	_save_settings()
	play_offline.emit(_player_name(), _color, _acc)


func _on_online() -> void:
	if _connecting:
		return
	_save_settings()
	var address := _address.text.strip_edges()
	_connecting = true
	_online_button.disabled = true
	if OS.has_feature("web") and not address.begins_with("ws"):
		_status.text = "Sunucu adresi alınıyor..."
		WebAddress.fetch(self, _on_web_address)
		return
	_connect(address if address != "" else Net.DEFAULT_ADDRESS)


func _on_web_address(address: String) -> void:
	if address == "":
		_on_problem("Sunucu adresi alınamadı. Sunucu kapalı olabilir.")
		return
	_connect(address)


func _connect(address: String) -> void:
	var host := address
	var port := Net.DEFAULT_PORT
	if not address.begins_with("ws") and ":" in address:
		host = address.rsplit(":", true, 1)[0]
		port = address.rsplit(":", true, 1)[1].to_int()
	var err := Net.connect_to(host, port, _player_name(), _code.text, _color, _acc)
	if err != OK:
		_on_problem("Bağlantı başlatılamadı.")
		return
	_status.text = "Bağlanılıyor..."


func _on_joined(pid: int, code: String) -> void:
	play_online.emit(pid, code)


func _on_problem(message: String) -> void:
	_connecting = false
	_online_button.disabled = false
	_status.text = message


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_name.text = str(cfg.get_value("oyuncu", "isim", ""))
		_code.text = str(cfg.get_value("oyuncu", "oda", ""))
		_address.text = str(cfg.get_value("oyuncu", "adres", ""))
		_color = posmod(int(cfg.get_value("oyuncu", "renk", _color)), Art.COLORS.size())
		_acc = posmod(int(cfg.get_value("oyuncu", "aksesuar", _acc)), Art.ACCESSORIES.size())
	_cycle_acc(0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("oyuncu", "isim", _name.text)
	cfg.set_value("oyuncu", "oda", _code.text)
	cfg.set_value("oyuncu", "adres", _address.text)
	cfg.set_value("oyuncu", "renk", _color)
	cfg.set_value("oyuncu", "aksesuar", _acc)
	cfg.save(CONFIG_PATH)
