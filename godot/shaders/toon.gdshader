// DEAD AIR toon material, default variant (opaque, FrontSide). materials.gd generates the other variants
// (transparent / BackSide / DoubleSide / depthWrite / Chromacast) with the same include; see toon.gdshaderinc.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, blend_mix, fog_disabled;
#include "res://shaders/toon.gdshaderinc"
