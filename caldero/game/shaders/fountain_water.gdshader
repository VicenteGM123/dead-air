// --- R3 WORLD3: el agua de la fuente del mercado (la pileta y el cuenco de arriba).
// Funciona en el renderer Compatibility (WebGL 2): sin SCREEN_TEXTURE ni DEPTH_TEXTURE, sin instance uniforms.
// Superficie con olas suaves (ruido animado), anillos que se abren donde caen los chorros, destellos en píxeles,
// una línea clara donde el agua toca la piedra y un poco de transparencia (se ven el fondo y las monedas).
// El patrón se cuantiza a una rejilla de `px` píxeles por metro para que case con el pixel art del juego.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.07, 0.27, 0.37, 1.0);
uniform vec4 shallow : source_color = vec4(0.26, 0.55, 0.62, 1.0);
uniform vec4 glint : source_color = vec4(0.90, 0.98, 1.0, 1.0);
uniform float alpha = 0.64;
uniform vec2 center = vec2(0.0);      // centro de la pileta (x, z del mundo)
uniform float radius = 1.18;          // radio del agua (hasta la pared)
uniform float px = 24.0;              // píxeles por metro del dibujo
uniform float jets_r = 0.98;          // radio donde caen los chorros
uniform float jets = 8.0;             // cuántos chorros (0 = ninguno)
uniform float jet_phase = 0.3927;     // ángulo del primer chorro (radianes)
uniform float center_jet = 0.0;       // 1 = también caen gotas en el centro (el cuenco de arriba)
uniform float ring_max = 0.42;        // hasta dónde se abre cada anillo

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// anillos que se abren desde un punto (dos a la vez, desfasados)
float rings(vec2 q, vec2 c, float seed, float t) {
	float d = length(q - c);
	float acc = 0.0;
	for (int k = 0; k < 2; k++) {
		float ph = fract(t * 0.85 + seed + float(k) * 0.5);
		float rr = 0.03 + ph * ring_max;
		float w = 0.022 + ph * 0.02;
		acc += (1.0 - smoothstep(0.0, w, abs(d - rr))) * (1.0 - ph);
	}
	return acc;
}

void fragment() {
	float t = TIME;
	vec2 q = floor((wpos.xz - center) * px + 0.5) / px;   // rejilla de píxeles
	float r = length(q);
	// olas suaves
	float n1 = vnoise(q * 2.6 + vec2(t * 0.32, t * 0.21));
	float n2 = vnoise(q * 5.2 - vec2(t * 0.27, -t * 0.33));
	float n = n1 * 0.65 + n2 * 0.35;
	// anillos donde caen los chorros
	float ring = 0.0;
	for (int i = 0; i < 8; i++) {
		if (float(i) < jets) {
			float a = jet_phase + float(i) * 6.2831853 / max(jets, 1.0);
			ring += rings(q, vec2(cos(a), sin(a)) * jets_r, float(i) * 0.37, t);
		}
	}
	if (center_jet > 0.5) {
		ring += rings(q, vec2(0.0), 0.11, t * 1.2) * 0.8;
	}
	ring = clamp(ring, 0.0, 1.0);
	// color: más claro en el centro, más hondo y oscuro junto a la pared (su sombra)
	float edge = smoothstep(radius - 0.22, radius - 0.02, r);
	vec3 col = mix(shallow.rgb, deep.rgb, clamp(r / radius * 0.55 + (n - 0.5) * 0.5, 0.0, 1.0));
	col = mix(col, deep.rgb * 0.62, edge * 0.55);
	col = mix(col, shallow.rgb * 1.25, ring * 0.45);
	// destellos: píxeles claros que aparecen y se apagan en las crestas
	float sp = vnoise(q * 11.0 + vec2(t * 0.9, -t * 0.7));
	float spark = step(0.9, sp) * step(0.55, n1);
	// la línea clara del borde, que ondula
	float rim = smoothstep(radius - 0.075, radius - 0.03, r) * (1.0 - smoothstep(radius - 0.03, radius, r));
	rim *= 0.55 + 0.45 * sin(t * 2.3 + atan(q.y, q.x) * 7.0);
	ALBEDO = col;
	EMISSION = glint.rgb * (ring * 0.55 + spark * 0.6 + rim * 0.32) + col * 0.05;
	ROUGHNESS = 0.14;
	SPECULAR = 0.55;
	ALPHA = clamp(alpha + ring * 0.12 + spark * 0.15 - edge * 0.05, 0.0, 1.0);
	// la normal sigue a las olas (reflejos del sol que se mueven)
	float e = 1.0 / px;
	float nx = vnoise((q + vec2(e, 0.0)) * 2.6 + vec2(t * 0.32, t * 0.21)) - n1;
	float nz = vnoise((q + vec2(0.0, e)) * 2.6 + vec2(t * 0.32, t * 0.21)) - n1;
	NORMAL_MAP = vec3(clamp(0.5 - nx * 3.0, 0.0, 1.0), clamp(0.5 - nz * 3.0, 0.0, 1.0), 1.0);
	NORMAL_MAP_DEPTH = 0.6;
}
