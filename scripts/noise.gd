extends Node
## Integer hash + value noise. Bit-for-bit the same as the browser build and the
## terrain shader, so the same seed gives the same map everywhere.

func imul(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFFFFFF
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & 0xFFFF
	return (lo + (hi << 16)) & 0xFFFFFFFF

func hash2(x: int, y: int, s: int) -> float:
	var h := (imul(x, 374761393) + imul(y, 668265263) + imul(s, 1442695041)) & 0xFFFFFFFF
	h = imul(h ^ (h >> 13), 1274126177)
	h ^= h >> 16
	return float(h) / 4294967296.0

func vnoise(x: float, y: float, s: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := hash2(xi, yi, s)
	var b := hash2(xi + 1, yi, s)
	var c := hash2(xi, yi + 1, s)
	var d := hash2(xi + 1, yi + 1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

func fbm(x: float, y: float, s: int, o: int) -> float:
	var t := 0.0
	var amp := 0.5
	var f := 1.0
	var n := 0.0
	for i in o:
		t += vnoise(x * f, y * f, s + i * 17) * amp
		n += amp
		amp *= 0.5
		f *= 2.0
	return t / n

func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func elev(x: float, y: float) -> float:
	var d := sqrt((x - 80.0) * (x - 80.0) + (y - 80.0) * (y - 80.0))
	return fbm(x / 26.0, y / 26.0, World.world_seed, 4) + sstep(30.0, 14.0, d) * 0.35

func moist(x: float, y: float) -> float:
	return fbm(x / 38.0 + 50.0, y / 38.0 - 20.0, World.world_seed + 9, 3)

## Ground colour, used for the minimap. The terrain shader has the same formula.
func ground_rgb(e: float, m: float, n: float) -> Color:
	var r: float
	var g: float
	var b: float
	if e < World.we:
		var d := clampf((World.we - e) / 0.07, 0.0, 1.0)
		return Color8(int(lerpf(62, 24, d)), int(lerpf(84, 46, d)), int(lerpf(80, 58, d)))
	var t1 := sstep(0.36, 0.48, m)
	var t2 := sstep(0.54, 0.66, m)
	r = lerpf(128, 92, t1); g = lerpf(104, 75, t1); b = lerpf(70, 52, t1)
	r = lerpf(r, 64, t2); g = lerpf(g, 78, t2); b = lerpf(b, 42, t2)
	var v := (n - 0.5) * 30.0
	r += v; g += v; b += v * 0.8
	var hi := sstep(0.6, 0.74, e)
	r = lerpf(r, 104, hi * 0.55); g = lerpf(g, 100, hi * 0.55); b = lerpf(b, 94, hi * 0.55)
	var sh := sstep(World.we + 0.03, World.we, e)
	r = lerpf(r, 52, sh * 0.75); g = lerpf(g, 50, sh * 0.75); b = lerpf(b, 40, sh * 0.75)
	return Color8(clampi(int(r), 0, 255), clampi(int(g), 0, 255), clampi(int(b), 0, 255))
