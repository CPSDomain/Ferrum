class_name Audio
extends Node
## Sound effects, the factory hum and music. Volumes come from the settings menu.

var main
var players: Array = []
var music: AudioStreamPlayer
var hum: AudioStreamPlayer
var streams := {}
var next := 0
var hum_db := -80.0

func setup(m) -> void:
	main = m
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	var ms: AudioStreamOggVorbis = load("res://assets/audio/music_frontier.ogg")
	ms.loop = true
	music.stream = ms
	add_child(music)
	hum = AudioStreamPlayer.new()
	hum.bus = "SFX"
	var hs: AudioStreamOggVorbis = load("res://assets/audio/hum.ogg")
	hs.loop = true
	hum.stream = hs
	hum.volume_db = -80.0
	add_child(hum)
	apply_volumes()
	music.play()
	hum.play()

func _ensure_bus(n: String) -> void:
	if AudioServer.get_bus_index(n) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, n)
	AudioServer.set_bus_send(i, "Master")

func _set_bus(n: String, pct: float) -> void:
	var i := AudioServer.get_bus_index(n)
	AudioServer.set_bus_mute(i, pct <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pct, 0.001) / 100.0))

func apply_volumes() -> void:
	_set_bus("Master", float(main.pref("vol_master", 80)))
	_set_bus("Music", float(main.pref("vol_music", 60)))
	_set_bus("SFX", float(main.pref("vol_sfx", 80)))

func play(sname: String, vol_db := 0.0, pitch_var := 0.05) -> void:
	if not streams.has(sname):
		streams[sname] = load("res://assets/audio/%s.wav" % sname)
	var p: AudioStreamPlayer = players[next]
	next = (next + 1) % players.size()
	p.stream = streams[sname]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

## World sounds get quieter with distance from the camera and are skipped when far away.
func play_at(sname: String, tile_pos: Vector2, vol_db := 0.0) -> void:
	if main.view == null or main.view.cam == null:
		return
	var c: Vector2 = main.view.cam.get_screen_center_position() / 32.0
	var d := c.distance_to(tile_pos)
	if d > 28.0:
		return
	play(sname, vol_db - d * 0.7)

func frame(delta: float) -> void:
	var target := -80.0
	if main.started and main.view and main.view.cam:
		var c: Vector2 = main.view.cam.get_screen_center_position() / 32.0
		var n := 0
		for list in [main.sim.machines, main.sim.miners, main.sim.gens]:
			for e in list:
				if (e.st == "work" or e.on) and absf(e.x + 1.5 - c.x) < 22 and absf(e.y + 1.5 - c.y) < 14:
					n += 1
		if n > 0:
			target = -24.0 + minf(12.0, n * 1.5)
	hum_db = lerpf(hum_db, target, minf(1.0, delta * 2.0))
	hum.volume_db = hum_db
