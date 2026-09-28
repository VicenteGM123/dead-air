"""Face attachments for baked characters — Blender-side port of src/art/face.js makeAttachBuilder (+ eyeTexture).

    b = makeAttachBuilder(ctx)   -> builder passed to def.attachments(b, ctx):
      b.eyes(EYE)                 eyeballs (canvas iris texture, catchlights), upper/lower lids with lash lines
      b.aviators(o) / b.glasses(o) glasses (frames + lenses)        b.hoops(o) earrings
      b.mesh(joint, geometry, material, O(pos, rot, scale, name, cast))  any rigid mesh on a joint (joint-local)
      b.mat(opts) (attachMaterial spec)  b.joint(name)  b.THREE (dalib.three_geo + the dalib scene graph classes)
The objects are built on a light three.js-like scene graph (dalib/scene.py) whose joints sit in the BIND pose; the
exporter (chars/build.py) places every top-level attachment in bind-pose model space with its joint + local
transform (FORMAT.md §5). The FaceController itself is runtime code (Godot): the builder records the eye nodes.
"""
import json
import math
import os
import sys

import numpy as np

_BL = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _BL not in sys.path:
    sys.path.insert(0, _BL)

from dalib import three_geo as T3            # noqa: E402
from dalib import scene as SG                # noqa: E402
from dalib.canvas2d import Canvas            # noqa: E402
from dalib import tex as dtex                # noqa: E402

from .jsutil import O, nz                    # noqa: E402

REPO = os.path.abspath(os.path.join(_BL, '..'))
TEX_DIR = os.path.join(REPO, 'godot', 'assets', 'chars', 'tex')
TEX_RES = 'res://assets/chars/tex'


class CharTexture(dtex.Texture):
    """Canvas texture of a character attachment: PNG in godot/assets/chars/tex/."""

    def res_path(self):
        return '%s/%s' % (TEX_RES, self.file_name())


def texture_file(t):
    if t is None or getattr(t, 'image', None) is None:
        return None
    p = dtex.texture_file(t, out_dir=TEX_DIR)
    if p is None:
        return None
    return p[0], '%s/%s' % (TEX_RES, os.path.basename(p[0]))


class _ThreeNS:
    """b.THREE: three.js namespace for attachment code (geometries/curves/math from dalib.three_geo, scene graph
    classes from dalib.scene, material/texture stand-ins)."""

    def __getattr__(self, k):
        if hasattr(SG, k):
            return getattr(SG, k)
        return getattr(T3, k)


THREE = _ThreeNS()

_texCache = {}


def _col(hexv):
    c = T3.Color(hexv)
    return np.array([c.r, c.g, c.b])


def eyeTexture(o):
    """Equirect eyeball texture: rows = polar angle from the +y pole (the iris sits on the pole)."""
    key = json.dumps(o, sort_keys=False, separators=(',', ':'), default=str)
    if key in _texCache:
        return _texCache[key]
    W, H = 512, 256
    cv = Canvas(W, H)
    g = cv.getContext('2d')
    img = g.createImageData(W, H)
    iris = _col(o.get('iris') or '#5A3420')
    irisLight = iris + (_col('#E8C070') - iris) * 0.35
    irisDark = iris * 0.35
    sclera = _col(o.get('sclera') or '#FBF6EE')
    scleraBack = _col('#E8C8C0')
    pupil = _col('#0E0A0C')
    irisSize = nz(o.get('irisSize'), 0.56)
    aI = math.asin(min(0.95, irisSize))
    aP = math.asin(min(0.9, irisSize * nz(o.get('pupilSize'), 0.42)))
    y = np.arange(H)
    x = np.arange(W)
    phi = ((y + 0.5) / H * math.pi)[:, None] * np.ones((1, W))
    lam = (x / W * math.pi * 2)[None, :] * np.ones((H, 1))
    c = np.zeros((H, W, 3))
    # iris
    t = (phi - aP) / (aI - aP)
    stri = 0.5 + 0.5 * np.sin(lam * 38 + np.sin(lam * 7) * 2) * np.sin(lam * 13 + 1.3)
    ci = irisLight + (iris - irisLight) * np.minimum(1, t * 1.3)[..., None]
    ci = ci + (irisDark - ci) * (np.power(np.maximum(t, 0), 3) * 0.9)[..., None]
    ci = ci * (0.85 + 0.3 * stri * (1 - t * 0.6))[..., None]
    small = t < 0.12
    ci = np.where(small[..., None], ci + (pupil - ci) * ((0.12 - t) / 0.12 * 0.6)[..., None], ci)
    # sclera
    ts = np.minimum(1, (phi - aI) / (math.pi * 0.6))
    cs = sclera + (scleraBack - sclera) * (np.power(np.maximum(ts, 0), 1.5) * 0.6)[..., None]
    edge = np.maximum(0, 1 - (phi - aI) / 0.08)
    cs = cs + (irisDark - cs) * (edge * 0.35)[..., None]
    c = np.where((phi < aP)[..., None], pupil, np.where((phi < aI)[..., None], ci, cs))
    out = np.floor(np.power(np.minimum(1, c), 1 / 2.2) * 255 + 0.5)
    data = np.zeros((H, W, 4), np.uint8)
    data[..., :3] = out.astype(np.uint8)
    data[..., 3] = 255
    img.data[:] = data.reshape(-1)
    g.putImageData(img, 0, 0)
    tx = CharTexture(cv, 'eye|' + key, repeat=False, ns='ch')
    tx.anisotropy = 4
    _texCache[key] = tx
    return tx


class AttachMat(SG.Material):
    pass


def attachMaterial(o):
    """charMaterial.attachMaterial(opts) -> dalib Material kind 'attach' (the Godot runtime builds the shader)."""
    o = dict(o)
    tex = o.pop('map', None)
    for k in ('globals', 'envMap'):
        o.pop(k, None)
    color = o.get('color') or '#ffffff'
    opts = {k: v for k, v in o.items() if k != 'color'}
    if 'side' in opts and isinstance(opts['side'], str):
        opts['side'] = {'front': 0, 'back': 1, 'double': 2}[opts['side']]
    m = SG.Material('attach', color if isinstance(color, str) else '#' + T3.Color(color).getHexString(), opts,
                    type='MeshPhysicalMaterial' if o.get('physical') else 'MeshStandardMaterial', map=tex,
                    transparent=bool(o.get('transparent')), opacity=nz(o.get('opacity'), 1),
                    side=opts.get('side', 0), vertexColors=bool(o.get('vertexColors')),
                    depthWrite=nz(o.get('depthWrite'), not o.get('transparent')))
    m.roughness = nz(o.get('rough'), 0.5)
    m.metalness = nz(o.get('metal'), 0)
    m._snap = m._tracked()
    return m


def basicMaterial(o):
    """THREE.MeshBasicMaterial -> dalib Material kind 'basic'."""
    o = dict(o)
    tex = o.pop('map', None)
    col = o.get('color', '#ffffff')
    if isinstance(col, T3.Color):
        hexv = '#' + col.getHexString()
        if max(col.r, col.g, col.b) > 1:
            o['color'] = [col.r, col.g, col.b]
        else:
            o['color'] = hexv
    else:
        hexv = col
    m = SG.Material('basic', hexv if isinstance(hexv, str) else '#ffffff', o, type='MeshBasicMaterial', map=tex,
                    transparent=bool(o.get('transparent')), opacity=nz(o.get('opacity'), 1),
                    depthWrite=nz(o.get('depthWrite'), True), toneMapped=nz(o.get('toneMapped'), True),
                    side=o.get('side', 0))
    m._snap = m._tracked()
    return m


def makeAttachBuilder(ctx):
    """ctx: O(joints {name: dalib Group in bind pose}, rimColor, face (records eyes))."""
    joints = ctx.joints
    face = ctx.face
    rimColor = ctx.rimColor

    def mat(o=None, **kw):
        oo = dict(o or {})
        oo.update(kw)
        base = {'rimColor': rimColor}
        base.update(oo)
        return attachMaterial(base)

    b = O()
    b.THREE = THREE
    b.joint = lambda n: joints[n]
    b.mat = mat

    def mesh(joint, geo, material, o=None):
        o = O(o or {})
        m = SG.Mesh(geo, material)
        if o.pos:
            m.position.set(*o.pos)
        if o.rot:
            m.rotation.set(*o.rot)
        if o.scale:
            if isinstance(o.scale, (int, float)):
                m.scale.setScalar(o.scale)
            else:
                m.scale.set(*o.scale)
        m.name = o.name or 'attach'
        m.castShadow = nz(o.cast, True)
        (joints[joint] if isinstance(joint, str) else joint).add(m)
        return m
    b.mesh = mesh

    def eyes(E):
        tex = eyeTexture(E)
        eyeMat = mat(map=tex, rough=0.12, envIntensity=0.6, rim=0.12, wrap=0.3, physical=True, clearcoat=1, clearcoatRough=0.04)
        # lids are seen at grazing angles: no fresnel rim (it made them glow white), soft skin shading
        lidMat = mat(color=E.lid, rough=0.55, sss=0.6, wrap=0.6, rim=0.02)
        lashMat = mat(color=E.lash or '#2A1A14', rough=0.6, rim=0.05)
        gl = nz(E.glint, 1)   # catchlight size scale (STYLE_GUIDE §4: one large + one small catchlight)
        glint = basicMaterial({'color': T3.Color(1.2, 1.2, 1.16), 'toneMapped': False, 'transparent': True, 'opacity': 0.95, 'depthWrite': False})
        r = E.r
        for s in (1, -1):
            side = 'L' if s > 0 else 'R'
            root = SG.Group()
            root.name = 'eye' + side
            # head-local: EYE.x is |x|; joints mirror: L is -x.
            root.position.set(-s * E.x, E.y, E.z)
            root.rotation.set(0, -s * nz(E.yaw, 0.08), -s * nz(E.tilt, 0))
            joints['head'].add(root)
            ball = SG.Group()
            ball.name = 'eye' + side + '_ball'
            root.add(ball)
            sph = SG.Mesh(T3.SphereGeometry(r, 40, 28), eyeMat)
            sph.rotation.x = -math.pi / 2   # iris pole -> forward (-z)
            sph.castShadow = False
            sph.name = 'eye' + side + '_sphere'
            ball.add(sph)
            # catchlights (fixed in head space)
            g1 = SG.Mesh(T3.CircleGeometry(r * 0.2 * gl, 18), glint)
            pos = T3.Vector3(0.36, 0.42, -1).normalize().multiplyScalar(r * 1.005)
            g1.position.copy(pos)
            g1.lookAt(pos.clone().multiplyScalar(3))
            g1.renderOrder = 2
            g1.name = 'eye' + side + '_glint1'
            root.add(g1)
            g2 = SG.Mesh(T3.CircleGeometry(r * 0.09 * gl, 12), glint)
            pos2 = T3.Vector3(-0.28, -0.2, -1).normalize().multiplyScalar(r * 1.005)
            g2.position.copy(pos2)
            g2.lookAt(pos2.clone().multiplyScalar(3))
            g2.renderOrder = 2
            g2.name = 'eye' + side + '_glint2'
            root.add(g2)
            # lids: caps around +y (upper) / -y (lower), rotated about x
            lr = r * nz(E.lidScale, 1.06)
            cap = math.pi * 0.53
            upper = SG.Group()
            upper.name = 'eye' + side + '_upper'
            ug = SG.Mesh(T3.SphereGeometry(lr, 36, 14, 0, math.pi * 2, 0, cap), lidMat)
            ug.name = 'eye' + side + '_upperLid'
            upper.add(ug)
            lashU = SG.Mesh(T3.TorusGeometry(lr * math.sin(cap), r * 0.075, 6, 32, math.pi * 1.1), lashMat)
            lashU.position.y = lr * math.cos(cap)
            lashU.rotation.set(math.pi / 2, 0, math.pi * 0.95 - math.pi * 0.5 * 1.1 + math.pi * 0.5)
            lashU.name = 'eye' + side + '_lash'
            upper.add(lashU)
            root.add(upper)
            lower = SG.Group()
            lower.name = 'eye' + side + '_lower'
            lg = SG.Mesh(T3.SphereGeometry(lr * 0.995, 36, 12, 0, math.pi * 2, math.pi - cap, cap), lidMat)
            lg.name = 'eye' + side + '_lowerLid'
            lower.add(lg)
            root.add(lower)
            for mm in (ug, lg, lashU):
                mm.castShadow = False
            face.addEye(O(side=side, root=root, ball=ball, upper=upper, lower=lower, cap=cap, E=E))
    b.eyes = eyes

    def aviators(o):
        """Aviators: teardrop rims (gold tube), gradient-tinted lenses, double bridge, temples to the ears."""
        o = O(o)
        E = o.eye
        frameMat = mat(color=o.frame or '#E3B04B', metal=1, rough=0.32, envIntensity=0.6, rim=0.06)
        # Low-opacity tinted lenses (STYLE_GUIDE §4: the eyes must stay visible) with a soft reflection, no glow.
        lensMat = mat(color='#ffffff', vertexColors=True, rough=0.1, transparent=True, opacity=nz(o.lensOpacity, 0.32),
                      envIntensity=nz(o.lensEnv, 0.45), rim=nz(o.lensRim, 0.06), rimColor='#FFE0B0', side='double')
        w, h = nz(o.w, 0.05), nz(o.h, 0.042)
        zf = nz(o.z, E.z - E.r - 0.018)
        cy0 = E.y - 0.004 + nz(o.dy, 0)   # dy < 0: aviators sit lower on the nose (brows stay visible)
        bar = nz(o.barR, max(0.0024, nz(o.rimR, 0.0027) * 0.9))
        cTop = T3.Color(o.lensTop or o.lens or '#E4501A')
        cBot = T3.Color(o.lens or '#FF7A2E').lerp(T3.Color('#FFD0A0'), 0.35)
        # Outline for the lens on the +x side (local x: + = toward the temple)
        outline = []
        for i in range(48):
            t = (i / 48) * math.pi * 2
            c, sn = math.cos(t), math.sin(t)
            if o.shape == 'round':
                x, y = c * w, sn * h
            elif o.shape == 'teardrop':
                # classic aviator teardrop: straight top bar with rounded corners, deep round bottom whose lowest point
                # sits toward the OUTER side (o.drop, default 0.22): the lens leans out like a drop
                drop = nz(o.drop, 0.22)
                if sn >= 0:
                    x = math.copysign(1, c) * math.pow(abs(c), 2 / 3.6) * w if c != 0 else 0.0
                    y = math.pow(sn, 2 / 3.6) * h * 0.74
                else:
                    x = (math.copysign(1, c) * math.pow(abs(c), 2 / 2.3) * w if c != 0 else 0.0) + drop * 0.35 * w * -sn * (1 - abs(c))
                    y = -math.pow(-sn, 2 / 2.3) * h * (1 + drop * c * 0.9)
            else:
                # aviator teardrop: squarish flat top (superellipse), round bottom dropping lower toward the nose side
                top = sn > 0
                e = 3.2 if top else 2.1
                x = (math.copysign(1, c) * math.pow(abs(c), 2 / e) * w) if c != 0 else 0.0
                y = (math.copysign(1, sn) * math.pow(abs(sn), 2 / e) * h) if sn != 0 else 0.0
                if top:
                    y *= 0.8 + 0.06 * max(0, -c)
                else:
                    y *= 1.08 + 0.12 * max(0, -c) - 0.1 * max(0, c)
            outline.append([x, y])

        def place(s, x, y):
            # s = +1 lens on +x side. lens center, curved back toward the temples
            cx, cy = s * (E.x + 0.004), cy0
            xo = x  # + toward temple
            z = zf + 2.6 * max(0, xo) * max(0, xo) + 0.35 * max(0, -xo) * max(0, -xo) + 0.06 * xo
            return T3.Vector3(cx + s * x, cy + y, z)
        for s in (1, -1):
            P3 = [place(s, x, y) for x, y in outline]
            mesh('head', T3.TubeGeometry(T3.CatmullRomCurve3(P3, True, 'centripetal'), 96, nz(o.rimR, 0.0027), 8, True), frameMat, O(name='aviatorRim'))
            # lens: fan triangulation of the outline with vertex-color gradient
            pos, col, idx = [], [], []
            c = place(s, 0, 0)
            pos += [c.x, c.y, c.z + 0.0005]
            cm = cTop.clone().lerp(cBot, 0.5)
            col += [cm.r, cm.g, cm.b]
            for x, y in outline:
                p = place(s, x * 0.99, y * 0.99)
                pos += [p.x, p.y, p.z + 0.0005]
                k = min(1, max(0, 0.5 - y / (2.4 * h)))
                cc = cTop.clone().lerp(cBot, k)
                col += [cc.r, cc.g, cc.b]
            for i in range(len(outline)):
                idx += [0, 1 + i, 1 + ((i + 1) % len(outline))]
            lg = T3.Geometry()
            lg.setAttribute('position', T3.Float32BufferAttribute(pos, 3))
            lg.setAttribute('color', T3.Float32BufferAttribute(col, 3))
            lg.setIndex(idx)
            lg.computeVertexNormals()
            lens = mesh('head', lg, lensMat, O(name='aviatorLens', cast=False))
            lens.renderOrder = 3
            # temple arm from the upper outer corner to behind the ear
            tA = place(s, w * 0.96, h * 0.45)
            tB = T3.Vector3(s * nz(o.templeX, 0.155), cy0 + 0.01 + h * 0.3, zf + 0.05)
            tC = T3.Vector3(s * (nz(o.templeX, 0.155) - 0.004), cy0 + h * 0.2, E.z + nz(o.earZ, 0.1))
            mesh('head', T3.TubeGeometry(T3.CatmullRomCurve3([tA, tB, tC]), 16, bar, 6), frameMat, O(name='aviatorTemple'))
        # double bridge (brow bar + nose bridge)
        def L(x, y):
            return place(-1, x, y)

        def Rr(x, y):
            return place(1, x, y)
        top = T3.CatmullRomCurve3([L(-w * 0.62, h * 0.74), T3.Vector3(0, cy0 + h * 0.86, zf - 0.004), Rr(-w * 0.62, h * 0.74)])
        mesh('head', T3.TubeGeometry(top, 20, bar, 6), frameMat, O(name='aviatorBridge'))
        low = T3.CatmullRomCurve3([L(-w * 0.98, h * 0.2), T3.Vector3(0, cy0 + h * 0.34, zf - 0.007), Rr(-w * 0.98, h * 0.2)])
        mesh('head', T3.TubeGeometry(low, 20, bar * 1.08, 6), frameMat, O(name='aviatorBridge2'))
    b.aviators = aviators

    def glasses(o):
        """Round/square glasses (Skip, Penny): o = { eye, shape:'round'|'square', color, thick, w, h, z }"""
        o = O(o)
        E = o.eye
        frameMat = mat(color=o.color or '#1E1624', rough=0.3, rim=0.2)
        glassMat = mat(color='#EAF4FF', rough=0.03, transparent=True, opacity=0.14, envIntensity=1.5, rim=0.6, rimColor='#FFFFFF', side='double')
        zf = nz(o.z, E.z - E.r - 0.02)
        w, h, t = nz(o.w, 0.05), nz(o.h, 0.045), nz(o.thick, 0.006)
        for s in (1, -1):
            cx = -s * E.x
            shape = T3.Shape()
            if o.shape == 'square':
                r = min(w, h) * 0.35
                shape.moveTo(-w + r, -h)
                shape.lineTo(w - r, -h)
                shape.quadraticCurveTo(w, -h, w, -h + r)
                shape.lineTo(w, h - r)
                shape.quadraticCurveTo(w, h, w - r, h)
                shape.lineTo(-w + r, h)
                shape.quadraticCurveTo(-w, h, -w, h - r)
                shape.lineTo(-w, -h + r)
                shape.quadraticCurveTo(-w, -h, -w + r, -h)
            else:
                shape.absellipse(0, 0, w, h, 0, math.pi * 2)
            hole = T3.Path([p.clone().multiplyScalar((min(w, h) - t) / min(w, h)) for p in shape.getPoints(32)])
            shape.holes.append(hole)
            g = T3.ExtrudeGeometry(shape, {'depth': t * 0.9, 'bevelEnabled': True, 'bevelThickness': t * 0.3, 'bevelSize': t * 0.25, 'bevelSegments': 2, 'curveSegments': 24})
            mesh('head', g, frameMat, O(pos=[cx, E.y, zf - t * 0.45], name='glassesFrame'))
            lens = mesh('head', T3.ShapeGeometry(T3.Shape(hole.getPoints(32)), 16), glassMat, O(pos=[cx, E.y, zf], cast=False, name='glassesLens'))
            lens.renderOrder = 3
            tA = T3.Vector3(cx - s * w, E.y + h * 0.4, zf)
            tC = T3.Vector3(-s * nz(o.templeX, 0.13), E.y, E.z + 0.1)
            mesh('head', T3.TubeGeometry(T3.CatmullRomCurve3([tA, T3.Vector3(tC.x, tA.y, zf + 0.05), tC]), 12, t * 0.45, 5), frameMat, O(name='glassesTemple'))
        br = T3.CatmullRomCurve3([T3.Vector3(E.x - w, E.y + h * 0.2, zf), T3.Vector3(0, E.y + h * 0.35, zf - 0.004), T3.Vector3(-E.x + w, E.y + h * 0.2, zf)])
        mesh('head', T3.TubeGeometry(br, 12, t * 0.5, 6), frameMat, O(name='glassesBridge'))
    b.glasses = glasses

    def hoops(o):
        o = O(o)
        m = mat(color=o.color or '#FFC23A', metal=1, rough=0.2, envIntensity=1.2)
        for s in (1, -1):
            mesh('head', T3.TorusGeometry(o.r or 0.04, o.t or 0.008, 8, 28), m, O(pos=[s * o.x, o.y, o.z or 0], rot=[0, math.pi / 2, 0], name='hoop'))
    b.hoops = hoops
    return b


class FaceRecorder:
    """Collects what the JS FaceController gets from the builder (eyes) for the header."""

    def __init__(self):
        self.eyes = []

    def addEye(self, e):
        self.eyes.append(e)
