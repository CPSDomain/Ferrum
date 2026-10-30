extends Node
## The static map: water tiles, resource nodes, decor, burrow and crash-pod spots.
## generate(settings) rebuilds everything from the seed + world settings, so every
## peer in a multiplayer game produces the identical map from the same settings.

signal regenerated

var settings := {}
var world_seed := 1337
var we := 0.335                       # water threshold
var tiles := PackedByteArray()        # 1 = water
var elev_t := PackedFloat32Array()    # per-tile elevation (cached for previews)
var moist_t := PackedFloat32Array()
var nodes: Array = []                 # {res, pur (50/100/200), cx, cy}
var node_grid := PackedInt32Array()   # node index + 1, 0 = none
var decor: Array = []                 # {x, y, kind, v, jx, jy}
var nests: Array = []                 # Vector2i in milli-tiles
var pods: Array = []                  # Vector2i in milli-tiles

func _ready() -> void:
	generate(Data.default_settings())

## Stage names shown on the loading screen, in order.
const STAGES := ["Generating terrain", "Placing resource nodes", "Spawning wildlife and crash pods", "Growing flora"]
var _R: Rng

func generate(s: Dictionary) -> void:
	_gen_begin(s)
	_gen_terrain(0, Data.MH)
	_gen_nodes()
	_gen_wild()
	_gen_decor()
	regenerated.emit()

## Same result as generate(), spread over frames. progress.call(stage_index, fraction).
func generate_async(s: Dictionary, progress: Callable) -> void:
	_gen_begin(s)
	var rows := 20
	for y in range(0, Data.MH, rows):
		_gen_terrain(y, mini(y + rows, Data.MH))
		progress.call(0, float(y + rows) / Data.MH)
		await get_tree().process_frame
	progress.call(1, 0.0)
	await get_tree().process_frame
	_gen_nodes()
	progress.call(2, 0.0)
	await get_tree().process_frame
	_gen_wild()
	progress.call(3, 0.0)
	await get_tree().process_frame
	_gen_decor()
	regenerated.emit()

func _gen_begin(s: Dictionary) -> void:
	settings = s.duplicate()
	world_seed = int(s.get("seed", Data.SEED))
	we = Data.sval(s, "water")
	var MW := Data.MW
	var MH := Data.MH
	tiles.resize(MW * MH)
	elev_t.resize(MW * MH)
	moist_t.resize(MW * MH)
	node_grid.resize(MW * MH)
	node_grid.fill(0)
	nodes = []
	decor = []
	nests = []
	pods = []

func _gen_terrain(y0: int, y1: int) -> void:
	var MW := Data.MW
	for y in range(y0, y1):
		for x in MW:
			var e := Hash.elev(x + 0.5, y + 0.5)
			elev_t[y * MW + x] = e
			moist_t[y * MW + x] = Hash.moist(x + 0.5, y + 0.5)
			tiles[y * MW + x] = 1 if e < we else 0

func _gen_nodes() -> void:
	var MW := Data.MW
	var MH := Data.MH
	_R = Rng.new(world_seed ^ 0x9e37)
	var R := _R
	var s := settings
	# guaranteed starter nodes around the HUB
	var fixed := [["iron_ore", 100, 90, 74], ["iron_ore", 50, 92, 86], ["copper_ore", 100, 70, 73], ["limestone", 100, 69, 88], ["coal", 100, 85, 94], ["iron_ore", 100, 64, 81], ["coal", 50, 96, 79]]
	for f in fixed:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				tiles[(f[3] + dy) * MW + f[2] + dx] = 0
		_add_node(f[0], f[1], f[2], f[3])
	# random nodes, weighted by the per-ore settings
	var weights := [["iron_ore", 0.35 * Data.sval(s, "iron")], ["copper_ore", 0.25 * Data.sval(s, "copper")], ["limestone", 0.2 * Data.sval(s, "limestone")], ["coal", 0.2 * Data.sval(s, "coal")]]
	var wsum := 0.0
	for w in weights:
		wsum += w[1]
	var target: int = Data.sval(s, "nodes")
	var pur_mode: int = Data.sval(s, "purity")
	var near_t: Array = [[0.6, 0.97], [0.4, 0.9], [0.2, 0.75]][pur_mode]
	var far_t: Array = [[0.4, 0.85], [0.2, 0.62], [0.1, 0.45]][pur_mode]
	var tries := 0
	while wsum > 0.0 and nodes.size() < target and tries < 6000:
		tries += 1
		var cx := 2 + int(floor(R.next_f() * (MW - 4)))
		var cy := 2 + int(floor(R.next_f() * (MH - 4)))
		var d := sqrt(float((cx - 80) * (cx - 80) + (cy - 80) * (cy - 80)))
		if d < 22.0 or not _free(cx, cy, 2):
			continue
		var close := false
		for n in nodes:
			if (n.cx - cx) * (n.cx - cx) + (n.cy - cy) * (n.cy - cy) < 36:
				close = true
				break
		if close:
			continue
		var rv := R.next_f() * wsum
		var res := "coal"
		for w in weights:
			if rv < w[1]:
				res = w[0]
				break
			rv -= w[1]
		var pv := R.next_f()
		var th: Array = near_t if d < 40.0 else far_t
		var pur := 50 if pv < th[0] else (100 if pv < th[1] else 200)
		_add_node(res, pur, cx, cy)

func _gen_wild() -> void:
	var MW := Data.MW
	var MH := Data.MH
	var s := settings
	var R := _R
	var tries := 0
	# burrows: next to pure nodes first, then scattered
	var wild: int = Data.sval(s, "wildlife")
	if wild > 0:
		var nest_target := 18 if wild == 3 else 12
		var guard_chance := 0.9 if wild == 3 else 0.75
		for n in nodes:
			var d := sqrt(float((n.cx - 80) * (n.cx - 80) + (n.cy - 80) * (n.cy - 80)))
			if n.pur == 200 and d > 30.0 and R.next_f() < guard_chance:
				for k in 10:
					var a := R.next_f() * PI * 2.0
					var x := int(round(n.cx + cos(a) * 4.5))
					var y := int(round(n.cy + sin(a) * 4.5))
					if x > 2 and y > 2 and x < MW - 3 and y < MH - 3 and tiles[y * MW + x] == 0 and node_grid[y * MW + x] == 0:
						nests.append(Vector2i(x * 1000 + 500, y * 1000 + 500))
						break
		tries = 0
		while nests.size() < nest_target and tries < 3000:
			tries += 1
			var x := 3.0 + R.next_f() * (MW - 6)
			var y := 3.0 + R.next_f() * (MH - 6)
			if (x - 80) * (x - 80) + (y - 80) * (y - 80) < 36.0 * 36.0:
				continue
			var ix := int(x)
			var iy := int(y)
			if tiles[iy * MW + ix] or node_grid[iy * MW + ix]:
				continue
			var near := false
			for q in nests:
				if Vector2(q.x / 1000.0, q.y / 1000.0).distance_to(Vector2(x, y)) < 12.0:
					near = true
					break
			if not near:
				nests.append(Vector2i(ix * 1000 + 500, iy * 1000 + 500))
	var pod_target: int = Data.sval(s, "pods")
	tries = 0
	while pods.size() < pod_target and tries < 4000:
		tries += 1
		var x := 3.0 + R.next_f() * (MW - 6)
		var y := 3.0 + R.next_f() * (MH - 6)
		var d := sqrt((x - 80) * (x - 80) + (y - 80) * (y - 80))
		if d < 24.0 or d > 74.0 or not _free(int(x), int(y), 1):
			continue
		var near := false
		for q in pods:
			if Vector2(q.x / 1000.0, q.y / 1000.0).distance_to(Vector2(x, y)) < 14.0:
				near = true
				break
		if not near:
			pods.append(Vector2i(int(x) * 1000 + 500, int(y) * 1000 + 500))

func _gen_decor() -> void:
	var MW := Data.MW
	var MH := Data.MH
	for y in range(1, MH - 1):
		for x in range(1, MW - 1):
			if tiles[y * MW + x] or node_grid[y * MW + x]:
				continue
			if (x - 80) * (x - 80) + (y - 80) * (y - 80) < 81:
				continue
			var h := Hash.hash2(x, y, 404 + world_seed)
			if h < 0.05:
				var m := moist_t[y * MW + x]
				var kind := "rock"
				if m > 0.55:
					kind = "stalk" if h < 0.02 else "shrub"
				elif m > 0.45:
					kind = "shrub" if h < 0.025 else "rock"
				decor.append({"x": x, "y": y, "kind": kind, "v": int(h * 1000) % 3, "jx": (Hash.hash2(x, y, 9) - 0.5) * 0.4, "jy": (Hash.hash2(x, y, 10) - 0.5) * 0.4})

## Map image for the minimap and the world-setup preview.
func preview_image(with_markers := true) -> Image:
	var img := Image.create(Data.MW, Data.MH, false, Image.FORMAT_RGBA8)
	for y in Data.MH:
		for x in Data.MW:
			var k := y * Data.MW + x
			img.set_pixel(x, y, Hash.ground_rgb(elev_t[k], moist_t[k], 0.5))
	for nd in nodes:
		var col := Color("#101012") if nd.res == "coal" else Color(Data.ITEMS[nd.res]["c"])
		img.fill_rect(Rect2i(nd.cx - 1, nd.cy - 1, 3, 3), col)
	if with_markers:
		img.fill_rect(Rect2i(Data.HUBX, Data.HUBY, 5, 5), Color("#f5a524"))
		for n in nests:
			img.fill_rect(Rect2i(n.x / 1000 - 1, n.y / 1000 - 1, 3, 3), Color("#ff3b2a"))
		for p in pods:
			img.fill_rect(Rect2i(p.x / 1000 - 1, p.y / 1000 - 1, 3, 3), Color("#d79bff"))
	return img

func _in_hub(x: int, y: int) -> bool:
	return x >= Data.HUBX - 2 and x <= Data.HUBX + 6 and y >= Data.HUBY - 2 and y <= Data.HUBY + 8

func _free(cx: int, cy: int, rad: int) -> bool:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 1 or y < 1 or x >= Data.MW - 1 or y >= Data.MH - 1:
				return false
			if tiles[y * Data.MW + x] or node_grid[y * Data.MW + x] or _in_hub(x, y):
				return false
	return true

func _add_node(res: String, pur: int, cx: int, cy: int) -> void:
	var i := nodes.size()
	nodes.append({"res": res, "pur": pur, "cx": cx, "cy": cy})
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			node_grid[(cy + dy) * Data.MW + cx + dx] = i + 1

func node_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= Data.MW or y >= Data.MH:
		return -1
	return node_grid[y * Data.MW + x] - 1

func is_water(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= Data.MW or y >= Data.MH:
		return true
	return tiles[y * Data.MW + x] == 1
