class_name WorldView
extends Node2D
## Draws the world from the simulation state. Reads Sim, never writes it.

const T := 32.0
const K := 32.0 / 48.0   # sprite pixels (48 per tile) -> world pixels
const LAYER := preload("res://scripts/layer.gd")

var main
var cam: Camera2D
var layers := {}
var particles: Array = []
var bolts: Array = []
var shake := 0.0
var rpos := {}
var walk := {}
var time := 0.0
var font: Font
var ground_ver := -1
var spr := {}
var belt_tex := {}
var node_tex: Array = []
var decor_tex := {}
var vr := Rect2i()
var terrain_mat: ShaderMaterial
var pings: Array = []
var name_font: Font

func setup(m) -> void:
	main = m
	var terrain := ColorRect.new()
	terrain.size = Vector2(Data.MW * T, Data.MH * T)
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain.material = terrain_mat
	add_child(terrain)
	for k in ["ground", "under", "belts", "items", "build", "top", "cursor"]:
		var l := Node2D.new()
		l.set_script(LAYER)
		l.view = self
		l.kind = k
		add_child(l)
		layers[k] = l
	cam = Camera2D.new()
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	font = load("res://assets/fonts/titillium-web-latin-900-normal.woff2")
	for k in ["miner1", "miner2", "smelter", "constructor", "assembler", "foundry", "coalgen", "hub", "elevator", "crate", "splitter", "merger", "nest", "pod"]:
		spr[k] = Data.tex("sprites/" + k)
	for b in ["belt1", "belt2", "belt3"]:
		belt_tex[b] = [Data.tex("belts/%s_straight" % b), Data.tex("belts/%s_curve" % b)]
	for k in ["rock", "shrub", "stalk"]:
		decor_tex[k] = [Data.tex("decor/%s_0" % k), Data.tex("decor/%s_1" % k), Data.tex("decor/%s_2" % k)]
	name_font = load("res://assets/fonts/titillium-web-latin-700-normal.woff2")
	rebuild_world()

## Call whenever World.generate() has run (new seed / settings, join, load).
func rebuild_world() -> void:
	if terrain_mat == null:
		return
	terrain_mat.set_shader_parameter("seed_i", World.world_seed)
	terrain_mat.set_shader_parameter("water_e", World.we)
	node_tex.clear()
	for i in World.nodes.size():
		var nd: Dictionary = World.nodes[i]
		node_tex.append(Data.tex("nodes/%s_%d_%d" % [nd.res, nd.pur, i % 3]))
	ground_ver = -1

func sim() -> Sim:
	return main.sim

func frame(delta: float) -> void:
	time += delta
	var s := sim()
	for pid in s.players:
		var p: Dictionary = s.players[pid]
		var target := Vector2(p.x, p.y) / 1000.0 * T
		if pid == main.pid:
			target = Vector2(main.local_pos()) / 1000.0 * T
		if not rpos.has(pid) or rpos[pid].distance_to(target) > T * 3:
			rpos[pid] = target
		var before: Vector2 = rpos[pid]
		rpos[pid] = before.lerp(target, minf(1.0, delta * 22.0))
		walk[pid] = walk.get(pid, 0.0) + before.distance_to(rpos[pid]) * 0.35
	if rpos.has(main.pid):
		cam.position = rpos[main.pid]
	cam.zoom = Vector2(main.zoom, main.zoom)
	shake = maxf(0.0, shake - delta * 3.0)
	cam.offset = Vector2(randf() - 0.5, randf() - 0.5) * shake * 8.0 / main.zoom if shake > 0 else Vector2.ZERO
	for g in s.gens:
		if g.on and s.nets.has(g.net) and s.nets[g.net].load > 0 and randf() < delta * 6.0 * s.nets[g.net].load / 1000.0:
			var a: float = g.dir * PI / 2.0
			var l := Vector2(-32, -32) * K
			var c := Vector2((g.x + 1.5) * T, (g.y + 1.5) * T) + l.rotated(a)
			particles.append({"p": c, "v": Vector2(8 + randf() * 6, -5 - randf() * 6), "life": 2.6, "max": 2.6, "col": Color("#2e2c2a"), "size": 8.0, "kind": "smoke"})
	for q in particles:
		q.life -= delta
		q.p += q.v * delta
		if q.kind == "smoke":
			q.size += delta * 8.0
		elif q.kind == "item":
			pass
		else:
			q.v *= 0.92
	particles = particles.filter(func(q): return q.life > 0)
	for b in bolts:
		b.t -= delta
	bolts = bolts.filter(func(b): return b.t > 0)
	pings = pings.filter(func(pg): return time - pg.t < 5.0)
	var size := get_viewport_rect().size / cam.zoom
	var c0 := cam.get_screen_center_position()
	vr = Rect2i(int(floor((c0.x - size.x / 2) / T)) - 2, int(floor((c0.y - size.y / 2) / T)) - 2, int(size.x / T) + 5, int(size.y / T) + 5)
	if s.topo_version != ground_ver:
		ground_ver = s.topo_version
		layers.ground.queue_redraw()
	for k in ["under", "belts", "items", "build", "top", "cursor"]:
		layers[k].queue_redraw()

func on_event(ev: Dictionary) -> void:
	match ev.t:
		"bolt":
			bolts.append({"a": Vector2(ev.x1, ev.y1) / 1000.0 * T, "b": Vector2(ev.x2, ev.y2) / 1000.0 * T, "t": 0.09, "seed": randi()})
			_burst(Vector2(ev.x2, ev.y2) / 1000.0 * T, Color("#9fe8ff"), 5, 90.0, 0.25, 2.0)
		"burst":
			_burst(Vector2(ev.x, ev.y) / 1000.0 * T, Color(ev.c), ev.n, 120.0, 0.6, 3.0)
		"chip":
			_burst(Vector2(ev.x, ev.y) / 1000.0 * T, Color(Data.ITEMS[ev.k]["c"]), 6, 80.0, 0.4, 1.6)
		"hurt":
			if ev.pid == main.pid:
				shake = 0.6
		"pickup":
			var loc := belt_local(ev.curve, ev.pos / float(Data.BELT_LEN))
			var r := rot_local(loc, ev.dir)
			var from := Vector2(ev.bx + r.x, ev.by + r.y) * T
			var to: Vector2 = rpos.get(ev.pid, from)
			particles.append({"p": from, "v": (to - from) * 4.5, "life": 0.22, "max": 0.22, "col": Color.WHITE, "size": 6.0, "kind": "item", "tex": Data.icon(ev.k)})

func add_ping(x: int, y: int, who: String) -> void:
	pings.append({"p": Vector2(x + 0.5, y + 0.5) * T, "t": time, "who": who})

func _burst(at: Vector2, col: Color, n: int, spd: float, life: float, size: float) -> void:
	for i in n:
		var a := randf() * TAU
		var s := spd * (0.3 + randf() * 0.7)
		particles.append({"p": at, "v": Vector2(cos(a), sin(a)) * s, "life": life, "max": life, "col": col, "size": size, "kind": "spark"})

func in_view(x: int, y: int, n: int) -> bool:
	return x + n >= vr.position.x and x <= vr.end.x and y + n >= vr.position.y and y <= vr.end.y

static func belt_local(curve: int, p: float) -> Vector2:
	if curve == 0:
		return Vector2(0.5, 1.0 - p)
	var th := (1.0 - p) * PI / 2.0
	var x := 0.5 * cos(th)
	var y := 0.5 * sin(th)
	return Vector2(x, y) if curve == -1 else Vector2(1.0 - x, y)

static func rot_local(l: Vector2, d: int) -> Vector2:
	var v := l - Vector2(0.5, 0.5)
	for i in d:
		v = Vector2(-v.y, v.x)
	return v + Vector2(0.5, 0.5)

# ------------------------------------------------------------------ layers
func draw_layer(c: Node2D, kind: String) -> void:
	match kind:
		"ground": _draw_ground(c)
		"under": _draw_under(c)
		"belts": _draw_belts(c)
		"items": _draw_items(c)
		"build": _draw_build(c)
		"top": _draw_top(c)
		"cursor": _draw_cursor(c)

func _draw_ground(c: Node2D) -> void:
	var s := sim()
	for i in World.nodes.size():
		var nd: Dictionary = World.nodes[i]
		c.draw_texture_rect(node_tex[i], Rect2((nd.cx - 2) * T, (nd.cy - 2) * T, 5 * T, 5 * T), false)
	for d in World.decor:
		if s.grid[d.y * Data.MW + d.x] != 0:
			continue
		c.draw_texture_rect(decor_tex[d.kind][d.v], Rect2((d.x + d.jx - 0.1) * T, (d.y + d.jy - 0.15) * T, 1.2 * T, 1.2 * T), false)

func _draw_under(c: Node2D) -> void:
	var s := sim()
	var hov: Sim.Ent = main.hover_ent()
	if main.hand == "pole" or (hov != null and hov.type == "pole"):
		for p in s.poles:
			if not in_view(p.x - 3, p.y - 3, 7):
				continue
			var r := Rect2((p.x - 3) * T, (p.y - 3) * T, 7 * T, 7 * T)
			c.draw_rect(r, Color(0.35, 0.67, 1.0, 0.10))
			c.draw_rect(r, Color(0.47, 0.75, 1.0, 0.45), false, 1.0)

func _draw_belts(c: Node2D) -> void:
	for b in sim().belts:
		if not in_view(b.x, b.y, 1):
			continue
		var tx: Array = belt_tex[b.type]
		var spd: float = Data.BUILD[b.type]["speed"] * 60.0 / Data.BELT_LEN
		var f := int(time * spd * 64.0) % 8
		c.draw_set_transform(Vector2((b.x + 0.5) * T, (b.y + 0.5) * T), b.dir * PI / 2.0, Vector2(-1, 1) if b.curve == 1 else Vector2.ONE)
		c.draw_texture_rect_region(tx[0 if b.curve == 0 else 1], Rect2(-T / 2 - 0.3, -T / 2 - 0.3, T + 0.6, T + 0.6), Rect2(f * 64, 0, 64, 64))
	for e in sim().tunnels:
		if in_view(e.x, e.y, 1):
			_draw_tunnel(c, e.x, e.y, e.dir, e.role, e.partner != 0, 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Underground belt: belt on the open half, a dark mouth where items dive under.
## Entrances show the belt behind the mouth; exits show it in front.
func _draw_tunnel(c: Node2D, x: int, y: int, dir: int, role: int, paired: bool, alpha: float) -> void:
	var spd: float = 60.0 / Data.BELT_LEN
	var f := int(time * spd * 64.0) % 8
	c.draw_set_transform(Vector2((x + 0.5) * T, (y + 0.5) * T), dir * PI / 2.0, Vector2.ONE)
	var h := T / 2.0
	var belt_rect := Rect2(-h, 0, T, h) if role != 2 else Rect2(-h, -h, T, h)
	var src := Rect2(f * 64, 32, 64, 32) if role != 2 else Rect2(f * 64, 0, 64, 32)
	c.draw_texture_rect_region(belt_tex.belt1[0], belt_rect, src, Color(1, 1, 1, alpha))
	var hood_y := -h if role != 2 else 0.0
	c.draw_rect(Rect2(-h + 1, hood_y, T - 2, h), Color(0.17, 0.16, 0.15, alpha))
	c.draw_rect(Rect2(-h + 1, hood_y, 4, h), Color(0.89, 0.7, 0.24, alpha))
	c.draw_rect(Rect2(h - 5, hood_y, 4, h), Color(0.89, 0.7, 0.24, alpha))
	var mouth_y := 0.0 if role != 2 else 0.0
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + i * PI / 12.0
		pts.append(Vector2(cos(a) * (h - 6), mouth_y + sin(a) * (h - 4) * (1 if role != 2 else -1)))
	c.draw_colored_polygon(pts, Color(0.03, 0.03, 0.02, alpha))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, -h + 1), Vector2(5, -h + 7), Vector2(-5, -h + 7)]), Color(0.95, 0.7, 0.24, alpha))
	if not paired:
		c.draw_rect(Rect2(-h + 1, -h + 1, T - 2, T - 2), Color(0.89, 0.31, 0.23, 0.8 * alpha), false, 2.0)

func _draw_items(c: Node2D) -> void:
	var sz := T * 0.42
	for b in sim().belts:
		if not in_view(b.x, b.y, 1):
			continue
		for o in b.items:
			var r := rot_local(belt_local(b.curve, o.y / float(Data.BELT_LEN)), b.dir)
			c.draw_texture_rect(Data.icon(Data.ITEM_KEYS[o.x]), Rect2((b.x + r.x) * T - sz / 2, (b.y + r.y) * T - sz / 2, sz, sz), false)

func _draw_build(c: Node2D) -> void:
	var s := sim()
	var list: Array = []
	for id in s.ents:
		var e: Sim.Ent = s.ents[id]
		if Data.is_belt(e.type) or e.type == "pole" or e.type == "tunnel":
			continue
		if in_view(e.x, e.y, e.n):
			list.append(e)
	for e in list:
		c.draw_rect(Rect2(e.x * T + T * 0.22, e.y * T + T * 0.18, e.n * T - T * 0.1, e.n * T - T * 0.12), Color(0, 0, 0, 0.38))
	for e in list:
		var sz: float = e.n * T
		var ctr := Vector2((e.x + e.n / 2.0) * T, (e.y + e.n / 2.0) * T)
		c.draw_set_transform(ctr, e.dir * PI / 2.0, Vector2.ONE)
		c.draw_texture_rect(spr[e.type], Rect2(-sz / 2, -sz / 2, sz, sz), false)
		c.draw_set_transform(ctr, e.dir * PI / 2.0, Vector2(K, K))
		_dyn(c, e)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if main.alt_mode:
			var ik := ""
			if e.type == "coalgen":
				ik = "coal" if (e.fuel > 0 or e.energy > 0) else ""
			elif e.recipe == "mine":
				ik = World.nodes[e.node].res
			elif Data.RECIPES.has(e.recipe):
				ik = Data.recipe_icon(e.recipe)
			if ik != "":
				c.draw_circle(ctr, T * 0.42, Color(0, 0, 0, 0.55))
				c.draw_texture_rect(Data.icon(ik), Rect2(ctr - Vector2(T, T) * 0.36, Vector2(T, T) * 0.72), false)
		if (e.st == "nopower" or e.st == "norecipe") and sin(time * 6.0) > -0.2:
			var p := Vector2(ctr.x, (e.y + 0.55) * T)
			var s2 := T * 0.32
			var tri := PackedVector2Array([p + Vector2(0, -s2), p + Vector2(s2, s2 * 0.8), p + Vector2(-s2, s2 * 0.8)])
			c.draw_colored_polygon(tri, Color("#e2503b") if e.st == "nopower" else Color("#f2b33d"))
			c.draw_polyline(tri + PackedVector2Array([tri[0]]), Color("#111111"), 1.5)
			c.draw_string(font, p + Vector2(-s2, s2 * 0.62), "!", HORIZONTAL_ALIGNMENT_CENTER, s2 * 2, int(s2 * 1.3), Color("#111111"))

func _poly(pts: Array, rot: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2(q[0], q[1]).rotated(rot) + off)
	return out

func _dyn(c: Node2D, e: Sim.Ent) -> void:
	var w := e.st == "work"
	match e.type:
		"miner1", "miner2":
			var a := e.anim * TAU
			for i in 3:
				var pts := _poly([[-6, 0], [6, 0], [3, 34], [-3, 34]], a + i * TAU / 3.0, Vector2(0, 8))
				c.draw_colored_polygon(pts, Color("#8c8f93"))
				c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#2a2b2d"), 1.5)
			c.draw_circle(Vector2(0, 8), 10, Color("#3f86c4") if e.type == "miner2" else Color("#d8a136"))
		"smelter":
			var al := 0.55 + 0.3 * sin(time * 9.0 + e.id) if w else 0.08
			if w:
				c.draw_rect(Rect2(-34, -61, 68, 28), Color(1.0, 0.55, 0.15, al * 0.25))
			c.draw_rect(Rect2(-29, -57, 58, 20), Color(1.0, (120 + 60 * al) / 255.0, 0.16, al))
		"constructor":
			var y := sin(e.anim * TAU * 2.0) * 12.0
			c.draw_rect(Rect2(-30, -6 + y, 60, 18), Color("#8d949b"))
			c.draw_rect(Rect2(-30, -6 + y, 60, 18), Color("#111111"), false, 2.0)
			c.draw_rect(Rect2(-26, -1 + y, 52, 3), Color("#d8792a"))
		"assembler":
			var pts := PackedVector2Array()
			var a := e.anim * TAU * 0.4
			for i in 20:
				var r := 26.0 if i % 2 else 32.0
				pts.append(Vector2(cos(a + i * TAU / 20.0), sin(a + i * TAU / 20.0)) * r + Vector2(0, 6))
			c.draw_colored_polygon(pts, Color("#8b98a3"))
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#26303a"), 2.0)
			c.draw_circle(Vector2(0, 6), 10, Color("#26303a"))
		"foundry":
			for x in [-26, 26]:
				var al := 0.7 + 0.25 * sin(time * 6.0 + x) if w else 0.12
				c.draw_circle(Vector2(x, 12), 19, Color(1.0, 0.35, 0.08, al * 0.45))
				c.draw_circle(Vector2(x, 12), 11, Color(1.0, 0.86, 0.47, al))
		"coalgen":
			var a := e.anim * TAU
			for i in 6:
				c.draw_colored_polygon(_poly([[-3, 4], [3, 4], [7, 30], [-7, 30]], a + i * TAU / 6.0, Vector2(16, 12)), Color("#9aa28f"))
			c.draw_circle(Vector2(16, 12), 8, Color("#d8a136"))
			if not e.on:
				c.draw_circle(Vector2(16, 12), 34, Color(0, 0, 0, 0.25))
		"elevator":
			var s := sim()
			var f := 1.0
			if s.elevator.phase < Data.PHASES.size():
				var req := s.phase_req(s.elevator.phase)
				var have := 0
				var need := 0
				for k in req:
					need += req[k]
					have += s.elevator.del.get(k, 0)
				f = float(have) / need
			if f > 0:
				c.draw_arc(Vector2.ZERO, 83, -PI / 2, -PI / 2 + f * TAU, 64, Color("#f5a524"), 6.0)
			var al := 0.5 + 0.4 * sin(time * 3.0)
			c.draw_circle(Vector2.ZERO, 16, Color(0.37, 0.83, 1.0, al * 0.3))
			c.draw_circle(Vector2.ZERO, 9, Color(0.37, 0.83, 1.0, al))
		"hub":
			if sin(time * 4.0) > 0:
				c.draw_circle(Vector2(-104, -104), 4, Color(0.47, 1.0, 0.47))

func _draw_top(c: Node2D) -> void:
	var s := sim()
	for p in s.poles:
		if not in_view(p.x - 1, p.y - 2, 3):
			continue
		var b := Vector2((p.x + 0.5) * T, (p.y + 0.5) * T)
		c.draw_line(b, b + Vector2(T * 0.7, -T * 0.15), Color(0, 0, 0, 0.35), T * 0.12)
		c.draw_rect(Rect2(b.x - T * 0.18, b.y - T * 0.14, T * 0.36, T * 0.3), Color("#2b2b2d"))
		c.draw_line(b, b - Vector2(0, T * 0.95), Color("#3b2a18"), T * 0.16)
		c.draw_line(b, b - Vector2(0, T * 0.95), Color("#7a5a34"), T * 0.1)
		c.draw_rect(Rect2(b.x - T * 0.3, b.y - T * 0.98, T * 0.6, T * 0.1), Color("#5a5d61"))
		c.draw_circle(b + Vector2(-T * 0.26, -T), T * 0.05, Color("#c46a3a"))
		c.draw_circle(b + Vector2(T * 0.26, -T), T * 0.05, Color("#c46a3a"))
	for wpair in s.wires:
		var a: Sim.Ent = wpair[0]
		var bb: Sim.Ent = wpair[1]
		if not in_view(mini(a.x, bb.x) - 1, mini(a.y, bb.y) - 2, absi(a.x - bb.x) + absi(a.y - bb.y) + 3):
			continue
		var pa := Vector2((a.x + 0.5) * T, (a.y + 0.5) * T - T)
		var pb := Vector2((bb.x + 0.5) * T, (bb.y + 0.5) * T - T)
		var mid := (pa + pb) / 2.0 + Vector2(0, pa.distance_to(pb) * 0.12)
		var pts := PackedVector2Array()
		for i in 13:
			var t := i / 12.0
			pts.append(pa.lerp(mid, t).lerp(mid.lerp(pb, t), t))
		c.draw_polyline(pts, Color(0.8, 0.49, 0.24, 0.9), maxf(1.0, T * 0.035))
	for pd in s.pods:
		var pp := Vector2(pd.x, pd.y) / 1000.0 * T
		if not in_view(int(pp.x / T) - 2, int(pp.y / T) - 2, 4):
			continue
		c.draw_texture_rect(spr.pod, Rect2(pp - Vector2(T, T), Vector2(T, T) * 2), false, Color(1, 1, 1, 0.5 if pd.taken else 1.0))
		if not pd.taken:
			var al := 0.5 + 0.5 * sin(time * 4.0)
			for i in 4:
				c.draw_circle(pp, T * (1.4 - i * 0.3), Color(0.78, 0.49, 1.0, 0.09 * al))
	for n in s.nests:
		var np := Vector2(n.x, n.y) / 1000.0 * T
		if not in_view(int(np.x / T) - 2, int(np.y / T) - 2, 4):
			continue
		c.draw_texture_rect(spr.nest, Rect2(np - Vector2(T, T), Vector2(T, T) * 2), false, Color(1, 1, 1, 1.0 if n.alive else 0.35))
		if n.alive and n.hp < 160:
			c.draw_rect(Rect2(np.x - 0.7 * T, np.y - 1.2 * T, 1.4 * T, T * 0.12), Color("#111111"))
			c.draw_rect(Rect2(np.x - 0.7 * T, np.y - 1.2 * T, 1.4 * T * n.hp / 160.0, T * 0.12), Color("#e2503b"))
	for cr in s.critters:
		var cp := Vector2(cr.x, cr.y) / 1000.0 * T
		if not in_view(int(cp.x / T) - 1, int(cp.y / T) - 1, 2):
			continue
		_draw_critter(c, cp, atan2(cr.vy, cr.vx))
	for pid in s.players:
		var p: Dictionary = s.players[pid]
		if p.dead > 0 or not rpos.has(pid):
			continue
		_draw_player(c, rpos[pid], atan2(p.fy, p.fx), walk.get(pid, 0.0), p.hp, pid)
		if pid != main.pid and main.started:
			var nm: String = p.get("name", "Engineer")
			var at: Vector2 = rpos[pid] + Vector2(-60, -T * 0.78)
			c.draw_string_outline(name_font, at, nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.8))
			c.draw_string(name_font, at, nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color("#bfeaff"))
	for b in bolts:
		var rng := RandomNumberGenerator.new()
		rng.seed = b.seed
		var pts := PackedVector2Array([b.a])
		for i in range(1, 6):
			pts.append(b.a.lerp(b.b, i / 6.0) + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * T * 0.4)
		pts.append(b.b)
		c.draw_polyline(pts, Color(0.37, 0.83, 1.0, 0.35), 6.0)
		c.draw_polyline(pts, Color("#bff2ff"), 2.0)
	for pg in pings:
		var age: float = time - pg.t
		for k in 3:
			var ph := fmod(age * 0.9 + k / 3.0, 1.0)
			c.draw_arc(pg.p, T * (0.4 + ph * 2.6), 0, TAU, 40, Color(0.37, 0.83, 1.0, (1.0 - ph) * clampf(5.0 - age, 0, 1)), 3.0)
		c.draw_circle(pg.p, T * 0.18, Color(0.37, 0.83, 1.0, clampf(5.0 - age, 0, 1)))
		c.draw_string_outline(name_font, pg.p + Vector2(-60, -T * 1.1), pg.who, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.8))
		c.draw_string(name_font, pg.p + Vector2(-60, -T * 1.1), pg.who, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color("#bfeaff"))
	for q in particles:
		var al: float = q.life / q.max
		if q.kind == "item":
			var sz: float = T * 0.4 * (0.5 + al * 0.5)
			c.draw_texture_rect(q.tex, Rect2(q.p - Vector2(sz, sz) / 2, Vector2(sz, sz)), false)
		else:
			var col: Color = q.col
			col.a = al * (0.5 if q.kind == "smoke" else 1.0)
			c.draw_circle(q.p, q.size, col)

func _draw_critter(c: Node2D, at: Vector2, ang: float) -> void:
	var s := T * 0.3
	c.draw_set_transform(at, ang, Vector2.ONE)
	c.draw_circle(Vector2(s * 0.2, s * 0.3), s * 0.95, Color(0, 0, 0, 0.3))
	for i in 3:
		var sw := sin(time * 12.0 + i * 2.0) * 0.4
		for sd in [-1, 1]:
			c.draw_line(Vector2((i - 1) * s * 0.5, 0), Vector2((i - 1) * s * 0.6 + sw * s * 0.5, sd * s * 1.15), Color("#3a1a10"), maxf(1.0, s * 0.18))
	_ellipse(c, Vector2.ZERO, Vector2(s * 0.95, s * 0.7), Color("#b5532e"))
	_ellipse(c, Vector2(-s * 0.15, -s * 0.12), Vector2(s * 0.55, s * 0.35), Color("#d9784a"))
	c.draw_circle(Vector2(s * 0.7, -s * 0.25), s * 0.13, Color("#ffe066"))
	c.draw_circle(Vector2(s * 0.7, s * 0.25), s * 0.13, Color("#ffe066"))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ellipse(c: Node2D, at: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := i * TAU / 20.0
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_colored_polygon(pts, col)

func _draw_player(c: Node2D, at: Vector2, face: float, wk: float, hp: int, pid: int) -> void:
	var s := T * 0.3
	_ellipse(c, at + Vector2(s * 0.4, s * 0.5), Vector2(s * 1.05, s * 0.75), Color(0, 0, 0, 0.4))
	c.draw_set_transform(at, face, Vector2.ONE)
	var lg := sin(wk) * s * 0.35
	_ellipse(c, Vector2(lg, -s * 0.42), Vector2(s * 0.32, s * 0.2), Color("#2a2a2e"))
	_ellipse(c, Vector2(-lg, s * 0.42), Vector2(s * 0.32, s * 0.2), Color("#2a2a2e"))
	c.draw_rect(Rect2(-s * 1.05, -s * 0.6, s * 0.6, s * 1.2), Color("#3d4148"))
	var suit := Color("#e07b2a") if pid == main.pid else Color("#3fa7d6")
	c.draw_circle(Vector2.ZERO, s * 0.78, suit)
	c.draw_arc(Vector2.ZERO, s * 0.78, 0, TAU, 24, suit.darkened(0.6), 1.5)
	c.draw_circle(Vector2(s * 0.12, 0), s * 0.5, Color("#d9dde1"))
	var vis := PackedVector2Array([Vector2(s * 0.12, 0)])
	for i in 9:
		var a := -0.9 + i * 0.225
		vis.append(Vector2(s * 0.12, 0) + Vector2(cos(a), sin(a)) * s * 0.42)
	c.draw_colored_polygon(vis, Color("#2fb8e0"))
	c.draw_rect(Rect2(s * 0.3, s * 0.45, s * 0.85, s * 0.22), Color("#8b9096"))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < 100000:
		c.draw_rect(Rect2(at.x - T * 0.4, at.y - T * 0.62, T * 0.8, T * 0.09), Color("#111111"))
		c.draw_rect(Rect2(at.x - T * 0.4, at.y - T * 0.62, T * 0.8 * hp / 100000.0, T * 0.09), Color("#e2503b"))

func _corners(c: Node2D, r: Rect2, col: Color) -> void:
	var l := minf(r.size.x, r.size.y) * 0.22
	var w := maxf(2.0, T * 0.07)
	for q in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
		var p: Vector2 = q[0]
		c.draw_polyline(PackedVector2Array([p + Vector2(0, q[2] * l), p, p + Vector2(q[1] * l, 0)]), col, w)

func _draw_cursor(c: Node2D) -> void:
	var s := sim()
	if not main.started or main.paused:
		return
	var me: Dictionary = s.players.get(main.pid, {})
	if me.is_empty() or me.dead > 0:
		return
	var hand: String = main.hand
	if hand != "":
		var g: Rect2i = main.ghost_rect()
		var why := s.check(main.pid, hand, g.position.x, g.position.y, main.rot)
		var ok := why == "" or why == "same"
		var sz := g.size.x * T
		var ctr := Vector2((g.position.x + g.size.x / 2.0) * T, (g.position.y + g.size.y / 2.0) * T)
		c.draw_set_transform(ctr, main.rot * PI / 2.0, Vector2.ONE)
		var rect := Rect2(-sz / 2, -sz / 2, sz, sz)
		if Data.is_belt(hand):
			c.draw_texture_rect_region(belt_tex[hand][0], rect, Rect2(0, 0, 64, 64), Color(1, 1, 1, 0.55))
		elif hand == "tunnel":
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_tunnel(c, g.position.x, g.position.y, main.rot, _tunnel_role_preview(g.position, main.rot), true, 0.6)
			c.draw_set_transform(ctr, main.rot * PI / 2.0, Vector2.ONE)
		elif hand == "pole":
			c.draw_texture_rect(Data.tex("icons/pole_world"), rect, false, Color(1, 1, 1, 0.6))
		else:
			c.draw_texture_rect(spr[hand], rect, false, Color(1, 1, 1, 0.55))
		if g.size.x == 1:
			c.draw_colored_polygon(PackedVector2Array([Vector2(0, -sz * 0.32), Vector2(sz * 0.18, -sz * 0.05), Vector2(-sz * 0.18, -sz * 0.05)]), Color.WHITE)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var wr := Rect2(g.position.x * T, g.position.y * T, sz, sz)
		c.draw_rect(wr, Color(0.42, 0.75, 0.29, 0.18) if ok else Color(0.89, 0.31, 0.23, 0.22))
		_corners(c, wr, Color("#8fe06a") if ok else Color("#ff6a52"))
		if hand == "pole":
			c.draw_rect(Rect2((g.position.x - 3) * T, (g.position.y - 3) * T, 7 * T, 7 * T), Color(0.47, 0.75, 1.0, 0.7), false, 1.5)
	else:
		var h: Sim.Ent = main.hover_ent()
		if h != null:
			_corners(c, Rect2(h.x * T - 2, h.y * T - 2, h.n * T + 4, h.n * T + 4), Color("#f5d58a"))
	for gh in main.ghosts:
		var gn: int = Data.BUILD[gh.type]["size"]
		var gs := gn * T
		var gc := Vector2((gh.x + gn / 2.0) * T, (gh.y + gn / 2.0) * T)
		c.draw_set_transform(gc, gh.dir * PI / 2.0, Vector2.ONE)
		var gr := Rect2(-gs / 2, -gs / 2, gs, gs)
		if Data.is_belt(gh.type):
			c.draw_texture_rect_region(belt_tex[gh.type][0], gr, Rect2(0, 0, 64, 64), Color(1, 1, 1, 0.4))
		elif spr.has(gh.type):
			c.draw_texture_rect(spr[gh.type], gr, false, Color(1, 1, 1, 0.4))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_corners(c, Rect2(gh.x * T, gh.y * T, gs, gs), Color(0.96, 0.65, 0.14, 0.8))
	var mp: Vector2 = main.mouse_world()
	var rad: float = 14.0 / main.zoom
	var lw: float = 4.0 / main.zoom
	if main.dec_id != 0 and s.ents.has(main.dec_id):
		var need := 0.12 if Data.is_belt(s.ents[main.dec_id].type) else 0.35
		c.draw_arc(mp, rad, -PI / 2, -PI / 2 + TAU * minf(1.0, main.dec_t / need), 32, Color("#ff6a52"), lw)
	if me.mine_t > 0:
		c.draw_arc(mp, rad, -PI / 2, -PI / 2 + TAU * me.mine_t / 33.0, 32, Color("#8fe06a"), lw)


## What a tunnel placed here would become: an exit if an unpaired entrance waits behind it.
func _tunnel_role_preview(at: Vector2i, dir: int) -> int:
	var d: Vector2i = Data.DIRS[dir]
	for k in range(1, int(Data.BUILD["tunnel"]["range"]) + 2):
		var t: Sim.Ent = sim().ent_at(at.x - d.x * k, at.y - d.y * k)
		if t != null and t.type == "tunnel" and t.dir == dir:
			return 2 if (t.role == 1 and t.partner == 0) else 1
	return 1
