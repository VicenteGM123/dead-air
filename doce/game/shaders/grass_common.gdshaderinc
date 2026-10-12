// DOCE meadow: where and how tall a clump grows (shared by meadow_grass, meadow_bloom, wheat_canopy and
// wheat_ears). Include AFTER pharos.gdshaderinc and wind.gdshaderinc.
//
// Each MultiMesh instance is one cell of a camera-centred chunk (scripts/world/anime_meadow.gd and wheat_field.gd move
// whole chunks on a fixed world grid), so the same world cell always grows the same clump. The cell is hashed for
// jitter, turn, height and colour; the root sits exactly on the terrain triangle (height_tex, same triangulation as
// the mesh); what grows comes from the ground: color_tex (ground colour, a = grassiness), the ground map (B paths,
// A no grass under props, G bare soil, R contact AO) and the meadow map (R grass height, G density, B flower drift,
// A species). Instances that should not grow collapse to a point far below (no fragments).

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D color_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D meadow_tex : filter_linear, repeat_disable;
uniform vec4 grid = vec4(-192.0, -192.0, 1.0, 385.0); // origin x, origin z, cell, vertices per side
uniform vec4 ground_rect = vec4(-192.0, -192.0, 384.0, 384.0);
uniform vec4 meadow_rect = vec4(-192.0, -192.0, 384.0, 384.0);
uniform float spacing = 0.4; // this ring's cell size
// Ring: instances fade in between x and y (camera distance, m) and out between z and w, each one at its own
// distance (hash), shrinking into the ground over the last metres so nothing pops.
uniform vec4 ring = vec4(0.0, 0.0, 20.0, 26.0);
uniform float density = 1.0; // quality multiplier
uniform float max_height = 1.0; // metres for meadow_tex.r = 1

float gc_h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float terrain_h(vec2 p) {
	vec2 f = (p - grid.xy) / grid.z;
	vec2 fi = floor(f);
	ivec2 i = ivec2(fi);
	int n = int(grid.w) - 2;
	i = clamp(i, ivec2(0), ivec2(n));
	vec2 t = clamp(f - vec2(i), 0.0, 1.0);
	float ha = texelFetch(height_tex, i, 0).r;
	float hb = texelFetch(height_tex, i + ivec2(1, 0), 0).r;
	float hc = texelFetch(height_tex, i + ivec2(1, 1), 0).r;
	float hd = texelFetch(height_tex, i + ivec2(0, 1), 0).r;
	if (((i.x + i.y) & 1) == 0) {
		if (t.x >= t.y) {
			return ha + (hb - ha) * t.x + (hc - hb) * t.y;
		}
		return ha + (hc - hd) * t.x + (hd - ha) * t.y;
	}
	if (t.x + t.y <= 1.0) {
		return ha + (hb - ha) * t.x + (hd - ha) * t.y;
	}
	return hc + (hd - hc) * (1.0 - t.x) + (hb - hc) * (1.0 - t.y);
}

vec4 sample_color(vec2 p) {
	return texture(color_tex, ((p - grid.xy) / grid.z + 0.5) / grid.w);
}

vec4 sample_ground(vec2 p) {
	vec2 uv = (p - ground_rect.xy) / ground_rect.zw;
	return textureLod(ground_tex, uv, 0.0);
}

vec4 sample_meadow(vec2 p) {
	return textureLod(meadow_tex, (p - meadow_rect.xy) / meadow_rect.zw, 0.0);
}

// The cell of an instance and its four hashes.
vec2 grass_cell(vec3 inst) {
	return floor(inst.xz / spacing);
}

vec4 grass_rand(vec2 cell) {
	return vec4(gc_h21(cell), gc_h21(cell + vec2(13.1, 7.7)), gc_h21(cell + vec2(27.7, 3.1)), gc_h21(cell + vec2(41.3, 19.9)));
}

// How much of an instance is left by the ring fades (0 gone .. 1 full), for its hash `r`.
float ring_grow(float dist, float r) {
	float vis = smoothstep(ring.x, ring.y, dist) * (1.0 - smoothstep(ring.z, ring.w, dist));
	if (ring.y <= 0.0) {
		vis = 1.0 - smoothstep(ring.z, ring.w, dist);
	}
	return clamp((vis - r) / 0.14 + 0.5, 0.0, 1.0) * step(0.001, vis);
}

// Grassiness of the ground at p (paths, props, bare soil, the terrain's own grass weight): 0 .. 1.
float grass_keep(vec4 gc, vec4 gm) {
	return gc.a * (1.0 - smoothstep(0.34, 0.5, gm.b)) * (1.0 - smoothstep(0.3, 0.6, gm.a)) * (1.0 - gm.g * 0.55);
}

// The ground under the grass: exact height (same triangles as the mesh) and a smooth normal (bilinear gradient of the
// cell's four corners), from height_tex.
float terrain_hn(vec2 p, out vec3 n) {
	vec2 f = (p - grid.xy) / grid.z;
	vec2 fi = floor(f);
	ivec2 i = ivec2(fi);
	int nn = int(grid.w) - 2;
	i = clamp(i, ivec2(0), ivec2(nn));
	vec2 t = clamp(f - vec2(i), 0.0, 1.0);
	float ha = texelFetch(height_tex, i, 0).r;
	float hb = texelFetch(height_tex, i + ivec2(1, 0), 0).r;
	float hc = texelFetch(height_tex, i + ivec2(1, 1), 0).r;
	float hd = texelFetch(height_tex, i + ivec2(0, 1), 0).r;
	float dx = mix(hb - ha, hc - hd, t.y) / grid.z;
	float dz = mix(hd - ha, hc - hb, t.x) / grid.z;
	n = normalize(vec3(-dx, 1.0, -dz));
	float y;
	if (((i.x + i.y) & 1) == 0) {
		y = t.x >= t.y ? ha + (hb - ha) * t.x + (hc - hb) * t.y : ha + (hc - hd) * t.x + (hd - ha) * t.y;
	} else {
		y = t.x + t.y <= 1.0 ? ha + (hb - ha) * t.x + (hd - ha) * t.y : hc + (hd - hc) * (1.0 - t.x) + (hb - hc) * (1.0 - t.y);
	}
	return y;
}
