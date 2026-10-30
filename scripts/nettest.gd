class_name NetTest
extends Node
## Scripted multiplayer smoke test. Run two copies:
##   godot --headless --path . -- --nettest=host
##   godot --headless --path . -- --nettest=client
## Each prints "CS <tick> <checksum>" every 300 ticks; matching lines mean the two
## simulations stayed identical.

const PORT := 34199
var main
var mode := ""
var t0 := 0.0
var done := false
var last_cs_tick := -1

static func start(m, which: String) -> void:
	var n := NetTest.new()
	n.main = m
	n.mode = which
	m.add_child(n)

func _ready() -> void:
	main.stepped.connect(_on_step)
	if mode == "host":
		var s := Data.default_settings()
		s.seed = 4242
		var err: String = main.start_host(s, "Host", PORT)
		print("host start: ", "ok" if err == "" else err)
	else:
		await get_tree().create_timer(1.5).timeout
		main.start_join("127.0.0.1", PORT, "Guest")
		print("client connecting")

func _q(c: Dictionary) -> void:
	main.queue_cmd(c)

func _on_step() -> void:
	var s: Sim = main.sim
	var t := s.tick
	if t % 300 == 0 and t != last_cs_tick:
		last_cs_tick = t
		print("CS %d %d" % [t, s.checksum()])
	if mode == "host":
		_host_script(s, t)
	else:
		_client_script(s, t)

func _host_script(s: Sim, t: int) -> void:
	match t:
		30:
			main.test_input = {"mx": 1, "my": 1, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
		110:
			main.test_input = {"mx": 0, "my": 0, "f": false, "mine": Vector2i(85, 94), "cur": Vector2i(-1, -1)}
		400:
			main.test_input = {"mx": 0, "my": 0, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
			_q({"t": "place", "type": "miner1", "x": 91, "y": 85, "dir": 3})
			_q({"t": "place", "type": "belt1", "x": 90, "y": 86, "dir": 3})
			_q({"t": "place", "type": "belt1", "x": 89, "y": 86, "dir": 3})
			_q({"t": "place", "type": "smelter", "x": 86, "y": 85, "dir": 2})
			_q({"t": "place", "type": "crate", "x": 87, "y": 88, "dir": 0})
			_q({"t": "place", "type": "coalgen", "x": 88, "y": 90, "dir": 0})
			_q({"t": "place", "type": "pole", "x": 89, "y": 88, "dir": 0})
		420:
			var sm := s.ent_at(86, 85)
			var g := s.ent_at(88, 90)
			if sm and g:
				_q({"t": "recipe", "id": sm.id, "k": "iron_ingot"})
				_q({"t": "fuel", "id": g.id})
			print("host built: ", s.ents.size(), " entities, coal fuel ", g.fuel if g else -1)
		1500:
			var sm := s.ent_at(86, 85)
			if sm:
				_q({"t": "clock", "id": sm.id, "v": 80})
		3000:
			var cr := s.ent_at(87, 88)
			print("host: crate holds ", cr.store if cr else {}, ", players: ", s.players.size())
			print("upnp: ", main.net.upnp_state, " | ", main.net.upnp_msg, " | lan ", main.net.lan_ips())
			print("NETTEST HOST DONE")
			get_tree().quit()

func _client_script(s: Sim, t: int) -> void:
	if not s.players.has(main.pid):
		return
	var p: Dictionary = s.players[main.pid]
	if not has_meta("t0"):
		set_meta("t0", t)
		print("client joined at tick ", t, " as pid ", main.pid)
	var r: int = t - int(get_meta("t0"))
	match r:
		10:
			main.test_input = {"mx": 1, "my": -1, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
		70:
			main.test_input = {"mx": 0, "my": 0, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
			for x in range(82, 87):
				_q({"t": "place", "type": "belt1", "x": x, "y": 80, "dir": 1})
			_q({"t": "craft", "k": "cable", "n": 3})
			_q({"t": "chat", "msg": "hello from the client"})
			_q({"t": "ping", "x": 85, "y": 80})
		200:
			_q({"t": "remove", "x": 84, "y": 80})
			main.test_input = {"mx": -1, "my": 1, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
		260:
			main.test_input = {"mx": 0, "my": 0, "f": true, "mine": Vector2i(-1, -1), "cur": Vector2i(88, 86)}
		600:
			main.test_input = {"mx": 0, "my": 0, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}
		1800:
			print("client: pos ", p.x, ",", p.y, "  inv ", p.inv, "  pred ", main.pred, "  lag ", main.lag)
			print("client desyncs: ", main.net.desyncs)
			print("NETTEST CLIENT DONE")
			get_tree().quit()
