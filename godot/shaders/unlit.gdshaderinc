// DEAD AIR unlit materials: glow() (DA_GLOW: MeshBasicMaterial colour x intensity, HDR for the bloom, with the camera
// occlusion fade and fog-as-uniform) and basic() (plain MeshBasicMaterial: colour, map, vertex colours, fog).
// materials.gd builds the variants: render_mode unshaded, fog_disabled, <cull>, <depth_draw>, <blend_mix|blend_add>;
// #define DA_GLOW / DA_TRANSPARENT; #include "res://shaders/unlit.gdshaderinc".
#include "res://shaders/da_common.gdshaderinc"

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uIntensity = 1.0;
uniform float uOpacity = 1.0;
uniform float uFogK = 1.0;
uniform float uAlphaTest = 0.0;
uniform float uVColor = 0.0;
uniform int uMapMode = 0;
uniform float uMapFlip = 1.0;
uniform vec4 uMapXf = vec4(1.0, 1.0, 0.0, 0.0);   // three map repeat.xy, offset.zw
uniform sampler2D mapRL : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mapCL : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mapRN : source_color, filter_nearest, repeat_enable;
uniform sampler2D mapCN : source_color, filter_nearest, repeat_disable;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// Compatibility (web build): per-instance uniforms share a 4096-slot UBO that the level overflows, so instanceColor
// is a material uniform there (DAU.setInstanceColor gives the few tinted instances their own material copy).
uniform vec4 instanceColor : source_color = vec4(1.0);
#else
instance uniform vec4 instanceColor : source_color = vec4(1.0);
#endif

vec4 daMapSample(vec2 uv) {
	vec2 t0 = uv * uMapXf.xy + uMapXf.zw;
	vec2 st = vec2(t0.x, uMapFlip > 0.5 ? 1.0 - t0.y : t0.y);
	if (uMapMode == 1) return daIn4(texture(mapRL, st));
	if (uMapMode == 2) return daIn4(texture(mapCL, st));
	if (uMapMode == 3) return daIn4(texture(mapRN, st));
	return daIn4(texture(mapCN, st));
}

void fragment() {
	float viewZ = -VERTEX.z;
	vec4 c = vec4(daIn(uColor) * uIntensity, uOpacity);
	if (uMapMode > 0) c *= daMapSample(UV);
	if (uVColor > 0.5) c.rgb *= COLOR.rgb;
	c.rgb *= daIn(instanceColor.rgb);
	if (uAlphaTest > 0.0 && c.a < uAlphaTest) discard;
#ifdef DA_GLOW
	if (!daIsShadowPass(PROJECTION_MATRIX)) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (daOccDrop(viewZ, wp, FRAGCOORD.xy, CAMERA_POSITION_WORLD)) discard;
	}
#endif
	c.rgb = mix(c.rgb, daFogColor, daFogF(viewZ, CAMERA_VISIBLE_LAYERS) * uFogK);
	ALBEDO = daOut(c.rgb);
#ifdef DA_TRANSPARENT
	ALPHA = c.a;
#endif
}
