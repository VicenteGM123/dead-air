// --- R4 SCENES: tela que ondea (estandartes, gallardetes, banderines, toldos) en los escenarios de los eventos.
// La textura es pixel art con alpha recortado; el viento la mueve más cuanto más lejos del borde sujeto.
// Va sobre un QuadMesh subdividido. Compatibility (WebGL 2): solo TIME y la posición del nodo (sin uniforms por
// instancia, sin texturas de pantalla).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform float amp = 0.06;          // desplazamiento máximo (m) del borde libre
uniform float freq = 1.2;          // ondas a lo largo de la tela
uniform float speed = 1.8;
uniform float pin_left = 0.0;      // 0: sujeta arriba (estandarte que cuelga); 1: sujeta a la izquierda (bandera en un mástil)
uniform float droop = 0.0;         // la punta libre cae un poco (gallardetes), en m
uniform vec4 tint : source_color = vec4(1.0);
uniform float shade = 0.18;        // las ondas aclaran y oscurecen un poco la tela

varying float wave;

void vertex() {
	float t = mix(UV.y, UV.x, pin_left);                  // 0 en el borde sujeto, 1 en el libre
	float ph = dot(NODE_POSITION_WORLD, vec3(1.7, 0.9, 2.3));
	float w = sin(t * freq * 6.2831 - TIME * speed + ph) + 0.35 * sin(t * freq * 15.0 - TIME * speed * 1.7 + ph * 1.9);
	wave = w * t;
	VERTEX.z += w * amp * t;
	VERTEX.y -= droop * t * t * pin_left;
}

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * (1.0 + wave * shade);
	ROUGHNESS = 0.95;
}
