"""DEAD AIR — Blender scene building + glTF export (SPEC §5.1–5.5).

    from dalib import export
    export.build_props(ids=['sample_portable_tv'])        # every variant of that id in props/variants.json
    export.export_graph(root, '/abs/out.glb')              # any kit/scene graph -> GLB (world, runtime assets …)

Each asset is built into a fresh, empty Blender scene (read_factory_settings(use_empty=True)) so names are
deterministic, converted by dalib/scene.py (three.js -> Blender axes, materials, vertex colours, UVs, "da" custom
properties) and exported with the SPEC §5.3 settings. Textures are NOT embedded: after the export the GLB's images
are pointed (relative uri) at the shared PNGs in godot/assets/textures/ written by dalib/tex.py, so every prop that
uses e.g. the teak wood shares one Godot texture resource. The textureInfo carries KHR_texture_transform
(scale [1,-1], offset [0,1]) so a plain glTF viewer / Godot's own StandardMaterial3D show the canvas the right way up
(three.js flipY); game materials (materials.gd fromSpec) ignore it and sample (u, 1 - v) themselves.
"""
from __future__ import annotations

import json
import os
import struct
import sys
import time
import traceback

from . import scene as S
from . import tex as T

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.abspath(os.path.join(HERE, '..'))
REPO = os.path.abspath(os.path.join(BLENDER_DIR, '..'))
GODOT = os.path.join(REPO, 'godot')
PROPS_OUT = os.path.join(GODOT, 'assets', 'props')
BLEND_OUT = os.path.join(BLENDER_DIR, 'out')
VARIANTS = os.path.join(BLENDER_DIR, 'props', 'variants.json')

GLTF_SETTINGS = dict(
    export_format='GLB', export_extras=True, export_yup=True, export_apply=True, export_attributes=True,
    export_vertex_color='ACTIVE', export_all_vertex_colors=True, export_active_vertex_color_when_no_material=True,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials='EXPORT',
    export_image_format='NONE', export_cameras=False, export_lights=False, export_animations=False,
    export_skins=False, export_morph=False, use_selection=False, use_visible=False, use_renderable=False,
    export_shared_accessors=False, export_gpu_instances=False, check_existing=False,
)


# ================================================================================================ blender
def _bpy():
    import bpy
    return bpy


def reset_scene():
    """Fresh, empty Blender scene (deterministic names)."""
    bpy = _bpy()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        import addon_utils
        addon_utils.enable('io_scene_gltf2', default_set=True, persistent=False)
    except Exception:
        pass
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.render.engine = 'BLENDER_WORKBENCH' if 'BLENDER_WORKBENCH' in \
        [e.identifier for e in type(sc.render).bl_rna.properties['engine'].enum_items] else sc.render.engine
    return sc


def export_glb(path):
    bpy = _bpy()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(GLTF_SETTINGS)
    props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = {k: v for k, v in kw.items() if k in props}   # Blender 4.2 … 5.x option sets differ slightly
    bpy.ops.export_scene.gltf(filepath=path, **kw)
    return path


# =================================================================================================== GLB
def read_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, version, length = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF', 'not a GLB: %s' % path
    off = 12
    js, bin_ = None, b''
    while off < length:
        clen, ctype = struct.unpack_from('<I4s', data, off)
        chunk = data[off + 8:off + 8 + clen]
        if ctype == b'JSON':
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == b'BIN\0':
            bin_ = chunk
        off += 8 + clen
    return js, bin_


def write_glb(path, js, bin_):
    j = json.dumps(js, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    j += b' ' * ((4 - len(j) % 4) % 4)
    b = bytes(bin_)
    b += b'\0' * ((4 - len(b) % 4) % 4)
    total = 12 + 8 + len(j) + (8 + len(b) if b else 0)
    out = struct.pack('<4sII', b'glTF', 2, total) + struct.pack('<I4s', len(j), b'JSON') + j
    if b:
        out += struct.pack('<I4s', len(b), b'BIN\0') + b
    with open(path, 'wb') as f:
        f.write(out)


def link_textures(glb_path, tex_dir=None):
    """Points every material whose "da" spec has a canvas map at the shared PNG (relative uri + sampler +
    KHR_texture_transform flip). Returns the number of linked materials."""
    js, bin_ = read_glb(glb_path)
    mats = js.get('materials') or []
    images, textures, samplers = js.setdefault('images', []), js.setdefault('textures', []), js.setdefault('samplers', [])
    img_idx, smp_idx = {}, {}
    n = 0
    tex_dir = tex_dir or T.OUT_DIR
    base = os.path.dirname(os.path.abspath(glb_path))
    for m in mats:
        da = (m.get('extras') or {}).get('da')
        if not da:
            continue
        spec = json.loads(da) if isinstance(da, str) else da
        f = spec.get('mapFile')
        if not f:
            continue
        fname = f.rsplit('/', 1)[-1]
        uri = os.path.relpath(os.path.join(tex_dir, fname), base).replace(os.sep, '/')
        if uri not in img_idx:
            img_idx[uri] = len(images)
            images.append({'uri': uri, 'mimeType': 'image/png', 'name': fname[:-4]})
        wrap = 10497 if spec.get('mapWrap') == 'repeat' else 33071
        near = spec.get('mapFilter') == 'nearest'
        sk = (wrap, near)
        if sk not in smp_idx:
            smp_idx[sk] = len(samplers)
            samplers.append({'magFilter': 9728 if near else 9729, 'minFilter': 9984 if near else 9987,
                             'wrapS': wrap, 'wrapT': wrap})
        ti = len(textures)
        textures.append({'source': img_idx[uri], 'sampler': smp_idx[sk]})
        info = {'index': ti, 'texCoord': 0}
        if spec.get('flipY', True):
            info['extensions'] = {'KHR_texture_transform': {'offset': [0, 1], 'scale': [1, -1]}}
        m.setdefault('pbrMetallicRoughness', {})['baseColorTexture'] = info
        n += 1
    if not images:
        for k in ('images', 'textures', 'samplers'):
            if not js.get(k):
                js.pop(k, None)
    else:
        used = js.setdefault('extensionsUsed', [])
        if any('extensions' in (m.get('pbrMetallicRoughness') or {}).get('baseColorTexture', {}) for m in mats) \
                and 'KHR_texture_transform' not in used:
            used.append('KHR_texture_transform')
    write_glb(glb_path, js, bin_)
    return n


# ================================================================================================ graphs
def export_graph(root, glb_path, root_name=None, save_blend=None, tex_dir=None):
    """Kit/scene graph -> Blender objects (fresh scene) -> GLB (+ .blend). Returns the name map."""
    reset_scene()
    names = S.assign_names(root, root_name)

    def texfile(t):
        return T.texture_file(t, tex_dir)
    S.to_blender(root, names, texfile)
    export_glb(glb_path)
    link_textures(glb_path, tex_dir)
    if save_blend:
        bpy = _bpy()
        os.makedirs(os.path.dirname(save_blend), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=save_blend, check_existing=False, relative_remap=True, compress=True)
    return names


# ================================================================================================= props
def load_variants(path=VARIANTS):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def build_variant(v, game=None, out_dir=PROPS_OUT, save_blend=False, tex_dir=None):
    """Builds one variant {id, opts, key} into <out_dir>/<key>.glb. Returns an info dict."""
    from . import kit as K
    game = game or K.Game()
    t0 = time.time()
    root = K.buildProp(v['id'], game, json.loads(json.dumps(v.get('opts') or {})))
    t1 = time.time()
    glb = os.path.join(out_dir, v['key'] + '.glb')
    blend = os.path.join(BLEND_OUT, v['key'] + '.blend') if save_blend else None
    export_graph(root, glb, root_name=root.name or 'prop_%s' % v['id'], save_blend=blend, tex_dir=tex_dir)
    st = dict(root.userData.stats or K.stats(root))
    return {'key': v['key'], 'id': v['id'], 'glb': glb, 'build_s': round(t1 - t0, 2),
            'export_s': round(time.time() - t1, 2), 'stats': st}


def write_index(built, variants, out_dir=PROPS_OUT):
    """(Re)writes <out_dir>/index.json = { id: [ {key, opts}, … ] }: every variant whose GLB exists."""
    p = os.path.join(out_dir, 'index.json')
    idx = {}
    for v in variants:
        if os.path.exists(os.path.join(out_dir, v['key'] + '.glb')):
            idx.setdefault(v['id'], []).append({'key': v['key'], 'opts': v.get('opts') or {}})
    os.makedirs(out_dir, exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(idx, f, indent=1, ensure_ascii=False)
    return p


def build_props(ids=None, keys=None, out_dir=PROPS_OUT, save_blend=False, variants_path=VARIANTS, stop_on_error=False,
                tex_dir=None):
    """Builds the variants of `ids` (or `keys`, or all) listed in props/variants.json. Returns (ok, failed)."""
    from props import load_all
    from . import kit as K
    load_all()
    variants = load_variants(variants_path)
    todo = [v for v in variants if (not ids or v['id'] in ids) and (not keys or v['key'] in keys)]
    if ids:
        known = {v['id'] for v in variants}
        for i in ids:
            if i not in known and i in K.PROPS:
                # registered but not in variants.json: default opts, next free key
                n = len(variants)
                v = {'id': i, 'opts': {}, 'key': '%s__%03d' % (i, n)}
                variants.append(v)
                todo.append(v)
                print('[build] %s is not in variants.json: building default opts as %s' % (i, v['key']))
    ok, failed = [], []
    game = K.Game()
    for n, v in enumerate(todo):
        if v['id'] not in K.PROPS:
            failed.append((v['key'], 'not registered (category module not ported yet?)'))
            continue
        try:
            info = build_variant(v, game, out_dir, save_blend, tex_dir)
            ok.append(info)
            print('[build] %3d/%d %-40s tris %6d meshes %3d  build %.1fs export %.1fs' % (
                n + 1, len(todo), v['key'], info['stats'].get('tris', 0), info['stats'].get('meshes', 0),
                info['build_s'], info['export_s']), flush=True)
        except Exception:
            tb = traceback.format_exc()
            failed.append((v['key'], tb))
            print('[build] FAILED %s\n%s' % (v['key'], tb), file=sys.stderr, flush=True)
            if stop_on_error:
                break
    write_index(ok, variants, out_dir)
    return ok, failed
