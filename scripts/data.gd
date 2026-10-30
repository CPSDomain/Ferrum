extends Node
## Static game data: items, recipes, buildings, milestones. Everything the simulation
## reads lives here as plain integers or strings so the sim stays deterministic.

const T := 32
const MW := 160
const MH := 160
const SEED := 1337
const WE := 0.335
const HUBX := 78
const HUBY := 78
const SPAWN_X := 80500          # milli-tiles
const SPAWN_Y := 85500
const BELT_LEN := 240           # sub-units per belt tile
const BELT_SP := 60             # minimum spacing between items (4 per tile)
const REACH := 14000            # milli-tiles
const MINE_REACH := 6000
const TICK_RATE := 60
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const PUR_NAME := {50: "Impure", 100: "Normal", 200: "Pure"}
## Power multiplier per clock %, in per-mille: round(1000 * (clock/100)^1.321928).
## Precomputed so every machine computes identical numbers (needed for lockstep multiplayer).
const CLOCK_POW := [0,2,6,10,14,19,24,30,35,41,48,54,61,67,74,81,89,96,104,111,119,127,135,143,152,160,169,177,186,195,204,213,222,231,240,250,259,269,278,288,298,308,318,328,338,348,358,369,379,389,400,411,421,432,443,454,465,476,487,498,509,520,532,543,554,566,577,589,601,612,624,636,648,660,672,684,696,708,720,732,745,757,769,782,794,807,819,832,845,857,870,883,896,909,921,934,947,961,974,987,1000,1013,1027,1040,1053,1067,1080,1094,1107,1121,1134,1148,1162,1175,1189,1203,1217,1231,1245,1259,1273,1287,1301,1315,1329,1343,1357,1372,1386,1400,1415,1429,1443,1458,1472,1487,1502,1516,1531,1545,1560,1575,1590,1605,1619,1634,1649,1664,1679,1694,1709,1724,1739,1754,1770,1785,1800,1815,1831,1846,1861,1877,1892,1908,1923,1939,1954,1970,1985,2001,2017,2032,2048,2064,2080,2095,2111,2127,2143,2159,2175,2191,2207,2223,2239,2255,2271,2287,2304,2320,2336,2352,2369,2385,2401,2418,2434,2451,2467,2483,2500,2517,2533,2550,2566,2583,2600,2616,2633,2650,2667,2683,2700,2717,2734,2751,2768,2785,2802,2819,2836,2853,2870,2887,2904,2921,2938,2956,2973,2990,3007,3025,3042,3059,3077,3094,3111,3129,3146,3164,3181,3199,3216,3234,3252,3269,3287,3305,3322,3340,3358]

var ITEMS := {
	"iron_ore": {"n": "Iron Ore", "c": "#6f87a4"},
	"copper_ore": {"n": "Copper Ore", "c": "#bd6b3b"},
	"limestone": {"n": "Limestone", "c": "#d4cbad"},
	"coal": {"n": "Coal", "c": "#2e2e33"},
	"iron_ingot": {"n": "Iron Ingot", "c": "#a9b4bd"},
	"copper_ingot": {"n": "Copper Ingot", "c": "#d98a4e"},
	"steel_ingot": {"n": "Steel Ingot", "c": "#6f7a85"},
	"iron_plate": {"n": "Iron Plate", "c": "#b8c2ca"},
	"iron_rod": {"n": "Iron Rod", "c": "#9aa5ae"},
	"screw": {"n": "Screw", "c": "#c6ccd2"},
	"wire": {"n": "Wire", "c": "#e0904f"},
	"cable": {"n": "Cable", "c": "#34343b"},
	"concrete": {"n": "Concrete", "c": "#bdb8ad"},
	"steel_beam": {"n": "Steel Beam", "c": "#66727e"},
	"steel_pipe": {"n": "Steel Pipe", "c": "#7c8893"},
	"reinforced_plate": {"n": "Reinforced Plate", "c": "#9fb0bf"},
	"rotor": {"n": "Rotor", "c": "#a8b0b8"},
	"modular_frame": {"n": "Modular Frame", "c": "#8a96a2"},
	"stator": {"n": "Stator", "c": "#d18a3c"},
	"smart_plating": {"n": "Smart Plating", "c": "#e2a93b"},
	"versatile_framework": {"n": "Versatile Framework", "c": "#5fa3d6"},
	"automated_wiring": {"n": "Automated Wiring", "c": "#5ab878"},
	"power_shard": {"n": "Power Shard", "c": "#5fd4ff"},
	"data_drive": {"n": "Data Drive", "c": "#b46be8"},
}

## t = seconds per craft at 100% clock
var RECIPES := {
	"iron_ingot": {"m": "smelter", "in": {"iron_ore": 1}, "out": {"iron_ingot": 1}, "t": 2},
	"copper_ingot": {"m": "smelter", "in": {"copper_ore": 1}, "out": {"copper_ingot": 1}, "t": 2},
	"iron_plate": {"m": "constructor", "in": {"iron_ingot": 3}, "out": {"iron_plate": 2}, "t": 6},
	"iron_rod": {"m": "constructor", "in": {"iron_ingot": 1}, "out": {"iron_rod": 1}, "t": 4},
	"screw": {"m": "constructor", "in": {"iron_rod": 1}, "out": {"screw": 4}, "t": 6},
	"wire": {"m": "constructor", "in": {"copper_ingot": 1}, "out": {"wire": 2}, "t": 4},
	"cable": {"m": "constructor", "in": {"wire": 2}, "out": {"cable": 1}, "t": 2},
	"concrete": {"m": "constructor", "in": {"limestone": 3}, "out": {"concrete": 1}, "t": 4},
	"steel_beam": {"m": "constructor", "in": {"steel_ingot": 4}, "out": {"steel_beam": 1}, "t": 4},
	"steel_pipe": {"m": "constructor", "in": {"steel_ingot": 3}, "out": {"steel_pipe": 2}, "t": 6},
	"reinforced_plate": {"m": "assembler", "in": {"iron_plate": 6, "screw": 12}, "out": {"reinforced_plate": 1}, "t": 12},
	"rotor": {"m": "assembler", "in": {"iron_rod": 5, "screw": 25}, "out": {"rotor": 1}, "t": 15},
	"modular_frame": {"m": "assembler", "in": {"reinforced_plate": 3, "iron_rod": 12}, "out": {"modular_frame": 2}, "t": 60},
	"smart_plating": {"m": "assembler", "in": {"reinforced_plate": 1, "rotor": 1}, "out": {"smart_plating": 1}, "t": 30},
	"stator": {"m": "assembler", "in": {"steel_pipe": 3, "wire": 8}, "out": {"stator": 1}, "t": 12},
	"versatile_framework": {"m": "assembler", "in": {"modular_frame": 1, "steel_beam": 12}, "out": {"versatile_framework": 2}, "t": 24},
	"automated_wiring": {"m": "assembler", "in": {"stator": 1, "cable": 20}, "out": {"automated_wiring": 1}, "t": 24},
	"steel_ingot": {"m": "foundry", "in": {"iron_ore": 3, "coal": 3}, "out": {"steel_ingot": 3}, "t": 4},
	"alt_cast_screw": {"m": "constructor", "in": {"iron_ingot": 5}, "out": {"screw": 20}, "t": 24, "alt": true, "n": "Cast Screw"},
	"alt_iron_wire": {"m": "constructor", "in": {"iron_ingot": 5}, "out": {"wire": 9}, "t": 24, "alt": true, "n": "Iron Wire"},
	"alt_steel_screw": {"m": "constructor", "in": {"steel_beam": 1}, "out": {"screw": 52}, "t": 12, "alt": true, "n": "Steel Screw"},
	"alt_stitched": {"m": "assembler", "in": {"iron_plate": 10, "wire": 20}, "out": {"reinforced_plate": 3}, "t": 32, "alt": true, "n": "Stitched Iron Plate"},
	"alt_bolted": {"m": "assembler", "in": {"reinforced_plate": 3, "screw": 56}, "out": {"modular_frame": 2}, "t": 24, "alt": true, "n": "Bolted Frame"},
	"alt_steel_rotor": {"m": "assembler", "in": {"steel_pipe": 2, "wire": 6}, "out": {"rotor": 1}, "t": 12, "alt": true, "n": "Steel Rotor"},
	"alt_solid_steel": {"m": "foundry", "in": {"iron_ingot": 2, "coal": 2}, "out": {"steel_ingot": 3}, "t": 3, "alt": true, "n": "Solid Steel Ingot"},
	"alt_iron_alloy": {"m": "foundry", "in": {"iron_ore": 2, "copper_ore": 2}, "out": {"iron_ingot": 5}, "t": 6, "alt": true, "n": "Iron Alloy Ingot"},
}

## speed = belt sub-units per tick; power = kW at 100%; base_ticks = ticks per item on a Normal node
var BUILD := {
	"belt1": {"n": "Conveyor Belt Mk.1", "size": 1, "cost": {"iron_plate": 1}, "speed": 4},
	"belt2": {"n": "Conveyor Belt Mk.2", "size": 1, "cost": {"iron_plate": 1, "screw": 4}, "speed": 8},
	"belt3": {"n": "Conveyor Belt Mk.3", "size": 1, "cost": {"steel_pipe": 1}, "speed": 12},
	"splitter": {"n": "Splitter", "size": 1, "cost": {"iron_plate": 2, "cable": 2}},
	"merger": {"n": "Merger", "size": 1, "cost": {"iron_plate": 2, "iron_rod": 2}},
	"crate": {"n": "Storage Crate", "size": 1, "cost": {"iron_plate": 6}},
	"tunnel": {"n": "Underground Belt", "size": 1, "cost": {"iron_plate": 4, "iron_rod": 4}, "range": 5},
	"pole": {"n": "Power Pole", "size": 1, "cost": {"iron_rod": 2, "wire": 3}},
	"coalgen": {"n": "Coal Generator", "size": 3, "cost": {"iron_plate": 20, "iron_rod": 10, "cable": 10}, "gen": 75000},
	"miner1": {"n": "Miner Mk.1", "size": 3, "cost": {"iron_plate": 10, "iron_rod": 8}, "power": 5000, "base_ticks": 120},
	"miner2": {"n": "Miner Mk.2", "size": 3, "cost": {"modular_frame": 2, "rotor": 4, "cable": 10}, "power": 12000, "base_ticks": 60},
	"smelter": {"n": "Smelter", "size": 3, "cost": {"iron_rod": 5, "wire": 8}, "power": 4000, "m": "smelter"},
	"constructor": {"n": "Constructor", "size": 3, "cost": {"iron_plate": 8, "cable": 8}, "power": 4000, "m": "constructor"},
	"assembler": {"n": "Assembler", "size": 3, "cost": {"reinforced_plate": 8, "rotor": 4, "cable": 10}, "power": 15000, "m": "assembler"},
	"foundry": {"n": "Foundry", "size": 3, "cost": {"modular_frame": 6, "rotor": 6, "concrete": 20}, "power": 16000, "m": "foundry"},
	"elevator": {"n": "Space Elevator", "size": 5, "cost": {"concrete": 100, "iron_plate": 100, "modular_frame": 10}},
	"hub": {"n": "The HUB", "size": 5, "cost": {}},
}

var QUICK := ["belt1", "belt2", "splitter", "merger", "pole", "miner1", "smelter", "constructor", "assembler", "coalgen", "crate", "tunnel", "belt3", "miner2", "foundry", "elevator"]

var MILESTONES := [
	{"n": "Base Camp", "req": {"iron_ingot": 50, "copper_ingot": 20}, "ub": ["constructor", "splitter", "merger"], "ur": []},
	{"n": "Field Logistics", "req": {"iron_plate": 150, "iron_rod": 100, "wire": 150}, "ub": ["tunnel"], "ur": ["screw", "concrete"], "research": true},
	{"n": "Part Assembly", "req": {"screw": 150, "cable": 50, "concrete": 50}, "ub": ["assembler", "belt2"], "ur": ["reinforced_plate", "rotor", "modular_frame", "smart_plating"]},
	{"n": "Heavy Industry", "req": {"reinforced_plate": 30, "rotor": 20, "modular_frame": 10, "concrete": 150}, "ub": ["foundry", "miner2", "elevator"], "ur": ["steel_ingot", "steel_beam", "steel_pipe"]},
	{"n": "Motorization", "req": {"steel_beam": 100, "steel_pipe": 100, "modular_frame": 30}, "ub": ["belt3"], "ur": ["stator", "versatile_framework", "automated_wiring"]},
]

var PHASES := [
	{"n": "Phase 1 · Distribution Platform", "req": {"smart_plating": 50}},
	{"n": "Phase 2 · Construction Dock", "req": {"smart_plating": 100, "versatile_framework": 50}},
	{"n": "Phase 3 · Orbital Tether", "req": {"versatile_framework": 100, "automated_wiring": 100}},
]

const START_INV := {"iron_plate": 120, "iron_rod": 80, "wire": 80, "cable": 40}
const START_BUILD := ["belt1", "miner1", "smelter", "coalgen", "pole", "crate"]
const START_RECIPES := ["iron_ingot", "copper_ingot", "iron_plate", "iron_rod", "wire", "cable"]
const MNAME := {"smelter": "Smelter", "constructor": "Constructor", "assembler": "Assembler", "foundry": "Foundry"}

var ITEM_KEYS: Array = []
var ITEM_IDX := {}
var ALTS: Array = []
var _tex := {}

func _ready() -> void:
	ITEM_KEYS = ITEMS.keys()
	for i in ITEM_KEYS.size():
		ITEM_IDX[ITEM_KEYS[i]] = i
	for k in RECIPES:
		var r: Dictionary = RECIPES[k]
		if not r.has("n"):
			r["n"] = ITEMS[r["out"].keys()[0]]["n"]
		if r.get("alt", false):
			ALTS.append(k)

func is_belt(t: String) -> bool:
	return t == "belt1" or t == "belt2" or t == "belt3"

func is_miner(t: String) -> bool:
	return t == "miner1" or t == "miner2"

func is_machine(t: String) -> bool:
	return BUILD.has(t) and BUILD[t].has("m")

func item_name(k: String) -> String:
	return ITEMS[k]["n"]

func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load("res://assets/" + path + ".png")
	return _tex[path]

func icon(k: String) -> Texture2D:
	return tex("items/" + k)

func recipe_icon(k: String) -> String:
	return RECIPES[k]["out"].keys()[0]

func cost_str(c: Dictionary) -> String:
	var parts := []
	for k in c:
		parts.append("%d %s" % [c[k], item_name(k)])
	return ", ".join(parts)

# ------------------------------------------------------------------ world settings
const VERSION := "0.4.0"
const DEFAULT_PORT := 34197

## Each setting stores an option index; `values` holds what the index means.
var SETTING_DEFS := [
	{"key": "water", "label": "Water", "options": ["Dry", "Normal", "Wet", "Islands"], "values": [0.29, 0.335, 0.37, 0.41], "default": 1},
	{"key": "nodes", "label": "Resource nodes", "options": ["Sparse", "Normal", "Plenty"], "values": [45, 72, 105], "default": 1},
	{"key": "purity", "label": "Node purity", "options": ["Poor", "Normal", "Rich"], "values": [0, 1, 2], "default": 1},
	{"key": "iron", "label": "Iron ore", "options": ["Off", "Low", "Normal", "High"], "values": [0.0, 0.5, 1.0, 1.6], "default": 2},
	{"key": "copper", "label": "Copper ore", "options": ["Off", "Low", "Normal", "High"], "values": [0.0, 0.5, 1.0, 1.6], "default": 2},
	{"key": "limestone", "label": "Limestone", "options": ["Off", "Low", "Normal", "High"], "values": [0.0, 0.5, 1.0, 1.6], "default": 2},
	{"key": "coal", "label": "Coal", "options": ["Off", "Low", "Normal", "High"], "values": [0.0, 0.5, 1.0, 1.6], "default": 2},
	{"key": "wildlife", "label": "Wildlife", "options": ["Off", "Passive", "Normal", "Hostile"], "values": [0, 1, 2, 3], "default": 2},
	{"key": "pods", "label": "Crash pods", "options": ["Few", "Normal", "Many"], "values": [4, 8, 14], "default": 1},
	{"key": "kit", "label": "Starting kit", "options": ["Light", "Standard", "Generous"], "values": [50, 100, 200], "default": 1},
	{"key": "speed", "label": "Machine speed", "options": ["50%", "100%", "200%"], "values": [50, 100, 200], "default": 1},
	{"key": "ms_cost", "label": "Milestone costs", "options": ["Cheap", "Normal", "Expensive"], "values": [50, 100, 150], "default": 1},
]

func default_settings() -> Dictionary:
	var s := {"seed": SEED}
	for d in SETTING_DEFS:
		s[d.key] = d.default
	return s

func sval(settings: Dictionary, key: String):
	for d in SETTING_DEFS:
		if d.key == key:
			return d.values[clampi(int(settings.get(key, d.default)), 0, d.values.size() - 1)]
	return null

## Seeds can be typed as numbers or words; words hash to a number.
func parse_seed(text: String) -> int:
	text = text.strip_edges()
	if text.is_valid_int():
		return absi(text.to_int()) % 2147483647
	var h := 5381
	for ch in text.to_utf8_buffer():
		h = ((h * 33) ^ ch) & 0x7FFFFFFF
	return h

## Ground-level things the player can walk over.
func is_walkable(t: String) -> bool:
	return is_belt(t) or t == "tunnel"
