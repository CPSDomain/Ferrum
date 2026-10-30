extends Node
signal stepped
## Game loop and input. Turns keyboard/mouse into commands, steps the simulation at a
## fixed 60 Hz (or replays the host's bundles when we're a client), and hands events
## to the view and HUD.

const TICK := 1.0 / 60.0
const SAVE_PATH := "user://ferrum_save.json"   # pre-0.4 single save, migrated on start
const SAVE_DIR := "user://saves/"
const LOG_PATH := "user://ferrum.log"
const PREFS_PATH := "user://prefs.cfg"
const T := 32.0

var sim: Sim
var net: NetLink
var view: WorldView
var hud: Hud
var audio: Audio
var pid := 1
var started := false
var paused := true
var hand := ""
var rot := 0
var alt_mode := true
var zoom := 1.0
var acc := 0.0
var pending: Array = []
var seq := 0
var last_input := {}
var mouse_l := false
var mouse_r := false
var dec_t := 0.0
var dec_id := 0
var dragging := false
var last_tile := Vector2i.ZERO
var save_t := 0.0
var demo_t := 0.0
var prefs := ConfigFile.new()
# client-side prediction of our own engineer
var pred := Vector2i.ZERO
var hist := {}
var ctick := 0
var lag := -1
# loading / saves
var loading := false
var catching_up := false
var world_name := ""
var slot := ""
# building helpers
var ghosts: Array = []          # placements sent but not yet confirmed by the sim (clients)
var clip := {}                  # copied machine settings
var pole_drag := false
var last_pole := Vector2i.ZERO
# scripted test driver (nettest)
var test_input = null
var test_mode := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--selftest" in args:
		SelfTest.run()
		set_process(false)
		get_tree().quit()
		return
	prefs.load(PREFS_PATH)
	_migrate_old_save()
	log_line("Ferrum Frontier %s started" % Data.VERSION)
	net = NetLink.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.dropped.connect(_on_dropped)
	net.upnp_done.connect(func(): hud.on_upnp())
	net.connected.connect(_on_net_connected)
	reset_demo()
	view = WorldView.new()
	add_child(view)
	view.setup(self)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	audio = Audio.new()
	add_child(audio)
	audio.setup(self)
	apply_display_settings()
	for a in args:
		if a.begins_with("--shots="):
			_dev_shots(a.trim_prefix("--shots="))
		elif a.begins_with("--nettest="):
			test_mode = a.trim_prefix("--nettest=")
			NetTest.start(self, test_mode)

func pref(key: String, def):
	return prefs.get_value("player", key, def)

func set_pref(key: String, v) -> void:
	prefs.set_value("player", key, v)
	prefs.save(PREFS_PATH)

func is_net() -> bool:
	return net.mode != "offline"

# ------------------------------------------------------------------ game lifecycle
## Title-screen backdrop: a fresh sim on whatever world is generated right now.
func reset_demo() -> void:
	sim = Sim.new()
	pid = 1
	sim.setup_new(pid)
	started = false
	paused = true
	if view:
		view.rebuild_world()
		view.rpos.clear()

func _fresh_world(settings: Dictionary) -> void:
	if settings != World.settings:
		World.generate(settings)
	if view:
		view.rebuild_world()
	if hud:
		hud.rebuild_minimap()

func _int_settings(st: Dictionary) -> Dictionary:
	var out := {}
	for k in st:
		out[k] = int(st[k])
	return out

func player_name() -> String:
	var n := str(pref("name", "Engineer")).strip_edges()
	return n if n != "" else "Engineer"

## Single player, new world.
func start_offline(settings: Dictionary, pname: String, wname := "") -> void:
	if loading:
		return
	net.shutdown()
	await _new_world_async(settings, pname, wname, "NEW WORLD")
	hud.toast("Landed. Mine a node, smelt it, and belt the ingots into the HUB.", "cy")

## Host a new world (save_path empty) or a saved one. Returns an error message or "".
func start_host(settings: Dictionary, pname: String, port: int, wname := "", save_path := "") -> String:
	if loading:
		return "Already loading."
	var err := net.host(port, pname)
	if err != "":
		return err
	net.accepting = false
	_host_async(settings, pname, wname, save_path, port)
	return ""

func _host_async(settings: Dictionary, pname: String, wname: String, save_path: String, port: int) -> void:
	if save_path != "":
		if not await _load_async(save_path, "HOSTING SAVED WORLD"):
			net.shutdown()
			hud.show_title()
			hud.toast("That save could not be read.", "bad")
			return
		if sim.players.has(1):
			sim.players[1].name = pname
	else:
		await _new_world_async(settings, pname, wname, "HOSTING NEW WORLD")
	net.flush_pending()
	log_line("Hosting '%s' on port %d" % [world_name, port])
	hud.toast("Hosting on port %d. Friends join with the address in the player list." % port, "cy")

func start_join(addr: String, port: int, pname: String) -> String:
	return net.join(addr, port, pname)

const JOIN_STEPS := ["Connecting to host", "Downloading world from host", "Generating terrain", "Placing resource nodes", "Spawning wildlife and crash pods", "Growing flora", "Building the map", "Catching up with the host"]

func _on_net_connected() -> void:
	hud.show_loading("JOINING GAME", JOIN_STEPS)
	hud.loading_step(1)

func _new_world_async(settings: Dictionary, pname: String, wname: String, title: String) -> void:
	loading = true
	var steps: Array = World.STAGES.duplicate()
	steps.append_array(["Building the map", "Landing at the HUB"])
	hud.show_loading(title, steps)
	await World.generate_async(settings, func(i, f): hud.loading_step(i, f))
	hud.loading_step(4)
	await get_tree().process_frame
	view.rebuild_world()
	hud.rebuild_minimap()
	pid = 1
	sim = Sim.new()
	sim.setup_new(pid, pname)
	_reset_local()
	world_name = wname if wname.strip_edges() != "" else "World %d" % World.world_seed
	slot = _unique_slot(world_name)
	hud.loading_step(5)
	await get_tree().process_frame
	await get_tree().process_frame
	loading = false
	hud.hide_loading()
	begin()

## Loads a save with the loading screen. Returns false if the file is unreadable.
func _load_async(path: String, title := "LOADING WORLD") -> bool:
	loading = true
	var steps: Array = ["Reading save"]
	steps.append_array(World.STAGES)
	steps.append_array(["Building the map", "Restoring your factory"])
	hud.show_loading(title, steps)
	hud.loading_step(0)
	await get_tree().process_frame
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(d) != TYPE_DICTIONARY:
		log_line("Could not read save %s" % path)
		loading = false
		hud.hide_loading()
		return false
	await World.generate_async(_int_settings(d.get("settings", Data.default_settings())), func(i, f): hud.loading_step(1 + i, f))
	hud.loading_step(5)
	await get_tree().process_frame
	view.rebuild_world()
	hud.rebuild_minimap()
	hud.loading_step(6)
	await get_tree().process_frame
	sim = Sim.new()
	sim.from_dict(d)
	pid = 1
	if not sim.players.has(1):
		sim.add_player(1, player_name())
	var meta: Dictionary = d.get("meta", {})
	world_name = str(meta.get("name", "Saved world"))
	slot = str(meta.get("slot", _unique_slot(world_name)))
	_reset_local()
	loading = false
	hud.hide_loading()
	begin()
	return true

## Continue / Load screen.
func load_and_play(path: String) -> void:
	if loading:
		return
	net.shutdown()
	if not await _load_async(path):
		hud.show_title()
		hud.toast("That save could not be read.", "bad")

func _reset_local() -> void:
	hand = ""
	pending = []
	last_input = {}
	acc = 0.0
	hist.clear()
	lag = -1
	ctick = 0
	ghosts.clear()
	if view:
		view.rpos.clear()
		view.particles.clear()
	if hud:
		hud.close_panel()

## Called by NetLink when the host's snapshot arrives.
func client_start(my_pid: int, d: Dictionary) -> void:
	loading = true
	pid = my_pid
	hud.show_loading("JOINING GAME", JOIN_STEPS)
	hud.loading_step(2)
	await World.generate_async(_int_settings(d.get("settings", Data.default_settings())), func(i, f): hud.loading_step(2 + i, f))
	hud.loading_step(6)
	await get_tree().process_frame
	view.rebuild_world()
	hud.rebuild_minimap()
	sim = Sim.new()
	sim.from_dict(d)
	_reset_local()
	for t in net.bundles.keys():
		if t < sim.tick:
			net.bundles.erase(t)
	world_name = ""
	slot = ""
	hud.loading_step(7)
	loading = false
	catching_up = true
	begin()

func client_resync(d: Dictionary) -> void:
	sim = Sim.new()
	sim.from_dict(d)
	hist.clear()
	lag = -1
	for t in net.bundles.keys():
		if t < sim.tick:
			net.bundles.erase(t)

func begin() -> void:
	started = true
	paused = false
	hud.show_play()

func to_title(msg := "") -> void:
	catching_up = false
	hud.hide_loading()
	net.shutdown()
	reset_demo()
	hud.show_title()
	if msg != "":
		hud.toast(msg, "bad")

func _on_dropped(msg: String) -> void:
	log_line("Disconnected: " + msg)
	loading = false
	catching_up = false
	if not started:
		net.shutdown()
		hud.hide_loading()
		hud.open_join()
		hud.on_dropped(msg)
		return
	to_title(msg)

func toggle_menu() -> void:
	paused = not paused
	hud.show_menu(paused)

func queue_cmd(c: Dictionary) -> void:
	c["pid"] = pid
	c["seq"] = seq
	seq += 1
	pending.append(c)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if started:
		if net.mode == "client":
			_client_frame(delta)
		elif not paused or net.mode == "host":
			_host_frame(delta)
		if not paused:
			_input_frame(delta)
		if net.mode != "client" and not loading:
			save_t += delta
			if save_t > 60.0 and sim.players.has(pid):
				save_t = 0.0
				save_game(true)
	elif sim.players.has(pid):
		demo_t += delta
		var p: Dictionary = sim.players[pid]
		p.x = Data.SPAWN_X + int(sin(demo_t / 9.0) * 4000)
		p.y = Data.SPAWN_Y - 2000 + int(cos(demo_t / 11.0) * 3000)
	view.frame(delta)
	hud.frame(delta)
	audio.frame(delta)
	var now := Time.get_ticks_msec()
	ghosts = ghosts.filter(func(g): return now - g.t < 2000 and not _ghost_landed(g))

func _ghost_landed(g: Dictionary) -> bool:
	var e := sim.ent_at(g.x, g.y)
	return e != null and e.type == g.type

func _host_frame(delta: float) -> void:
	acc += delta
	var n := 0
	while acc >= TICK and n < 6:
		acc -= TICK
		n += 1
		var local := pending
		pending = []
		var inp := _make_input()
		if _input_changed(inp):
			queue_cmd(inp)
			local.append(pending.pop_back())
		var all := local
		if net.mode == "host":
			all = net.host_bundle(local)
			net.broadcast(sim.tick, all)
		sim.step(all)
		_drain_events()
		if net.mode == "host":
			net.host_after_step(sim)
		stepped.emit()
	if n == 6:
		acc = 0.0

func _client_frame(delta: float) -> void:
	acc += delta
	var n := 0
	while acc >= TICK and n < 6:
		acc -= TICK
		n += 1
		ctick += 1
		var out := pending
		pending = []
		var inp := _make_input()
		if _input_changed(inp):
			inp["ct"] = ctick
			queue_cmd(inp)
			out.append(pending.pop_back())
		net.send_cmds(out)
		_predict_step()
	if n == 6:
		acc = 0.0
	var steps := 0
	var max_steps := 240 if net.bundles.size() > 120 else 20
	while net.bundles.has(sim.tick) and steps < max_steps:
		var t := sim.tick
		var list: Array = net.bundles[t]
		net.bundles.erase(t)
		for c in list:
			if c.t == "input" and c.pid == pid and c.has("ct"):
				lag = t - int(c.ct)
		sim.step(list)
		_drain_events()
		net.client_after_step(sim)
		_reconcile(t)
		stepped.emit()
		steps += 1
	if catching_up and net.bundles.size() <= 3 and sim.players.has(pid):
		catching_up = false
		hud.hide_loading()
		hud.toast("Joined the game.", "cy")

func _drain_events() -> void:
	for ev in sim.events:
		_dispatch(ev)
	sim.events.clear()

func _dispatch(ev: Dictionary) -> void:
	match ev.t:
		"toast":
			if ev.pid == -1 or ev.pid == pid:
				hud.toast(ev.msg, ev.kind)
				if ev.kind == "bad" and ev.pid == pid:
					audio.play("error", -4.0, 0.0)
		"placed":
			audio.play_at("place", Vector2(ev.x, ev.y), -2.0)
		"removed":
			audio.play_at("remove", Vector2(ev.x, ev.y), -4.0)
		"milestone":
			audio.play("milestone", -2.0, 0.0)
		"unlock":
			audio.play("unlock", -2.0, 0.0)
		"crafted":
			if ev.pid == pid:
				audio.play("crafted", -8.0)
		"chat":
			hud.add_chat(ev.name, ev.msg, ev.pid == pid)
			audio.play("chat", -6.0, 0.0)
		"ping":
			view.add_ping(ev.x, ev.y, ev.name)
			hud.add_ping(ev.x, ev.y)
			audio.play("ping", -4.0, 0.0)
			if ev.pid != pid:
				hud.toast("%s pinged a spot on the map" % ev.name, "cy")
		"victory":
			if not is_net():
				paused = true
			hud.show_victory()
		_:
			view.on_event(ev)
			match ev.t:
				"bolt":
					audio.play_at("zap", Vector2(ev.x1, ev.y1) / 1000.0, -8.0)
				"burst":
					audio.play_at("hit", Vector2(ev.x, ev.y) / 1000.0, -4.0)
				"chip":
					audio.play_at("chip", Vector2(ev.x, ev.y) / 1000.0, -6.0)
				"pickup":
					if ev.pid == pid:
						audio.play("pickup", -10.0, 0.1)
				"hurt":
					if ev.pid == pid:
						audio.play("hurt", -2.0)

func _make_input() -> Dictionary:
	if test_input != null:
		var ti: Dictionary = test_input.duplicate()
		ti["t"] = "input"
		return ti
	var mx := 0
	var my := 0
	var f := false
	if not paused and not hud.typing():
		mx = int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		my = int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		f = Input.is_physical_key_pressed(KEY_F)
	var mt := mouse_tile()
	var mine := Vector2i(-1, -1)
	if mouse_l and hand == "" and not dragging and not paused and World.node_at(mt.x, mt.y) >= 0:
		mine = mt
	# cursor only matters while F is held; leaving it out keeps the input from changing every frame
	return {"t": "input", "mx": mx, "my": my, "f": f, "mine": mine, "cur": mt if f else Vector2i(-1, -1)}

func _input_changed(inp: Dictionary) -> bool:
	for k in ["mx", "my", "f", "mine", "cur"]:
		if last_input.get(k) != inp[k]:
			last_input = inp.duplicate()
			return true
	return false

# ------------------------------------------------------------------ prediction (clients)
func _predict_step() -> void:
	if not sim.players.has(pid):
		return
	var p: Dictionary = sim.players[pid]
	if p.dead > 0 or lag < 0:
		pred = Vector2i(p.x, p.y)
		hist.clear()
		hist[ctick] = pred
		return
	var mx: int = last_input.get("mx", 0)
	var my: int = last_input.get("my", 0)
	if mx != 0 or my != 0:
		var sp := 103 if (mx == 0 or my == 0) else 73
		var nx: int = pred.x + mx * sp
		var ny: int = pred.y + my * sp
		if not sim._blocked(nx, pred.y):
			pred.x = nx
		if not sim._blocked(pred.x, ny):
			pred.y = ny
	hist[ctick] = pred

func _reconcile(t: int) -> void:
	if not sim.players.has(pid):
		return
	var p: Dictionary = sim.players[pid]
	var auth := Vector2i(p.x, p.y)
	if lag < 0 or p.dead > 0:
		pred = auth
		return
	var k := t - lag
	if not hist.has(k):
		return
	var err: Vector2i = auth - hist[k]
	if absi(err.x) + absi(err.y) > 3000:
		pred = auth
		hist.clear()
		return
	if err != Vector2i.ZERO:
		pred += err
		for kk in hist.keys():
			if kk > k:
				hist[kk] += err
	for kk in hist.keys():
		if kk < k:
			hist.erase(kk)

## Where to draw our own engineer, in milli-tiles.
func local_pos() -> Vector2i:
	if net.mode == "client" and lag >= 0 and sim.players.has(pid) and sim.players[pid].dead == 0:
		return pred
	if sim.players.has(pid):
		return Vector2i(sim.players[pid].x, sim.players[pid].y)
	return Vector2i(Data.SPAWN_X, Data.SPAWN_Y)

# ------------------------------------------------------------------ mouse helpers
func mouse_world() -> Vector2:
	return view.get_global_mouse_position()

func mouse_tile() -> Vector2i:
	var m := mouse_world() / T
	return Vector2i(floori(m.x), floori(m.y))

func hover_ent() -> Sim.Ent:
	var t := mouse_tile()
	return sim.ent_at(t.x, t.y)

func ghost_rect() -> Rect2i:
	var n: int = Data.BUILD[hand]["size"]
	var m := mouse_world() / T
	var x := floori(m.x - (n - 1) / 2.0)
	var y := floori(m.y - (n - 1) / 2.0)
	if Data.is_miner(hand):
		var bd := 3.0
		for nd in World.nodes:
			var d := Vector2(nd.cx + 0.5, nd.cy + 0.5).distance_to(m)
			if d < bd:
				bd = d
				x = nd.cx - 1
				y = nd.cy - 1
	return Rect2i(x, y, n, n)

func select_quick(i: int) -> void:
	var t: String = Data.QUICK[i]
	if not sim.unlock_b.has(t):
		hud.toast("%s is not unlocked yet" % Data.BUILD[t]["n"], "bad")
		return
	hand = "" if hand == t else t
	hud.close_panel()

# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if hud and hud.intro_active() and event is InputEventKey and event.pressed:
		hud.end_intro()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_l = false
			dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_r = false
			dec_id = 0
			dec_t = 0.0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and hud.chat_open():
			hud.close_chat()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and hud.sub_overlay_open():
			hud.close_sub_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and not started:
			if hud.back_to_title():
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and started:
			if hud.victory_ov.visible:
				return
			if hud.panel_kind() != "":
				hud.close_panel()
			elif hand != "":
				hand = ""
			else:
				toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ALT:
			alt_mode = not alt_mode

func _unhandled_input(event: InputEvent) -> void:
	if not started or paused:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clampf(zoom * 1.12, 0.45, 2.2)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clampf(zoom / 1.12, 0.45, 2.2)
			MOUSE_BUTTON_LEFT:
				mouse_l = true
				if event.shift_pressed and hand == "":
					_paste_settings()
				else:
					_left_click()
			MOUSE_BUTTON_RIGHT:
				if event.shift_pressed:
					_copy_settings()
				else:
					mouse_r = true
					dec_t = 0.0
					dec_id = 0
			MOUSE_BUTTON_MIDDLE:
				_ping()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)

func _left_click() -> void:
	if not sim.players.has(pid) or sim.players[pid].dead > 0:
		return
	if hand != "":
		var g := ghost_rect()
		_place(hand, g.position.x, g.position.y, rot)
		if Data.is_belt(hand):
			dragging = true
			last_tile = g.position
		elif hand == "pole":
			pole_drag = true
			last_pole = g.position
		return
	var e := hover_ent()
	if e != null and not Data.is_belt(e.type) and e.type != "pole":
		if not sim.in_reach(pid, e):
			hud.toast("Out of reach", "bad")
			return
		var kind := "logi"
		if Data.is_machine(e.type) or Data.is_miner(e.type): kind = "machine"
		elif e.type == "coalgen": kind = "gen"
		elif e.type == "crate": kind = "crate"
		elif e.type == "hub": kind = "hub"
		elif e.type == "elevator": kind = "elevator"
		hud.open_panel(kind, e.id)
	else:
		hud.close_panel()

## Queue a placement and remember it as a ghost until the sim confirms it.
func _place(type: String, x: int, y: int, dir: int) -> void:
	queue_cmd({"t": "place", "type": type, "x": x, "y": y, "dir": dir})
	if net.mode == "client" and sim.check(pid, type, x, y, dir) == "":
		ghosts.append({"type": type, "x": x, "y": y, "dir": dir, "t": Time.get_ticks_msec()})

func _ping() -> void:
	var t := mouse_tile()
	queue_cmd({"t": "ping", "x": t.x, "y": t.y})

## Shift + right click: copy a machine's recipe and clock speed.
func _copy_settings() -> void:
	var e := hover_ent()
	if e == null or not (Data.is_machine(e.type) or Data.is_miner(e.type)):
		return
	clip = {"type": e.type, "recipe": e.recipe, "clock": e.clock}
	var what := "Clock %d%%" % e.clock
	if Data.RECIPES.has(e.recipe):
		what = "%s at %d%%" % [Data.RECIPES[e.recipe]["n"], e.clock]
	hud.toast("Copied: %s. Shift + left click another machine to paste." % what, "cy")
	audio.play("ui_click")

## Shift + left click: paste onto a machine of a compatible kind.
func _paste_settings() -> void:
	var e := hover_ent()
	if clip.is_empty() or e == null or not (Data.is_machine(e.type) or Data.is_miner(e.type)):
		return
	if Data.RECIPES.has(clip.recipe) and Data.is_machine(e.type) and Data.BUILD[e.type].get("m", "") == Data.RECIPES[clip.recipe]["m"]:
		queue_cmd({"t": "recipe", "id": e.id, "k": clip.recipe})
	queue_cmd({"t": "clock", "id": e.id, "v": clip.clock})
	audio.play("place", -10.0)

func _key(ev: InputEventKey) -> void:
	var k := ev.keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		hud.open_chat()
		return
	if k == KEY_G:
		_ping()
		return
	if k == KEY_R:
		var d := 3 if ev.shift_pressed else 1
		if hand != "":
			rot = (rot + d) % 4
		else:
			var e := hover_ent()
			if e != null:
				queue_cmd({"t": "rotate", "id": e.id, "d": d})
	elif k == KEY_Q:
		if hand != "":
			hand = ""
		else:
			var e := hover_ent()
			if e != null and sim.unlock_b.has(e.type):
				hand = e.type
				rot = e.dir
				hud.close_panel()
	elif k == KEY_E:
		if hud.panel_kind() == "inv":
			hud.close_panel()
		else:
			hud.open_panel("inv", 0)
	elif k >= KEY_0 and k <= KEY_9:
		select_quick(9 if k == KEY_0 else k - KEY_1)

func _input_frame(delta: float) -> void:
	if pole_drag and mouse_l and hand == "pole":
		var pt := mouse_tile()
		if pt.distance_to(last_pole) >= 6.0:
			_place("pole", pt.x, pt.y, 0)
			last_pole = pt
	elif not mouse_l:
		pole_drag = false
	if dragging and mouse_l and Data.is_belt(hand):
		var t := mouse_tile()
		var c := last_tile
		var guard := 0
		while c != t and guard < 64:
			guard += 1
			var dx := t.x - c.x
			var dy := t.y - c.y
			var d := 0
			if absi(dx) >= absi(dy):
				d = 1 if dx > 0 else 3
			else:
				d = 2 if dy > 0 else 0
			queue_cmd({"t": "set_dir", "x": c.x, "y": c.y, "dir": d})
			c += Data.DIRS[d]
			rot = d
			_place(hand, c.x, c.y, d)
		last_tile = c
	if mouse_r:
		var e := hover_ent()
		if e != null and e.type != "hub" and sim.in_reach(pid, e):
			if e.id != dec_id:
				dec_id = e.id
				dec_t = 0.0
			dec_t += delta
			var need := 0.12 if Data.is_belt(e.type) else 0.35
			if dec_t >= need:
				queue_cmd({"t": "remove", "x": e.x, "y": e.y})
				dec_t = -0.15
		else:
			dec_id = 0
			dec_t = 0.0

# ------------------------------------------------------------------ save / load
func log_line(msg: String) -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(LOG_PATH) else FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > 512 * 1024:
		f.close()
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), msg])
	f.close()

static func _slug(n: String) -> String:
	var out := ""
	for ch in n.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("-"):
			out += "-"
	out = out.trim_suffix("-").substr(0, 40)
	return out if out != "" else "world"

func _unique_slot(n: String) -> String:
	var base := _slug(n)
	var s2 := base
	var i := 2
	while FileAccess.file_exists(SAVE_DIR + s2 + ".meta.json"):
		s2 = "%s-%d" % [base, i]
		i += 1
	return s2

## Manual saves go to <slot>.json; autosaves rotate through <slot>.auto1-3.json.
func save_game(auto: bool) -> void:
	if net.mode == "client":
		if not auto:
			hud.toast("Only the host can save a multiplayer game.", "bad")
		return
	if not started or loading or not sim.players.has(pid):
		return
	if slot == "":
		slot = _unique_slot(world_name if world_name != "" else "World")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var meta := {"name": world_name, "slot": slot, "saved_at": int(Time.get_unix_time_from_system()), "seed": World.world_seed,
		"milestone": sim.milestone, "phase": sim.elevator.phase, "tick": sim.tick, "version": Data.VERSION}
	var d := sim.to_dict()
	d["meta"] = meta
	var file := slot + ".json"
	if auto:
		var dir := DirAccess.open(SAVE_DIR)
		for i in [2, 1]:
			var from := "%s.auto%d.json" % [slot, i]
			if dir.file_exists(from):
				dir.rename(from, "%s.auto%d.json" % [slot, i + 1])
		file = slot + ".auto1.json"
	var f := FileAccess.open(SAVE_DIR + file, FileAccess.WRITE)
	if f == null:
		if not auto:
			hud.toast("Could not write the save file.", "bad")
		log_line("Save failed: " + file)
		return
	f.store_string(JSON.stringify(d, "", false))
	f.close()
	meta["latest"] = file
	var mf := FileAccess.open(SAVE_DIR + slot + ".meta.json", FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(meta, "  ", false))
		mf.close()
	if not auto:
		hud.toast("Saved \"%s\"" % world_name, "good")

## Newest first. Each entry is a world (slot) with its latest save.
func list_saves() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if not fn.ends_with(".meta.json"):
			continue
		var m = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + fn))
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var latest: String = SAVE_DIR + str(m.get("latest", ""))
		if not FileAccess.file_exists(latest):
			continue
		m["path"] = latest
		m["slot"] = fn.trim_suffix(".meta.json")
		var autos := []
		for i in [1, 2, 3]:
			var ap := "%s%s.auto%d.json" % [SAVE_DIR, m.slot, i]
			if FileAccess.file_exists(ap):
				autos.append(ap)
		m["autos"] = autos
		out.append(m)
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out

func delete_slot(s2: String) -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for fn in [s2 + ".json", s2 + ".auto1.json", s2 + ".auto2.json", s2 + ".auto3.json", s2 + ".meta.json"]:
		if dir.file_exists(fn):
			dir.remove(fn)

func latest_save_path() -> String:
	var l := list_saves()
	return l[0].path if l.size() else ""

## v0.3 kept one save at user://ferrum_save.json; turn it into a world slot.
func _migrate_old_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var s2 := _unique_slot("Old world")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_DIR + s2 + ".json"))
	var meta := {"name": "Old world", "slot": s2, "saved_at": int(Time.get_unix_time_from_system()), "latest": s2 + ".json"}
	var mf := FileAccess.open(SAVE_DIR + s2 + ".meta.json", FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(meta))
		mf.close()

# ------------------------------------------------------------------ display settings
func apply_display_settings() -> void:
	var fs: bool = pref("fullscreen", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if pref("vsync", true) else DisplayServer.VSYNC_DISABLED)
	hud.set_ui_scale(float(pref("ui_scale", 1.0)))
	if audio:
		audio.apply_volumes()

# ------------------------------------------------------------------ dev screenshots
## godot -- --shots=/some/dir   renders a few screenshots and quits.
func _dev_shots(dir: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await _snap(dir + "/intro.png")
	for i in 200:
		await get_tree().process_frame
	await _snap(dir + "/title.png")
	hud.open_setup("host")
	for i in 40:
		await get_tree().process_frame
	await _snap(dir + "/setup.png")
	var s := Data.default_settings()
	s.seed = 987654
	s.water = 3
	start_offline(s, "Rob", "Shot World")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap(dir + "/loading.png")
	while not started:
		await get_tree().process_frame
	SelfTest._chain(sim)
	sim.add_ent("belt1", 79, 89, 1)
	sim.add_ent("tunnel", 80, 89, 1)
	sim.add_ent("tunnel", 84, 89, 1)
	sim.players[pid].x = 85500
	sim.players[pid].y = 85000
	sim.add_player(99, "Guest")
	sim.players[99].x = 88000
	sim.players[99].y = 84000
	queue_cmd({"t": "chat", "msg": "First belt line is up"})
	queue_cmd({"t": "ping", "x": 90, "y": 80})
	for i in 90:
		await get_tree().process_frame
	await _snap(dir + "/game.png")
	save_game(false)
	toggle_menu()
	hud.open_settings(true)
	for i in 10:
		await get_tree().process_frame
	await _snap(dir + "/settings.png")
	hud.close_sub_overlay()
	toggle_menu()
	to_title()
	hud.open_saves()
	for i in 10:
		await get_tree().process_frame
	await _snap(dir + "/saves.png")
	get_tree().quit()

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
