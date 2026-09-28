"""Z_CREW — "Tuned-In" zombie variant: the WZTV crew member (GDD §8.1, STYLE_GUIDE §7, ref
docs/ref/meshy_refs/zombie_crew_vest.png). (Port of src/art/chars/z_crew.js.)
Stocky little guy: navy WZTV vest over a cream shirt with rolled sleeves, rolled jeans with a plaid knee patch, tan
work boots, walkie-talkie on the belt, red lanyard with an ID card, "13 ADMIT ONE" ticket stub in the vest pocket.
Exaggerated feature: PEAR HEAD (tiny cranium on a big jowly jaw) + two big buck teeth in an open "O" mouth.

This file also exports the SHARED ZOMBIE HELPERS used by every z_*.py variant (from .z_crew import ...):
  ZOMBIE_MATS            base materials (skin, lid, mouth, teeth, tongue) — spread into def.materials
  zEye(sd, E)            socket recess + droopy upper lid + plum under-eye (inside sd.bone('head'))
  zMouth(sd, M)          open "O" mouth: puffy lip ring, dark cavity, big square teeth, optional tongue
  zHand(sd, o)           big cartoon zombie hand (1.4x), palm facing back (= palm down when the arms reach forward)
  staticEyes(b, EYES)    attachments: TV-static eye discs + cyan rims (mesh.userData.staticEye = true)
  ticketStub(b, o)       attachment: the "13 ADMIT ONE" ticket stub (mesh name 'ticketStub')
  patchDecal(b, o)       attachment: small printed patch / badge (canvas text)
"""
import math

import numpy as np

from ..jsutil import O, nz
from ._sculpt import onEllipsoid

ZSKIN = '#A9C7A4'
ZSHADOW = '#7FA08A'
ZPLUM = '#7A5C8E'

ZOMBIE_MATS = O(
    skin=O(color='#A3C99C', rough=0.48, sss=0.25, wrap=0.5, cav=0.5, spec=0.7),
    lid=O(color='#95BC90', rough=0.48, sss=0.2, wrap=0.5, cav=0.5, spec=0.7),
    mouth=O(color='#3B2340', rough=0.7, spec=0.3),
    teeth=O(color='#F4EDD6', rough=0.3, spec=0.8, cav=0.3),
    tongue=O(color='#B25A78', rough=0.35, sss=0.3, spec=0.8),
)


# ---------------------------------------------------------------------------------------------------------------
# Eye: E = { x, y, z (disc center = where the disc meets the skin), r, pitch, yaw, lid (0..1 coverage from the
# top), droop (rad, + = outer corner lower), depth (dome height / r) }. Head-local, call inside sd.bone('head').
# The disc itself is an attachment (staticEyes); the sculpt adds a clean recess, a smooth lid and the plum ring.
def eyeFrame(E):
    return O(pos=[E.x, E.y, E.z], rot=[E.pitch or 0, E.yaw or 0, 0])


def zEyeSocket(sd, E):
    # recess the dome sits in (flush, clean edge) — call INSIDE the head group
    sd.frame(eyeFrame(E), lambda: sd.ellipsoid(op='sub', k=0.006, pos=[0, 0, 0.004], r=[E.r * 1.02, E.r * 1.02, E.r * 0.5]))


def zEyeLid(sd, E):
    # upper lid: a shell over the dome, cut by a (drooping) plane — call OUTSIDE the head group, after it
    side = 1 if E.x >= 0 else -1
    dep = nz(E.depth, 0.55)
    cover = nz(E.lid, 0.35)            # 0 = no lid, 1 = closed
    h = E.r * (1 - 2 * cover)          # lid edge height in the eye frame
    with sd.frame(eyeFrame(E)):
        with sd.group(mat='lid', blend=0.01, k=0.006):
            sd.ellipsoid(pos=[0, 0, 0.002], r=[E.r * 1.1, E.r * 1.1, E.r * dep + 0.011])
            sd.frame({'rot': [0, 0, -side * nz(E.droop, 0.18)]}, lambda: sd.plane(op='int', k=0.006, n=[0, -1, 0], d=-h))
            sd.plane(op='int', k=0.004, n=[0, 0, 1], d=0.012)      # no lid behind the skin


def zEyePaint(sd, E):
    # plum ring under the eye (skin only; the disc and the lid cover the rest)
    sd.frame(eyeFrame(E), lambda: sd.paint({'color': ZPLUM, 'soft': 0.014, 'strength': 0.8, 'only': ['skin']}, lambda:
             sd.ellipsoid(pos=[0, -E.r * 0.28, 0], r=[E.r * 1.3, E.r * 1.26, E.r * 1.2])))


# ---------------------------------------------------------------------------------------------------------------
# Mouth: M = { pos (surface center), pitch (rad, face normal tilt: + = facing down), R, r (lip tube), open [rx, ry],
# teeth: [{ x, y, w, h, lower }], tongue: { len, droop, w } }. Head-local. Lip ring goes INSIDE the head group
# (zMouthLip), cavity + teeth + tongue after the group (zMouthInside).
def mouthFrame(M):
    return O(pos=M.pos, rot=[-(M.pitch or 0), M.yaw or 0, M.roll or 0])


def zMouthLip(sd, M):
    with sd.frame(mouthFrame(M)):
        if M.lipPts:
            sd.worm(pts=M.lipPts, r=M.r, k=0.012, segs=40)
        else:
            sd.torus(rot=[math.pi / 2, 0, 0], R=M.R, r=M.r, k=0.012)
        sd.ellipsoid(op='sub', k=0.004, cutMat='mouth', pos=[0, 0, 0.012], r=[M.open[0], M.open[1], 0.04])


def zMouthInside(sd, M):
    with sd.frame(mouthFrame(M)):
        for t in (M.teeth or []):
            t = O(t)
            sd.box(mat='teeth', pos=[t.x, t.y, nz(t.z, 0.006)], rot=[0, 0, t.rot or 0], size=[t.w, t.h, 0.009], round=min(t.w, t.h) * 0.55, k=0.004)
        if M.tongue:
            T = O(M.tongue)
            sd.worm(mat='tongue', pts=T.pts, r=T.r, flat=nz(T.flat, 0.55), up=[0, 1, -0.3], k=0.006, segs=18)


# ---------------------------------------------------------------------------------------------------------------
# Big zombie hand, in sd.bone('handL') (mirrored for R): palm faces +z (back) so it faces DOWN when the arm reaches
# forward; thumb on the medial (+x) side. o = { scale, curl }.
def zHand(sd, o=None):
    o = O(o or {})
    s, curl = nz(o.scale, 1.4), nz(o.curl, 0.35)
    with sd.frame(scale=s, pos=[0, 0.004, 0]):
        with sd.group(mat='skin', k=0.012, blend=0.012):
            sd.roundCone(a=[0, 0.014, 0], b=[0, -0.03, 0.001], ra=0.03, rb=0.036, k=0.015)
            sd.box(pos=[0, -0.056, 0.002], size=[0.046, 0.046, 0.02], round=0.018, k=0.016)
            fx, fl = [-0.0366, -0.0122, 0.0122, 0.0366], [0.054, 0.064, 0.062, 0.052]
            for i in range(4):
                x, l, sp = fx[i], fl[i], (i - 1.5) * 0.0025
                sd.worm(pts=[[x, -0.088, 0.002], [x + sp, -0.088 - l * 0.55, 0.002 + l * 0.12 * curl], [x + sp * 1.6, -0.088 - l, l * 0.42 * curl]], r=[0.0102, 0.0098, 0.0092], k=0.003, segs=8)
            sd.worm(pts=[[0.03, -0.034, -0.006], [0.052, -0.058, -0.016], [0.058, -0.082, -0.02]], r=[0.015, 0.0132, 0.0118], k=0.012, segs=8)


# Molded-toy hair clump: path [[az, el, lift], ...] on the guide ellipsoid E, each point snapped onto the OUTERMOST of
# `nodes` (e.g. [headSkin, hairMass]) so clumps can run from the hair mass onto the forehead. lift: <0 buried.
def hairClump(sd, nodes, E, path, o=None):
    o = O(o or {})
    pts, ups = [], []
    for e in path:
        lift = e[3] if o.xyz else (e[2] if len(e) > 2 else None)
        g = [e[0], e[1], e[2]] if o.xyz else onEllipsoid(E, e[0], e[1], 0.1)
        # snap onto every node; keep the candidate that lies on the OUTER surface of the union (not buried in another node)
        best, bn, bd = None, None, math.inf
        cand = [sd.snap(n, g, nz(lift, 0)) for n in nodes]
        for i, n in enumerate(nodes):
            q = cand[i]
            w = sd.toWorld(q)
            buried = False
            for m in nodes:
                if m is not n and m.fn(w[0], w[1], w[2]) < nz(lift, 0) - 0.002:
                    buried = True
            d = math.hypot(q[0] - g[0], q[1] - g[1], q[2] - g[2]) + (1 if buried else 0)
            if d < bd:
                bd, best, bn = d, q, n
        pts.append(best)
        ups.append(sd.normalAt(bn, best))
    return sd.worm(pts=pts, r=o.r, flat=nz(o.flat, 0.62), up=ups[0], ups=ups, k=nz(o.k, 0.012), segs=o.segs or 16, color2=o.tip, flow=o.flow)


# ---------------------------------------------------------------------------------------------------------------
# Attachments.
# Static grain: about 1/12 of the eye diameter (not per-texel glitter). The dome UVs span STATIC_CELLS texels of the
# game's 128² staticNoise() across the disc (zombieTypes swaps the dome material for it); our own preview texture
# (STATIC_N² soft cells, linear filtered, low contrast, horizontal streaks) is repeated to the same grain.
STATIC_CELLS, STATIC_N = 12, 32
UV_SPAN = STATIC_CELLS / 128
_cache = {}


def cached(key, make):
    v = _cache.get(key)
    if v is None:
        v = make()
        _cache[key] = v
    return v


def _data_texture(key, data, N, M, repeat, nearest=False):
    from ..face import CharTexture
    from dalib.canvas2d import Canvas
    cv = Canvas(N, M)
    g = cv.getContext('2d')
    img = g.createImageData(N, M)
    # three DataTexture rows start at the BOTTOM (flipY false, v = 0 = first row): the canvas is drawn top-down
    img.data[:] = np.flipud(np.asarray(data, np.uint8).reshape(M, N, 4)).reshape(-1)
    g.putImageData(img, 0, 0)
    t = CharTexture(cv, key, repeat=repeat, ns='ch')
    return t


def staticTexture():
    def make():
        N = STATIC_N
        data = np.zeros(N * N * 4, np.int64)
        s = 0x2545F491
        for i in range(N * N):
            s ^= (s << 13) & 0xFFFFFFFF
            s ^= s >> 17
            s ^= (s << 5) & 0xFFFFFFFF
            s &= 0xFFFFFFFF
            v = 150 + (((s >> 24) & 0xff) * 100) / 255       # soft contrast: 150..250
            # TV snow: horizontal streaks (a texel often copies its left neighbour) with a cool bias
            w = data[(i - 1) * 4 + 1] if (i % N != 0 and ((s >> 8) & 3) < 2) else v
            data[i * 4] = int(max(0, w - 14))
            data[i * 4 + 1] = int(w)
            data[i * 4 + 2] = int(min(255, w + 10))
            data[i * 4 + 3] = 255
        return _data_texture('zombieStaticEye', data, N, N, True)
    return cached('staticTex', make)


def veilTexture():
    """Veil over the static (NOT tagged staticEye, so it survives the game's material swap): a soft dark centre a bit
    below the middle (the droopy gaze still reads) + an inner cyan glow vignette toward the rim."""
    def make():
        N = 128
        data = np.zeros((N, N, 4), np.float64)

        def ss(a, b, x):
            t = np.clip((x - a) / (b - a), 0, 1)
            return t * t * (3 - 2 * t)
        dark, glow = np.array([10, 20, 40]), np.array([150, 246, 255])
        j, i = np.meshgrid(np.arange(N), np.arange(N), indexing='ij')
        u = (i + 0.5) / N * 2 - 1
        v = (j + 0.5) / N * 2 - 1
        dc = np.hypot(u * 1.05, v + 0.16)
        dr = np.hypot(u, v)
        ad = 0.34 + 0.56 * (1 - ss(0.14, 0.52, dc))
        ag = 0.9 * ss(0.56, 1.0, dr)
        a = ag + ad * (1 - ag)
        for c in range(3):
            data[..., c] = np.floor((glow[c] * ag + dark[c] * ad * (1 - ag)) / np.maximum(1e-6, a) + 0.5)
        data[..., 3] = np.floor(np.minimum(1, a) * 255 + 0.5)
        return _data_texture('zombieEyeVeil', data.astype(np.uint8), N, N, False)
    return cached('veilTex', make)


def domeGeo(T3, r, span, du, repeat=1.0):
    g = T3.SphereGeometry(r, 32, 12, 0, math.pi * 2, 0, math.pi / 2)
    # planar UVs across the disc (no pole pinch); the texture repeat is baked into the UVs
    p, uv = g.attributes.position, g.attributes.uv
    for i in range(p.count):
        uv.setXY(i, (0.5 + p.getX(i) / (2 * r) * span + du) * repeat, (0.5 + p.getZ(i) / (2 * r) * span) * repeat)
    return g


def staticEyes(b, EYES):
    """Eye discs filled with animated TV static + dark centre / glow veil + thin cyan rim. The game swaps the dome
    material for core/textures staticNoise() (domes are tagged userData.staticEye; the veil and rim keep theirs)."""
    from ..face import basicMaterial
    T3 = b.THREE
    tex = staticTexture()
    rep = STATIC_CELLS / (STATIC_N * UV_SPAN)
    eyeMat = cached('eyeMat', lambda: basicMaterial({'map': tex, 'color': '#DDF3F8', 'name': 'zombieStaticEye'}))
    veilMat = cached('veilMat', lambda: basicMaterial({'map': veilTexture(), 'transparent': True, 'depthWrite': False, 'name': 'zombieEyeVeil'}))
    rimMat = cached('rimMat', lambda: basicMaterial({'color': '#7FE6F2', 'name': 'zombieEyeRim'}))
    head = b.joint('head')
    for E in EYES:
        E = O(E)
        g = T3.Group()
        g.name = 'staticEyeRoot'
        g.position.set(E.x, E.y, E.z)
        g.rotation.set(E.pitch or 0, E.yaw or 0, 0)
        head.add(g)
        dome = T3.Mesh(domeGeo(T3, E.r, UV_SPAN, E.x * 7, rep), eyeMat)
        dome.rotation.x = -math.pi / 2             # pole (+y) -> forward (-z)
        dome.scale.set(1, nz(E.depth, 0.55), 1)
        dome.name = 'staticEye'
        dome.userData['staticEye'] = True
        dome.castShadow = False
        g.add(dome)
        veil = T3.Mesh(domeGeo(T3, E.r * 1.012, 1, 0), veilMat)
        veil.rotation.x = -math.pi / 2
        veil.scale.set(1, nz(E.depth, 0.55) * 1.01, 1)
        veil.name = 'staticEyeVeil'
        veil.renderOrder = 2
        veil.castShadow = False
        g.add(veil)
        rim = T3.Mesh(T3.TorusGeometry(E.r * 1.0, E.r * nz(E.rim, 0.06), 6, 40), rimMat)
        rim.name = 'staticEyeRim'
        rim.userData['staticEyeRim'] = True
        rim.castShadow = False
        g.add(rim)


def roundRectPath(g, x, y, w, h, r):
    g.beginPath()
    g.moveTo(x + r, y)
    g.arcTo(x + w, y, x + w, y + h, r)
    g.arcTo(x + w, y + h, x, y + h, r)
    g.arcTo(x, y + h, x, y, r)
    g.arcTo(x, y, x + w, y, r)
    g.closePath()


def card(b, o, paint, shape, name):
    """Flat printed card with a canvas face (ticket, patch, badge). shape: 'ticket' (notched ends) | 'round'."""
    o = O(o)
    key = 'card|%s|%s|%s|%s|%s|%s|%s' % (name, o.w, o.h, o.text or '', o.bg or '', o.band or '', o.edge or '')
    C = cached(key, lambda: makeCard(b, o, paint, shape, key))
    m = b.mesh(o.joint or 'chest', C['geo'], C['mats'], O(pos=o.pos, rot=o.rot, name=name))
    m.rotation.order = 'XYZ'
    return m


def makeCard(b, o, paint, shape, key):
    from ..face import CharTexture
    from dalib.canvas2d import Canvas
    T3 = b.THREE
    W, H = 512, int(math.floor(512 * o.h / o.w + 0.5))
    cv = Canvas(W, H)
    g = cv.getContext('2d')
    paint(g, W, H)
    tex = CharTexture(cv, key, repeat=False, ns='ch')
    tex.anisotropy = 4
    w, h = o.w / 2, o.h / 2
    r = min(w, h) * 0.18
    sh = T3.Shape()
    if shape == 'ticket':
        n = h * 0.28
        sh.moveTo(-w + r, -h)
        sh.lineTo(w - r, -h)
        sh.quadraticCurveTo(w, -h, w, -h + r)
        sh.lineTo(w, -n)
        sh.absarc(w, 0, n, -math.pi / 2, math.pi / 2, True)
        sh.lineTo(w, h - r)
        sh.quadraticCurveTo(w, h, w - r, h)
        sh.lineTo(-w + r, h)
        sh.quadraticCurveTo(-w, h, -w, h - r)
        sh.lineTo(-w, n)
        sh.absarc(-w, 0, n, math.pi / 2, -math.pi / 2, True)
        sh.lineTo(-w, -h + r)
        sh.quadraticCurveTo(-w, -h, -w + r, -h)
    else:
        sh.moveTo(-w + r, -h)
        sh.lineTo(w - r, -h)
        sh.quadraticCurveTo(w, -h, w, -h + r)
        sh.lineTo(w, h - r)
        sh.quadraticCurveTo(w, h, w - r, h)
        sh.lineTo(-w + r, h)
        sh.quadraticCurveTo(-w, h, -w, h - r)
        sh.lineTo(-w, -h + r)
        sh.quadraticCurveTo(-w, -h, -w + r, -h)
    geo = T3.ExtrudeGeometry(sh, {'depth': nz(o.t, 0.0025), 'bevelEnabled': False, 'curveSegments': 10})
    p, uv = geo.attributes.position, geo.attributes.uv
    # u flipped: the printed face is the cap that faces -z (outward from the chest)
    for i in range(p.count):
        uv.setXY(i, (w - p.getX(i)) / (2 * w), (p.getY(i) + h) / (2 * h))
    geo.translate(0, 0, -nz(o.t, 0.0025))
    face = b.mat(map=tex, rough=0.75, rim=0.15, rimColor='#8FF3FF', wrap=0.5)
    edge = b.mat(color=o.edge or '#E9D9B4', rough=0.8, rim=0.1)
    return {'geo': geo, 'mats': [face, edge]}


FONT = '"Arial Black", Impact, sans-serif'


def ticketStub(b, o):
    def paint(g, W, H):
        g.fillStyle = '#F6E7C8'
        g.fillRect(0, 0, W, H)
        g.strokeStyle = '#E23B3B'
        g.lineWidth = W * 0.022
        roundRectPath(g, W * 0.085, H * 0.12, W * 0.83, H * 0.76, H * 0.1)
        g.stroke()
        # perforation line
        g.fillStyle = '#C9B48E'
        y = H * 0.18
        while y < H * 0.84:
            g.beginPath()
            g.arc(W * 0.34, y, W * 0.009, 0, math.pi * 2)
            g.fill()
            y += H * 0.1
        g.fillStyle = '#E23B3B'
        g.font = '900 %dpx %s' % (int(math.floor(H * 0.52 + 0.5)), FONT)
        g.textAlign = 'center'
        g.textBaseline = 'middle'
        g.fillText('13', W * 0.215, H * 0.53)
        g.fillStyle = '#2B2238'
        g.font = '900 %dpx %s' % (int(math.floor(H * 0.25 + 0.5)), FONT)
        g.fillText('ADMIT', W * 0.63, H * 0.37)
        g.fillText('ONE', W * 0.63, H * 0.67)
    return card(b, O({'w': 0.084, 'h': 0.046}, o), paint, 'ticket', 'ticketStub')


def patchDecal(b, o):
    o = O(o)

    def paint(g, W, H):
        g.fillStyle = o.bg or '#F4F1E8'
        g.fillRect(0, 0, W, H)
        g.fillStyle = o.band or '#2F5BD3'
        roundRectPath(g, W * 0.05, H * 0.1, W * 0.9, H * 0.8, H * 0.18)
        g.fill()
        g.fillStyle = '#F4F1E8'
        g.font = '900 %dpx %s' % (int(math.floor(H * 0.5 + 0.5)), FONT)
        g.textAlign = 'center'
        g.textBaseline = 'middle'
        g.fillText(o.text or 'WZTV', W * 0.5, H * 0.47)
        g.fillStyle = '#E23B3B'
        g.fillRect(W * 0.16, H * 0.74, W * 0.68, H * 0.07)
    return card(b, O({'w': 0.07, 'h': 0.034, 'edge': o.edgeColor or '#F4F1E8'}, o), paint, 'round', o.name or 'patch')


# ===============================================================================================================
# Z_CREW definition
HAIR = '#4A3428'
# Head-local anchors (origin = head joint = top of the neck; y up, -z forward). Eyes kept inside the head silhouette
# (moderate yaw) with a droopy upper lid covering >= 1/3 of each disc.
EYES = [
    O(x=0.088, y=0.3, z=-0.151, r=0.066, pitch=0.12, yaw=-0.3, lid=0.36, droop=0.2, depth=0.7),
    O(x=-0.082, y=0.296, z=-0.153, r=0.054, pitch=0.1, yaw=0.28, lid=0.42, droop=0.14, depth=0.7),
]
MOUTH = O(
    pos=[0, 0.094, -0.174], pitch=0.48, R=0.05, r=0.0155, open=[0.037, 0.036],
    teeth=[
        O(x=-0.0158, y=0.02, w=0.0138, h=0.0175, rot=0.06),
        O(x=0.0152, y=0.02, w=0.0138, h=0.0175, rot=-0.05),
        O(x=0.021, y=-0.026, w=0.01, h=0.011, rot=0.12),
    ],
    tongue=O(pts=[[-0.016, -0.024, 0.016], [0.0, -0.021, 0.008], [0.014, -0.025, 0.014]], r=0.014, flat=0.5),
)

HM = O(c=[0, 0.345, 0.014], r=[0.174, 0.207, 0.184])  # hair guide ellipsoid (just above the cranium)


def headShapes(sd):
    """PEAR HEAD: tiny cranium on a big jowly jaw (also the base of the molded hair shell)"""
    with sd.group(k=0.09):
        sd.ellipsoid(pos=[0, 0.175, -0.006], r=[0.22, 0.18, 0.19])   # big jowly jaw
        sd.ellipsoid(pos=[0, 0.345, 0.014], r=[0.162, 0.195, 0.172])  # small cranium


def crewTorso(sd):
    sd.ellipsoid(pos=[0, 0.79, 0.005], r=[0.196, 0.13, 0.136])
    sd.ellipsoid(pos=[0, 0.662, -0.014], r=[0.186, 0.13, 0.142])
    sd.ellipsoid(pos=[0, 0.866, 0.012], r=[0.204, 0.062, 0.116])


def sculpt(sd, ctx=None):
    # ---------------- torso: shirt, vest, collar ----------------
    shirtNode = sd.group({'name': 'shirt', 'mat': 'shirt', 'bone': 'torso', 'k': 0.05}, lambda: crewTorso(sd))
    # neck (short, mostly hidden by the big head)
    sd.capsule(mat='skin', bone='torso', a=[0, 0.87, 0.012], b=[0, 1.0, 0.0], r=0.066, k=0.02)
    # collar: soft roll band
    with sd.group(name='collar', mat='shirt', bone='torso', blend=0.012, k=0.02):
        sd.torus(pos=[0, 0.918, 0.014], rot=[0.1, 0, 0], R=0.074, r=0.02)
    with sd.group(name='vest', mat='vest', bone='torso', blend=0.006, k=0.02) as vest:
        sd.group({'offset': 0.013, 'k': 0.05}, lambda: crewTorso(sd))
        # open front (narrow at the belly, wide at the chest)
        sd.roundCone(op='sub', k=0.012, a=[0, 0.6, -0.166], b=[0, 0.95, -0.15], ra=0.03, rb=0.095)
        # armholes (small: the vest covers the top of the shoulder, no sleeve "ball" pokes out), neck, hem
        sd.mirrorX(lambda: sd.ellipsoid(op='sub', k=0.015, pos=[0.232, 0.83, 0.012], r=[0.062, 0.078, 0.082]))
        sd.capsule(op='sub', k=0.02, a=[0, 0.9, 0.02], b=[0, 1.1, 0.02], r=0.098)
        sd.plane(op='int', k=0.008, n=[0, -1, 0], d=-0.606)
        # scalloped hem: clean rounded bites torn out of the front panels and the back
        for x, y, z, r in [[-0.145, 0.6, -0.11, 0.04], [-0.07, 0.598, -0.152, 0.03], [0.118, 0.6, -0.132, 0.036],
                           [0.06, 0.6, 0.15, 0.04], [-0.1, 0.6, 0.13, 0.03]]:
            sd.sphere(op='sub', k=0.006, pos=[x, y, z], r=r)
        # round hole in the back panel (shirt shows through)
        sd.sphere(op='sub', k=0.005, pos=[0.075, 0.76, 0.165], r=0.032)

    # vest pockets (stitched outlines) + edge piping stitches
    @sd.mirrorX
    def _():
        sd.stitch([[0.07, 0.8, -0.2], [0.07, 0.74, -0.2], [0.142, 0.74, -0.2], [0.142, 0.8, -0.2]], mats=['vest'], color='#9DB0E8', smooth=False)
        sd.stitch([[0.068, 0.802, -0.2], [0.144, 0.802, -0.2]], mats=['vest'], color='#9DB0E8', smooth=False)

    # lanyard (red cord from behind the collar to an ID card on the belly)
    @sd.mirrorX
    def _():
        pts = sd.snapAll(shirtNode, [[0.062, 0.915, -0.04], [0.058, 0.87, -0.13], [0.036, 0.8, -0.16], [0.012, 0.745, -0.16]], 0.009)
        sd.worm(mat='lanyard', bone='torso', pts=pts, r=0.0072, flat=0.75, up=[0, 0, -1], k=0.006, segs=12)
    cardC = sd.snap(shirtNode, [0, 0.71, -0.2], 0.012)
    with sd.group(name='idcard', mat='badge', bone='chest', rigid=True, blend=0.004):
        sd.box(pos=cardC, rot=[0.28, 0, 0.06], size=[0.03, 0.038, 0.0055], round=0.005)
        sd.box(pos=[cardC[0], cardC[1] + 0.03, cardC[2] - 0.004], rot=[0.28, 0, 0.06], size=[0.008, 0.012, 0.006], round=0.004, mat='buckle', k=0.003)
    sd.paint({'color': '#2F5BD3', 'soft': 0.002, 'only': ['badge']}, lambda: sd.box(pos=[cardC[0], cardC[1] + 0.017, cardC[2]], rot=[0.28, 0, 0.06], size=[0.034, 0.011, 0.03], round=0.002))
    sd.paint({'color': '#E23B3B', 'soft': 0.002, 'only': ['badge']}, lambda: sd.box(pos=[cardC[0], cardC[1] - 0.02, cardC[2]], rot=[0.28, 0, 0.06], size=[0.034, 0.004, 0.03], round=0.001))

    # ---------------- head ----------------
    with sd.bone('head'):
        with sd.group(name='head', mat='skin', k=0.02, blend=0.03) as head:
            headShapes(sd)
            # bulbous nose
            sd.sphere(pos=[0, 0.218, -0.2], r=0.047, k=0.022)

            # ears (one a bit floppier)
            @sd.mirrorX
            def _(m):
                sd.ellipsoid(pos=[0.214, 0.235, 0.03], rot=[0, -0.35, -0.28 if m else 0.12], r=[0.026, 0.052, 0.036], k=0.014)
                sd.ellipsoid(op='sub', k=0.008, pos=[0.233, 0.235, 0.024], rot=[0, -0.35, -0.28 if m else 0.12], r=[0.012, 0.032, 0.02])
            for E in EYES:
                zEyeSocket(sd, E)
            zMouthLip(sd, MOUTH)
        for E in EYES:
            zEyeLid(sd, E)
        zMouthInside(sd, MOUTH)
        for E in EYES:
            zEyePaint(sd, E)
        sd.paint({'color': '#8DB58A', 'soft': 0.02, 'strength': 0.6, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.218, -0.21], r=0.04))
        sd.paint({'color': ZSHADOW, 'soft': 0.03, 'strength': 0.35, 'only': ['skin']}, lambda: sd.ellipsoid(pos=[0, 0.03, -0.03], r=[0.2, 0.06, 0.2]))

        # ---- hair: a SOLID molded-toy piece that follows the pear (the head shapes inflated): from the back it is one
        #      clean pear of hair down to a low nape edge (no cap sitting on a bulb = no acorn, no crown curl); rounded
        #      hairline, ears clear, a soft side part and a fringe of 4 WIDE, SHORT rounded tufts overlapping each other,
        #      all swept to his right (tips down-right). Flow = constant sideways sweep.
        with sd.group(name='hair', mat='hair', flow=[1, 0, 0.25]):
            with sd.group(name='hairmass', k=0.05):
                sd.group({'offset': 0.022, 'k': 0.09}, lambda: headShapes(sd))
                sd.ellipsoid(pos=[0, 0.3, 0.16], r=[0.07, 0.12, 0.06], k=0.04)                              # nape taper
                sd.ellipsoid(op='sub', k=0.02, pos=[0, 0.19, -0.23], r=[0.26, 0.2, 0.2])                   # face opening
                # swept fringe: narrow notches cut up-left into the hairline -> wide, short rounded tufts pointing down-right
                for x, y, l in [[-0.052, 0.4, 0.03], [0.018, 0.4, 0.034], [0.086, 0.388, 0.032]]:
                    sd.ellipsoid(op='sub', k=0.012, pos=[x, y, -0.2], rot=[0, 0, 0.72], r=[0.0125, l, 0.12])
                sd.mirrorX(lambda: sd.ellipsoid(op='sub', k=0.03, pos=[0.245, 0.215, 0.01], r=[0.08, 0.1, 0.12]))  # ears clear
                sd.plane(op='int', k=0.03, n=[0, -0.707, -0.707], d=-0.198)                                 # nape (low at the back)
                sd.capsule(op='sub', k=0.022, a=[-0.07, 0.6, -0.16], b=[-0.075, 0.6, 0.06], r=0.005)       # soft side part

    # ---------------- belt + pants ----------------
    with sd.group(name='pelvis', mat='denim', bone='torso', k=0.03):
        sd.ellipsoid(pos=[0, 0.55, 0.0], r=[0.176, 0.104, 0.132])
    with sd.group(name='belt', mat='leather', bone='torso'):
        sd.ellipsoid(pos=[0, 0.572, -0.003], r=[0.17, 0.112, 0.133], offset=0.007)
        sd.box(op='int', k=0.003, pos=[0, 0.572, 0], size=[0.3, 0.02, 0.3], round=0.002)
    with sd.group(name='buckle', mat='buckle', bone='hips', rigid=True, k=0.003):
        sd.box(pos=[0, 0.572, -0.142], size=[0.03, 0.024, 0.008], round=0.007)
        sd.box(op='sub', k=0.002, pos=[0, 0.572, -0.151], size=[0.019, 0.013, 0.006], round=0.004)
    # walkie-talkie on the left hip
    with sd.group(name='walkie', mat='walkie', bone='hips', rigid=True, blend=0.004, k=0.006):
        with sd.frame(pos=[-0.2, 0.53, -0.02], rot=[0.04, -1.37, 0.05]):
            sd.box(pos=[0, 0, 0], size=[0.036, 0.064, 0.024], round=0.014)
            sd.capsule(a=[0.016, 0.055, 0.004], b=[0.018, 0.14, 0.004], r=0.009, k=0.004)
            sd.sphere(pos=[0.018, 0.143, 0.004], r=0.013, k=0.003, mat='lanyard')
            sd.box(pos=[-0.013, 0.068, 0.002], size=[0.008, 0.01, 0.008], round=0.005, mat='buckle')
    sd.paint({'color': '#F2C63A', 'soft': 0.002, 'only': ['walkie']}, lambda: sd.frame({'pos': [-0.2, 0.53, -0.02], 'rot': [0.04, -1.37, 0.05]}, lambda:
             sd.box(pos=[0, 0.026, -0.024], size=[0.024, 0.01, 0.02], round=0.004)))

    @sd.mirrorX
    def _(m):
        with sd.bone('hipL'):
            fr = sd.patternFrame(pos=[0, -0.2, 0], mode='cyl', radius=0.085)
            with sd.group(mat='denim', k=0.035, blend=0.035, pframe=fr):
                sd.roundCone(a=[0.035, -0.03, 0.004], b=[0, -0.235, 0], ra=0.098, rb=0.088)
                sd.roundCone(a=[0, -0.235, 0], b=[0, -0.385, 0.008], ra=0.088, rb=0.08)
                if not m:
                    sd.ellipsoid(op='sub', k=0.006, cutMat='skin', pos=[0.012, -0.12, -0.112], rot=[0, 0, 0.3], r=[0.046, 0.036, 0.04])   # big rounded tear (left thigh)
            # rolled cuff
            with sd.group(mat='cuff', blend=0.004, k=0.01, pframe=fr):
                sd.torus(pos=[0, -0.405, 0.008], R=0.078, r=0.023)
                sd.cylinder(pos=[0, -0.405, 0.008], r=0.087, h=0.019, round=0.012)
            sd.stitch([[math.sin(a) * 0.11, -0.386, 0.008 + math.cos(a) * 0.11] for a in [(i / 24) * math.pi * 2 for i in range(25)]], mats=['cuff'], smooth=False)
            sd.stitch([[-0.11, 0.03, 0], [-0.096, -0.2, 0], [-0.084, -0.38, 0.008]], mats=['denim'])
            if m:
                # plaid knee patch with stitched border (right knee)
                kf = sd.patternFrame(pos=[0, -0.23, -0.08], mode='tri')
                sd.paint({'mat': 'patch', 'soft': 0.001, 'only': ['denim'], 'pframe': kf}, lambda:
                         sd.box(pos=[0.006, -0.235, -0.08], rot=[0, 0, 0.18], size=[0.05, 0.05, 0.04], round=0.018))
                sq = []
                for i in range(33):
                    a = (i / 32) * math.pi * 2
                    c, s = math.cos(a), math.sin(a)
                    e = 0.041 / math.pow(math.pow(abs(c), 4) + math.pow(abs(s), 4), 0.25)
                    x, y, rr = c * e, s * e, 0.18
                    sq.append([0.006 + x * math.cos(rr) - y * math.sin(rr), -0.235 + x * math.sin(rr) + y * math.cos(rr), -0.12])
                sd.stitch(sq, mats=['patch', 'denim'], color='#F6E7C8', smooth=False)
        with sd.bone('footL'):
            def upper():
                sd.cylinder(pos=[0, 0.02, 0.008], r=0.07, h=0.07, round=0.03)
                sd.ellipsoid(pos=[0, -0.026, -0.07], r=[0.07, 0.048, 0.13])
                sd.sphere(pos=[0, -0.024, -0.15], r=0.058)
            sd.group({'mat': 'boot', 'k': 0.035}, upper)
            with sd.group(mat='sole', blend=0.0):
                sd.group({'offset': 0.008, 'k': 0.035}, upper)
                sd.box(op='int', k=0.003, pos=[0, -0.061, -0.06], size=[0.12, 0.011, 0.26], round=0.003)
            # boot laces / tongue seam
            sd.stitch([[0, 0.06, -0.075], [0, 0.02, -0.09], [0, -0.005, -0.13]], mats=['boot'], color='#F2E3C4', width=0.004, dash=0.012, duty=0.55)
            sd.stitch([[-0.07, -0.045, -0.2], [-0.07, -0.045, 0.06]], mats=['boot'], color='#7A4A22')

    # jeans back pockets + yoke seam
    sd.mirrorX(lambda: sd.stitch([[0.04, 0.53, 0.2], [0.04, 0.47, 0.2], [0.075, 0.45, 0.2], [0.11, 0.47, 0.2], [0.11, 0.53, 0.2]], mats=['denim'], smooth=False))
    sd.stitch([[-0.16, 0.545, 0.2], [0, 0.525, 0.2], [0.16, 0.545, 0.2]], mats=['denim'])

    # ---------------- arms ----------------
    # Sleeves are straight tapered tubes that grow out of the torso (blend, no shoulder ball). Left: neat flat roll at
    # mid-upper-arm. Right: torn short sleeve with a scalloped hem and a round hole.
    @sd.mirrorX
    def _(m):
        with sd.bone('shoulderL'):
            with sd.group(mat='shirt', k=0.03, blend=0.02):
                sd.roundCone(a=[0.02, 0.012, 0], b=[0, -0.125, 0], ra=0.058, rb=0.058)
                sd.plane(op='int', k=0.006, n=[0, -1, 0], d=0.14)   # sleeve hem
                if m:
                    for x, z, r in [[-0.05, -0.03, 0.024], [-0.02, 0.05, 0.022]]:
                        sd.sphere(op='sub', k=0.005, pos=[x, -0.142, z], r=r)
                    sd.sphere(op='sub', k=0.005, cutMat='skin', pos=[-0.052, -0.07, -0.03], r=0.026)
            if not m:
                with sd.group(mat='shirt', blend=0.004, k=0.008):
                    sd.cylinder(pos=[0, -0.118, 0], r=0.064, h=0.014, round=0.009)
            sd.roundCone(mat='skin', a=[0, -0.1, 0], b=[0, -0.225, 0], ra=0.05, rb=0.048, k=0.01)
        with sd.bone('elbowL'):
            sd.roundCone(mat='skin', a=[0, 0.01, 0], b=[0, -0.215, 0], ra=0.049, rb=0.043, k=0.02)
        sd.bone('handL', lambda: zHand(sd, O(scale=1.42, curl=0.4)))


def attachments(b, ctx=None):
    staticEyes(b, EYES)
    # chest joint is at y 0.746 (bind pose = rest for the torso, so chest-local = world - [0, 0.746, 0])
    ticketStub(b, O(joint='chest', pos=[0.097, 0.056, -0.147], rot=[0.05, -0.3, 0.22], w=0.1, h=0.055))
    patchDecal(b, O(joint='chest', pos=[-0.108, 0.07, -0.143], rot=[0.04, 0.36, -0.03], text='WZTV', w=0.08, h=0.038))


DEF = O(
    id='z_crew',
    name='Tuned-In: WZTV Crew',
    kind='zombie',
    rig=O(height=1.56, headScale=1.34, shoulderW=0.44, hipW=0.28, legLen=0.7, torsoLen=0.5),
    bake=O(voxel=0.0046, tris=9400, aoStrength=0.9, aoReach=0.1),
    armOut=0.1,
    # hunch: spine + chest + neck ~18 deg forward on top of the zombie lean, head pushed forward (chin up to keep the
    # face readable), arms at different heights (left reaching higher, right drooping).
    poseOffset=O(
        spine=[-0.16, 0, 0.02], chest=[-0.14, 0.05, 0], neck=[-0.14, 0, 0], head=[0.36, 0.06, 0.09],
        shoulderL=[0.2, 0, 0.02], shoulderR=[-0.2, 0, -0.04], elbowL=[0.12, 0, 0], elbowR=[0.1, 0, 0],
        handL=[-0.45, 0, 0], handR=[-0.3, 0, 0.12],
    ),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        ZOMBIE_MATS,
        hair=O(color=HAIR, rough=0.4, sheen=1, sheenExp=70, spec=0.35, wrap=0.5, cav=0.5),
        shirt=O(color='#E8D3AA', rough=0.75, fuzz=0.3, wrap=0.55, lines=True),
        vest=O(color='#2A3D7C', rough=0.72, fuzz=0.35, wrap=0.5, lines=True),
        denim=O(color='#ffffff', rough=0.85, fuzz=0.4, lines=True, bump=0.2, pattern=O(type='denim', color='#3E5DA6', scale=0.05)),
        cuff=O(color='#ffffff', rough=0.85, fuzz=0.4, lines=True, pattern=O(type='denim', color='#6A88C8', scale=0.05)),
        patch=O(color='#ffffff', rough=0.8, fuzz=0.4, lines=True,
                pattern=O(type='plaid', base='#D9432E', bands=[['#F6E7C8', 0.12, 0.25, 0.9], ['#7A2418', 0.18, 0.7, 0.8]], scale=0.05)),
        leather=O(color='#5A3A26', rough=0.45, spec=0.5),
        buckle=O(color='#D9CFB8', metal=1, rough=0.28),
        boot=O(color='#B9793C', rough=0.45, spec=0.55, lines=True),
        sole=O(color='#3B2A20', rough=0.65),
        walkie=O(color='#2C2C35', rough=0.35, spec=0.8),
        lanyard=O(color='#E23B3B', rough=0.6, fuzz=0.2),
        badge=O(color='#F4F1E8', rough=0.4, spec=0.6),
    ),
    anchors=lambda ctx=None: O(EYES=EYES, MOUTH=MOUTH),
    sculpt=sculpt,
    attachments=attachments,
)
