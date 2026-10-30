class_name Sim
extends RefCounted
## The whole game state and its fixed 60 Hz tick.
##
## Rules that keep it lockstep-ready:
##  * Every change comes in through apply(cmd). The UI and input code never touch state.
##  * Integers only for anything that affects outcomes (positions are milli-tiles,
##    belt positions are 1/240 of a tile, power is kW, satisfaction is per-mille).
##  * Randomness comes from `rng` (seeded, saved), never from randf().
##  * `events` is a one-way feed to the view (toasts, sparks). Nothing reads it back.

class Ent:
	var id := 0
	var type := ""
	var x := 0
	var y := 0
	var dir := 0
	var n := 1
	var items: Array = []        # belts: Vector2i(item_idx, pos), front item first
	var curve := 0               # belts: 0 straight, -1 fed from left, 1 fed from right
	var recipe := ""
	var inp := {}
	var out := {}
	var prog := 0
	var clock := 100
	var shards := 0
	var st := "idle"
	var want := false
	var anim := 0.0              # visual only
	var node := -1
	var fuel := 0
	var energy := 0
	var on := false
	var store := {}
	var buf: Array = []
	var partner := 0              # underground belts: id of the paired tunnel
	var role := 0                 # underground belts: 1 entrance, 2 exit
	var tq: Array = []            # underground belts: Vector2i(item_idx, ticks_left)
	var rr := 0
	var rr2 := 0
	var net := 0

const MW := 160
const MH := 160

var tick := 0
var next_id := 1
var rng: Rng
var ents := {}
var grid := PackedInt32Array()
var players := {}
var hub := {}
var unlock_b := {}
var unlock_r := {}
var milestone := 0
var research := {"count": 0, "offer": []}
var alts := {}
var elevator := {"phase": 0, "del": {}}
var nests: Array = []
var pods: Array = []
var critters: Array = []
var won := false
var events: Array = []
var settings := {}

var dirty := true
var topo_version := 0
var belts: Array = []
var machines: Array = []
var miners: Array = []
var gens: Array = []
var poles: Array = []
var logis: Array = []
var crates: Array = []
var tunnels: Array = []
var wires: Array = []
var elev_ent: Ent = null
var nets := {}

# ------------------------------------------------------------------ setup
## Call after World.generate(settings).
func setup_new(first_pid: int, first_name := "Engineer") -> void:
	settings = World.settings.duplicate()
	grid.resize(MW * MH)
	grid.fill(0)
	rng = Rng.new((World.world_seed * 7 + 1) & 0x7FFFFFFF)
	for t in Data.START_BUILD:
		unlock_b[t] = true
	for r in Data.START_RECIPES:
		unlock_r[r] = true
	for n in World.nests:
		nests.append({"x": n.x, "y": n.y, "hp": 160, "alive": true, "spawn": 0})
	for p in World.pods:
		pods.append({"x": p.x, "y": p.y, "taken": false})
	add_ent("hub", Data.HUBX, Data.HUBY, 0)
	add_player(first_pid, first_name)

func add_player(pid: int, pname := "Engineer") -> void:
	if players.has(pid):
		return
	var kit: int = Data.sval(settings, "kit")
	var inv := {}
	for k in Data.START_INV:
		inv[k] = Data.START_INV[k] * kit / 100
	players[pid] = {"x": Data.SPAWN_X, "y": Data.SPAWN_Y, "hp": 100000, "hurt": 0, "dead": 0, "cd": 0,
		"mx": 0, "my": 0, "fx": 0, "fy": 1, "f": false, "mine": Vector2i(-1, -1), "cur": Vector2i(-1, -1),
		"mine_t": 0, "pick_t": 0, "inv": inv, "craft_q": [], "craft_t": 0, "name": pname}

## Milestone / phase requirements after the "Milestone costs" setting.
func ms_req(i: int) -> Dictionary:
	var pct: int = Data.sval(settings, "ms_cost")
	var out := {}
	var req: Dictionary = Data.MILESTONES[i]["req"]
	for k in req:
		out[k] = maxi(1, (req[k] * pct + 99) / 100)
	return out

func phase_req(i: int) -> Dictionary:
	var pct: int = Data.sval(settings, "ms_cost")
	var out := {}
	var req: Dictionary = Data.PHASES[i]["req"]
	for k in req:
		out[k] = maxi(1, (req[k] * pct + 99) / 100)
	return out

# ------------------------------------------------------------------ helpers
func ent_at(x: int, y: int) -> Ent:
	if x < 0 or y < 0 or x >= MW or y >= MH:
		return null
	var id := grid[y * MW + x]
	if id == 0:
		return null
	return ents[id]

func inv_count(pid: int, k: String) -> int:
	return players[pid]["inv"].get(k, 0)

func give(pid: int, k: String, n: int) -> void:
	if n <= 0 or not players.has(pid):
		return
	var inv: Dictionary = players[pid]["inv"]
	inv[k] = inv.get(k, 0) + n

func take_inv(pid: int, k: String, n: int) -> void:
	var inv: Dictionary = players[pid]["inv"]
	inv[k] = inv.get(k, 0) - n
	if inv[k] <= 0:
		inv.erase(k)

func have(pid: int, k: String) -> int:
	return hub.get(k, 0) + inv_count(pid, k)

func take_any(pid: int, k: String, n: int) -> void:
	var h := mini(hub.get(k, 0), n)
	hub[k] = hub.get(k, 0) - h
	if hub[k] <= 0:
		hub.erase(k)
	if n - h > 0:
		take_inv(pid, k, n - h)

func afford(pid: int, cost: Dictionary, refund: Dictionary = {}) -> bool:
	for k in cost:
		if inv_count(pid, k) + refund.get(k, 0) < cost[k]:
			return false
	return true

func toast(pid: int, msg: String, kind: String = "") -> void:
	events.append({"t": "toast", "pid": pid, "msg": msg, "kind": kind})

func dist2(ax: int, ay: int, bx: int, by: int) -> int:
	return (ax - bx) * (ax - bx) + (ay - by) * (ay - by)

func ent_center(e: Ent) -> Vector2i:
	return Vector2i(e.x * 1000 + e.n * 500, e.y * 1000 + e.n * 500)

func in_reach(pid: int, e: Ent) -> bool:
	var p: Dictionary = players[pid]
	var c := ent_center(e)
	return dist2(p.x, p.y, c.x, c.y) <= Data.REACH * Data.REACH

func power_kw(e: Ent) -> int:
	return Data.BUILD[e.type]["power"] * Data.CLOCK_POW[e.clock] / 1000

func recipes_for(type: String) -> Array:
	var m: String = Data.BUILD[type].get("m", "")
	var out := []
	for k in Data.RECIPES:
		if Data.RECIPES[k]["m"] == m and unlock_r.has(k):
			out.append(k)
	return out

func miner_required(e: Ent) -> int:
	var nd: Dictionary = World.nodes[e.node]
	return Data.BUILD[e.type]["base_ticks"] * 10000 / nd.pur

# ------------------------------------------------------------------ entities
func add_ent(type: String, x: int, y: int, dir: int, id: int = 0) -> Ent:
	var e := Ent.new()
	if id == 0:
		id = next_id
		next_id += 1
	elif id >= next_id:
		next_id = id + 1
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.dir = dir
	e.n = Data.BUILD[type]["size"]
	if Data.is_miner(type):
		e.node = World.node_grid[(y + 1) * MW + x + 1] - 1
		e.recipe = "mine"
	if Data.is_machine(type) or Data.is_miner(type):
		e.st = "norecipe" if not Data.is_miner(type) else "idle"
	for j in e.n:
		for i in e.n:
			grid[(y + j) * MW + x + i] = id
	ents[id] = e
	dirty = true
	if type == "tunnel" and e.role == 0:
		_pair_tunnel(e)
	return e

## A new underground belt becomes the exit of an unpaired entrance behind it
## (same direction, within range); otherwise it is a new entrance.
func _pair_tunnel(e: Ent) -> void:
	e.role = 1
	var d: Vector2i = Data.DIRS[e.dir]
	for k in range(1, int(Data.BUILD["tunnel"]["range"]) + 2):
		var t := ent_at(e.x - d.x * k, e.y - d.y * k)
		if t != null and t.type == "tunnel" and t.dir == e.dir:
			if t.role == 1 and t.partner == 0:
				t.partner = e.id
				e.partner = t.id
				e.role = 2
			return

func tunnel_len(entrance: Ent) -> int:
	if not ents.has(entrance.partner):
		return 0
	var ex: Ent = ents[entrance.partner]
	return absi(ex.x - entrance.x) + absi(ex.y - entrance.y)

func contents(e: Ent) -> Dictionary:
	var out := {}
	for it in e.items:
		var k: String = Data.ITEM_KEYS[it.x]
		out[k] = out.get(k, 0) + 1
	for d in [e.inp, e.out, e.store]:
		for k in d:
			out[k] = out.get(k, 0) + d[k]
	for k in e.buf:
		out[k] = out.get(k, 0) + 1
	for q in e.tq:
		var k2: String = Data.ITEM_KEYS[q.x]
		out[k2] = out.get(k2, 0) + 1
	if e.fuel > 0:
		out["coal"] = out.get("coal", 0) + e.fuel
	if e.shards > 0:
		out["power_shard"] = out.get("power_shard", 0) + e.shards
	return out

func remove_ent(pid: int, e: Ent) -> void:
	if e.type == "hub":
		return
	var c: Dictionary = Data.BUILD[e.type]["cost"]
	for k in c:
		give(pid, k, c[k])
	var ct := contents(e)
	for k in ct:
		give(pid, k, ct[k])
	for j in e.n:
		for i in e.n:
			grid[(e.y + j) * MW + e.x + i] = 0
	if e.type == "tunnel" and ents.has(e.partner):
		var pt: Ent = ents[e.partner]
		pt.partner = 0
		if pt.role == 2:
			pt.role = 1
	ents.erase(e.id)
	events.append({"t": "removed", "pid": pid, "x": e.x, "y": e.y})
	dirty = true

## Returns "" if placement is valid, "same" for a no-op belt, otherwise a reason.
func check(pid: int, type: String, x: int, y: int, dir: int) -> String:
	if not unlock_b.has(type):
		return "Not unlocked yet"
	var n: int = Data.BUILD[type]["size"]
	if x < 0 or y < 0 or x + n > MW or y + n > MH:
		return "Outside the map"
	var p: Dictionary = players[pid]
	if dist2(x * 1000 + n * 500, y * 1000 + n * 500, p.x, p.y) > Data.REACH * Data.REACH:
		return "Out of reach"
	if Data.is_miner(type):
		var ni := World.node_at(x + 1, y + 1)
		if ni < 0 or World.nodes[ni].cx != x + 1 or World.nodes[ni].cy != y + 1:
			return "Place it on a resource node"
	if type == "elevator" and elev_ent != null:
		return "Only one Space Elevator"
	var rep: Ent = null
	for j in n:
		for i in n:
			var k := (y + j) * MW + x + i
			if World.tiles[k]:
				return "Cannot build on water"
			if not Data.is_miner(type) and not Data.is_walkable(type) and type != "pole" and World.node_grid[k]:
				return "A resource node is in the way"
			var id := grid[k]
			if id:
				var o: Ent = ents[id]
				if Data.is_belt(type) and Data.is_belt(o.type):
					rep = o
				else:
					return "Space is occupied"
	if not Data.is_walkable(type):
		for qid in players:
			var q: Dictionary = players[qid]
			if q.dead == 0 and q.x + 300 > x * 1000 and q.x - 300 < (x + n) * 1000 and q.y + 300 > y * 1000 and q.y - 300 < (y + n) * 1000:
				return "Someone is standing there"
	if rep != null and rep.type == type and rep.dir == dir:
		return "same"
	var refund: Dictionary = Data.BUILD[rep.type]["cost"] if rep != null else {}
	if not afford(pid, Data.BUILD[type]["cost"], refund):
		return "Missing materials"
	return ""

func place(pid: int, type: String, x: int, y: int, dir: int) -> void:
	var why := check(pid, type, x, y, dir)
	if why != "":
		if why != "same" and why != "Out of reach":
			toast(pid, why, "bad")
		return
	var cost: Dictionary = Data.BUILD[type]["cost"]
	var rep := ent_at(x, y) if Data.is_belt(type) else null
	if rep != null:
		for k in Data.BUILD[rep.type]["cost"]:
			give(pid, k, Data.BUILD[rep.type]["cost"][k])
		for k in cost:
			take_inv(pid, k, cost[k])
		rep.type = type
		rep.dir = dir
		dirty = true
		return
	for k in cost:
		take_inv(pid, k, cost[k])
	events.append({"t": "placed", "pid": pid, "x": x, "y": y})
	var e := add_ent(type, x, y, dir)
	if Data.is_machine(type):
		var opts := recipes_for(type)
		if opts.size() == 1:
			e.recipe = opts[0]

# ------------------------------------------------------------------ commands
func apply(c: Dictionary) -> void:
	var pid: int = c.get("pid", 0)
	if c.t == "join":
		add_player(pid, str(c.get("name", "Engineer")).substr(0, 20))
		toast(-1, "%s joined" % players[pid].name, "cy")
		return
	if c.t == "leave":
		if players.has(pid):
			for k in players[pid].inv:
				hub[k] = hub.get(k, 0) + players[pid].inv[k]
			toast(-1, "%s left. Their inventory went into the HUB." % players[pid].name, "")
			players.erase(pid)
		return
	if not players.has(pid):
		return
	var p: Dictionary = players[pid]
	var e: Ent = ents.get(c.get("id", -1), null)
	match c.t:
		"chat":
			var msg := str(c.get("msg", "")).strip_edges().substr(0, 200)
			if msg != "":
				events.append({"t": "chat", "pid": pid, "name": p.name, "msg": msg})
		"ping":
			events.append({"t": "ping", "pid": pid, "name": p.name, "x": int(c.x), "y": int(c.y)})
		"input":
			p.mx = c.mx
			p.my = c.my
			if c.mx != 0 or c.my != 0:
				p.fx = c.mx
				p.fy = c.my
			p.f = c.f
			p.mine = c.mine
			p.cur = c.cur
		"place":
			place(pid, c.type, c.x, c.y, c.dir)
		"set_dir":
			var b := ent_at(c.x, c.y)
			if b != null and Data.is_belt(b.type) and b.dir != c.dir:
				b.dir = c.dir
				dirty = true
		"remove":
			var r := ent_at(c.x, c.y)
			if r != null and in_reach(pid, r):
				remove_ent(pid, r)
		"rotate":
			if e != null and e.type != "hub" and in_reach(pid, e):
				e.dir = posmod(e.dir + c.d, 4)
				dirty = true
		"recipe":
			if e != null and e.recipe != c.k and recipes_for(e.type).has(c.k):
				for k in e.inp:
					give(pid, k, e.inp[k])
				for k in e.out:
					give(pid, k, e.out[k])
				e.inp = {}
				e.out = {}
				e.prog = 0
				e.recipe = c.k
		"clock":
			if e != null and e.recipe != "":
				e.clock = clampi(c.v, 1, 100 + 50 * e.shards)
		"shard_add":
			if e != null and e.shards < 3 and inv_count(pid, "power_shard") > 0:
				take_inv(pid, "power_shard", 1)
				e.shards += 1
		"shard_rem":
			if e != null and e.shards > 0:
				e.shards -= 1
				give(pid, "power_shard", 1)
				e.clock = mini(e.clock, 100 + 50 * e.shards)
		"take_out":
			if e != null:
				for k in e.out:
					give(pid, k, e.out[k])
				e.out = {}
		"fill_in":
			if e != null and Data.RECIPES.has(e.recipe):
				var R: Dictionary = Data.RECIPES[e.recipe]
				for k in R["in"]:
					var n := mini(inv_count(pid, k), in_cap(R["in"][k]) - e.inp.get(k, 0))
					if n > 0:
						take_inv(pid, k, n)
						e.inp[k] = e.inp.get(k, 0) + n
		"fuel":
			if e != null and e.type == "coalgen":
				var n := mini(inv_count(pid, "coal"), 50 - e.fuel)
				if n > 0:
					take_inv(pid, "coal", n)
					e.fuel += n
		"crate_take":
			if e != null and e.type == "crate":
				var keys: Array = [c.k] if c.k != "" else e.store.keys()
				for k in keys:
					give(pid, k, e.store.get(k, 0))
					e.store.erase(k)
		"hub_take":
			give(pid, c.k, hub.get(c.k, 0))
			hub.erase(c.k)
		"hub_dep":
			for k in p.inv.keys():
				if k == "power_shard" or k == "data_drive":
					continue
				hub[k] = hub.get(k, 0) + p.inv[k]
				p.inv.erase(k)
		"submit_ms":
			submit_milestone(pid)
		"research":
			do_research(pid)
		"pick_alt":
			if research.offer.has(c.k):
				alts[c.k] = true
				unlock_r[c.k] = true
				research.offer = []
				events.append({"t": "unlock"})
				toast(-1, "Alternate recipe unlocked: " + Data.RECIPES[c.k]["n"], "cy")
		"elev_dep":
			if elevator.phase < Data.PHASES.size():
				var req := phase_req(elevator.phase)
				for k in req:
					var n := mini(inv_count(pid, k), req[k] - elevator.del.get(k, 0))
					if n > 0:
						take_inv(pid, k, n)
						elevator.del[k] = elevator.del.get(k, 0) + n
		"elev_launch":
			launch_phase()
		"craft":
			var R: Dictionary = Data.RECIPES[c.k]
			var made := 0
			for j in c.get("n", 1):
				var ok := true
				for k in R["in"]:
					if inv_count(pid, k) < R["in"][k]:
						ok = false
				if not ok:
					break
				for k in R["in"]:
					take_inv(pid, k, R["in"][k])
				p.craft_q.append(c.k)
				made += 1
			if made == 0:
				toast(pid, "Not enough materials", "bad")
		"cancel_craft":
			var i: int = c.i
			if i >= 0 and i < p.craft_q.size():
				var R: Dictionary = Data.RECIPES[p.craft_q[i]]
				for k in R["in"]:
					give(pid, k, R["in"][k])
				p.craft_q.remove_at(i)
				if i == 0:
					p.craft_t = 0

func submit_milestone(pid: int) -> void:
	if milestone >= Data.MILESTONES.size():
		return
	var m: Dictionary = Data.MILESTONES[milestone]
	var req := ms_req(milestone)
	for k in req:
		if have(pid, k) < req[k]:
			return
	for k in req:
		take_any(pid, k, req[k])
	for b in m.ub:
		unlock_b[b] = true
	for r in m.ur:
		unlock_r[r] = true
	milestone += 1
	events.append({"t": "milestone"})
	toast(-1, "Milestone complete: " + m.n, "good")
	var names := []
	for b in m.ub:
		names.append(Data.BUILD[b]["n"])
	for r in m.ur:
		names.append(Data.RECIPES[r]["n"])
	if names.size():
		toast(-1, "Unlocked: " + ", ".join(names), "good")
	if m.get("research", false):
		toast(-1, "Data Drive analysis is open in the HUB", "cy")
	if milestone >= Data.MILESTONES.size():
		toast(-1, "All milestones done. Build the Space Elevator.", "good")

func research_cost() -> Dictionary:
	var n: int = research.count
	return {"data_drive": 1, "iron_plate": 20 + 15 * n, "cable": 10 + 10 * n}

func do_research(pid: int) -> void:
	if milestone < 2 or research.offer.size() > 0:
		return
	var c := research_cost()
	for k in c:
		if have(pid, k) < c[k]:
			return
	var pool := []
	for k in Data.ALTS:
		if not alts.has(k):
			pool.append(k)
	if pool.is_empty():
		return
	for k in c:
		take_any(pid, k, c[k])
	research.count += 1
	var offer := []
	while offer.size() < mini(2, pool.size()):
		var x: String = pool[rng.next_i(pool.size())]
		if not offer.has(x):
			offer.append(x)
	research.offer = offer

func launch_phase() -> void:
	if elevator.phase >= Data.PHASES.size():
		return
	var ph: Dictionary = Data.PHASES[elevator.phase]
	var req := phase_req(elevator.phase)
	for k in req:
		if elevator.del.get(k, 0) < req[k]:
			return
	elevator.phase += 1
	elevator.del = {}
	events.append({"t": "milestone"})
	toast(-1, ph.n + " launched", "good")
	if elevator.phase >= Data.PHASES.size():
		won = true
		events.append({"t": "victory"})

# ------------------------------------------------------------------ topology
func _next_belt(b: Ent) -> Ent:
	var d: Vector2i = Data.DIRS[b.dir]
	var t := ent_at(b.x + d.x, b.y + d.y)
	if t != null and Data.is_belt(t.type) and t.dir != (b.dir + 2) % 4:
		return t
	return null

func _calc_curve(b: Ent) -> int:
	var d := b.dir
	var bd: Vector2i = Data.DIRS[d]
	var bh := ent_at(b.x - bd.x, b.y - bd.y)
	if bh != null:
		if not Data.is_belt(bh.type) or bh.dir == d:
			return 0
	var L := (d + 3) % 4
	var Rr := (d + 1) % 4
	var lt := ent_at(b.x + Data.DIRS[L].x, b.y + Data.DIRS[L].y)
	var rt := ent_at(b.x + Data.DIRS[Rr].x, b.y + Data.DIRS[Rr].y)
	var fl := lt != null and Data.is_belt(lt.type) and lt.dir == Rr
	var fr := rt != null and Data.is_belt(rt.type) and rt.dir == L
	if fl and not fr:
		return -1
	if fr and not fl:
		return 1
	return 0

func recompute() -> void:
	dirty = false
	topo_version += 1
	belts = []; machines = []; miners = []; gens = []; poles = []; logis = []; crates = []; tunnels = []; elev_ent = null
	for id in ents:
		var e: Ent = ents[id]
		var t := e.type
		if Data.is_belt(t): belts.append(e)
		elif Data.is_machine(t): machines.append(e)
		elif Data.is_miner(t): miners.append(e)
		elif t == "coalgen": gens.append(e)
		elif t == "pole": poles.append(e)
		elif t == "splitter" or t == "merger": logis.append(e)
		elif t == "crate": crates.append(e)
		elif t == "tunnel": tunnels.append(e)
		elif t == "elevator": elev_ent = e
	for b in belts:
		b.curve = _calc_curve(b)
	# depth = distance to the end of the belt line; front belts update first
	var depth := {}
	for b in belts:
		if depth.has(b.id):
			continue
		var chain: Array = []
		var onpath := {}
		var cur: Ent = b
		var d_last := 0
		while true:
			onpath[cur.id] = true
			chain.append(cur)
			var t := _next_belt(cur)
			if t == null:
				d_last = 0
				break
			if depth.has(t.id):
				d_last = depth[t.id] + 1
				break
			if onpath.has(t.id):
				d_last = 0
				break
			cur = t
		for k in chain.size():
			depth[chain[k].id] = d_last + chain.size() - 1 - k
	belts.sort_custom(func(a, b2): return depth[a.id] < depth[b2.id] or (depth[a.id] == depth[b2.id] and a.id < b2.id))
	# power networks: poles within 9 tiles link (up to 5 nearest each)
	var par := {}
	for p in poles:
		par[p.id] = p.id
	wires = []
	var seen := {}
	for p in poles:
		var near := []
		for q in poles:
			if q != p and dist2(q.x, q.y, p.x, p.y) <= 81:
				near.append(q)
		near.sort_custom(func(a, b2):
			var da := dist2(a.x, a.y, p.x, p.y)
			var db := dist2(b2.x, b2.y, p.x, p.y)
			return da < db or (da == db and a.id < b2.id))
		for q in near.slice(0, 5):
			var key := "%d:%d" % [mini(p.id, q.id), maxi(p.id, q.id)]
			if not seen.has(key):
				seen[key] = true
				wires.append([p, q])
				par[_find(par, p.id)] = _find(par, q.id)
	for p in poles:
		p.net = _find(par, p.id)
	for list in [miners, machines, gens]:
		for e in list:
			e.net = 0
			for p in poles:
				if p.x + 3 >= e.x and p.x - 3 <= e.x + e.n - 1 and p.y + 3 >= e.y and p.y - 3 <= e.y + e.n - 1:
					e.net = p.net
					break

func _find(par: Dictionary, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]
		x = par[x]
	return x

# ------------------------------------------------------------------ transport
static func out_cap(n: int) -> int:
	return maxi(n * 4, 20)

static func in_cap(n: int) -> int:
	return maxi(n * 2, 10)

func belt_insert(b: Ent, item: String, from: int) -> bool:
	var d := b.dir
	if from == (d + 2) % 4:
		return false
	var p := 0
	if from != d:
		var fl := from == (d + 1) % 4
		if not ((b.curve == -1 and fl) or (b.curve == 1 and not fl)):
			p = Data.BELT_LEN / 2
	var it := b.items
	for o in it:
		if absi(o.y - p) < Data.BELT_SP:
			return false
	var i := 0
	while i < it.size() and it[i].y > p:
		i += 1
	it.insert(i, Vector2i(Data.ITEM_IDX[item], p))
	return true

func accept(t: Ent, item: String, from: int) -> bool:
	match t.type:
		"smelter", "constructor", "assembler", "foundry":
			if not Data.RECIPES.has(t.recipe):
				return false
			var R: Dictionary = Data.RECIPES[t.recipe]
			if not R["in"].has(item):
				return false
			if t.inp.get(item, 0) >= in_cap(R["in"][item]):
				return false
			t.inp[item] = t.inp.get(item, 0) + 1
			return true
		"coalgen":
			if item != "coal" or t.fuel >= 50:
				return false
			t.fuel += 1
			return true
		"crate":
			var s := 0
			for k in t.store:
				s += t.store[k]
			if s >= 800:
				return false
			t.store[item] = t.store.get(item, 0) + 1
			return true
		"hub":
			hub[item] = hub.get(item, 0) + 1
			return true
		"elevator":
			if elevator.phase >= Data.PHASES.size():
				return false
			var req := phase_req(elevator.phase)
			if not req.has(item) or elevator.del.get(item, 0) >= req[item]:
				return false
			elevator.del[item] = elevator.del.get(item, 0) + 1
			return true
		"tunnel":
			if t.role != 1 or from != t.dir or not ents.has(t.partner):
				return false
			var ln := tunnel_len(t)
			if t.tq.size() >= ln * 4 + 2:
				return false
			if t.tq.size() and t.tq[t.tq.size() - 1].y > ln * 60 - 15:
				return false
			t.tq.append(Vector2i(Data.ITEM_IDX[item], ln * 60))
			return true
		"splitter", "merger":
			if t.buf.size() >= 2 or from == (t.dir + 2) % 4:
				return false
			t.buf.append(item)
			return true
	return false

func try_push(x: int, y: int, item: String, dir: int) -> bool:
	var t := ent_at(x, y)
	if t == null:
		return false
	if Data.is_belt(t.type):
		return belt_insert(t, item, dir)
	return accept(t, item, dir)

func front_tile(e: Ent) -> Vector2i:
	var h := (e.n + 1) / 2
	var c := (e.n - 1) / 2
	var d: Vector2i = Data.DIRS[e.dir]
	return Vector2i(e.x + c + d.x * h, e.y + c + d.y * h)

func push_out(e: Ent) -> void:
	var ks := e.out.keys()
	if ks.is_empty():
		return
	var ft := front_tile(e)
	e.rr2 += 1
	var st := e.rr2 % ks.size()
	for i in ks.size():
		var k: String = ks[(st + i) % ks.size()]
		if e.out[k] > 0 and try_push(ft.x, ft.y, k, e.dir):
			e.out[k] -= 1
			if e.out[k] <= 0:
				e.out.erase(k)
			return

func net_sat(id: int) -> int:
	if not nets.has(id):
		return 0
	return nets[id]["sat"]

func upd_miner(e: Ent) -> void:
	var nd: Dictionary = World.nodes[e.node]
	var res: String = nd.res
	e.want = false
	if e.out.get(res, 0) >= 50:
		e.st = "full"
	else:
		e.want = true
		var sat := net_sat(e.net) if e.net else 0
		if sat <= 0:
			e.st = "nopower"
		else:
			e.st = "work"
			var step := e.clock * sat * int(Data.sval(settings, "speed")) / 100000
			e.prog += step
			e.anim += step / 1200.0
			var req := miner_required(e)
			if e.prog >= req:
				e.prog -= req
				e.out[res] = e.out.get(res, 0) + 1
	push_out(e)

func upd_machine(e: Ent) -> void:
	e.want = false
	if not Data.RECIPES.has(e.recipe):
		e.st = "norecipe"
		push_out(e)
		return
	var R: Dictionary = Data.RECIPES[e.recipe]
	var room := true
	for k in R["out"]:
		if e.out.get(k, 0) + R["out"][k] > out_cap(R["out"][k]):
			room = false
	var has_all := true
	for k in R["in"]:
		if e.inp.get(k, 0) < R["in"][k]:
			has_all = false
	if not room:
		e.st = "full"
	elif not has_all and e.prog <= 0:
		e.st = "input"
	else:
		e.want = true
		var sat := net_sat(e.net) if e.net else 0
		if sat <= 0:
			e.st = "nopower"
		else:
			e.st = "work"
			if e.prog <= 0:
				for k in R["in"]:
					e.inp[k] -= R["in"][k]
					if e.inp[k] <= 0:
						e.inp.erase(k)
				e.prog = 1
			var step := e.clock * sat * int(Data.sval(settings, "speed")) / 100000
			e.prog += step
			e.anim += step / 6000.0
			if e.prog >= int(R["t"]) * 6000:
				for k in R["out"]:
					e.out[k] = e.out.get(k, 0) + R["out"][k]
				e.prog = 0
	push_out(e)

func upd_belt(b: Ent) -> void:
	var it := b.items
	if it.is_empty():
		return
	var v: int = Data.BUILD[b.type]["speed"]
	var d: Vector2i = Data.DIRS[b.dir]
	var i := 0
	while i < it.size():
		var o: Vector2i = it[i]
		var np := o.y + v
		if i == 0 and np >= Data.BELT_LEN:
			if try_push(b.x + d.x, b.y + d.y, Data.ITEM_KEYS[o.x], b.dir):
				it.remove_at(0)
				continue
			np = Data.BELT_LEN
		elif i > 0:
			var lim: int = it[i - 1].y - Data.BELT_SP
			if np > lim:
				np = maxi(o.y, lim)
		it[i] = Vector2i(o.x, np)
		i += 1

func upd_logi(e: Ent) -> void:
	if e.buf.is_empty():
		return
	var outs := [e.dir, (e.dir + 3) % 4, (e.dir + 1) % 4] if e.type == "splitter" else [e.dir]
	for k in outs.size():
		var d: int = outs[(e.rr + k) % outs.size()]
		if try_push(e.x + Data.DIRS[d].x, e.y + Data.DIRS[d].y, e.buf[0], d):
			e.buf.remove_at(0)
			e.rr = (e.rr + k + 1) % outs.size()
			break

## Items travel underground at Mk.1 belt speed (60 ticks per tile) and leave the exit forwards.
func upd_tunnel(e: Ent) -> void:
	if e.role != 1 or e.tq.is_empty():
		return
	for i in e.tq.size():
		var q: Vector2i = e.tq[i]
		if q.y > 0:
			e.tq[i] = Vector2i(q.x, q.y - 4)
	var f: Vector2i = e.tq[0]
	if f.y <= 0 and ents.has(e.partner):
		var ex: Ent = ents[e.partner]
		var d: Vector2i = Data.DIRS[ex.dir]
		if try_push(ex.x + d.x, ex.y + d.y, Data.ITEM_KEYS[f.x], ex.dir):
			e.tq.remove_at(0)

## Crates feed any belt on any side that points away from them.
func upd_crate(e: Ent) -> void:
	var ks := e.store.keys()
	if ks.is_empty():
		return
	for d in 4:
		var b := ent_at(e.x + Data.DIRS[d].x, e.y + Data.DIRS[d].y)
		if b == null or not Data.is_belt(b.type) or b.dir != d:
			continue
		e.rr += 1
		var k: String = ks[e.rr % ks.size()]
		if e.store.get(k, 0) <= 0:
			continue
		if belt_insert(b, k, d):
			e.store[k] -= 1
			if e.store[k] <= 0:
				e.store.erase(k)
				ks = e.store.keys()
				if ks.is_empty():
					return

# ------------------------------------------------------------------ tick
func step(cmds: Array) -> void:
	for c in cmds:
		apply(c)
	_tick()

func _tick() -> void:
	if dirty:
		recompute()
	tick += 1
	nets = {}
	for g in gens:
		g.on = false
		if g.net and (g.energy > 0 or g.fuel > 0):
			_net(g.net).cap += Data.BUILD["coalgen"]["gen"]
			g.on = true
	for list in [miners, machines]:
		for e in list:
			if e.net and e.want:
				_net(e.net).dem += power_kw(e)
	for id in nets:
		var n: Dictionary = nets[id]
		n.sat = 0 if n.cap <= 0 else (1000 if n.dem <= 0 else mini(1000, n.cap * 1000 / n.dem))
		n.load = mini(1000, n.dem * 1000 / n.cap) if n.cap > 0 else 0
	for g in gens:
		if not g.on:
			continue
		var load: int = nets[g.net].load
		g.energy -= load
		g.anim += (0.4 + load * 0.007) / 60.0
		if g.energy <= 0:
			if g.fuel > 0:
				g.fuel -= 1
				g.energy += 240000
			else:
				g.energy = 0
	for e in miners:
		upd_miner(e)
	for e in machines:
		upd_machine(e)
	for b in belts:
		upd_belt(b)
	for e in logis:
		upd_logi(e)
	for e in crates:
		upd_crate(e)
	for e in tunnels:
		upd_tunnel(e)
	for pid in players:
		_upd_player(pid)
	_upd_wild()

func _net(id: int) -> Dictionary:
	if not nets.has(id):
		nets[id] = {"cap": 0, "dem": 0, "sat": 0, "load": 0}
	return nets[id]

func _solid(x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return true
	var tx := x / 1000
	var ty := y / 1000
	if tx >= MW or ty >= MH:
		return true
	if World.tiles[ty * MW + tx]:
		return true
	var id := grid[ty * MW + tx]
	if id == 0:
		return false
	return not Data.is_walkable(ents[id].type)

func _blocked(x: int, y: int) -> bool:
	var r := 280
	return _solid(x - r, y - r) or _solid(x + r, y - r) or _solid(x - r, y + r) or _solid(x + r, y + r)

func _upd_player(pid: int) -> void:
	var p: Dictionary = players[pid]
	if p.dead > 0:
		p.dead -= 1
		if p.dead == 0:
			p.x = Data.SPAWN_X
			p.y = Data.SPAWN_Y
			p.hp = 100000
		return
	if p.mx != 0 or p.my != 0:
		var sp := 103 if (p.mx == 0 or p.my == 0) else 73
		var nx: int = p.x + p.mx * sp
		var ny: int = p.y + p.my * sp
		if not _blocked(nx, p.y):
			p.x = nx
		if not _blocked(p.x, ny):
			p.y = ny
	p.hurt += 1
	if p.hurt > 240:
		p.hp = mini(100000, p.hp + 100)
	for pod in pods:
		if not pod.taken and dist2(pod.x, pod.y, p.x, p.y) < 1400 * 1400:
			pod.taken = true
			give(pid, "data_drive", 1)
			give(pid, "power_shard", 1)
			toast(pid, "Crash pod salvaged: 1 Data Drive and 1 Power Shard", "cy")
	# zapper
	p.cd -= 1
	if p.cd <= 0:
		var best = null
		var bd := 7000 * 7000
		for c in critters:
			var d := dist2(c.x, c.y, p.x, p.y)
			if d < bd:
				bd = d
				best = c
		if best == null:
			for n in nests:
				if not n.alive:
					continue
				var d := dist2(n.x, n.y, p.x, p.y)
				if d < bd:
					bd = d
					best = n
		if best != null:
			best.hp -= 10
			p.cd = 18
			events.append({"t": "bolt", "x1": p.x, "y1": p.y, "x2": best.x, "y2": best.y})
			if best.hp <= 0:
				if best.has("nest"):
					critters.erase(best)
					events.append({"t": "burst", "x": best.x, "y": best.y, "c": "#b5532e", "n": 14})
				else:
					best.alive = false
					var ni := nests.find(best)
					var keep := []
					for c in critters:
						if c.nest != ni:
							keep.append(c)
					critters = keep
					give(pid, "power_shard", 1)
					events.append({"t": "burst", "x": best.x, "y": best.y, "c": "#ff7a3a", "n": 30})
					toast(pid, "Burrow destroyed. Recovered a Power Shard", "cy")
	# hand mining
	var mt: Vector2i = p.mine
	var ni2 := World.node_at(mt.x, mt.y)
	if ni2 >= 0 and grid[mt.y * MW + mt.x] == 0 and dist2(mt.x * 1000 + 500, mt.y * 1000 + 500, p.x, p.y) <= Data.MINE_REACH * Data.MINE_REACH:
		p.mine_t += 1
		if p.mine_t >= 33:
			p.mine_t = 0
			var res: String = World.nodes[ni2].res
			give(pid, res, 1)
			events.append({"t": "chip", "x": mt.x * 1000 + 500, "y": mt.y * 1000 + 500, "k": res})
	else:
		p.mine_t = 0
	# pick up from belts (hold F)
	if p.f:
		p.pick_t += 1
		if p.pick_t >= 2:
			p.pick_t = 0
			_pickup(pid, p)
	else:
		p.pick_t = 0
	# hand crafting
	if p.craft_q.size():
		var R: Dictionary = Data.RECIPES[p.craft_q[0]]
		p.craft_t += 1
		if p.craft_t >= int(R["t"]) * 24:
			p.craft_t = 0
			p.craft_q.remove_at(0)
			for k in R["out"]:
				give(pid, k, R["out"][k])
			events.append({"t": "crafted", "pid": pid})
	else:
		p.craft_t = 0

func _pickup(pid: int, p: Dictionary) -> void:
	var ptx: int = p.x / 1000
	var pty: int = p.y / 1000
	var cand: Array = []
	for y in range(pty - 2, pty + 3):
		for x in range(ptx - 2, ptx + 3):
			var b := ent_at(x, y)
			if b != null and Data.is_belt(b.type) and b.items.size() and dist2(x * 1000 + 500, y * 1000 + 500, p.x, p.y) <= 1800 * 1800:
				cand.append(b)
	var cur: Vector2i = p.cur
	var hb := ent_at(cur.x, cur.y)
	if hb != null and Data.is_belt(hb.type) and hb.items.size() and in_reach(pid, hb) and not cand.has(hb):
		cand.append(hb)
	if cand.is_empty():
		return
	var b: Ent = cand[0]
	var o: Vector2i = b.items.pop_back()
	var k: String = Data.ITEM_KEYS[o.x]
	give(pid, k, 1)
	events.append({"t": "pickup", "pid": pid, "k": k, "bx": b.x, "by": b.y, "dir": b.dir, "curve": b.curve, "pos": o.y})

func _upd_wild() -> void:
	var wild: int = Data.sval(settings, "wildlife")
	var aggro := 9000 if wild == 3 else 7000
	var dmg := 18000 if wild == 3 else 12000
	var chase := 66 if wild == 3 else 57
	for i in nests.size():
		var n: Dictionary = nests[i]
		if not n.alive:
			continue
		n.spawn -= 1
		if n.spawn <= 0:
			var count := 0
			for c in critters:
				if c.nest == i:
					count += 1
			if count < 3:
				critters.append({"x": n.x + rng.next_i(1000) - 500, "y": n.y + rng.next_i(1000) - 500, "hp": 30, "nest": i,
					"atk": 0, "wt": 0, "tx": n.x, "ty": n.y, "vx": 0, "vy": 0})
			n.spawn = 1200
	for c in critters:
		var n: Dictionary = nests[c.nest]
		var target = null
		var bd := aggro * aggro
		for pid in players:
			if wild <= 1:
				break
			var p: Dictionary = players[pid]
			if p.dead > 0:
				continue
			var d := dist2(p.x, p.y, c.x, c.y)
			if d < bd and dist2(p.x, p.y, n.x, n.y) < 16000 * 16000:
				bd = d
				target = pid
		var tx: int
		var ty: int
		var sp: int
		if target != null:
			var p: Dictionary = players[target]
			tx = p.x
			ty = p.y
			sp = chase
			if bd < 750 * 750 and c.atk <= 0:
				p.hp -= dmg
				p.hurt = 0
				c.atk = 60
				events.append({"t": "hurt", "pid": target})
				if p.hp <= 0:
					p.hp = 0
					p.dead = 180
					p.craft_t = 0
					toast(target, "You were overrun. Redeploying at the HUB", "bad")
		else:
			c.wt -= 1
			if c.wt <= 0:
				c.tx = n.x + rng.next_i(8000) - 4000
				c.ty = n.y + rng.next_i(8000) - 4000
				c.wt = 120 + rng.next_i(180)
			tx = c.tx
			ty = c.ty
			sp = 22
		c.atk -= 1
		var dx: int = tx - c.x
		var dy: int = ty - c.y
		var dd := int(sqrt(float(dx * dx + dy * dy)))
		if dd > 300:
			var nx: int = c.x + dx * sp / dd
			var ny: int = c.y + dy * sp / dd
			if not World.is_water(nx / 1000, ny / 1000):
				c.x = nx
				c.y = ny
			c.vx = dx
			c.vy = dy

# ------------------------------------------------------------------ save / load / checksum
func to_dict() -> Dictionary:
	var el := []
	for id in ents:
		var e: Ent = ents[id]
		var o := {"id": e.id, "t": e.type, "x": e.x, "y": e.y, "d": e.dir}
		if Data.is_belt(e.type):
			var its := []
			for it in e.items:
				its.append([Data.ITEM_KEYS[it.x], it.y])
			o["it"] = its
		if e.recipe != "":
			o.merge({"r": e.recipe, "in": e.inp, "out": e.out, "pg": e.prog, "ck": e.clock, "sh": e.shards})
		if e.type == "coalgen":
			o.merge({"fu": e.fuel, "en": e.energy})
		if e.type == "crate":
			o["st"] = e.store
		if e.buf.size():
			o["bf"] = e.buf
		if e.rr or e.rr2 or e.want:
			o["rr"] = [e.rr, e.rr2, e.want]
		if e.type == "tunnel":
			var q := []
			for it in e.tq:
				q.append([Data.ITEM_KEYS[it.x], it.y])
			o["tn"] = [e.partner, e.role, q]
		el.append(o)
	var pl := {}
	for pid in players:
		var p: Dictionary = players[pid].duplicate(true)
		p.mine = [p.mine.x, p.mine.y]
		p.cur = [p.cur.x, p.cur.y]
		pl[str(pid)] = p
	return {"v": 3, "settings": settings, "tick": tick, "next_id": next_id, "rng": rng.state, "players": pl, "hub": hub,
		"unlock_b": unlock_b.keys(), "unlock_r": unlock_r.keys(), "milestone": milestone, "research": research,
		"alts": alts.keys(), "elevator": elevator, "nests": nests, "pods": pods, "critters": critters, "won": won, "ents": el}

## World.generate(d.settings) must have run first.
func from_dict(d: Dictionary) -> void:
	settings = d.get("settings", Data.default_settings())
	for k in settings:
		settings[k] = int(settings[k])
	grid.resize(MW * MH)
	grid.fill(0)
	tick = int(d.tick)
	rng = Rng.new(int(d.rng))
	hub = _ints(d.hub)
	for k in d.unlock_b: unlock_b[k] = true
	for k in d.unlock_r: unlock_r[k] = true
	for k in d.alts: alts[k] = true
	milestone = int(d.milestone)
	research = {"count": int(d.research.count), "offer": d.research.offer}
	elevator = {"phase": int(d.elevator.phase), "del": _ints(d.elevator.del)}
	won = d.won
	for n in d.nests:
		nests.append({"x": int(n.x), "y": int(n.y), "hp": int(n.hp), "alive": n.alive, "spawn": int(n.spawn)})
	for p in d.pods:
		pods.append({"x": int(p.x), "y": int(p.y), "taken": p.taken})
	for c in d.critters:
		critters.append({"x": int(c.x), "y": int(c.y), "hp": int(c.hp), "nest": int(c.nest), "atk": int(c.atk), "wt": int(c.wt), "tx": int(c.tx), "ty": int(c.ty), "vx": int(c.vx), "vy": int(c.vy)})
	for pid_s in d.players:
		var s: Dictionary = d.players[pid_s]
		var pid := int(pid_s)
		add_player(pid, str(s.get("name", "Engineer")))
		var p: Dictionary = players[pid]
		for k in ["x", "y", "hp", "hurt", "dead", "cd", "mx", "my", "fx", "fy", "mine_t", "pick_t", "craft_t"]:
			p[k] = int(s.get(k, p[k]))
		p.f = bool(s.get("f", false))
		if s.has("mine") and s.mine is Array:
			p.mine = Vector2i(int(s.mine[0]), int(s.mine[1]))
			p.cur = Vector2i(int(s.cur[0]), int(s.cur[1]))
		p.inv = _ints(s.inv)
		p.craft_q = s.craft_q.duplicate()
	for o in d.ents:
		var e := Ent.new()
		if o.t == "tunnel":
			# restore pairing from the save instead of re-pairing
			e = _restore_tunnel(o)
		else:
			e = add_ent(o.t, int(o.x), int(o.y), int(o.d), int(o.id))
		if o.has("it"):
			for it in o.it:
				e.items.append(Vector2i(Data.ITEM_IDX[it[0]], int(it[1])))
		if o.has("r"):
			e.recipe = o.r
			e.inp = _ints(o["in"])
			e.out = _ints(o.out)
			e.prog = int(o.pg)
			e.clock = int(o.ck)
			e.shards = int(o.sh)
		if o.has("fu"):
			e.fuel = int(o.fu)
			e.energy = int(o.en)
		if o.has("st"):
			e.store = _ints(o.st)
		if o.has("bf"):
			e.buf = o.bf.duplicate()
		if o.has("rr"):
			e.rr = int(o.rr[0])
			e.rr2 = int(o.rr[1])
			e.want = bool(o.rr[2])
	next_id = maxi(next_id, int(d.next_id))
	dirty = true

func _restore_tunnel(o: Dictionary) -> Ent:
	var e := Ent.new()
	e.role = int(o.tn[1])     # non-zero role skips auto-pairing in add_ent
	if e.role == 0:
		e.role = 1
	var made := add_ent_preset(e, o.t, int(o.x), int(o.y), int(o.d), int(o.id))
	made.partner = int(o.tn[0])
	for it in o.tn[2]:
		made.tq.append(Vector2i(Data.ITEM_IDX[it[0]], int(it[1])))
	return made

## add_ent for an Ent whose role is already set (used when loading tunnels).
func add_ent_preset(e: Ent, type: String, x: int, y: int, dir: int, id: int) -> Ent:
	if id >= next_id:
		next_id = id + 1
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.dir = dir
	e.n = Data.BUILD[type]["size"]
	grid[y * MW + x] = id
	ents[id] = e
	dirty = true
	return e

## JSON turns ints into floats; convert counts back.
func _ints(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[k] = int(src[k])
	return out

## Cheap state hash. Lockstep peers compare this every few seconds to catch desyncs.
func checksum() -> int:
	var h := tick
	for id in ents:
		var e: Ent = ents[id]
		h = (h * 31 + e.id * 7 + e.x * 13 + e.y * 17 + e.dir + e.prog + e.fuel + e.energy + e.rr + e.rr2 + e.clock + e.partner + e.tq.size() * 5) & 0x7FFFFFFF
		for it in e.items:
			h = (h * 17 + it.x * 3 + it.y) & 0x7FFFFFFF
		for dct in [e.inp, e.out, e.store]:
			for k in dct:
				h = (h * 13 + dct[k]) & 0x7FFFFFFF
	for pid in players:
		var p: Dictionary = players[pid]
		h = (h * 31 + p.x + p.y * 3 + p.hp + p.inv.size() * 7) & 0x7FFFFFFF
		for k in p.inv:
			h = (h * 13 + p.inv[k]) & 0x7FFFFFFF
	for k in hub:
		h = (h * 13 + hub[k]) & 0x7FFFFFFF
	for c in critters:
		h = (h * 7 + c.x + c.y * 3 + c.hp) & 0x7FFFFFFF
	return (h * 31 + milestone + rng.state) & 0x7FFFFFFF
