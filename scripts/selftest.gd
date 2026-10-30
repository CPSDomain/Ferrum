class_name SelfTest
extends RefCounted
## Headless checks: run with  godot --headless -- --selftest

static func _chain(s: Sim) -> void:
	s.add_ent("miner1", 89, 73, 3)
	s.add_ent("belt1", 88, 74, 3)
	s.add_ent("belt1", 87, 74, 3)
	var sm := s.add_ent("smelter", 84, 73, 3)
	sm.recipe = "iron_ingot"
	for y in range(74, 80):
		s.add_ent("belt1", 83, y, 2)
	s.add_ent("belt1", 83, 80, 3)
	var g := s.add_ent("coalgen", 88, 78, 0)
	g.fuel = 50
	s.add_ent("pole", 86, 77, 0)
	# crate that unloads onto belts on two sides
	var c := s.add_ent("crate", 84, 84, 0)
	c.store = {"iron_plate": 5, "iron_rod": 3}
	s.add_ent("belt1", 85, 84, 1)
	s.add_ent("belt1", 84, 83, 0)

static func _run_ticks(s: Sim, n: int, walk := false) -> void:
	for i in n:
		var cmds := []
		if walk and i < 120:
			cmds.append({"t": "input", "pid": 1, "mx": 1, "my": 0, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)})
		s.step(cmds)

static func run() -> void:
	var ok := true
	var a := Sim.new()
	a.setup_new(1)
	_chain(a)
	_run_ticks(a, 90 * 60, true)
	var ingots: int = a.hub.get("iron_ingot", 0)
	print("ingots in HUB after 90 s: ", ingots, "  (expect ~39-45)")
	ok = ok and ingots >= 35 and ingots <= 46
	var crate_left := 0
	for id in a.ents:
		if a.ents[id].type == "crate":
			for k in a.ents[id].store:
				crate_left += a.ents[id].store[k]
	print("crate items left: ", crate_left, "  (expect 0, emptied onto two belts)")
	ok = ok and crate_left == 0
	print("curve at corner: ", a.ent_at(83, 80).curve, "  (expect 1)")
	ok = ok and a.ent_at(83, 80).curve == 1
	# determinism: same commands -> same state
	var b := Sim.new()
	b.setup_new(1)
	_chain(b)
	_run_ticks(b, 90 * 60, true)
	print("checksums: ", a.checksum(), " vs ", b.checksum())
	ok = ok and a.checksum() == b.checksum()
	# save / load round trip, then keep running both
	var txt := JSON.stringify(a.to_dict(), "", false)
	var c := Sim.new()
	c.from_dict(JSON.parse_string(txt))
	_run_ticks(a, 600)
	_run_ticks(c, 600)
	print("after reload + 10 s: ", a.checksum(), " vs ", c.checksum())
	ok = ok and a.checksum() == c.checksum()
	# belt pickup: stand next to the right-hand crate belt
	var p: Dictionary = a.players[1]
	p.x = 85500
	p.y = 85600
	var before: int = a.inv_count(1, "iron_plate") + a.inv_count(1, "iron_rod")
	for i in 30:
		a.step([{"t": "input", "pid": 1, "mx": 0, "my": 0, "f": true, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1)}])
	var picked: int = a.inv_count(1, "iron_plate") + a.inv_count(1, "iron_rod") - before
	print("picked up with F: ", picked, "  (expect 4)")
	ok = ok and picked == 4
	# milestone + placement via commands
	a.hub["copper_ingot"] = 30
	a.hub["iron_ingot"] = 60
	a.step([{"t": "submit_ms", "pid": 1}])
	print("milestone: ", a.milestone, "  constructor unlocked: ", a.unlock_b.has("constructor"))
	ok = ok and a.milestone == 1 and a.unlock_b.has("constructor")
	# underground belt: crate -> belt -> tunnel in -> 3 tiles under -> tunnel out -> belt -> crate
	var u := Sim.new()
	u.setup_new(1)
	var src := u.add_ent("crate", 71, 91, 0)
	src.store = {"iron_plate": 10}
	u.add_ent("belt1", 72, 91, 1)
	var tin := u.add_ent("tunnel", 73, 91, 1)
	var tout := u.add_ent("tunnel", 77, 91, 1)
	u.add_ent("belt1", 78, 91, 1)
	var dst := u.add_ent("crate", 79, 91, 0)
	print("tunnel roles: ", tin.role, "/", tout.role, " paired: ", tin.partner == tout.id)
	ok = ok and tin.role == 1 and tout.role == 2 and tin.partner == tout.id
	_run_ticks(u, 120)
	var u2 := Sim.new()
	u2.from_dict(JSON.parse_string(JSON.stringify(u.to_dict(), "", false)))
	_run_ticks(u, 600)
	_run_ticks(u2, 600)
	var arrived: int = dst.store.get("iron_plate", 0)
	print("through the tunnel: ", arrived, "/10   reload checksum ", u.checksum(), " vs ", u2.checksum())
	ok = ok and arrived == 10 and u.checksum() == u2.checksum()
	# chat and ping are events only; they must not change the world
	var before_cs := u.checksum()
	u.apply({"t": "chat", "pid": 1, "msg": "hello"})
	u.apply({"t": "ping", "pid": 1, "x": 5, "y": 5})
	ok = ok and u.checksum() == before_cs
	if not ok:
		find_divergence()
	print("SELFTEST ", "PASS" if ok else "FAIL")

## Steps an original and a reloaded copy side by side and reports the first field
## that differs. Used when the save/load or join snapshot check fails.
static func find_divergence() -> void:
	var a := Sim.new()
	a.setup_new(1)
	_chain(a)
	_run_ticks(a, 90 * 60, true)
	var c := Sim.new()
	c.from_dict(JSON.parse_string(JSON.stringify(a.to_dict(), "", false)))
	print("checksum right after load: ", a.checksum(), " vs ", c.checksum())
	for id in a.ents:
		var e1: Sim.Ent = a.ents[id]
		var e2: Sim.Ent = c.ents[id]
		for f in ["x", "y", "dir", "prog", "fuel", "energy", "rr", "rr2", "clock", "items", "inp", "out", "store", "want", "recipe"]:
			if str(e1.get(f)) != str(e2.get(f)) or typeof(e1.get(f)) != typeof(e2.get(f)):
				print("ent ", id, " ", e1.type, " field ", f, ": ", e1.get(f), " (", typeof(e1.get(f)), ") vs ", e2.get(f), " (", typeof(e2.get(f)), ")")
	for pid in a.players:
		for f in a.players[pid]:
			if str(a.players[pid][f]) != str(c.players[pid][f]) or typeof(a.players[pid][f]) != typeof(c.players[pid][f]):
				print("player field ", f, ": ", a.players[pid][f], " vs ", c.players[pid][f])
	print("rng ", a.rng.state, " vs ", c.rng.state, "  tick ", a.tick, " ", c.tick, " crit ", a.critters.size(), " ", c.critters.size(), " hub ", a.hub, " vs ", c.hub)
	for i in 900:
		var ja := JSON.stringify(a.to_dict(), "", false)
		var jc := JSON.stringify(c.to_dict(), "", false)
		if ja != jc:
			print("diverged after ", i, " steps")
			var da: Dictionary = JSON.parse_string(ja)
			var dc: Dictionary = JSON.parse_string(jc)
			for k in da:
				var sa := JSON.stringify(da[k])
				var sc := JSON.stringify(dc[k])
				if sa != sc:
					var p := 0
					while p < sa.length() and p < sc.length() and sa[p] == sc[p]:
						p += 1
					print(" key ", k, "\n   A: ", sa.substr(maxi(0, p - 160), 260), "\n   C: ", sc.substr(maxi(0, p - 160), 260))
			return
		a.step([])
		c.step([])
	print("no divergence in 900 steps")
