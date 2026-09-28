"""DEAD AIR — prop kit, Python port of src/props/kit.js (docs/PROPKIT.md). Same names, same numbers.

    from dalib import kit as K
    from dalib.kit import registerProp, registerScene, PAL, THREE

   Registry   registerProp(id, build(game, opts) -> Group, meta) · buildProp(id, game, opts) · listProps(cat?)
              propMeta(id) · registerScene(name, spec) · getScene(name) · listScenes() · cloneProp(group)
   Result     prop(id, {...}) -> Group with the PROP RESULT CONVENTION userData · finish(game, group, o)
   Materials  mat(game, preset, color, extra) — presets: lacquer walnut teak vinyl chrome brass plastic fabric felt
              crt rubber paint metal ceramic soil leaf  (always vertexColors so bakeAO shows; keepColor via extra)
              glow(game, color, intensity) · screen(game, w, h, {card, bulge, group}) -> CRT mesh
              material(kind, color, opts, **fields) — any other Godot material kind (bubble, chromacast …)
   Geometry   box(w,h,d,r,{uv,swap,seg}) (centered) · cushion(w,h,d,{r,puff,uv}) (centered) · cyl(rt,rb,h,{bevel})
              (base at y=0) · lathe(profile,{seg,round}) · roundProfile(pts,r) · extrude(shape|pts,depth,{bevel})
              roundRect(w,h,r) · tube(pts,r,{seg,radial,closed}) · roundRectPath(w,d,r,y) · leaf(len,w,{...})
              leafCluster({...}) · taper(geo,{axis,k}) · uvBox(geo, perMeter, {swap}) · uvScale(geo, su, sv)
              uvRect(geo,u0,v0,u1,v1) · weldNormals(geo) · tint(geo, color) · m(geo, mat, o) (mesh shortcut)
   Textures   tex.wood/burl/shag/weave/pebble/brushed/label/canvas (cached, seeded) — dalib/tex.py
   Baking     bakeAO(group, opts) — vertex-color AO: height-above-floor band + voxel ray occlusion (numpy, same
              operation order as the JS scalar code)
   Utils      merge(group) (mergeByMaterial) · stats(group) -> {tris, meshes, mats} · R (bevel presets) · PAL
   Game shim  Game() -> game.mats (toon/glow/basic/glass/skin/screen/rubberGlass/screenGeometry/variant/
              applyHeroFade/uniforms) · game.tex (textures.js) · game.PAL · game.screens/lights/level = None
   THREE      namespace with the three.js classes the builders use (geometries, math, Group/Mesh/InstancedMesh,
              Shape/Path/curves, side/wrap/blending constants, BufferAttribute …)

PROP RESULT CONVENTION — every builder returns a Group whose userData is:
  { id, size:[w,h,d], colliders:[{min:[x,y,z], max:[x,y,z]}], screens:[{mesh, group}], lightAnchors:[{pos,
    color, intensity, distance}], parts:{name: Object3D}, interact:{point:[x,y,z], radius}|None, stats }
  Local space: floor at y=0, prop centered on x/z, FRONT FACES -Z. Only the ROOT userData may hold Object3D
  references (clones remap them); children userData must stay JSON-safe (noMerge / noShadow / noAO flags).

JS -> Python: opts objects are dicts ({'seg': 12}); `a ?? b` -> `x if x is not None else b`; the Game shim is
passed as `game`. See blender/README.md (kit guide) for the porting patterns.
"""
from __future__ import annotations

import math
import sys
import types

import numpy as np

from . import three_geo as _TG
from . import geo as G
from .three_geo import (Geometry, BufferAttribute, Float32BufferAttribute, mergeGeometries, Shape, Path,
                        ExtrudeGeometry, PlaneGeometry, BoxGeometry, LatheGeometry)
from .mathutils3 import (JSObj, Vector2, Vector3, Vector4, Matrix3, Matrix4, Quaternion, Euler, Color, Box3,
                         MathUtils, js_json, js_str, js_round, clamp, lerp, smoothstep)
from .scene import (Object3D, Group, Mesh, InstancedMesh, Line, LineSegments, Points, Material, Layers,
                    FrontSide, BackSide, DoubleSide, NoBlending, NormalBlending, AdditiveBlending,
                    SubtractiveBlending, MultiplyBlending, box_from_object)
from . import tex as _tex
from .tex import (tex, getCard, cardInfo, Texture, CardTexture, Textures, RepeatWrapping, ClampToEdgeWrapping,
                  MirroredRepeatWrapping, NearestFilter, LinearFilter, LinearMipmapLinearFilter, SRGBColorSpace)
from .canvas2d import Canvas
from .rng import mulberry32
from .pal import PAL

__all__ = ['registerProp', 'buildProp', 'listProps', 'propMeta', 'cloneProp', 'registerScene', 'getScene',
           'listScenes', 'MAT', 'mat', 'glow', 'screen', 'material', 'R', 'box', 'uvBox', 'taper', 'uvRect',
           'uvScale', 'weldNormals', 'cushion', 'roundProfile', 'lathe', 'cyl', 'roundRect', 'extrude', 'tube',
           'roundRectPath', 'leaf', 'leafCluster', 'tint', 'm', 'tex', 'bakeAO', 'aoStats', 'prop', 'finish',
           'merge', 'stats', 'PAL', 'THREE', 'Game', 'Materials', 'getCard', 'cardInfo', 'document', 'r3']


# ============================================================================================ THREE shim
def _instanced_attr(items):
    class _L(list):
        pass
    lst = _L(items)
    lst.needsUpdate = False
    return lst


def _canvas_texture(canvas, *a, **k):
    """new THREE.CanvasTexture(canvas): anonymous canvas textures get a key from their pixels at export."""
    t = Texture(canvas, None, False, 'cv')
    t.wrapS = t.wrapT = ClampToEdgeWrapping
    return t


def _material_factory(kind, type_):
    def make(params=None, **kw):
        p = dict(params or {})
        p.update(kw)
        color = p.pop('color', '#ffffff')
        if not isinstance(color, str):
            color = '#' + Color(color).getHexString()
        fields = {k: p[k] for k in ('transparent', 'opacity', 'side', 'depthWrite', 'vertexColors', 'map',
                                    'blending', 'toneMapped', 'fog', 'name', 'uniforms') if k in p}
        opts = {k: v for k, v in p.items() if k not in ('uniforms',)}
        if 'blending' in opts:
            opts['blending'] = {0: 'none', 1: 'normal', 2: 'additive', 3: 'subtractive', 4: 'multiply'}.get(
                opts['blending'], opts['blending'])
        if 'roughness' in opts:
            opts['rough'] = opts.pop('roughness')
        if 'metalness' in opts:
            opts['metal'] = opts.pop('metalness')
        return Material(kind, color, opts, type=type_, **fields)
    return make


THREE = types.SimpleNamespace()
for _n in dir(_TG):
    if not _n.startswith('_'):
        setattr(THREE, _n, getattr(_TG, _n))
THREE.__dict__.update(dict(
    Object3D=Object3D, Group=Group, Mesh=Mesh, InstancedMesh=InstancedMesh, Line=Line, LineSegments=LineSegments,
    Points=Points, Layers=Layers, Scene=Group,
    Vector2=Vector2, Vector3=Vector3, Vector4=Vector4, Matrix3=Matrix3, Matrix4=Matrix4, Quaternion=Quaternion,
    Euler=Euler, Color=Color, Box3=Box3, MathUtils=MathUtils,
    FrontSide=FrontSide, BackSide=BackSide, DoubleSide=DoubleSide, NoBlending=NoBlending,
    NormalBlending=NormalBlending, AdditiveBlending=AdditiveBlending, SubtractiveBlending=SubtractiveBlending,
    MultiplyBlending=MultiplyBlending, RepeatWrapping=RepeatWrapping, ClampToEdgeWrapping=ClampToEdgeWrapping,
    MirroredRepeatWrapping=MirroredRepeatWrapping, NearestFilter=NearestFilter, LinearFilter=LinearFilter,
    LinearMipmapLinearFilter=LinearMipmapLinearFilter, SRGBColorSpace=SRGBColorSpace,
    LinearSRGBColorSpace='srgb-linear', CanvasTexture=_canvas_texture,
    MeshStandardMaterial=_material_factory('standard', 'MeshStandardMaterial'),
    MeshBasicMaterial=_material_factory('basic', 'MeshBasicMaterial'),
    MeshLambertMaterial=_material_factory('standard', 'MeshLambertMaterial'),
    ShaderMaterial=_material_factory('shader', 'ShaderMaterial'),
    LineBasicMaterial=_material_factory('basic', 'LineBasicMaterial'),
))
THREE.BufferGeometry = Geometry


class _Document:
    """document.createElement('canvas') -> dalib.canvas2d.Canvas (300x150 like the DOM; set width/height)."""

    @staticmethod
    def createElement(tag):
        if tag != 'canvas':
            raise ValueError('document.createElement: only canvas is supported')
        return Canvas(300, 150)


document = _Document()


# =============================================================================================== registry
PROPS = {}
SCENES = {}
_PROTOS = {}  # id(game) -> {key: prototype group}


def registerProp(id, build, meta=None):
    """meta: { category, tags:[], size:[w,h,d] (nominal, for layout tools), desc, cache=true, hero=false }"""
    meta = meta or {}
    if id in PROPS:
        sys.stderr.write('[props] "%s" registered twice; the last one wins\n' % id)
    PROPS[id] = {
        'id': id, 'build': build,
        'meta': {'category': meta.get('category', 'misc'), 'tags': meta.get('tags', []), 'size': meta.get('size'),
                 'desc': meta.get('desc', ''), 'cache': meta.get('cache', True), 'hero': bool(meta.get('hero'))},
    }


def propMeta(id):
    e = PROPS.get(id)
    return dict({'id': id}, **e['meta']) if e else None


def listProps(category=None):
    out = []
    for e in PROPS.values():
        if not category or e['meta']['category'] == category:
            out.append(dict({'id': e['id']}, **e['meta']))
    return out


def buildProp(id, game, opts=None):
    """Builds a prop. Props without screens are built once per (game, id, opts) and cloned afterwards (geometry and
    materials shared, userData Object3D refs remapped). opts.unique = True forces a fresh build."""
    opts = {} if opts is None else opts
    e = PROPS.get(id)
    if not e:
        raise KeyError('[props] unknown prop "%s"' % id)
    cache = _PROTOS.setdefault(_game_key(game), {})
    key = '%s|%s' % (id, js_json(opts))
    hit = cache.get(key)
    if hit is not None:
        return cloneProp(hit)
    g = e['build'](game, opts)
    _normalizeUserData(g, id)
    if e['meta']['cache'] and not opts.get('unique') and not len(g.userData.screens):
        cache[key] = g
        return cloneProp(g)
    return g


def _game_key(game):
    return game.__dict__.setdefault('_propkit_key', len(_PROTOS) + 1) if hasattr(game, '__dict__') else 0


def _truthy(v):
    """JS truthiness (arrays and objects are truthy even when empty)."""
    if v is None or v is False:
        return False
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v == v and v != 0
    if isinstance(v, str):
        return v != ''
    return True


def _or(v, default):
    return v if _truthy(v) else default


def _normalizeUserData(g, id):
    u = g.userData
    u.id = _or(u.id, id)
    u.colliders = _or(u.colliders, [])
    u.screens = _or(u.screens, [])
    u.lightAnchors = _or(u.lightAnchors, [])
    u.parts = _or(u.parts, JSObj())
    if 'interact' not in u:
        u.interact = None
    if not _truthy(u.size):
        bb = box_from_object(g)
        s = bb.getSize(Vector3())
        u.size = [r3(s.x), r3(s.y), r3(s.z)]


def cloneProp(src):
    ud = src.userData
    src.userData = JSObj()
    c = src.clone(True)
    src.userData = ud
    mp = {}

    def walk(a, b):
        mp[id(a)] = b
        for i in range(len(a.children)):
            walk(a.children[i], b.children[i])
    walk(src, c)

    def remap(v):
        if v is not None and getattr(v, 'isObject3D', False):
            return mp.get(id(v), v)
        if isinstance(v, list):
            return [remap(x) for x in v]
        if isinstance(v, dict):
            o = JSObj()
            for k in v:
                o[k] = remap(v[k])
            return o
        return v
    c.userData = remap(ud)
    return c


# Set-dressing test scenes for tools/propview (kept for parity; the pipeline does not use them).
def registerScene(name, spec):
    SCENES[name] = spec


def getScene(name):
    return SCENES.get(name)


def listScenes():
    return list(SCENES.keys())


# ============================================================================================ materials
# Roughness/metal/rim presets tuned for the toon shader + ACES grade. env = RoomEnvironment reflection amount.
# All force vertexColors (bakeAO writes them). Colors: pass a hex; textured presets usually use '#ffffff'.
MAT = {
    'lacquer': {'rough': 0.36, 'rim': 0.22, 'env': 0.12},          # glossy lacquered wood / enamel paint
    'walnut': {'rough': 0.42, 'rim': 0.2, 'env': 0.08},
    'teak': {'rough': 0.5, 'rim': 0.2, 'env': 0.05},
    'vinyl': {'rough': 0.36, 'rim': 0.32, 'env': 0.1},              # naugahyde, tolex
    'chrome': {'rough': 0.2, 'metal': 1, 'rim': 0.18, 'env': 0.55},  # use mid-grey colors (#A8B0BA)
    'brass': {'rough': 0.3, 'metal': 1, 'rim': 0.2, 'env': 0.45},
    'plastic': {'rough': 0.34, 'rim': 0.3, 'env': 0.12},            # ABS / bakelite
    'fabric': {'rough': 0.95, 'rim': 0.5, 'wrap': 0.7, 'rimPower': 1.8},  # velvet-ish sheen on silhouettes
    'felt': {'rough': 1, 'rim': 0.55, 'wrap': 0.75, 'rimPower': 1.6},
    'crt': {'rough': 0.06, 'rim': 0.55, 'env': 0.5},               # dark glass (unpowered tubes, lenses)
    'rubber': {'rough': 0.85, 'rim': 0.12},
    'paint': {'rough': 0.6, 'rim': 0.2},                           # matte painted wood/metal
    'metal': {'rough': 0.42, 'metal': 0.7, 'rim': 0.2, 'env': 0.35},  # brushed / painted steel
    'ceramic': {'rough': 0.22, 'rim': 0.3, 'env': 0.15},
    'soil': {'rough': 1, 'rim': 0.05},
    'leaf': {'rough': 0.55, 'rim': 0.4, 'wrap': 0.8, 'side': DoubleSide, 'rimColor': '#EFFFB0'},
}


def mat(game, preset='plastic', color='#ffffff', extra=None):
    p = MAT.get(preset)
    if p is None:
        sys.stderr.write('[props] unknown material preset "%s"\n' % preset)
    o = dict(p or {})
    o['vertexColors'] = True
    o.update(extra or {})
    return game.mats.toon(color, o)


def glow(game, color=None, intensity=2.5, opts=None):
    return game.mats.glow(PAL.tungsten if color is None else color, intensity, opts or {})


def material(kind, color='#ffffff', opts=None, type='MeshStandardMaterial', **fields):
    """Any other material kind the Godot side knows (materials.gd fromSpec): e.g.
    material('bubble', '#hex', {'intensity': 1.1}, type='ShaderMaterial', transparent=True, depthWrite=False,
    blending=AdditiveBlending) or material('chromacast', '#ffffff', toonOpts, extra={'chroma': {...}})."""
    return Material(kind, color, opts, type=type, **fields)


def screen(game, w, h, opts=None):
    """CRT/monitor face: slightly domed plane with the engine CRT material. Push the result into
    userData.screens as { mesh, group } so rooms can hand it to game.screens.register (placeProp does it).
    opts: { card='station_id' (preview art until ScreenManager takes over), bright=0.85, dome, bulge, group }"""
    opts = opts or {}
    dome = opts['dome'] if opts.get('dome') is not None else min(w, h) * 0.05
    g = PlaneGeometry(w, h, 12, 9)
    pos = g.attributes.position
    for i in range(pos.count):
        x, y = (pos.getX(i) / w) * 2, (pos.getY(i) / h) * 2
        pos.setZ(i, dome * (1 - x * x * 0.5 - y * y * 0.5))
    g.computeVertexNormals()
    g.rotateY(math.pi)  # face -z (prop front)
    card = None if ('card' in opts and opts['card'] is None) else getCard(opts.get('card') or 'station_id')
    mt = game.mats.screen(card, {'w': w, 'h': h, 'bulge': opts.get('bulge') or 0,
                                 'bright': opts['bright'] if opts.get('bright') is not None else 0.85})
    mesh = Mesh(g, mt)
    mesh.name = 'screen'
    mesh.userData.noMerge = True
    mesh.userData.screenGroup = opts.get('group') or 'scr_decor'
    mesh.castShadow = False
    return mesh


class Materials:
    """game.mats shim: the JS factories (src/core/materials.js) returning cached Material specs."""

    def __init__(self, game=None):
        self.game = game
        self._cache = {}
        self.PAL = PAL
        self.envMap = None
        self.uniforms = JSObj({k: JSObj(value=v) for k, v in (
            ('uSatEnv', 0.7), ('uAmber', 0.08), ('uWaveOrigin', Vector3()), ('uWaveRadius', -1), ('uTime', 0),
            ('uHeroFade', 1), ('uRimAmbient', 1))})

    @staticmethod
    def _key(kind, color, p):
        q = {}
        for k in p:
            v = p[k]
            q[k] = ('tex:' + (v.uuid if hasattr(v, 'uuid') else v.key)) if (
                getattr(v, 'isTexture', False) or getattr(v, 'isCard', False)) else v
        return '%s|%s|%s' % (kind, color, js_json(q))

    def toon(self, color='#ffffff', opts=None):
        opts = opts or {}
        hx = color if isinstance(color, str) else '#' + Color(color).getHexString()
        g = opts.get

        def d(k, v):
            x = g(k)
            return v if x is None else x
        p = {
            'rough': d('rough', 0.75), 'metal': d('metal', 0), 'emissive': d('emissive', None),
            'emissiveIntensity': d('emissiveIntensity', 1), 'rim': d('rim', 0.35), 'rimColor': d('rimColor', '#FFE9CC'),
            'rimPower': d('rimPower', 2.4), 'wrap': d('wrap', 0.5), 'steps': d('steps', 0), 'map': d('map', None),
            'transparent': bool(g('transparent')), 'opacity': d('opacity', 1), 'side': d('side', FrontSide),
            'flat': bool(g('flat')), 'keepColor': bool(g('keepColor')), 'heroFade': bool(g('heroFade')),
            'vertexColors': bool(g('vertexColors')), 'env': d('env', None), 'alphaTest': d('alphaTest', 0),
            'depthWrite': d('depthWrite', True), 'fog': d('fog', True), 'name': d('name', ''),
        }
        key = self._key('toon', hx, p)
        mt = self._cache.get(key)
        if mt is not None:
            return mt
        mt = Material('toon', hx, p, type='MeshStandardMaterial', name=p['name'] or 'toon:%s' % hx)
        if p['emissive']:
            mt.emissive.set(p['emissive'])
            mt.emissiveIntensity = p['emissiveIntensity']
        mt.roughness = p['rough']
        mt.metalness = p['metal']
        mt.flatShading = p['flat']
        mt.userData.daToon = JSObj(color=hx, params=p)
        mt._snap = mt._tracked()
        self._cache[key] = mt
        return mt

    def variant(self, mt, extra):
        """Same material with some params overridden (e.g. {heroFade: True}); non-toon materials as-is."""
        d = mt.userData.daToon if mt is not None else None
        if not d:
            return mt
        o = dict(d.params)
        o.update(extra)
        return self.toon(d.color, o)

    def applyHeroFade(self, root):
        def f(o):
            if not getattr(o, 'isMesh', False):
                return
            if o.material is not None and o.material.userData.daToon:
                o.material = self.variant(o.material, {'heroFade': True})
            else:
                o.userData.daHideOnFade = True
        root.traverse(f)

    def noOcclusion(self, root):
        def f(o):
            m = getattr(o, 'material', None)
            if m is not None and getattr(m, 'isMaterial', False) and m.userData.daToon and not m.opts.get('heroFade'):
                m.extra['noOcclusion'] = True
        if root is not None:
            root.traverse(f)

    def glow(self, color='#ffffff', intensity=2, opts=None):
        """Unlit HDR emissive. opts: { transparent, opacity, additive, map, fog=true, side }"""
        opts = opts or {}
        q = {'intensity': intensity}
        q.update(opts)
        key = self._key('glow', color, q)
        mt = self._cache.get(key)
        if mt is not None:
            return mt
        c = Color(color).multiplyScalar(intensity)
        mt = Material('glow', color, q, type='MeshBasicMaterial', name='glow:%s' % color, colorValue=c,
                      transparent=bool(opts.get('transparent')) or bool(opts.get('additive')),
                      opacity=opts.get('opacity', 1),
                      blending=AdditiveBlending if opts.get('additive') else NormalBlending,
                      depthWrite=not opts.get('additive'), side=opts.get('side', FrontSide), map=opts.get('map'))
        self._cache[key] = mt
        return mt

    def basic(self, color='#ffffff', opts=None):
        """Plain unlit color (UI-ish props, backdrops). Cached."""
        opts = opts or {}
        key = self._key('basic', color, opts)
        mt = self._cache.get(key)
        if mt is None:
            fields = {k: opts[k] for k in ('transparent', 'opacity', 'side', 'depthWrite', 'vertexColors', 'map',
                                           'blending', 'toneMapped', 'fog') if k in opts}
            o = dict(opts)
            if 'blending' in o:
                o['blending'] = {0: 'none', 1: 'normal', 2: 'additive', 3: 'subtractive', 4: 'multiply'}.get(
                    o['blending'], o['blending'])
            mt = Material('basic', color if isinstance(color, str) else '#' + Color(color).getHexString(), o,
                          type='MeshBasicMaterial', **fields)
            self._cache[key] = mt
        return mt

    def glass(self, color='#CFE8FF', opts=None):
        opts = opts or {}
        return self.toon(color, {
            'rough': 0.05, 'transparent': True, 'opacity': opts.get('opacity', 0.22), 'rim': 0.6,
            'rimColor': '#ffffff', 'rimPower': 2.0, 'env': 1.2, 'depthWrite': False,
            'keepColor': opts.get('keepColor', True), 'side': opts.get('side', DoubleSide), 'name': 'glass'})

    def skin(self, tone='#F2B48C', opts=None):
        o = {'rough': 0.58, 'wrap': 0.7, 'rim': 0.35, 'rimColor': PAL.rimHero, 'keepColor': True}
        o.update(opts or {})
        return self.toon(tone, o)

    _SCREEN_DEFAULTS = {'barrel': 0.06, 'scan': 0.35, 'chroma': 1.5, 'vignette': 0.8, 'gloss': 1, 'lines': 120}

    def screen(self, texture=None, opts=None):
        """CRT screen material (NOT cached: ScreenManager swaps the map per screen at runtime).
        opts: { bulge=0, barrel=0.06, scan=0.35, bright=1.35, chroma=1.5, vignette=0.8, gloss=1, lines=120, w, h }"""
        opts = dict(opts or {})
        scr = {'w': opts.get('w', 1), 'h': opts.get('h', 0.75), 'bulge': opts.get('bulge', 0),
               'bright': opts.get('bright', 1.35)}
        rest = {k: v for k, v in opts.items() if k not in ('w', 'h', 'bulge', 'bright')
                and self._SCREEN_DEFAULTS.get(k, object()) != v}
        extra = {'screen': scr}
        if getattr(texture, 'isCard', False):
            extra['card'] = texture.card
            extra['cardOpts'] = texture.cardOpts
            mp = None
        else:
            mp = texture
        mt = Material('screen', '#ffffff', rest, type='ShaderMaterial', name='crt', extra=extra, map=mp)
        if mp is not None:
            mt.opts['map'] = mp
        mt._card = texture
        return mt

    def rubberGlass(self, texture=None, opts=None):
        o = {'bulge': 0.03, 'barrel': 0.04, 'scan': 0.3}
        o.update(opts or {})
        return self.screen(texture, o)

    def screenGeometry(self, w=0.8, h=0.6):
        """Plane subdivided 24x18 for bulging screens (cached per size)."""
        return G.plane(w, h, 24, 18)


class Game:
    """The `game` object prop builders receive (static build: no level/lights/screens)."""

    def __init__(self):
        self.mats = Materials(self)
        self.tex = Textures(self)
        self.PAL = PAL
        self.screens = None
        self.lights = None
        self.level = None
        self.params = JSObj()


# ============================================================================================== geometry
# Bevel radius presets (meters). Never ship raw box edges: xs for trims, sm/md for furniture, lg/xl for chunky toys.
R = JSObj(xs=0.006, sm=0.012, md=0.025, lg=0.05, xl=0.09)


def r3(n):
    return js_round(n * 1000) / 1000


def _rad(r):
    return R.get(r, R.md) if isinstance(r, str) else r


def box(w, h, d, r='md', opts=None):
    """Rounded box, centered. r: preset name or meters (clamped). seg auto: 1 for tiny radii, 2, 3 for big ones.
    opts.uv = repeats per meter -> box-projected UVs (consistent texel density; returns an own copy)."""
    opts = opts or {}
    rr = min(_rad(r), min(w, h, d) / 2 - 1e-4)
    rr = max(rr, 1e-4)
    seg = opts['seg'] if opts.get('seg') is not None else (1 if rr < 0.015 else 2 if rr < 0.05 else 3)
    g = G.roundedBox(w, h, d, rr, seg)
    return uvBox(g, opts['uv'], opts) if opts.get('uv') else g


def uvBox(geo, perMeter=1, opts=None):
    """Box-projected UVs (dominant normal axis), `perMeter` texture repeats per meter. Returns a new geometry.
    swap: rotate the pattern 90deg (e.g. wood grain along x on a table top)."""
    swap = bool((opts or {}).get('swap', False))
    g = geo.clone()
    p = np.asarray(g.attributes.position, dtype=np.float64)
    n = np.asarray(g.attributes.normal, dtype=np.float64)
    ax, ay, az = np.abs(n[:, 0]), np.abs(n[:, 1]), np.abs(n[:, 2])
    top = (ay >= ax) & (ay >= az)
    side = ~top & (ax >= az)
    u = np.where(top, p[:, 0], np.where(side, p[:, 2], p[:, 0]))
    v = np.where(top, p[:, 2], np.where(side, p[:, 1], p[:, 1]))
    if swap:
        u, v = v, u
    uv = np.empty((len(p), 2))
    uv[:, 0] = u * perMeter
    uv[:, 1] = v * perMeter
    g.setAttribute('uv', BufferAttribute(uv, 2))
    return g


def taper(geo, opts=None):
    """Tapers a geometry along an axis (returns a copy): cross-section scaled from 1 at the min end to `k` at the
    max end. opts: { axis='z', k=0.7, center:[cx,cy] of the cross-section (default 0,0), ease=1 }."""
    o = opts or {}
    axis, k, center, ease = o.get('axis', 'z'), o.get('k', 0.7), o.get('center', [0, 0]), o.get('ease', 1)
    g = geo.clone()
    p = g.attributes.position
    g.computeBoundingBox()
    ai = {'x': 0, 'y': 1, 'z': 2}[axis]
    lo, hi = g.boundingBox.min.getComponent(ai), g.boundingBox.max.getComponent(ai)
    u, v = [i for i in (0, 1, 2) if i != ai]
    for i in range(p.count):
        a = [p.getX(i), p.getY(i), p.getZ(i)]
        t = math.pow((a[ai] - lo) / max(1e-6, hi - lo), ease)
        s = 1 + (k - 1) * t
        a[u] = center[0] + (a[u] - center[0]) * s
        a[v] = center[1] + (a[v] - center[1]) * s
        p.setXYZ(i, a[0], a[1], a[2])
    g.computeVertexNormals()
    return g


def uvRect(g, u0, v0, u1, v1):
    """Remaps a geometry's 0..1 UVs into the atlas rect [u0,v0]-[u1,v1] in place (returns it; use on your copy)."""
    uv = g.attributes.uv
    a = np.asarray(uv, dtype=np.float64)
    uv[:, 0] = u0 + a[:, 0] * (u1 - u0)
    uv[:, 1] = v0 + a[:, 1] * (v1 - v0)
    return g


def uvScale(g, su=1, sv=None):
    """Scales a geometry's UVs in place (returns it). Use on your own copies (not on cached kit/geo results)."""
    sv = su if sv is None else sv
    uv = g.attributes.uv
    if uv is None:
        return g
    a = np.asarray(uv, dtype=np.float64)
    uv[:, 0] = a[:, 0] * su
    uv[:, 1] = a[:, 1] * sv
    return g


def _jsround_arr(q):
    r = np.floor(q)
    return r + ((q - r) >= 0.5)


def weldNormals(g, eps=1e-4):
    """Averages normals of coincident vertices (removes shading seams on welded-looking shapes)."""
    p = np.asarray(g.attributes.position, dtype=np.float64)
    n = g.attributes.normal
    na = np.asarray(n, dtype=np.float64)
    keys = _jsround_arr(p / eps)
    _, inv = np.unique(keys, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1 if len(inv) else 0, 3))
    np.add.at(acc, inv, na)
    a = acc[inv]
    ln = np.sqrt(a[:, 0] * a[:, 0] + a[:, 1] * a[:, 1] + a[:, 2] * a[:, 2])
    ln[ln == 0] = 1
    s = 1 / ln
    out = np.empty_like(a)
    out[:, 0], out[:, 1], out[:, 2] = a[:, 0] * s, a[:, 1] * s, a[:, 2] * s
    n[:, :] = out
    return g


_geoCache = {}


def _cachedGeo(key, make):
    g = _geoCache.get(key)
    if g is None:
        g = make()
        g.name = key
        _geoCache[key] = g
    return g


def cushion(w, h, d, opts=None):
    """Upholstery cushion: rounded box with extra face subdivisions and a soft "puff" (faces bulge, edges stay).
    opts: { r (edge radius, default 30% of the thinnest side), puff (m, default 0.18*h), seg:[nx,ny,nz], uv, swap }"""
    opts = opts or {}
    key = 'cush|%s|%s|%s|%s' % (js_str(r3(w)), js_str(r3(h)), js_str(r3(d)), js_json(opts))

    def make():
        hx, hy, hz = w / 2, h / 2, d / 2
        r = min(opts['r'] if opts.get('r') is not None else min(w, h, d) * 0.3, hx - 1e-3, hy - 1e-3, hz - 1e-3)
        puff = opts['puff'] if opts.get('puff') is not None else h * 0.18

        def ns(s):
            return clamp(js_round(s / 0.07) + 2, 4, 12)
        nx, ny, nz = opts['seg'] if opts.get('seg') is not None else [ns(w), ns(h), ns(d)]
        g = BoxGeometry(2, 2, 2, nx, ny, nz)
        pos = g.attributes.position

        def f(t):  # denser near edges
            return _sign(t) * (0.45 * abs(t) + 0.55 * (1 - (1 - abs(t)) ** 2))
        faceMin = [min(h, d), min(w, d), min(w, h)]
        fm = max(faceMin)
        c, o = Vector3(), Vector3()
        inner = [hx - r, hy - r, hz - r]
        for i in range(pos.count):
            p = [f(pos.getX(i)) * hx, f(pos.getY(i)) * hy, f(pos.getZ(i)) * hz]
            c.set(clamp(p[0], -inner[0], inner[0]), clamp(p[1], -inner[1], inner[1]), clamp(p[2], -inner[2], inner[2]))
            o.set(p[0] - c.x, p[1] - c.y, p[2] - c.z).normalize()
            # puff along the dominant axis, fading to 0 at the edges
            a = [abs(o.x), abs(o.y), abs(o.z)]
            dom = 0 if (a[0] >= a[1] and a[0] >= a[2]) else 1 if a[1] >= a[2] else 2
            t1 = c.y / (inner[1] or 1) if dom == 0 else c.x / (inner[0] or 1)
            t2 = c.y / (inner[1] or 1) if dom == 2 else c.z / (inner[2] or 1)
            wgt = (1 - t1 * t1) * (1 - t2 * t2) * a[dom] ** 2 * (faceMin[dom] / fm)
            k = r + puff * max(0, wgt)
            pos.setXYZ(i, c.x + o.x * k, c.y + o.y * k, c.z + o.z * k)
        g.computeVertexNormals()
        weldNormals(g)
        return uvBox(g, opts['uv'], opts) if opts.get('uv') else g
    return _cachedGeo(key, make)


def _sign(t):
    return 1.0 if t > 0 else -1.0 if t < 0 else t


def roundProfile(pts, r=0.01, steps=3):
    """Rounds the interior corners of a 2D polyline ([[x,y],...]) with quadratic arcs of radius r."""
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        px, py = pts[i - 1]
        x, y = pts[i]
        nx, ny = pts[i + 1]
        l0, l1 = math.hypot(px - x, py - y), math.hypot(nx - x, ny - y)
        rr = ((r[i] if i < len(r) and r[i] is not None else 0) if isinstance(r, (list, tuple)) else r)
        d = min(rr, l0 / 2, l1 / 2)
        if d <= 1e-5:
            out.append(pts[i])
            continue
        a = [x + ((px - x) / l0) * d, y + ((py - y) / l0) * d]
        b = [x + ((nx - x) / l1) * d, y + ((ny - y) / l1) * d]
        for s in range(steps + 1):
            t = s / steps
            u = 1 - t
            out.append([u * u * a[0] + 2 * u * t * x + t * t * b[0], u * u * a[1] + 2 * u * t * y + t * t * b[1]])
    out.append(pts[-1])
    return out


def lathe(profile, opts=None):
    """Lathe around Y from a [[radius, y], ...] profile (bottom to top). opts: { seg=20, round, steps=2 }"""
    opts = opts or {}
    pts = roundProfile(profile, opts['round'], opts.get('steps', 2) if opts.get('steps') is not None else 2) \
        if opts.get('round') else profile
    return G.lathe([[max(0, x), y] for x, y in pts], opts['seg'] if opts.get('seg') is not None else 20)


def cyl(rt, rb, h, opts=None):
    """Bevelled solid cylinder / cone, BASE AT y=0 (closed caps, soft rims). opts: { bevel=0.008, seg=20 }"""
    opts = opts or {}
    b = min(opts['bevel'] if opts.get('bevel') is not None else 0.008, (rt * 0.5) or (rb * 0.5), h / 2)
    return lathe([[0, 0], [rb, 0], [rt, h], [0, h]],
                 {'round': b, 'seg': opts['seg'] if opts.get('seg') is not None else 20, 'steps': 2})


def roundRect(w, h, r=0.02):
    s = Shape()
    x, y = -w / 2, -h / 2
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    s.moveTo(x + r, y)
    s.lineTo(x + w - r, y)
    s.quadraticCurveTo(x + w, y, x + w, y + r)
    s.lineTo(x + w, y + h - r)
    s.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
    s.lineTo(x + r, y + h)
    s.quadraticCurveTo(x, y + h, x, y + h - r)
    s.lineTo(x, y + r)
    s.quadraticCurveTo(x, y, x + r, y)
    return s


def extrude(shape, depth, opts=None):
    """Extruded bevelled slab along z (centered). shape: Shape or [[x,y],...] (corners rounded by opts.round).
    Outer size equals the shape (bevel is inset), total thickness equals depth. UVs: shape meters * opts.uv."""
    opts = opts or {}
    bevel = min(opts['bevel'] if opts.get('bevel') is not None else 0.008, depth / 2 - 1e-4)
    s = shape
    if isinstance(shape, (list, tuple)):
        pts = roundProfile(list(shape) + [shape[0]], opts['round'])[:-1] if opts.get('round') else shape
        s = Shape([Vector2(x, y) for x, y in pts])
    g = ExtrudeGeometry(s, {
        'depth': max(1e-4, depth - bevel * 2), 'bevelEnabled': bevel > 0, 'bevelThickness': bevel,
        'bevelSize': bevel, 'bevelOffset': -bevel,
        'bevelSegments': opts['bevelSeg'] if opts.get('bevelSeg') is not None else 2,
        'curveSegments': opts['curveSeg'] if opts.get('curveSeg') is not None else 12,
    })
    g.translate(0, 0, -(depth - bevel * 2) / 2)
    if opts.get('uv') and opts['uv'] != 1:
        uv = g.attributes.uv
        a = np.asarray(uv, dtype=np.float64)
        uv[:, 0] = a[:, 0] * opts['uv']
        uv[:, 1] = a[:, 1] * opts['uv']
    g.computeVertexNormals()
    return g


def tube(points, r, opts=None):
    """Tube along a Catmull-Rom curve through [[x,y,z],...]. opts: { seg=24, radial=8, closed=False }"""
    opts = opts or {}
    return G.tube(points, r, opts['seg'] if opts.get('seg') is not None else 24,
                  opts['radial'] if opts.get('radial') is not None else 8, opts.get('closed') or False)


def roundRectPath(w, d, r, y=0, steps=4):
    """Closed rounded-rectangle path at height y (for piping/welt cords around cushions, rims, table edges)."""
    pts = []
    hx, hz = w / 2 - r, d / 2 - r
    corners = [[hx, hz, 0], [-hx, hz, math.pi / 2], [-hx, -hz, math.pi], [hx, -hz, math.pi * 1.5]]
    for cx, cz, a0 in corners:
        for s in range(steps + 1):
            a = a0 + (s / steps) * (math.pi / 2)
            pts.append([cx + math.cos(a) * r, y, cz + math.sin(a) * r])
    return pts


def leaf(len_=0.4, width=0.12, opts=None):
    """One leaf: pointed blade with a V fold, arching from angle a0 to a1 (radians above horizontal), growing
    along +z from the origin. opts: { a0=1.1, a1=-0.35, fold=0.35, segL=8, segW=2, tip=0.8, twist=0 }"""
    o = opts or {}
    a0, a1, fold = o.get('a0', 1.1), o.get('a1', -0.35), o.get('fold', 0.35)
    segL, segW, tip, twist = o.get('segL', 8), o.get('segW', 2), o.get('tip', 0.8), o.get('twist', 0)
    cols = segW * 2 + 1
    pos, uv, idx = [], [], []
    y = z = 0.0
    step = len_ / segL
    for i in range(segL + 1):
        s = i / segL
        a = lerp(a0, a1, s * s * 0.6 + s * 0.4)
        if i > 0:
            y += math.sin(a) * step
            z += math.cos(a) * step
        half = width * 0.5 * math.pow(math.sin(math.pi * min(1, s * (1 - 0.001)) ** tip), 0.85) * \
            (s / 0.08 * 0.4 + 0.2 if s < 0.08 else 1)
        tw = twist * s
        for j in range(cols):
            u = (j / (cols - 1)) * 2 - 1
            x = u * half
            lift = abs(u) * half * fold
            # perpendicular to the blade direction in the yz plane for the fold
            ny, nz = math.cos(a), -math.sin(a)
            pos += [x * math.cos(tw), y + lift * ny + x * math.sin(tw), z + lift * nz]
            uv += [j / (cols - 1), s]
    for i in range(segL):
        for j in range(cols - 1):
            a = i * cols + j
            b = a + 1
            c = a + cols
            d = c + 1
            idx += [a, c, b, b, c, d]
    g = Geometry()
    g.setAttribute('position', Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', Float32BufferAttribute(uv, 2))
    g.setIndex(idx)
    g.computeVertexNormals()
    return g


def leafCluster(opts=None):
    """A crown of leaves around +y (houseplants, ferns, palms). Returns ONE merged geometry with per-leaf vertex
    color variation (multiplied into bakeAO). opts: { count=9, len=[0.35,0.5], width=0.13, a0=[0.9,1.35],
    a1=[-0.5,0.1], fold, seed=1, spread=0.03 (base radius), vary=0.18 (lightness variation), tilt=0 }"""
    o = opts or {}
    count, ln, width = o.get('count', 9), o.get('len', [0.35, 0.5]), o.get('width', 0.13)
    a0, a1, fold = o.get('a0', [0.9, 1.35]), o.get('a1', [-0.5, 0.1]), o.get('fold', 0.35)
    seed, spread, vary, segL = o.get('seed', 1), o.get('spread', 0.03), o.get('vary', 0.18), o.get('segL', 8)
    rnd = mulberry32(seed * 7919 + 13)

    def rr(v):
        return lerp(v[0], v[1], rnd()) if isinstance(v, (list, tuple)) else v
    geos = []
    for i in range(count):
        ang = i * 2.39996 + rnd() * 0.4
        L, W, A0, A1 = rr(ln), rr(width), rr(a0), rr(a1)
        g = leaf(L, W, {'a0': A0, 'a1': A1, 'fold': fold, 'segL': segL, 'twist': (rnd() - 0.5) * 0.6})
        g.rotateY(ang)
        g.translate(math.sin(ang) * spread, rnd() * 0.02, math.cos(ang) * spread)
        k = 1 - vary / 2 + rnd() * vary
        tint(g, Color(k, k * (0.98 + rnd() * 0.04), k * 0.95))
        geos.append(g)
    return mergeGeometries(geos, False)


def tint(g, color):
    """Multiplies a per-vertex color into a geometry (creates the attribute). color: Color|hex|fn(x,y,z)->Color"""
    p = g.attributes.position
    col = g.attributes.color
    if col is None:
        col = BufferAttribute(np.ones((p.count, 3)), 3)
        g.setAttribute('color', col)
    if callable(color) and not getattr(color, 'isColor', False):
        pa = np.asarray(p, dtype=np.float64)
        cs = np.empty((p.count, 3))
        for i in range(p.count):
            c = color(pa[i, 0], pa[i, 1], pa[i, 2])
            c = c if getattr(c, 'isColor', False) else Color(c)
            cs[i] = (c.r, c.g, c.b)
        a = np.asarray(col, dtype=np.float64)
        col[:, 0] = a[:, 0] * cs[:, 0]
        col[:, 1] = a[:, 1] * cs[:, 1]
        col[:, 2] = a[:, 2] * cs[:, 2]
    else:
        c = Color(color) if not getattr(color, 'isColor', False) else color
        a = np.asarray(col, dtype=np.float64)
        col[:, 0] = a[:, 0] * c.r
        col[:, 1] = a[:, 1] * c.g
        col[:, 2] = a[:, 2] * c.b
    return g


def m(geo, mt, opts=None):
    """Mesh shortcut: m(geo, mat, { pos:[x,y,z], rot:[x,y,z], scale:number|[x,y,z], cast=True, receive=True, name })"""
    o = opts or {}
    me = Mesh(geo, mt)
    pos, rot, scale = o.get('pos'), o.get('rot'), o.get('scale')
    if pos is not None:
        me.position.set(pos[0], pos[1], pos[2])
    if rot is not None:
        me.rotation.set(rot[0], rot[1], rot[2])
    if scale is not None:
        if isinstance(scale, (int, float)):
            me.scale.setScalar(scale)
        else:
            me.scale.set(scale[0], scale[1], scale[2])
    me.castShadow = o.get('cast', True) if o.get('cast') is not None else True
    me.receiveShadow = o.get('receive', True) if o.get('receive') is not None else True
    if o.get('name'):
        me.name = o['name']
    return me


# ================================================================================================= baking
aoStats = JSObj(bakes=0, hits=0, verts=0, marched=0, ms=0)
NO_AO = False   # globalThis.__propkitNoAO


def _smoothstep_arr(x, lo, hi):
    out = np.empty_like(x)
    le = x <= lo
    ge = x >= hi
    t = (x - lo) / (hi - lo)
    out[:] = t * t * (3 - 2 * t)
    out[ge] = 1
    out[le] = 0
    return out


def _world_np(o, m4):
    e = m4.elements
    P = np.asarray(o.geometry.attributes.position, dtype=np.float64)[:, :3]
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15])
    px = (e[0] * x + e[4] * y + e[8] * z + e[12]) * w
    py = (e[1] * x + e[5] * y + e[9] * z + e[13]) * w
    pz = (e[2] * x + e[6] * y + e[10] * z + e[14]) * w
    return px, py, pz


def bakeAO(root, opts=None):
    """Vertex-color ambient occlusion, run once at build time on the prop's own geometry:
      (a) height band: darkens the bottom `height` meters (contact with the floor),
      (b) occlusion: `rays` cosine-weighted rays per vertex, marched through a voxelization of every opaque mesh
          in the group (+ the floor plane at floorY), weighted by hit distance.
    Colors are multiplied into existing vertex colors. Every processed mesh gets its own geometry copy.
    opts: { rays=14, dist (default 30% of the largest side, clamped 0.12..0.6), strength=0.85, height=0.22,
    heightStrength=0.35, floorY=0, floor=True, res=44, tint='#4B3A5E', skip:(mesh)=>bool }"""
    opts = opts or {}
    g = opts.get
    rays, strength, height = g('rays', 14), g('strength', 0.85), g('height', 0.22)
    heightStrength, floorY = g('heightStrength', 0.35), g('floorY', 0)
    floor = g('floor', True)
    res, tintHex, skip = g('res', 44), g('tint', '#4B3A5E'), g('skip')
    root.updateMatrixWorld(True)
    inv = Matrix4().copy(root.matrixWorld).invert()
    meshes = []
    root.traverse(lambda o: meshes.append(o) if (getattr(o, 'isMesh', False) and o.visible
                                                 and not getattr(o, 'isInstancedMesh', False)
                                                 and not getattr(o, 'isSkinnedMesh', False)) else None)
    occluders = [o for o in meshes if not (o.material.transparent or o.material.userData.noOcclude
                                           or o.userData.noOcclude)]
    targets = [o for o in meshes if o.material.vertexColors and not o.userData.noAO and not (skip and skip(o))]
    if not targets:
        return root
    tintC = Color(tintHex)
    bb = Box3()
    mtx = {}
    for o in meshes:
        if o.geometry.boundingBox is None:
            o.geometry.computeBoundingBox()
        m4 = Matrix4().multiplyMatrices(inv, o.matrixWorld)
        mtx[id(o)] = m4
        bb.union(o.geometry.boundingBox.clone().applyMatrix4(m4))
    aoStats.bakes += 1
    shades = _bakeShades(opts, bb, occluders, targets, mtx, rays, strength, height, heightStrength, floorY, floor,
                         res)
    tr, tg, tb = tintC.r, tintC.g, tintC.b
    out = []
    for ti, o in enumerate(targets):
        gg = o.geometry.clone()
        if gg.attributes.normal is None:
            gg.computeVertexNormals()
        pos = gg.attributes.position
        ca = gg.attributes.color
        if ca is None:
            ca = BufferAttribute(np.ones((pos.count, 3)), 3)
            gg.setAttribute('color', ca)
        S = shades[ti]
        a = np.asarray(ca, dtype=np.float64)
        ca[:, 0] = a[:, 0] * (tr + (1 - tr) * S)
        ca[:, 1] = a[:, 1] * (tg + (1 - tg) * S)
        ca[:, 2] = a[:, 2] * (tb + (1 - tb) * S)
        out.append(gg)
        aoStats.verts += pos.count
    for ti, o in enumerate(targets):
        o.geometry = out[ti]
    return root


def _bakeShades(opts, bb, occluders, targets, mtx, rays, strength, height, heightStrength, floorY, floor, res):
    size = bb.getSize(Vector3())
    maxDim = max(size.x, size.y, size.z, 0.05)
    cell = maxDim / res
    dist = opts['dist'] if opts.get('dist') is not None else clamp(maxDim * 0.3, 0.12, 0.6)
    o0 = bb.min.clone().subScalar(cell * 2)
    ox, oy, oz = o0.x, o0.y, o0.z
    nx = math.ceil(size.x / cell) + 5
    ny = math.ceil(size.y / cell) + 5
    nz = math.ceil(size.z / cell) + 5
    vox = np.zeros(nx * ny * nz, dtype=np.uint8)
    _voxelize(vox, occluders, mtx, ox, oy, oz, cell, nx, ny, nz)
    # cosine-weighted hemisphere directions (tangent space, z = normal), max ~72deg off-normal
    dirs = []
    for i in range(rays):
        u = (i + 0.5) / rays
        phi = i * 2.39996
        r = math.sqrt(u) * 0.95
        dirs.append((math.cos(phi) * r, math.sin(phi) * r, math.sqrt(1 - r * r)))
    start, step = cell * 2.1, cell * 0.75
    ts = []
    t = start
    while t < dist:
        ts.append(t)
        t += step
    fl, hasH, fy1 = bool(floor), height > 0, floorY + height
    shades = []
    for o in targets:
        geo = o.geometry
        nor = geo.attributes.normal
        pos = geo.attributes.position
        if nor is None:  # same normals the caller's clone will compute
            g2 = Geometry()
            g2.setAttribute('position', pos)
            if geo.index is not None:
                g2.setIndex(geo.index)
            g2.computeVertexNormals()
            nor = g2.attributes.normal
        m4 = mtx[id(o)]
        e = m4.elements
        ne = Matrix3().getNormalMatrix(m4).elements
        L = np.concatenate([np.asarray(pos, dtype=np.float64)[:, :3], np.asarray(nor, dtype=np.float64)[:, :3]], 1)
        count = len(L)
        S = np.zeros(count)
        if count == 0:
            shades.append(S)
            continue
        # equal (local position, normal) -> equal shade: march each distinct vertex once
        Lu, inv = np.unique(L, axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        aoStats.marched += len(Lu)
        x, y, z = Lu[:, 0], Lu[:, 1], Lu[:, 2]
        w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15])
        px = (e[0] * x + e[4] * y + e[8] * z + e[12]) * w
        py = (e[1] * x + e[5] * y + e[9] * z + e[13]) * w
        pz = (e[2] * x + e[6] * y + e[10] * z + e[14]) * w
        lx, ly, lz = Lu[:, 3], Lu[:, 4], Lu[:, 5]
        nX = ne[0] * lx + ne[3] * ly + ne[6] * lz
        nY = ne[1] * lx + ne[4] * ly + ne[7] * lz
        nZ = ne[2] * lx + ne[5] * ly + ne[8] * lz
        ln = np.sqrt(nX * nX + nY * nY + nZ * nZ)
        ln = np.where(ln == 0, 1.0, ln)   # || 1 (NaN stays NaN like the JS)
        s = 1 / ln
        nX, nY, nZ = nX * s, nY * s, nZ * s
        flip = ~(np.abs(nY) < 0.9)
        ux = np.where(flip, 1.0, 0.0)
        uy = np.where(flip, 0.0, 1.0)
        uz = 0.0
        aX = uy * nZ - uz * nY
        aY = uz * nX - ux * nZ
        aZ = ux * nY - uy * nX
        la = np.sqrt(aX * aX + aY * aY + aZ * aZ)
        la = np.where(la == 0, 1.0, la)
        s = 1 / la
        aX, aY, aZ = aX * s, aY * s, aZ * s
        bX, bY, bZ = nY * aZ - nZ * aY, nZ * aX - nX * aZ, nX * aY - nY * aX
        occ = np.zeros(len(Lu))
        wsum = 0.0
        for X, Y, Z in dirs:
            dx = 0 + aX * X + bX * Y + nX * Z
            dy = 0 + aY * X + bY * Y + nY * Z
            dz = 0 + aZ * X + bZ * Y + nZ * Z
            wsum += Z  # cosine weight
            contrib = np.zeros(len(Lu))
            alive = np.ones(len(Lu), dtype=bool)
            for t in ts:
                idx = np.nonzero(alive)[0]
                if not len(idx):
                    break
                qy = py[idx] + dy[idx] * t
                val = Z * (1 - (t / dist) * 0.6)
                if fl:
                    hitf = qy < floorY
                    if hitf.any():
                        hi = idx[hitf]
                        contrib[hi] = val
                        alive[hi] = False
                        keep = ~hitf
                        idx, qy = idx[keep], qy[keep]
                ix = np.floor((px[idx] + dx[idx] * t - ox) / cell)
                iy = np.floor((qy - oy) / cell)
                iz = np.floor((pz[idx] + dz[idx] * t - oz) / cell)
                out = (ix < 0) | (iy < 0) | (iz < 0) | (ix >= nx) | (iy >= ny) | (iz >= nz) | np.isnan(ix) | \
                    np.isnan(iy) | np.isnan(iz)
                if out.any():
                    alive[idx[out]] = False
                    keep = ~out
                    idx, ix, iy, iz = idx[keep], ix[keep], iy[keep], iz[keep]
                if len(idx):
                    lin = (ix + nx * (iy + ny * iz)).astype(np.int64)
                    hv = vox[lin] != 0
                    if hv.any():
                        hi = idx[hv]
                        contrib[hi] = val
                        alive[hi] = False
            occ = occ + contrib
        occ = occ / wsum if wsum > 0 else occ * 0
        if hasH:
            hk = 1 - _smoothstep_arr(py, floorY, fy1)
        else:
            hk = np.zeros(len(Lu))
        Su = np.clip((1 - occ * strength) * (1 - hk * heightStrength), 0.12, 1)
        S = Su[inv]
        shades.append(S)
    return shades


_GRIDS = {}


def _grid(n):
    gr = _GRIDS.get(n)
    if gr is None:
        nd = max(1, n)
        us, vs = [], []
        for i in range(n + 1):
            u = i / nd
            for j in range(n - i + 1):
                us.append(u)
                vs.append(j / nd)
        u = np.array(us)
        v = np.array(vs)
        w0 = 1 - u - v
        gr = (u, v, w0)
        _GRIDS[n] = gr
    return gr


def _voxelize(vox, occluders, mtx, ox, oy, oz, cell, nx, ny, nz):
    """Marks every voxel that holds a sample of an occluder triangle (dense barycentric sampling, <= 60 steps per
    edge)."""
    c06 = cell * 0.6
    for o in occluders:
        px, py, pz = _world_np(o, mtx[id(o)])
        vc = len(px)
        idx = o.geometry.index
        if idx is not None:
            tri = np.asarray(idx, dtype=np.int64).reshape(-1)[:(idx.count // 3) * 3].reshape(-1, 3)
        else:
            tri = np.arange((vc // 3) * 3, dtype=np.int64).reshape(-1, 3)
        tri = tri[(tri < vc).all(axis=1)]
        if not len(tri):
            continue
        a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
        ax, ay, az = px[a], py[a], pz[a]
        bx, by, bz = px[b], py[b], pz[b]
        cx, cy, cz = px[c], py[c], pz[c]
        dx, dy, dz = ax - bx, ay - by, az - bz
        dab = np.sqrt(dx * dx + dy * dy + dz * dz)
        dx, dy, dz = bx - cx, by - cy, bz - cz
        dbc = np.sqrt(dx * dx + dy * dy + dz * dz)
        dx, dy, dz = cx - ax, cy - ay, cz - az
        dca = np.sqrt(dx * dx + dy * dy + dz * dz)
        mx = np.maximum(np.maximum(dab, dbc), dca)
        with np.errstate(invalid='ignore'):
            nn = np.ceil(mx / c06)
        valid = ~np.isnan(nn)
        nn = np.where(valid, np.minimum(60, nn), -1).astype(np.int64)
        for n in np.unique(nn):
            if n < 0:
                continue
            sel = np.nonzero(nn == n)[0]
            u, v, w0 = _grid(int(n))
            for chunk in range(0, len(sel), max(1, 400000 // len(u))):
                s = sel[chunk:chunk + max(1, 400000 // len(u))]
                IX = np.floor((0 + ax[s, None] * w0 + bx[s, None] * u + cx[s, None] * v - ox) / cell)
                IY = np.floor((0 + ay[s, None] * w0 + by[s, None] * u + cy[s, None] * v - oy) / cell)
                IZ = np.floor((0 + az[s, None] * w0 + bz[s, None] * u + cz[s, None] * v - oz) / cell)
                ok = (IX >= 0) & (IX < nx) & (IY >= 0) & (IY < ny) & (IZ >= 0) & (IZ < nz)
                lin = (IX[ok] + nx * (IY[ok] + ny * IZ[ok])).astype(np.int64)
                vox[lin] = 1


# ================================================================================================= result
def prop(id, fields=None):
    """Creates the prop root with the convention userData. Any field can be filled later (finish() fills gaps)."""
    g = Group()
    g.name = 'prop:%s' % id
    u = JSObj(id=id, size=None, colliders=None, screens=[], lightAnchors=[], parts=JSObj(), interact=None)
    for k, v in (fields or {}).items():
        u[k] = v
    g.userData = u
    return g


def finish(game, group, opts=None):
    """Final pass every builder should call: toon materials -> vertexColors variants, bakeAO, merge static meshes
    per material (parts under userData.noMerge stay separate), shadow flags, size/colliders defaults, screens
    collected from meshes flagged as screens, stats. opts: { ao=True | aoOpts, merge=True, cast=0.3 }"""
    opts = opts or {}
    ao = opts.get('ao', True)
    doMerge = opts.get('merge', True)
    cast = opts.get('cast', 0.3)

    def to_vc(o):
        if getattr(o, 'isMesh', False) and o.material is not None and getattr(o.material, 'userData', None) \
                and o.material.userData.daToon and not o.material.vertexColors:
            o.material = game.mats.variant(o.material, {'vertexColors': True})
    group.traverse(to_vc)
    if ao and not NO_AO:
        bakeAO(group, ao if isinstance(ao, dict) else {})

    # colors must exist wherever vertexColors are on (else the vertex color reads black)
    def ensure_col(o):
        if getattr(o, 'isMesh', False) and o.material is not None and o.material.vertexColors \
                and o.geometry.attributes.color is None:
            o.geometry = o.geometry.clone()
            o.geometry.setAttribute('color', BufferAttribute(np.ones((o.geometry.attributes.position.count, 3)), 3))
    group.traverse(ensure_col)
    u = group.userData
    u.screens = _or(u.screens, [])

    def scr(o):
        if getattr(o, 'isMesh', False) and o.userData.screenGroup and not any(s.get('mesh') is o for s in u.screens):
            u.screens.append(JSObj(mesh=o, group=o.userData.screenGroup))
    group.traverse(scr)
    if doMerge:
        merge(group)
    sz = Vector3()

    def shadows(o):
        if not getattr(o, 'isMesh', False):
            return
        if o.geometry.boundingBox is None:
            o.geometry.computeBoundingBox()
        o.geometry.boundingBox.getSize(sz)
        o.castShadow = (not o.userData.noShadow) and o.material.type != 'ShaderMaterial' and \
            not o.material.transparent and max(sz.x, sz.y, sz.z) >= cast
        o.receiveShadow = True
    group.traverse(shadows)
    bb = box_from_object(group)
    # setFromObject is in world space; props are built at the origin, so treat it as local.
    if not _truthy(u.size):
        bb.getSize(sz)
        u.size = [r3(sz.x), r3(sz.y), r3(sz.z)]
    if not _truthy(u.colliders):
        u.colliders = [JSObj(min=[r3(bb.min.x), 0, r3(bb.min.z)], max=[r3(bb.max.x), r3(bb.max.y), r3(bb.max.z)])]
    u.lightAnchors = _or(u.lightAnchors, [])
    u.parts = _or(u.parts, JSObj())
    if 'interact' not in u:
        u.interact = None
    u.stats = stats(group)
    return group


# ---------------------------------------------------------------------------------------- mergeByMaterial
def _blocked(o, root):
    p = o
    while p is not None and p is not root:
        if p.userData.dynamic or p.userData.noMerge:
            return True
        p = p.parent
    return False


def _prepare(mesh, wantColor, inv):
    src = mesh.geometry
    g = Geometry()
    count = src.attributes.position.count
    g.setAttribute('position', src.attributes.position.clone())
    if src.attributes.normal is not None:
        g.setAttribute('normal', src.attributes.normal.clone())
    g.setAttribute('uv', src.attributes.uv.clone() if src.attributes.uv is not None
                   else BufferAttribute(np.zeros((count, 2)), 2))
    if wantColor:
        g.setAttribute('color', src.attributes.color.clone() if src.attributes.color is not None
                       else BufferAttribute(np.ones((count, 3)), 3))
    if src.index is not None:
        g.setIndex(src.index.clone())
    else:
        g.setIndex(list(range(count)))
    if g.attributes.normal is None:
        g.computeVertexNormals()
    mm = Matrix4().multiplyMatrices(inv, mesh.matrixWorld)
    g.applyMatrix4(mm)
    if mm.determinant() < 0:
        # Mirrored transform: restore winding so faces stay front-facing.
        idx = np.asarray(g.index, dtype=np.int64).reshape(-1, 3)
        g.setIndex(idx[:, [0, 2, 1]].reshape(-1).tolist())
    return g


def merge(root):
    """G.mergeByMaterial: one mesh per (material, shadow flags, layers, renderOrder) under root. Meshes flagged
    userData.dynamic / noMerge (or under such an ancestor), meshes with children, instanced / skinned / morphing
    meshes are left alone. Returns the number of source meshes merged away."""
    root.updateMatrixWorld(True)
    inv = Matrix4().copy(root.matrixWorld).invert()
    groups = {}
    order = []

    def visit(o):
        if o is root or not getattr(o, 'isMesh', False) or getattr(o, 'isInstancedMesh', False) \
                or getattr(o, 'isSkinnedMesh', False):
            return
        if isinstance(o.material, list) or len(o.children) or not o.visible or o.morphTargetInfluences:
            return
        if _blocked(o, root):
            return
        key = (o.material.uuid, o.castShadow, o.receiveShadow, o.layers.mask, o.renderOrder)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(o)
    root.traverse(visit)
    merged = 0
    for key in order:
        lst = groups[key]
        if len(lst) < 2:
            continue
        src = lst[0]
        geos = [_prepare(mm, bool(src.material.vertexColors), inv) for mm in lst]
        g = mergeGeometries(geos, False)
        if g is None:
            continue
        g.computeBoundingSphere()
        out = Mesh(g, src.material)
        out.name = 'merged:%s' % (src.material.name or src.material.type)
        out.castShadow = src.castShadow
        out.receiveShadow = src.receiveShadow
        out.layers.mask = src.layers.mask
        out.renderOrder = src.renderOrder
        root.add(out)
        for mm in lst:
            mm.parent.remove(mm)
        merged += len(lst)
    return merged


def stats(group):
    """{ tris, meshes, mats } for budgets (typical prop <= 3k tris, hero <= 12k, <= 3 materials when possible)."""
    tris = 0.0
    meshes = 0
    mats = set()

    def f(o):
        nonlocal tris, meshes
        if not getattr(o, 'isMesh', False):
            return
        meshes += 1
        mats.add(o.material.uuid)
        g = o.geometry
        tris += (g.index.count if g.index is not None else g.attributes.position.count) / 3
    group.traverse(f)
    return JSObj(tris=js_round(tris), meshes=meshes, mats=len(mats))
