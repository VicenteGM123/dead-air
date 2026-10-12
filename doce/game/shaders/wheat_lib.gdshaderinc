// DOCE wheat field (scripts/world/wheat_field.gd): the field map, the wheat's colours, the canopy height and the big
// slow waves, shared by wheat_canopy.gdshader, wheat_ears.gdshader and terrain.gdshader. The meadow's principles
// (Trung Duy Nguyen's method, meadow_lib.gdshaderinc) at the wheat's scale: golden tones mixed by the cloud pattern,
// softer bigger mounds, the same wind (bigger, slower waves) with lighter crests and darker troughs, a CHOSEN warm
// shadow colour (amber-brown, never violet), a backlit glow at golden hour.
// Include AFTER pharos.gdshaderinc, wind.gdshaderinc and meadow_lib.gdshaderinc.

uniform sampler2D field_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec4 field_rect = vec4(0.0, 0.0, 1.0, 1.0); // x, z, width, depth (m)
uniform float canopy_h = 1.0;       // top of the ear canopy above the ground (m)
uniform float wave_scale = 1.45;    // wheat waves: x the meadow's gust wavelength (FIXER: 1.6 -> 1.45, narrower crests)
uniform float wave_speed = 1.0;     // wheat waves: x the meadow's gust speed (FIXER: 0.72 -> 1.0: a band crosses the
                                    // gameplay frame in 3-5 s, the slow rolling "Gladiator" waves)
uniform float wave_sharp = 1.6;     // FIXER: crest sharpness (power on the wave: narrower bright crests, wider troughs)
uniform float wheat_mound = 2.4;    // the wheat's mounds: x the meadow's mound size (bigger, softer)
uniform float wheat_mound_k = 0.26; // ... and their intensity
uniform float gold_k = 0.5;         // FIXER: contrast of the two golds mixed by the mound pattern (was 1: a leopard
                                    // pattern from afar)
uniform float wheat_cel_mid = 0.42; // the wheat's softer cel boundary (fraction of the flat ground's light)
uniform float wheat_cel_soft = 0.26;
uniform float light_desat = 0.35;   // the wheat reads gold, not orange, under the golden-hour sun
uniform float sheen = 0.8;          // the wave crests' sheen (lighter) and the troughs' depth (darker) (FIXER: 0.5 -> 0.8)
uniform float wheat_glow = 0.95;    // backlit glow of the ears and awns

// The wheat palette: sRGB display targets under the DAY light (like the meadow's, see meadow_lib.gdshaderinc).
const vec3 WH_EAR_PALE = vec3(242.0, 214.0, 128.0);
const vec3 WH_EAR_GOLD = vec3(224.0, 172.0, 76.0);
const vec3 WH_AWN = vec3(248.0, 230.0, 158.0);
const vec3 WH_STALK = vec3(184.0, 146.0, 66.0);   // the stalk at the top (olive gold); darker towards the foot
const vec3 WH_GREEN_EAR = vec3(184.0, 186.0, 94.0);
const vec3 WH_GREEN_STALK = vec3(118.0, 134.0, 58.0);
// the chosen shadows: warm amber-brown (ears) and deep olive-brown (stalks, the stand's depth)
const vec3 WH_SH_EAR = vec3(176.0, 118.0, 68.0);
const vec3 WH_SH_STALK = vec3(96.0, 70.0, 40.0);
const vec3 WH_SH_GREEN = vec3(104.0, 108.0, 56.0);

// The field map at p: R wheat weight (ragged edge, 0 on the road), G depth inside (0 edge .. 1 at 6 m), B the road,
// A greener patches.
vec4 wheat_field(vec2 p) {
	vec2 uv = (p - field_rect.xy) / field_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return textureLod(field_tex, uv, 0.0);
}

// The big slow waves rolling over the field (0 calm .. 1 crest): the meadow's travelling gusts, scaled up.
float wheat_wave(vec2 p) {
	return pow(wind_gust_k(p, wave_scale, wave_speed), wave_sharp);
}

// The height of the STALKS at a point of the field map (m): full height right to the field's edge (a wall of wheat
// along the road and the meadow), a little lower in the first metres.
float wheat_stalk_h(vec4 f) {
	return canopy_h * mix(0.86, 1.0, smoothstep(0.0, 0.25, f.g)) * smoothstep(0.4, 0.55, f.r);
}

// FIXER-2: 0 at the canopy's cut (the ragged edge, field weight 0.5, where wheat_canopy.gdshader discards) .. 1 inside:
// the plate slopes down to the ground exactly at its edge (behind the edge's stalks), never ending in a raised shelf.
float wheat_canopy_ramp(vec4 f) {
	return smoothstep(0.0, 0.13, f.g) * smoothstep(0.5, 0.85, f.r);
}

// The height of the ear CANOPY (the plate under the ears) at a point of the field map (m above the ground). FIXER: it
// ramps down to the ground over the last ~0.8 m before the edge (the depth f.g), so the plate never shows as a
// floating golden shelf along the verges: the edge is the stalks (3D clumps near the camera, edge cards beyond).
float wheat_canopy(vec4 f) {
	return canopy_h * mix(0.78, 1.0, smoothstep(0.0, 0.3, f.g)) * wheat_canopy_ramp(f);
}

// The wheat's cel ramp (softer than the meadow's: the field is one luminous mass).
float wheat_cel(float ndl, float sun_up) {
	float r = ndl / max(sun_up, 0.12);
	return smoothstep(wheat_cel_mid - wheat_cel_soft, wheat_cel_mid + wheat_cel_soft, r);
}

// The light colour for the wheat, a little desaturated (gold, not orange).
vec3 wheat_light(vec3 light_color) {
	float l = dot(light_color, vec3(0.2126, 0.7152, 0.0722));
	return mix(light_color, vec3(l) * 1.05, light_desat);
}

// The wheat's mound normal at p (bigger, softer mounds than the meadow's), tilted by the bend of the stalks.
vec3 wheat_normal(vec2 p, vec2 bend) {
	vec4 m = textureLod(mound_tex, p / (mound_tile * wheat_mound), 0.0);
	vec2 s = (m.rg * 2.0 - 1.0) * wheat_mound_k;
	vec3 n = normalize(vec3(-s.x, 1.0, -s.y));
	// the bent stalks turn the top of the field towards the wind (a little: the sheen does the rest)
	return normalize(n + vec3(bend.x, 0.0, bend.y) * 0.6);
}

// The mound pattern (blob tops warm, hollows cool) at the wheat's scale. FIXER: stretched along the wind (the field
// reads combed, not spotted) and its contrast halved (gold_k).
float wheat_pattern(vec2 p) {
	vec2 d = normalize(vec2(0.94, 0.34));
	vec2 q = vec2(dot(p, d) * 0.45, dot(p, vec2(-d.y, d.x)));
	return textureLod(mound_tex, q / (mound_tile * wheat_mound), 0.0).b;
}

// LIT albedo (linear) of the wheat: `part` 0 stalk .. 0.66 ear .. 1 awn, `pat` the mound pattern, `green` the greener
// patches, `hf` the height in the plant (0 foot .. 1 the ears).
vec3 wheat_albedo(float part, float pat, float green, float hf) {
	float t = mix(0.5, smoothstep(0.3, 0.7, pat), gold_k);
	vec3 c;
	if (part < 0.4) {
		c = mix(mlib_lin(WH_STALK) * 0.45, mlib_lin(WH_STALK), smoothstep(0.0, 0.85, hf));
		c = mix(c, mlib_lin(WH_GREEN_STALK) * mix(0.5, 1.0, hf), green * 0.8);
	} else if (part < 0.85) {
		c = mix(mlib_lin(WH_EAR_GOLD), mlib_lin(WH_EAR_PALE), t);
		c = mix(c, mlib_lin(WH_GREEN_EAR), green * 0.75);
	} else {
		c = mix(mlib_lin(WH_AWN), mlib_lin(WH_GREEN_EAR), green * 0.5);
	}
	return c / MLIB_LIT_DAY;
}

// The chosen SHADOW colour (linear, already lit by the ambient: multiply by wheat_amb_k()) of the same parts.
vec3 wheat_shadow(float part, float green, float hf) {
	vec3 c = part < 0.4 ? mlib_lin(WH_SH_STALK) * mix(0.45, 1.0, smoothstep(0.0, 0.85, hf)) : mlib_lin(WH_SH_EAR);
	return mix(c, mlib_lin(WH_SH_GREEN) * (part < 0.4 ? mix(0.5, 1.0, hf) : 1.0), green * 0.7);
}

// How the mood's ambient scales a chosen shadow colour defined under the day light: its brightness, and only a
// quarter of its hue (so the wheat's shadows stay warm at golden hour instead of turning violet).
vec3 wheat_amb_k(vec3 ambl) {
	vec3 lw = vec3(0.2126, 0.7152, 0.0722);
	float k = dot(ambl, lw) / dot(MLIB_AMB_DAY, lw);
	vec3 hue = (ambl / MLIB_AMB_DAY) / max(k, 1e-3);
	return k * mix(vec3(1.0), hue, 0.25);
}
