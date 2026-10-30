shader_type canvas_item;
// Ground colour from the same hash/noise as noise.gd, evaluated per pixel on the GPU.

uniform int seed_i = 1337;
uniform float water_e = 0.335;
varying vec2 wpos;

void vertex() {
	wpos = VERTEX / 32.0;
}

float hash2(int x, int y, int s) {
	uint h = uint(x) * 374761393u + uint(y) * 668265263u + uint(s) * 1442695041u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h) / 4294967296.0;
}

float vnoise(vec2 p, int s) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	int xi = int(i.x);
	int yi = int(i.y);
	float a = hash2(xi, yi, s);
	float b = hash2(xi + 1, yi, s);
	float c = hash2(xi, yi + 1, s);
	float d = hash2(xi + 1, yi + 1, s);
	return a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
}

float fbm(vec2 p, int s, int o) {
	float t = 0.0, amp = 0.5, f = 1.0, n = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= o) break;
		t += vnoise(p * f, s + i * 17) * amp;
		n += amp;
		amp *= 0.5;
		f *= 2.0;
	}
	return t / n;
}

float sstep(float a, float b, float x) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

void fragment() {
	int sd = seed_i;
	vec2 w = wpos;
	float d = length(w - vec2(80.0));
	float e = fbm(w / 26.0, sd, 4) + sstep(30.0, 14.0, d) * 0.35;
	float m = fbm(vec2(w.x / 38.0 + 50.0, w.y / 38.0 - 20.0), sd + 9, 3);
	float n = vnoise(w * 0.7, 77) * 0.65 + vnoise(w * 2.3, 78) * 0.35;
	float h = hash2(int(floor(w.x * 16.0)), int(floor(w.y * 16.0)), 5);
	vec3 col;
	if (e < water_e) {
		float dp = clamp((water_e - e) / 0.07, 0.0, 1.0);
		col = mix(vec3(62.0, 84.0, 80.0), vec3(24.0, 46.0, 58.0), dp);
		float rip = sin(w.x * 3.1 + TIME * 0.9 + n * 6.0) * sin(w.y * 2.7 - TIME * 0.7);
		col += vec3(6.0, 9.0, 11.0) * rip * (1.0 - dp * 0.6) + (n - 0.5) * vec3(5.6, 8.4, 14.0);
	} else {
		float t1 = sstep(0.36, 0.48, m), t2 = sstep(0.54, 0.66, m);
		col = mix(vec3(128.0, 104.0, 70.0), vec3(92.0, 75.0, 52.0), t1);
		col = mix(col, vec3(64.0, 78.0, 42.0), t2);
		float v = (n - 0.5) * 30.0;
		col += vec3(v, v, v * 0.8);
		float hi = sstep(0.6, 0.74, e);
		col = mix(col, vec3(104.0, 100.0, 94.0), hi * 0.55);
		float sh = sstep(water_e + 0.03, water_e, e);
		col = mix(col, vec3(52.0, 50.0, 40.0), sh * 0.75);
		col += (h - 0.5) * 14.0;
	}
	COLOR = vec4(col / 255.0, 1.0);
}
