# Character asset format (`godot/assets/chars/<id>.glb`) — authoritative

Written by `blender/chars/build.py` (port of `tools/bake/*.mjs` + `src/art/chars/*.js` + the attachment builders of
`src/art/face.js` / `z_crew.js`). The Godot runtime (`scripts/art/char_runtime.gd`, `char_material.gd`, `face.gd`)
reads it. Everything below is in **three.js coordinates** (metres, +Y up, the character faces −Z, feet at y = 0), the
bind (sculpt) pose, i.e. exactly what the JS `assets/baked/<id>.bin` + the JS attachment builder produced.

Build: `python3 blender/build_all.py --only chars [--id duke] [--save-blend]`
(or `blender --background --python blender/build_all.py -- --only chars --id duke`). Python API:
`blender/chars/build.py: build_chars(ids=None, save_blend=False)`.

## 1. Node tree (as imported by Godot)

```
<id>                      Node3D   root; meta "extras" = { "da": "<header JSON string>" }   (§2)
  ...Skeleton3D           the glTF skin (joint names = JS joint names, see §3)
     body                 MeshInstance3D, skinned, 1 surface, blend shapes = header.morphs (§4)
  part_<name>             MeshInstance3D per rigid baked part (brows, headband, afro, cloud …), bind-pose MODEL
                          coordinates (not joint-local); extras.da = {"part": name, "bone": joint, "pivot": [x,y,z]}
  <attachment nodes>      one top-level node per JS attachment (the object the JS added to a joint), extras.da =
                          {"name": <JS name>, "joint": <joint>, "local": {...}, "userData": {...}, ...} (§5).
```
Find nodes by name with `find_child(name, true, false)`; do not rely on the exact Skeleton3D path (the Blender
exporter/Godot importer choose it). Node names are unique inside one GLB: repeated JS names get a `_<n>` suffix
(`aviatorRim`, `aviatorRim_1`); the JS name is always `extras.da.name`. Import settings: every
`godot/assets/chars/*.glb.import` is written with `meshes/force_disable_compression=true`, `meshes/ensure_tangents=false`,
`meshes/generate_lods=false`, `nodes/use_name_suffixes=false` (exact per-vertex data, no LOD re-indexing).

## 2. Header (`root.get_meta("extras").da`, JSON)

Same keys as the JS baked header (`tools/bake/bake.mjs`), plus what the runtime half needs from the definition:

| key | meaning |
|---|---|
| `id`, `version`, `kind` (`hero`/`zombie`/`creature`), `name` | as JS |
| `bones` | joint names in skin order (= JS `R.bones`; skin JOINTS_0 indices refer to this order) |
| `parents` | `{joint: parentJoint or null}` |
| `bindPose` | `{joint: [x,y,z]}` Euler XYZ applied on top of rest to get the sculpt/bind pose |
| `rig` | humanoid: createRig spec with defaults (`height, headScale, shoulderW, hipW, armLen, legLen, torsoLen`); custom: the def's `rig` (`custom, joints[{name,parent,pos,tail,blend,gate}], bindPose, dims`) |
| `humanoid` | bool |
| `dims` | humanoid: `createRig().dims` (`height, headH, neckH, ankle, torso, leg, hipsY, upperLeg, lowerLeg, upperArm, foreArm, shoulderW, hipW, shoulderY`); custom: `rig.dims` or `{}` |
| `joints` | `{name: {"parent": p or null, "pos": [x,y,z] rest offset in the parent frame, "bind": [x,y,z] bind Euler XYZ}}` — rebuild the JS rig: Node3D per joint, `position = pos`, rest rotation identity (three convention), bind pose = `rotation = bind` |
| `materials` | `{name: {color, rough, metal, wrap, sss, fuzz, aniso, sheen, sheenExp, spec, lines, bump, cav, tint, pattern{…}}}` exactly the JS def |
| `matNames` | material names in index order (vertex `matId` indexes this list) |
| `patterns` | `{"size": 512, "layers": ["patterns/<file>.png", …], "layerOf": [layer or -1 per matNames index]}` (§6) |
| `morphs` | expression morph names in blend-shape order (`["smile","frown","o_mouth"]` for heroes, `[]` otherwise) |
| `parts` | `{name: {bone, pivot:[x,y,z] (model space), qbox, tris, node: "part_<name>"}}` |
| `stitches` | `[[ax,ay,az, bx,by,bz, t0, width, dash, duty, "#color", [matIdx…]], …]` projected stitch segments (model/bind space) |
| `stitchChunks` | `[[cx,cy,cz, radius, first, count], …]` |
| `qbox` | body `[minx,miny,minz, sizex,sizey,sizez]` |
| `stats` | `{tris, bodyTris, verts, rawTris, voxel, bakeMs, stitchSegs}` |
| `hair` | `{top, cz, radius, n}` = JS `hairInfo()` (head-bound vertices, head-joint frame) precomputed |
| `def` | JSON-safe definition fields the runtime needs: `armOut, poseOffset, rim, slots, animStyle, expressions, morphBone, name` (only those present in the JS def) |
| `anchors` | `def.anchors(ctx)` evaluated (e.g. `{EYE:{…}}`, `{EYES:[…], MOUTH:{…}}`) |
| `face` | `{"eyes": [{side:"L"/"R", root, ball, upper, lower (node names), cap, E:{…}}], "brows": [{part, side}]}` for FaceController |
| `attachments` | list of the top-level attachment node names in JS creation order |

## 3. Skeleton

glTF joint nodes are named like the JS joints; their rest local transforms are the **bind pose** JS locals:
`T(joint.pos) · R_xyz(bindPose[joint] or 0)` (the Blender armature rest = bind pose, bones built so the exported
node rotations are the three.js ones, no Blender axis roll). Inverse bind matrices = inverse(bind-pose world). The
body is modelled in that bind pose, so a plain import shows the character correctly. The JS runtime binds the mesh to
rest-rotation-identity joints with the bind-pose inverses; to drive it with the JS Animator, rebuild rests from
`header.joints` (identity rotation) and use `inverse(bindWorld(joint))` as the Skin bind poses (bindWorld = product of
`T(pos)·R_xyz(bind)` down the chain).

## 4. Body / part vertex data (per-vertex, as Godot sees it after import)

| Godot array | glTF | content |
|---|---|---|
| `ARRAY_VERTEX` | POSITION | bind-pose model position (three coords) |
| `ARRAY_NORMAL` | NORMAL | SDF-gradient normal (JS `nrm`, int8 quantised then normalised) |
| `ARRAY_COLOR` | COLOR_0 (vec4) | `(albedo.r, albedo.g, albedo.b, ao)`; albedo = **sRGB** `col_u8/255` (exact in Godot's 8-bit colour; the shader converts sRGB→linear exactly like the JS `LUT`), ao = `aux.x/255` |
| `ARRAY_TEX_UV` | TEXCOORD_0 | `(pco.x, pco.y)` pattern coords (m; cyl mode: u around incl. wrap copies, v along) |
| `ARRAY_TEX_UV2` | TEXCOORD_1 | `(pco.z, cavity)`; cavity = `(aux.y − 128)/127` (−1 concave … +1 convex) |
| `ARRAY_CUSTOM0` (RGBA_FLOAT) | TEXCOORD_2+3 | `(matId, patternMode, pw.x, pw.y)`; matId = `aux.z` (index into matNames), patternMode = `aux.w` (0 triplanar, 1 cylindrical), pw = triplanar weights `/255` |
| `ARRAY_CUSTOM1` (RGBA_FLOAT) | TEXCOORD_4+5 | `(pw.z, flow.x, flow.y, flow.z)`; flow = hair strand direction (int8/127), zero when none |
| `ARRAY_CUSTOM2` (RGBA_FLOAT) | TEXCOORD_6+7 | `(dc0, dc1, dc2, 0)` morph COLOUR deltas of morphs 0..2 (§4.1); 0 on parts / characters without morphs |
| `ARRAY_BONES/WEIGHTS` | JOINTS_0/WEIGHTS_0 | top-4 skin weights (JS u8/255), body only |
| blend shapes | targets POSITION+NORMAL | morph `i` = `header.morphs[i]`: position delta `dp` (JS int16/20000) and normal delta `dn` (JS int8/63); Godot stores blend shapes as absolute `base + delta` (normal renormalised) |

(`pw.w` and `flow.w` of the JS layout are always 0 and are not stored.) The JS shader's `vRest` = `ARRAY_VERTEX`.
Verified with Godot 4.7.2: TEXCOORD_2..7 import as CUSTOM0..2 `ARRAY_CUSTOM_RGBA_FLOAT`, values bit-exact.

### 4.1 Morph colour deltas (`CUSTOM2`)
Godot blend shapes cannot carry colours, so the JS morph colour deltas (`morph_<ex>_dc`, LINEAR, relative to the
linear base colour = `LUT[col_u8]`; the shader adds them after its sRGB→linear conversion) are packed
per vertex: `dcK = (r8 + 128) + (g8 + 128)·256 + (b8 + 128)·65536` (an integer < 2^24, exact in float32) with
`c8 = clamp(round(dc.c · 127), −127, 127)`. Decode in the shader:
`int v = int(dcK + 0.5); vec3 d = (vec3(v & 255, (v >> 8) & 255, (v >> 16) & 255) - 128.0) / 127.0;` and add
`Σ weight_K · d` to the vertex colour (JS: `vColor.rgb += morph colour · influence`). A vertex without a colour
delta for morph K has `dcK = 128 + 128·256 + 128·65536 = 8421504` (decodes to 0).

## 5. Attachments (eyes, lids, lashes, glasses, aviators, hoops, pointer, wheels, casters, googly eyes, ticket stub, decals …)

Every object the JS `attachments(b)` added to a joint (or to a group the def created on a joint, e.g. the heroes'
scaled `headScaled` group) is exported as a node tree built with the kit's scene graph (`blender/dalib/scene.py`),
placed in **bind-pose model space** (so a plain import shows it on the body). Node `extras.da` (JSON):
```
top-level node: { "name": "<JS name>", "joint": "<joint name>",
                  "local": {"pos": [x,y,z], "quat": [x,y,z,w], "scale": [sx,sy,sz], "rot": [x,y,z], "order": "XYZ"},
                  "userData": {…JS userData flags: staticEye, staticEyeRim, googlyEye, googlyPupil, googlyRim, wheel,
                               caster, pointer, tally, lensFront …},
                  "castShadow": bool (meshes), "renderOrder": n, "visible": bool }
child node:     { "name", "userData", "castShadow", "renderOrder", "visible" }   (+ "subMesh": true, see below)
```
`local` = the JS local transform in the joint frame: reparent the top node under the joint and set it (identical to
its bind-pose placement relative to `bindWorld(joint)`). Children keep the JS hierarchy and local transforms. Names
the JS left empty get stable names: eye rigs are `eyeL` (root) → `eyeL_ball` (→ `eyeL_sphere`), `eyeL_glint1/2`,
`eyeL_upper` (→ `eyeL_upperLid`, `eyeL_lash`, lash wings), `eyeL_lower` (→ `eyeL_lowerLid`); the header's
`face.eyes` gives the node names the FaceController drives. JS meshes with a material ARRAY (printed cards: face +
edge) are split: the node keeps group 0 / material 0, each other material group is a child mesh `<name>_<i>` with
`"subMesh": true` (same transform).

Materials (`material.extras.da`, JSON; the Blender Principled BSDF only previews it):
```
{ "kind": "attach", "color": "#hex", "rimColor": "#…",
  "opts": {…attachMaterial opts: rough, metal, rim, rimColor, wrap, sss, envIntensity, physical, clearcoat,
           clearcoatRough, transparent, opacity, depthWrite, side ('front'|'back'|'double'), vertexColors, lensEnv …},
  "map": "<texture key>" | null, "mapWrap", "mapFilter", "flipY": true, "mapFile": "res://assets/chars/tex/<file>.png" }
{ "kind": "basic", "color": "#hex", "opts": {color ([r,g,b] linear floats when the JS used Color(r,g,b) > 1, else
  "#hex"), transparent, opacity, depthWrite, toneMapped, name}, "map": …, "mapFile": … }   // THREE.MeshBasicMaterial
```
UV / texture convention = the kit's (SPEC §5.3, dalib/tex.py): glTF TEXCOORD_0 is the three.js uv (texture repeat /
offset baked in); canvas textures are PNGs stored top-down as drawn (`godot/assets/chars/tex/*.png`, also embedded
in the GLB) and three's flipY applies: sample at `(u, 1 − v)` like materials.gd. Vertex colours (aviator lens
gradient) are COLOR_0 (linear).

## 6. Pattern tiles
`godot/assets/chars/patterns/<type>_<hash8>.png` (+ .import: lossless, no mipmaps, no alpha-border fix): 512×512 RGBA, RGB = sRGB albedo, A = LINEAR height (JS
`patterns.js` `makeTile`, pixel-identical port). Shared between characters (file name = hash of the pattern spec).
`header.patterns.layers[k]` is the file of layer k (path relative to `godot/assets/chars/`); build a
`Texture2DArray` in that order (wrap repeat, linear + mipmaps, sRGB for RGB). Sample exactly like `daPattern()`.

## 7. Blender scene (`--save-blend` → `blender/out/char_<id>.blend`)
Root empty `<id>`, armature `<id>_rig` (bones = joints, rest = bind pose), `body` (vertex groups, shape keys, colour
attribute `Col` = albedo+AO, named attributes `pco`, `aux`, `pw`, `flow`, UV map `vid` = original vertex index used by
the exporter post-pass), `part_*`, attachment objects (empties for JS groups). The exported GLB is post-processed
(`blender/chars/glb_patch.py`): the body/part primitives' per-vertex channels of §4 are rewritten from the bake arrays
using the `vid` channel (the exporter reorders vertices), then `vid` is dropped.
