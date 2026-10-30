class_name Rng
extends RefCounted
## mulberry32 — small, fast and identical on every machine. The simulation only ever
## uses this (never randf()), which keeps it deterministic for lockstep multiplayer.

var state: int

func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF

func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var a := state
	var t := Hash.imul(a ^ (a >> 15), 1 | a)
	t = ((t + Hash.imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
	return (t ^ (t >> 14)) & 0xFFFFFFFF

func next_f() -> float:
	return float(next_u32()) / 4294967296.0

## Integer in [0, n)
func next_i(n: int) -> int:
	return int(next_f() * n)
