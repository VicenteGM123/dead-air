// DEAD AIR glow material, default variant (opaque FrontSide); see unlit.gdshaderinc / materials.gd glow().
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque, blend_mix;
#define DA_GLOW
#include "res://shaders/unlit.gdshaderinc"
