class_name Sfx
extends Node
## Sesler dosyadan değil, açılışta sentezlenerek üretilir.

const RATE := 22050
const POOL := 10

var _bank: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_bank = {
		"jump": _tone(320.0, 620.0, 0.11, 0.35),
		"pickup": _arp([660.0, 880.0, 1175.0], 0.07, 0.4),
		"finish": _arp([523.0, 659.0, 784.0, 1047.0], 0.09, 0.45),
		"death": _tone(420.0, 60.0, 0.32, 0.5, 0.5),
		"place": _tone(180.0, 120.0, 0.08, 0.5, 0.35),
		"spring": _tone(220.0, 980.0, 0.2, 0.42),
		"tick": _tone(700.0, 700.0, 0.06, 0.32),
		"go": _tone(1040.0, 1040.0, 0.24, 0.42),
		"error": _tone(170.0, 130.0, 0.14, 0.35),
	}
	for i in POOL:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)


func play(id: String, volume_db := 0.0) -> void:
	if _pool.is_empty() or not _bank.has(id):
		return
	var player := _pool[_next]
	_next = (_next + 1) % POOL
	player.stream = _bank[id]
	player.volume_db = volume_db
	player.play()


func _tone(from_hz: float, to_hz: float, seconds: float, volume: float, noise := 0.0) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	_append_sweep(samples, from_hz, to_hz, seconds, volume, noise)
	return _wav(samples)


func _arp(notes: Array, step_seconds: float, volume: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for hz: float in notes:
		_append_sweep(samples, hz, hz, step_seconds, volume, 0.0)
	return _wav(samples)


func _append_sweep(out: PackedFloat32Array, from_hz: float, to_hz: float, seconds: float, volume: float, noise: float) -> void:
	var count := int(seconds * RATE)
	var phase := 0.0
	for i in count:
		var k := float(i) / count
		phase += TAU * lerpf(from_hz, to_hz, k) / RATE
		var wave := 0.75 * sin(phase) + 0.25 * signf(sin(phase))
		var mixed := lerpf(wave, randf_range(-1.0, 1.0), noise)
		out.append(mixed * volume * minf(k * 30.0, 1.0) * pow(1.0 - k, 1.4))


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
