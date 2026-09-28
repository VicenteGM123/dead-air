"""Character build: bake (chars/bake) -> Blender scene -> godot/assets/chars/<id>.glb (FORMAT.md).

    build_chars(ids=None, save_blend=False)      called by blender/build_all.py `--only chars [--id duke]`
    python3 blender/chars/build.py [ids...] [--save-blend]     (standalone; bpy as a module)

Blender scene (three.js coordinates converted with Blender = (x, -z, y), SPEC §5.2): root empty <id> (custom
property "da" = header JSON), armature <id>_rig (rest = bind pose), skinned `body` (shape keys = morphs),
`part_<name>` meshes, attachment objects (dalib scene graph). The exported GLB is post-processed by glb_patch.py.
"""
import json
import math
import os
import sys
import time

import numpy as np

_BL = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _BL not in sys.path:
    sys.path.insert(0, _BL)

from chars.jsutil import O, nz                          # noqa: E402
from chars.defs import load_def, IDS                    # noqa: E402
from chars.sdf import _call                             # noqa: E402
from chars import m4                                    # noqa: E402
from chars.rig_build import jointTable, bindWorld       # noqa: E402

REPO = os.path.abspath(os.path.join(_BL, '..'))
OUT = os.path.join(REPO, 'godot', 'assets', 'chars')
PAT_DIR = os.path.join(OUT, 'patterns')
BLEND_OUT = os.path.join(_BL, 'out')

# glTF (three) <- Blender basis change used by the exporter (tree.py axis_basis_change)
A = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]], float)
Ainv = np.linalg.inv(A)

IMPORT_FILE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=false
nodes/use_node_type_suffixes=false
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=false
materials/extract=0
gltf/naming_version=2
gltf/embedded_image_handling=1
"""


def _b(P):
    """three (N,3) -> Blender (N,3)."""
    P = np.asarray(P, float)
    return np.stack([P[:, 0], -P[:, 2], P[:, 1]], 1)


def jsonable(v):
    if isinstance(v, dict):
        return {str(k): jsonable(x) for k, x in v.items() if not callable(x)}
    if isinstance(v, (list, tuple)):
        return [jsonable(x) for x in v]
    if isinstance(v, np.ndarray):
        return v.tolist()
    if isinstance(v, (np.integer,)):
        return int(v)
    if isinstance(v, (np.floating,)):
        return float(v)
    if callable(v):
        return None
    return v


# ------------------------------------------------------------------------------------------------ per-vertex data
def _lut(c8):
    c = c8 / 255.0
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def vertex_channels(m, morphs=None, morphNames=()):
    """FORMAT.md §4 channels for a baked mesh (m = bakeTree result), indexed by vertex."""
    n = m.n
    nrm = m.nrm8.astype(float) / 127.0
    ln = np.linalg.norm(nrm, axis=1)
    ln[ln == 0] = 1
    nrm = nrm / ln[:, None]
    col = np.zeros((n, 4))
    col[:, :3] = m.col / 255.0                       # sRGB u8/255 (FORMAT.md: exact in Godot's 8-bit colour)
    col[:, 3] = m.aux[:, 0] / 255.0
    pco = m.pco.astype(float)
    cav = (m.aux[:, 1].astype(float) - 128) / 127.0
    pw = m.pw.astype(float) / 255.0
    flow = m.flow.astype(float) / 127.0
    dc = np.full((n, 3), 8421504.0)
    for k, name in enumerate(morphNames[:3]):
        md = morphs[name]
        if md.dc is None:
            continue
        c8 = np.clip(np.floor(md.dc.astype(float) / 32767 * 127 + 0.5), -127, 127).astype(np.int64) + 128
        dc[md.ids, k] = (c8[:, 0] + c8[:, 1] * 256 + c8[:, 2] * 65536).astype(float)
    D = {
        'NORMAL': nrm, 'COLOR_0': col,
        'TEXCOORD_0': pco[:, 0:2], 'TEXCOORD_1': np.stack([pco[:, 2], cav], 1),
        'TEXCOORD_2': np.stack([m.aux[:, 2].astype(float), m.aux[:, 3].astype(float)], 1), 'TEXCOORD_3': pw[:, 0:2],
        'TEXCOORD_4': np.stack([pw[:, 2], flow[:, 0]], 1), 'TEXCOORD_5': flow[:, 1:3],
        'TEXCOORD_6': dc[:, 0:2], 'TEXCOORD_7': np.stack([dc[:, 2], np.zeros(n)], 1),
    }
    return D


def morph_arrays(body, morphs, names):
    out = []
    for name in names:
        md = morphs[name]
        dp = np.zeros((body.n, 3))
        dn = np.zeros((body.n, 3))
        dp[md.ids] = md.dp.astype(float) / 20000
        dn[md.ids] = md.dn.astype(float) / 63
        # Godot stores absolute normals (base + delta): keep the delta relative to the exported base normal
        out.append((name, dp, dn))
    return out


# ------------------------------------------------------------------------------------------------ attachments
def build_attachments(d, R, header, anchors):
    from dalib import scene as SG
    from chars.face import makeAttachBuilder, FaceRecorder
    root = SG.Group()
    root.name = d.id
    rigRoot = SG.Group()
    rigRoot.name = '__rig'
    root.add(rigRoot)
    joints = {}
    for n in R.bones:
        g = SG.Group()
        g.name = '__joint_' + n
        j = R.joints[n]
        g.position.set(*j.position)
        bp = R.bindPose.get(n)
        if bp:
            g.rotation.set(bp[0], bp[1], bp[2])
        joints[n] = g
    for n in R.bones:
        p = R.parents[n]
        (joints[p] if p else rigRoot).add(joints[n])
    face = FaceRecorder()
    rimColor = (d.rim or {}).get('color') or ('#8FF3FF' if d.kind == 'zombie' else '#FFD9A0')
    b = makeAttachBuilder(O(joints=joints, face=face, rimColor=rimColor))
    ctx = O(dims=R.rig.dims, header=header, A=anchors)
    if d.attachments:
        _call(d.attachments, b, ctx)
    root.updateMatrixWorld(True)
    # top-level attachments = objects the attachments added directly to a joint
    tops = []
    for n in R.bones:
        for c in list(joints[n].children):
            if c.name.startswith('__joint_'):
                continue
            tops.append((n, c))
    for n, c in tops:
        local = O(pos=[c.position.x, c.position.y, c.position.z], quat=[c.quaternion.x, c.quaternion.y, c.quaternion.z, c.quaternion.w],
                  scale=[c.scale.x, c.scale.y, c.scale.z], rot=[c.rotation.x, c.rotation.y, c.rotation.z], order=c.rotation.order)
        c.userData['joint'] = n
        c.userData['local'] = dict(local)
        root.attach(c)   # keeps the world (bind-pose) transform
    root.remove(rigRoot)
    _split_multimaterial(root)
    for o in _walk(root):
        if o is root:
            continue
        o.userData['jsName'] = o.name
    return root, face, [c for _, c in tops]


def _walk(o):
    yield o
    for c in o.children:
        yield from _walk(c)


def _split_multimaterial(root):
    """Meshes with a material array (geometry groups, e.g. the printed cards: face + edge) -> the mesh keeps group 0
    with material 0; every other group becomes a child mesh '<name>_<i>' with its material."""
    from dalib import scene as SG
    from dalib import three_geo as T3
    for o in list(_walk(root)):
        if getattr(o, 'isMesh', False) and isinstance(o.material, list):
            geo = o.geometry
            groups = geo.groups or [dict(start=0, count=len(geo.index) if geo.index is not None else geo.attributes.position.count, materialIndex=0)]
            mats = o.material
            subs = {}
            for g in groups:
                g = O(g)
                subs.setdefault(g.materialIndex, []).append((g.start, g.count))
            idx = np.asarray(geo.index.array).reshape(-1) if geo.index is not None else np.arange(geo.attributes.position.count)
            parts = []
            for mi, ranges in sorted(subs.items()):
                sel = np.concatenate([idx[s:s + c] for s, c in ranges])
                ng = T3.Geometry()
                for k in ('position', 'normal', 'uv', 'color'):
                    a = getattr(geo.attributes, k, None)
                    if a is not None:
                        ng.setAttribute(k, a.clone() if hasattr(a, 'clone') else a)
                ng.setIndex(sel.tolist())
                parts.append((mi, ng))
            o.geometry = parts[0][1]
            o.material = mats[parts[0][0]]
            for mi, ng in parts[1:]:
                ch = SG.Mesh(ng, mats[mi])
                ch.name = '%s_%d' % (o.name, mi)
                ch.castShadow = o.castShadow
                ch.userData['subMesh'] = True
                o.add(ch)


# ------------------------------------------------------------------------------------------------ Blender scene
def _new_mesh(bpy, name, pos, index, nrm, rgba, vid):
    me = bpy.data.meshes.new(name)
    n = len(pos)
    vb = _b(pos).astype(np.float32)
    me.vertices.add(n)
    me.vertices.foreach_set('co', vb.ravel())
    tris = np.asarray(index, np.int64).reshape(-1, 3)
    nl = tris.size
    me.loops.add(nl)
    me.loops.foreach_set('vertex_index', tris.ravel().astype(np.int32))
    me.polygons.add(len(tris))
    me.polygons.foreach_set('loop_start', np.arange(0, nl, 3, dtype=np.int32))
    me.update(calc_edges=True)
    me.polygons.foreach_set('use_smooth', np.ones(len(tris), dtype=bool))
    loop_v = tris.ravel()
    uv = me.uv_layers.new(name='vid')
    arr = np.zeros((nl, 2), np.float32)
    arr[:, 0] = vid[loop_v]
    uv.data.foreach_set('uv', arr.ravel())
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    ca.data.foreach_set('color', np.asarray(rgba, np.float32).ravel())
    me.color_attributes.active_color = ca
    nb = _b(nrm)
    ln = np.linalg.norm(nb, axis=1)
    ln[ln == 0] = 1
    nb = nb / ln[:, None]
    me.normals_split_custom_set_from_vertices([tuple(x) for x in nb])
    return me


def _add_attr(me, name, arr, dom='POINT'):
    arr = np.asarray(arr, np.float32)
    if arr.ndim == 1:
        a = me.attributes.new(name, 'FLOAT', dom)
        a.data.foreach_set('value', arr)
    elif arr.shape[1] == 2:
        a = me.attributes.new(name, 'FLOAT2', dom)
        a.data.foreach_set('vector', arr.ravel())
    else:
        a = me.attributes.new(name, 'FLOAT_VECTOR', dom)
        a.data.foreach_set('vector', arr[:, :3].ravel())


def build_blender(d, res, save_blend=False, log=print):
    import bpy
    import mathutils
    from dalib import scene as SG
    from chars.face import texture_file
    header = res.header
    body = res.body
    R = res.scene.R
    anchors = res.scene.ctx.A
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # ---- attachments graph (dalib) -> Blender (root object included)
    aroot, face, tops = build_attachments(d, R, header, anchors)
    names = SG.assign_names(aroot, d.id)
    reserved = {'body', d.id + '_rig'} | {'part_' + k for k in res.parts}
    for k, v in list(names.items()):
        if v in reserved:
            names[k] = v + '_att'
    rootOb = SG.to_blender(aroot, names, texture_file, d.id)
    _attachment_da(bpy, aroot, names)
    # ---- header
    bw = bindWorld(R)
    hair = _hair_info(body, R, bw)
    eyes = []
    for e in face.eyes:
        eyes.append(dict(side=e.side, root=names[id(e.root)], ball=names[id(e.ball)], upper=names[id(e.upper)],
                         lower=names[id(e.lower)], cap=e.cap, E=jsonable(e.E)))
    brows = [dict(part=k, side='L' if k.endswith('L') else 'R') for k in res.parts if k.startswith('brow')]
    from chars.patterns import write_tiles
    files, layerOf = write_tiles(d.materials, PAT_DIR)
    H = dict(jsonable(header))
    H['name'] = d.name
    H['joints'] = jointTable(R)
    H['dims'] = jsonable(R.rig.dims)
    H['hair'] = hair
    defKeys = ['armOut', 'poseOffset', 'rim', 'slots', 'animStyle', 'expressions', 'morphBone', 'name', 'skin', 'bindPose']
    H['def'] = {k: jsonable(d[k]) for k in defKeys if d.get(k) is not None}
    H['anchors'] = jsonable(anchors) if anchors is not None else {}
    H['face'] = dict(eyes=eyes, brows=brows)
    H['attachments'] = [names[id(c)] for c in tops]
    H['patterns'] = dict(size=512, layers=['patterns/' + f for f in files], layerOf=layerOf)
    for k, p in H['parts'].items():
        p['node'] = 'part_' + k
    H['vertexPacking'] = 'FORMAT.md §4 v1: COLOR=(srgb.rgb, ao) UV=pco.xy UV2=(pco.z,cav) CUSTOM0=(mat,pmode,pw.x,pw.y) CUSTOM1=(pw.z,flow.xyz) CUSTOM2=(dc0,dc1,dc2,0)'
    rootOb['da'] = json.dumps(H, separators=(',', ':'))
    # top-level attachment "da": move joint/local to the top level (they are in userData already)
    # ---- armature (rest = bind pose)
    arm = bpy.data.armatures.new(d.id + '_rig')
    armOb = bpy.data.objects.new(d.id + '_rig', arm)
    bpy.context.scene.collection.objects.link(armOb)
    armOb.parent = rootOb
    bpy.context.view_layer.objects.active = armOb
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = {}
    for n in R.bones:
        eb = arm.edit_bones.new(n)
        eb.length = 0.05
        Lb = Ainv @ bw[n]
        eb.matrix = mathutils.Matrix(Lb.tolist())
        ebs[n] = eb
    for n in R.bones:
        p = R.parents[n]
        if p:
            ebs[n].parent = ebs[p]
            ebs[n].use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    # ---- body
    D = vertex_channels(body, res.morphs, header.morphs)
    rgba = np.concatenate([_lut(body.col.astype(float)), body.aux[:, :1] / 255.0], 1)
    me = _new_mesh(bpy, 'body', body.pos, body.index, D['NORMAL'], rgba, np.arange(body.n, dtype=float))
    _add_attr(me, 'pco', body.pco)
    _add_attr(me, 'aux', body.aux.astype(float))
    _add_attr(me, 'pw', body.pw.astype(float) / 255)
    _add_attr(me, 'flow', body.flow.astype(float) / 127)
    mat = bpy.data.materials.new('char_' + d.id)
    mat['da'] = json.dumps({'kind': 'char', 'id': d.id}, separators=(',', ':'))
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((x for x in nt.nodes if x.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is not None:
        vc = nt.nodes.new('ShaderNodeVertexColor')
        vc.layer_name = 'Col'
        nt.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value = 0.6
    me.materials.append(mat)
    bodyOb = bpy.data.objects.new('body', me)
    bpy.context.scene.collection.objects.link(bodyOb)
    bodyOb.parent = armOb
    for bi, n in enumerate(R.bones):
        vg = bodyOb.vertex_groups.new(name=n)
    # vertex group weights (grouped per bone)
    for k in range(4):
        for bi, n in enumerate(R.bones):
            sel = np.nonzero((body.skinIndex[:, k] == bi) & (body.skinWeight[:, k] > 0))[0]
            if not len(sel):
                continue
            vg = bodyOb.vertex_groups[n]
            w = body.skinWeight[sel, k] / 255.0
            for wv in np.unique(w):
                ids = sel[w == wv].tolist()
                vg.add(ids, float(wv), 'ADD')
    mod = bodyOb.modifiers.new('Armature', 'ARMATURE')
    mod.object = armOb
    if header.morphs:
        bodyOb.shape_key_add(name='Basis', from_mix=False)
        for name in header.morphs:
            md = res.morphs[name]
            sk = bodyOb.shape_key_add(name=name, from_mix=False)
            P = body.pos.copy()
            P[md.ids] += md.dp.astype(float) / 20000
            sk.data.foreach_set('co', _b(P).astype(np.float32).ravel())
    # ---- parts (bind-pose model coordinates)
    for name, pm in res.parts.items():
        Dp = vertex_channels(pm)
        rgbp = np.concatenate([_lut(pm.col.astype(float)), pm.aux[:, :1] / 255.0], 1)
        mp = _new_mesh(bpy, 'part_' + name, pm.pos, pm.index, Dp['NORMAL'], rgbp, np.arange(pm.n, dtype=float))
        mp.materials.append(mat)
        ob = bpy.data.objects.new('part_' + name, mp)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = rootOb
        p = header.parts[name]
        ob['da'] = json.dumps({'part': name, 'bone': p.bone, 'pivot': jsonable(p.pivot)}, separators=(',', ':'))
    if save_blend:
        os.makedirs(BLEND_OUT, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_OUT, 'char_%s.blend' % d.id))
    return rootOb


_OWN = ('joint', 'local', 'jsName', 'subMesh')


def _attachment_da(bpy, aroot, names):
    """FORMAT.md §5 node "da": {name, joint, local (top-level only), userData, castShadow, renderOrder, visible}
    (+ material "da": rimColor at the top level)."""
    from dalib import scene as SG
    for o in _walk(aroot):
        if o is aroot:
            continue
        ob = bpy.data.objects.get(names[id(o)])
        if ob is None:
            continue
        ud = {k: v for k, v in dict(o.userData).items() if k not in _OWN}
        da = {'name': o.userData.get('jsName', o.name), 'userData': SG.jsonable(ud, names, strict=False)}
        if o.userData.get('joint'):
            da['joint'] = o.userData['joint']
            da['local'] = o.userData['local']
        if o.userData.get('subMesh'):
            da['subMesh'] = True
        if getattr(o, 'isMesh', False):
            da['castShadow'] = bool(o.castShadow)
        da['renderOrder'] = o.renderOrder
        da['visible'] = bool(o.visible)
        if o.rotation.order != 'XYZ':
            da['rotationOrder'] = o.rotation.order
        ob['da'] = json.dumps(da, separators=(',', ':'))
    for m in bpy.data.materials:
        if 'da' in m.keys():
            try:
                spec = json.loads(m['da'])
            except Exception:
                continue
            if spec.get('kind') == 'attach' and 'rimColor' not in spec:
                spec['rimColor'] = (spec.get('opts') or {}).get('rimColor')
                m['da'] = json.dumps(spec, separators=(',', ':'))


def _hair_info(body, R, bw):
    """charRuntime hairInfo(): head-bound vertices -> slot height and bounding radius (head-joint frame)."""
    if 'head' not in R.bones:
        return dict(top=0.3, cz=0, radius=0.2, n=0)
    hi = R.bones.index('head')
    w = np.zeros(body.n)
    for k in range(4):
        w += np.where(body.skinIndex[:, k] == hi, body.skinWeight[:, k].astype(float), 0)
    sel = w >= 200
    if not sel.any():
        return dict(top=0.3, cz=0, radius=0.2, n=0)
    qb = np.array(body.qbox)
    P = qb[:3] + body.qpos[sel].astype(float) / 65535 * qb[3:]
    inv = np.linalg.inv(bw['head'])
    L = P @ inv[:3, :3].T + inv[:3, 3]
    top = float(L[:, 1].max())
    cz = float(L[:, 2].mean())
    c = np.array([0, top * 0.55, cz])
    r = float(np.sqrt(((L - c) ** 2).sum(1)).max())
    return dict(top=top, cz=cz, radius=r, n=int(sel.sum()))


def export_glb(d, res, path, log=print):
    import bpy
    from chars.glb_patch import patch_glb
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_extras=True, export_yup=True, export_apply=False,
        export_texcoords=True, export_normals=True, export_materials='EXPORT', export_image_format='AUTO',
        export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_attributes=False,
        export_skins=True, export_morph=True, export_morph_normal=False, export_animations=False,
        export_rest_position_armature=True, export_def_bones=False, use_selection=False,
        export_tangents=False)
    meshes = {'body': dict(data=vertex_channels(res.body, res.morphs, res.header.morphs),
                           morphs=morph_arrays(res.body, res.morphs, res.header.morphs))}
    for name, pm in res.parts.items():
        meshes['part_' + name] = dict(data=vertex_channels(pm), morphs=None)
    done = patch_glb(path, meshes)
    imp = path + '.import'
    if not os.path.exists(imp):
        with open(imp, 'w') as f:
            f.write(IMPORT_FILE)
    return done


def build_char(cid, save_blend=False, log=print, res=None):
    from chars.bake.bake import bakeChar
    d = load_def(cid)
    t0 = time.time()
    if res is None:
        res = bakeChar(d, log=log)
    build_blender(d, res, save_blend=save_blend, log=log)
    path = os.path.join(OUT, cid + '.glb')
    done = export_glb(d, res, path, log=log)
    log('%s: exported %s (%s) in %.1f s' % (cid, os.path.relpath(path, REPO), ', '.join(done), time.time() - t0))
    return res


def build_chars(ids=None, save_blend=False, log=print):
    ids = ids or IDS
    out = {}
    for cid in ids:
        out[cid] = build_char(cid, save_blend=save_blend, log=log)
    return out


def build(ids=None, save_blend=False, godot=None):
    """blender/build_all.py `--only chars [--id duke]` entry point."""
    global OUT, PAT_DIR
    if godot:
        OUT = os.path.join(os.path.abspath(godot), 'assets', 'chars')
        PAT_DIR = os.path.join(OUT, 'patterns')
        import chars.face as F
        F.TEX_DIR = os.path.join(OUT, 'tex')
    ok = True
    for cid in (ids or IDS):
        try:
            build_char(cid, save_blend=save_blend)
        except Exception:
            import traceback
            traceback.print_exc()
            ok = False
    return ok


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    ids = [a for a in argv if not a.startswith('--')]
    build_chars(ids or None, save_blend='--save-blend' in argv)
