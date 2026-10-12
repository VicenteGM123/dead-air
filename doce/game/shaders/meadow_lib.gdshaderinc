// DOCE anime meadow, after Trung Duy Nguyen's "Anime Grass" method. Shared by the grass clumps (meadow_grass),
// the flowers (meadow_bloom), the wheat (wheat_ears, wheat_canopy) and the ground under them (terrain.gdshader).
// Include AFTER pharos.gdshaderinc and wind.gdshaderinc.
//
// 1. THE MOUND FIELD (Trung's "transfer vertex normal", the key). MeadowKit.mound_texture() builds, by code at
//    startup, a tiling height field: cloud noise CUT OUT into distinct blobs, BLURRED soft; its slope is stored in
//    mound_tex.rg and its height in mound_tex.b. Every grass clump, flower and wheat clump is shaded with the mound
//    normal sampled at its ROOT, and the ground under them with the mound normal at its own point: a whole clump
//    lights as one piece of that bumpy surface, grass and ground shade identically and merge, and the field gets
//    big hand-painted shadow shapes that follow the sun (long ones at golden hour).
// 2. COLOUR: two tones mixed by the same blob pattern (mound_tex.b), for the lit side AND for the shadow side (a
//    CHOSEN deep cool green, not a darkened lit colour: the anime hue shift, yellow-green light / blue-green shade),
//    the zone of the ground at the root (meadow, forest floor, golden garrigue, village lawn), the canopy gradient
//    (deep base, warm vivid tips) and the wind wave a little darker where it bends.
// 3. VALUE: a two-band cel ramp with clear contrast. Its input is the sun on the mound normal measured against the
//    flat ground's light (so the shapes stay balanced from noon to dusk) plus the mound height (the folds between
//    the masses sink into the shadow from every side, so the masses read even with the sun behind the camera).
//    In the Compatibility pipeline (pharos.gdshaderinc) the shadow colour is the base pass (EMISSION) and light()
//    adds the step up to the lit colour.

uniform sampler2D mound_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float mound_tile = 40.0;   // metres per tile of the mound texture
uniform float mound_k = 1.25;      // intensity: slope multiplier (1 = the 97th-percentile slope tilts 45 degrees)
uniform float mound_scale = 1.0;   // >1 = bigger mounds (the wheat)
// FIXER: a second, tuft-scale octave of the same mound field (sampled smaller and turned): every clump still takes ONE
// normal at its root, but neighbouring clumps now group into lit and shaded tufts of ~1-2 m inside the big masses (the
// painted, clumpy look of the reference) instead of flat 5-10 m puddles.
uniform float mound_tile2 = 11.0;  // metres per tile of the tuft octave
uniform float mound_k2 = 0.62;     // its intensity
uniform float cel_mid = 0.75;      // light / shadow boundary of the cel ramp (see mlib_value)
uniform float cel_soft = 0.1;      // its half width (FIXER: 0.05 -> 0.1, softer painted edges)
uniform float hollow_k = 0.35;     // how much the mound field's hollows sink into the shadow (FIXER: 0.75 -> 0.35 with a
                                   // softer cel edge: the crisp iso-height contours of a strong hollow term read as
                                   // stripes at 10-30 m; the shapes now come mostly from the slopes, i.e. the sun)
uniform float cast_k = 0.68;       // FIXER: CAST shadows (hero, beasts, trees) are this much of the chosen shadow colour,
                                   // so they read as the darkest tone on the grass, under the form shadows (the
                                   // painted mound shapes, which keep exactly their colour). See mlib_lit().
uniform float root_k = 0.42;       // FIXER: brightness of the blades' roots (the depth of the stand) vs. their tips
uniform float crest_k = 0.3;       // FIXER: the wind wave's crest sheen on the upper blades (lighter bands roll over)
uniform float tone_k = 1.0;        // strength of the two-tone (pattern) variation
uniform float tip_glow = 0.6;      // backlit translucency of the tips
uniform float wave_tint = 0.4;     // the wind wave's tint: how much darker the grass is where the gust bends it (Trung)
uniform float big_scale = 4.6;     // the big soft colour patches: x the mound tile (~180 m: patches of 15-40 m)
uniform float big_k = 1.0;         // ... and their strength

// The meadow palette, as sRGB display targets under the DAY light (sun FFF2DA x 1.12, sky ambient 7FA4EE x 0.84):
// a lit target becomes an albedo by dividing it by (sun + ambient), a shadow target by the ambient alone, so the
// moods (golden hour, dusk, night) shift both naturally. Two tones each (the blob pattern), the dry garrigue's straw.
const vec3 MLIB_LIT_DAY = vec3(1.298, 1.307, 1.503);
const vec3 MLIB_AMB_DAY = vec3(0.178, 0.312, 0.718);
const vec3 MLIB_LIT_WARM = vec3(110.0, 176.0, 52.0);  // lit, mound tops: warm yellow-green
const vec3 MLIB_LIT_COOL = vec3(72.0, 148.0, 60.0);   // lit, hollows: a cooler, deeper green
const vec3 MLIB_TIP = vec3(168.0, 206.0, 64.0);       // the lit tips: vivid, warm
const vec3 MLIB_SHADE_COOL = vec3(34.0, 76.0, 44.0);  // the chosen shadow: deep cool (blue) green
const vec3 MLIB_SHADE_WARM = vec3(46.0, 96.0, 46.0);  // ... its lighter tone on the mound tops
const vec3 MLIB_DRY_LIT_A = vec3(204.0, 182.0, 86.0); // golden garrigue / straw, lit
const vec3 MLIB_DRY_LIT_B = vec3(176.0, 162.0, 82.0);
const vec3 MLIB_DRY_SHADE = vec3(84.0, 82.0, 62.0);   // ... in shadow: a cool olive

vec3 mlib_lin(vec3 c255) {
	return pow(c255 / 255.0, vec3(2.2));
}

// The mound field at p (world xz): rg slope (-1..1 at intensity 1), b soft blobs 0..1, a cut-out levels 0..1.
vec4 mlib_mound(vec2 p) {
	vec4 m = textureLod(mound_tex, p / (mound_tile * mound_scale), 0.0);
	return vec4(m.rg * 2.0 - 1.0, m.b, m.a);
}

// Fragment version (mipmapped, for the ground).
vec4 mlib_mound_frag(vec2 p) {
	vec4 m = texture(mound_tex, p / (mound_tile * mound_scale));
	return vec4(m.rg * 2.0 - 1.0, m.b, m.a);
}

// FIXER: the tuft octave at p: the mound field sampled at mound_tile2, turned 37 degrees (no alignment with the big
// octave); rg = its slope in WORLD axes (-1..1), b = its height 0..1.
vec3 mlib_mound2(vec2 p) {
	mat2 R = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec4 m = textureLod(mound_tex, (R * p) / mound_tile2 + vec2(0.31, 0.77), 0.0);
	vec2 s = transpose(R) * (m.rg * 2.0 - 1.0);
	return vec3(s, m.b);
}

vec3 mlib_mound2_frag(vec2 p) {
	mat2 R = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec4 m = texture(mound_tex, (R * p) / mound_tile2 + vec2(0.31, 0.77));
	vec2 s = transpose(R) * (m.rg * 2.0 - 1.0);
	return vec3(s, m.b);
}

// FIXER: the combined slope of both octaves (big masses x mound_k, tufts x mound_k2), `k` scales both (mask, lawns).
vec2 mlib_slope(vec2 s1, vec3 m2, float k) {
	return (s1 * mound_k + m2.xy * mound_k2) * k;
}

// FIXER: the tuft octave fades out with the distance d (m): far away it would only foreshorten into streaks.
vec3 mlib_tuft_fade(vec3 m2, float d) {
	return vec3(m2.xy * (1.0 - smoothstep(18.0, 42.0, d)), m2.z);
}

// The big soft colour patches (0..1, ~0.5 on average): the mound field sampled very large and blurred (a high mip).
float mlib_big(vec2 p) {
	return textureLod(mound_tex, p / (mound_tile * big_scale) + vec2(0.37, 0.61), 4.0).b;
}

// The shading normal: the ground normal tilted by the mound slope (x intensity x mask).
vec3 mlib_normal(vec3 ground_n, vec2 slope, float k) {
	return normalize(ground_n + vec3(-slope.x, 0.0, -slope.y) * k / max(mound_scale, 0.5));
}

// The cel ramp's input: the sun on the (mound) normal against the flat ground's light `sun_up` (the sun's height,
// world), plus the mound height `mh` (0 hollow .. 1 top) times hollow_k.
float mlib_value(float ndl, float sun_up, float mh) {
	return ndl / max(sun_up, 0.12) + (mh - 0.5) * hollow_k;
}

// The two-band cel ramp for light().
float mlib_cel(float ndl, float sun_up, float mh) {
	float r = mlib_value(ndl, sun_up, mh);
	return smoothstep(cel_mid - cel_soft, cel_mid + cel_soft, r);
}

// FIXER: the sun's increment over the base pass on the meadow (grass, flowers, ground). The base pass (EMISSION) is the
// CAST shadow colour (`shadow` x cast_k); where no cast shadow falls (`att` 1) the sun lifts it to the chosen shadow
// colour (the form shadow, `drop` = shadow x (1 - cast_k)), then the cel ramp `k` (times the cloud shade) lifts it on
// to the lit colour (`lift` = albedo x ambient - shadow, plus the direct light `direct`). In a cast shadow the grass
// keeps the darker colour: the hero and the beasts stay grounded on it.
vec3 mlib_lit(vec3 direct, vec3 lift, vec3 drop, float k, float att, float cloud) {
	return ((direct + lift) * k * cloud + drop) * att;
}

// The same ramp, softened with the distance (`far` 0 near .. 1 far, mlib_far()): far away the masses keep their
// shapes but turn into soft painted gradients with less contrast (aerial perspective), not a crisp camouflage.
float mlib_cel_far(float ndl, float sun_up, float mh, float far) {
	float r = ndl / max(sun_up, 0.12) + (mh - 0.5) * hollow_k * (1.0 - 0.45 * far);
	float s = cel_soft + far * 0.42;
	float k = smoothstep(cel_mid - s, cel_mid + s, r);
	return mix(k, 0.35 + 0.65 * k, far * 0.6);
}

// 0 near .. 1 far for a view distance d (m).
float mlib_far(float d) {
	return smoothstep(40.0, 130.0, d);
}

// Dryness of a ground colour (sRGB): the golden garrigue and the straw (red over green). FINAL: from -0.075 (every
// green of the terrain is below it: meadow -0.13, village -0.07) to 0.03 (the olive garrigue A3A26E is +0.004, the
// straws +0.08..0.11), so the thumb, the west plateau and the hill tops read as sunburnt gold, as the old grass did.
float mlib_dry(vec3 ground_srgb) {
	return smoothstep(-0.075, 0.03, ground_srgb.r - ground_srgb.g);
}

// Zone brightness from the ground colour (the forest floor darker, the village lawn lighter).
float mlib_zone(vec3 ground_srgb) {
	float lum = dot(ground_srgb, vec3(0.299, 0.587, 0.114));
	return clamp(lum / 0.6, 0.78, 1.1);
}

// The meadow's LIT albedo (linear) at a point: two tones mixed by the blob pattern `pat` (0..1), the zone of the
// ground colour (sRGB), `hf` the height in the canopy (0 the foot .. 1 the tips; the ground takes ~0.5).
vec3 mlib_grass_albedo(vec3 ground_srgb, float pat, float hf, float big) {
	float t = mix(0.5, smoothstep(0.3, 0.7, pat), tone_k);
	t = clamp(t + (big - 0.5) * 0.9 * big_k, 0.0, 1.0);
	vec3 c = mix(mlib_lin(MLIB_LIT_COOL), mlib_lin(MLIB_LIT_WARM), t);
	// the tips: vivid and warm (the top third of the blades)
	c = mix(c, mlib_lin(MLIB_TIP), smoothstep(0.62, 1.0, hf) * 0.7);
	float dry = mlib_dry(ground_srgb);
	vec3 d = mix(mlib_lin(MLIB_DRY_LIT_B), mlib_lin(MLIB_DRY_LIT_A), t);
	c = mix(c, d, dry * 0.9);
	c /= MLIB_LIT_DAY;
	c *= mlib_zone(ground_srgb);
	// the big patches: lighter and warmer / deeper and cooler
	c *= 1.0 + (big - 0.5) * 0.36 * big_k;
	// the canopy gradient: a deep base (FIXER: root_k, the depth of the stand between the blades)
	c *= mix(root_k, 1.0, smoothstep(0.0, 0.75, hf));
	return c;
}

// The meadow's chosen SHADOW albedo (linear, to be multiplied by the ambient light): a deep cool green.
vec3 mlib_grass_shadow(vec3 ground_srgb, float pat, float hf, float big) {
	float t = mix(0.5, smoothstep(0.3, 0.7, pat), tone_k);
	t = clamp(t + (big - 0.5) * 0.9 * big_k, 0.0, 1.0);
	vec3 c = mix(mlib_lin(MLIB_SHADE_COOL), mlib_lin(MLIB_SHADE_WARM), t);
	float dry = mlib_dry(ground_srgb);
	c = mix(c, mlib_lin(MLIB_DRY_SHADE), dry * 0.85);
	c /= MLIB_AMB_DAY;
	c *= mlib_zone(ground_srgb);
	c *= 1.0 + (big - 0.5) * 0.3 * big_k;
	c *= mix(mix(root_k, 1.0, 0.45), 1.0, smoothstep(0.0, 0.65, hf));
	return c;
}

// FIXER: the wind wave's tint (Trung: darker where the grass bends) plus a SHEEN on the crest's upper blades (the bent
// blades turn their lit backs up), so the bands that roll over the meadow read lighter AND darker: `wave` 0..1,
// `gust` the gust strength, `hf` the height in the canopy.
float mlib_wave_tint(float wave, float gust, float hf) {
	float dark = wave_tint * wave * gust * 0.8 * (1.0 - smoothstep(0.25, 0.7, hf));
	float sheen = crest_k * pow(wave, 1.3) * gust * smoothstep(0.3, 0.9, hf);
	return 1.0 - dark + sheen;
}

// FIXER: how much the gust tilts the mass's normal along the wind (the light on the field changes as a wave rolls
// through it); used by the clumps and the ground alike.
const float MLIB_GUST_TILT = 0.55;

// FIXER: at dusk and dawn (twilight: the moods' night factor between ~0.2 and ~0.8) the meadow's chosen shadow keeps part
// of the mood's hue and a little more light, so it reads as coloured shade (like the paths and the props) instead of
// a muddy near-black olive. Day, golden hour and night are unchanged. `shadow` = the shadow colour (linear, lit by the
// ambient `ambl`).
vec3 mlib_mood_shadow(vec3 shadow, vec3 ambl) {
	vec3 lw = vec3(0.2126, 0.7152, 0.0722);
	float twilight = smoothstep(0.15, 0.45, g_night) * (1.0 - smoothstep(0.7, 0.95, g_night));
	if (twilight <= 0.0) {
		return shadow;
	}
	vec3 hue = ambl / max(dot(ambl, lw), 1e-4);
	float l = dot(shadow, lw);
	return mix(shadow, l * hue, 0.4 * twilight) * (1.0 + 0.45 * twilight);
}

// Trung's wind, from ONE noise at the root: the slow, smooth WIND WAVE (travelling bands, 0..1) and the fast WIND
// NOISE (-0.5..0.5). Returns (wave, noise).
vec2 mlib_wind(vec2 root, float wave_scale, float wave_speed) {
	float wave = wind_gust_k(root, wave_scale, wave_speed);
	float n = ph_noise(root * 0.7 - g_wind_dir * g_time * 2.6 + vec2(3.1, 7.7)) - 0.5;
	return vec2(wave, n);
}

// The bend of a plant rooted at `root3` (world): xy = bend direction (xz) * angle (radians), z = flattening, from
// the wind (wave + noise) and the pushers (hero, beasts).
vec3 mlib_bend(vec3 root3, vec2 wind, float flex) {
	float a_wind = (0.1 + 0.42 * wind.x * g_wind_gust.x + 0.2 * wind.y) * g_wind * flex;
	vec2 b = g_wind_dir * a_wind;
	vec3 push = wind_push(root3);
	b += push.xy * 1.25;
	float l = length(b);
	if (l > 1.35) {
		b *= 1.35 / l;
	}
	return vec3(b, push.z);
}

// Rotates `p` (relative to the root) by the bend (xz = direction * angle): rigid, the blades keep their length.
vec3 mlib_rotate(vec3 p, vec2 bend) {
	float a = length(bend);
	if (a < 1e-4) {
		return p;
	}
	vec2 d = bend / a;
	vec3 axis = vec3(d.y, 0.0, -d.x); // up x dir: tipping towards d
	float c = cos(a);
	float s = sin(a);
	return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}
