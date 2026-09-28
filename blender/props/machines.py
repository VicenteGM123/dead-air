"""DEAD AIR — props: machines (docs/PROPKIT.md, GDD §10). The station's showpieces.
Port of src/props/machines.js (line by line: same names, numbers, part hierarchy and pivots).

  telly           Telly, the living walnut console TV (hero): rubber-glass CRT diorama, VHF dial, rabbit ears,
                  telescoping legs, cord tail and the white four-fingered cartoon glove on a stretchy arm
  telly_lamp      Telly's home floor lamp (bulb = named part + light anchor; setLampLevel)
  telly_rug       Telly's home braided oval rug (parts.dust = 'dust_rect' footprint decal, opts.dust)
  telly_cord      the unplugged extension cord an empty home keeps
  sign_on_lever   Master Control Sign-On lever: red knife switch under a hinged red cover + ON AIR lamp
  uplink_dish     THE UPLINK: 5 m white dish on an az-el turntable (hero; tilt/yaw parts, instanced rim chasers)
  uplink_cradle   feed-horn cradle clamp at chest height with R/G/B lamps
  uplink_crank    alignment crank wheel with a glowing handle
  uplink_booth    little uplink control booth with blinking lamps (instanced)
  skylark_13      the satellite Skylark-13 (small, cute, blinking beacon)
  hut_tubes       transmitter-hut tube rack: 4 orange tubes + the green Perpetua-Tube
Scenes (tools/propview): telly_home, telly_home_empty, uplink, sign_on, uplink_yard.

Runtime helpers (setTellyLegs, setTellyDial, setTellyGlove, updateTellyArm, setLampLevel, setOnAirLamp,
setUplinkChase, setUplinkPose, setCradleLamps, setCrankGlow, setBoothLamps, setSkylarkBeacon) are ported here
because the JS builders call them to set the build-time pose/state of the exported asset; the game animates the
named parts with their GDScript ports (godot/scripts/game/*.gd). Every part name/pivot they rely on is kept.

Port notes (JS plumbing): `inst.instanceColor.needsUpdate = true`, `pos.needsUpdate`, `computeBoundingSphere()` of
the dynamic arm and `frustumCulled` have no effect on the exported asset (kept where harmless).
"""
import math

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE, getCard
from dalib.mathutils3 import JSObj, clamp, lerp, smoothstep, js_round, js_sign, js_str

TAU = math.pi * 2
UP = THREE.Vector3(0, 1, 0)


def V(x, y, z):
    return THREE.Vector3(x, y, z)


# ============================================================================================ local helpers
# Group that finish() leaves alone (animated part). Its own meshes are merged later by finishRig().
def grp(name, pos=None):
    pos = [0, 0, 0] if pos is None else pos
    g = THREE.Group()
    g.name = name
    g.position.set(pos[0], pos[1], pos[2])
    g.userData.noMerge = True
    return g


def keep(o):
    o.userData.noMerge = True
    return o


def tinted(geo, c):
    return K.tint(geo.clone(), c)


# Orients an object whose geometry runs along +Y so it goes from a toward b.
def aim(o, a, b):
    d = V(b[0] - a[0], b[1] - a[1], b[2] - a[2]).normalize()
    o.position.set(a[0], a[1], a[2])
    o.quaternion.setFromUnitVectors(UP, d)
    return o


def dist3(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2])


# Bevelled rod from a (radius r) to b (radius r2).
def rod(a, b, r, mat, o=None):
    o = o or {}
    ln = dist3(a, b)
    geo = K.cyl(o['r2'] if o.get('r2') is not None else r, r, ln,
                {'bevel': o['bevel'] if o.get('bevel') is not None else min(r * 0.45, 0.012),
                 'seg': o['seg'] if o.get('seg') is not None else 10})
    return aim(K.m(tinted(geo, o['tint']) if o.get('tint') else geo, mat), a, b)


def ringXZ(r, n, y=0):
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        pts.append([math.cos(a) * r, y, math.sin(a) * r])
    return pts


def ringXY(r, n, z=0):
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        pts.append([math.cos(a) * r, math.sin(a) * r, z])
    return pts


# Closed rounded-rectangle path in the XY plane (for tubes: lips, piping, pinstripes).
def rrXY(w, h, r, z=0, steps=4, cx=0, cy=0):
    pts = []
    hx, hy = w / 2 - r, h / 2 - r
    for x0, y0, a0 in [[hx, hy, 0], [-hx, hy, math.pi / 2], [-hx, -hy, math.pi], [hx, -hy, math.pi * 1.5]]:
        for s in range(steps + 1):
            a = a0 + (s / steps) * (math.pi / 2)
            pts.append([cx + x0 + math.cos(a) * r, cy + y0 + math.sin(a) * r, z])
    return pts


# Rounded-rect THREE.Path centered at (cx, cy) (holes for extrude()).
def rrPath(w, h, r, cx=0, cy=0, seg=8):
    return THREE.Path([THREE.Vector2(p.x + cx, p.y + cy) for p in K.roundRect(w, h, r).getPoints(seg)])


def rrShape(w, h, r, cx=0, cy=0):
    s = K.roundRect(w, h, r)
    if cx or cy:
        return THREE.Shape([THREE.Vector2(p.x + cx, p.y + cy) for p in s.getPoints(10)])
    return s


# Atlas cell UVs: canvas pixel rect -> uvRect (v from the bottom, CanvasTexture flipY).
def cellUV(g, x0, y0, x1, y1, S=512, SH=None):
    SH = S if SH is None else SH
    return K.uvRect(g, x0 / S, 1 - y1 / SH, x1 / S, 1 - y0 / SH)


# Disc facing -z (prop front) showing an atlas cell.
def disc(r, seg, cell, S=512, SH=None):
    g = THREE.CircleGeometry(r, seg)
    cellUV(g, cell[0], cell[1], cell[2], cell[3], S, SH)
    g.rotateY(math.pi)
    return g


# Knob: lathe with its base at z=0 facing -z (face at z=-h). flutes: knurled side ribs.
def knobGeo(r, h, o=None):
    o = o or {}
    flutes, amp, seg, flange = o.get('flutes', 0), o.get('amp', 0.06), o.get('seg', 28), o.get('flange', 1.08)
    prof = ([[0, 0], [r * flange, 0], [r * flange, h * 0.16], [r, h * 0.24], [r * 0.97, h * 0.84], [r * 0.84, h],
             [0, h]] if flange else [[0, 0], [r, 0], [r * 0.96, h * 0.84], [r * 0.82, h], [0, h]])
    g = K.lathe(prof, {'round': min(r * 0.16, h * 0.14), 'seg': seg, 'steps': 1}).clone()
    if flutes:
        p = g.attributes.position
        for i in range(p.count):
            x, y, z = p.getX(i), p.getY(i), p.getZ(i)
            rr = math.hypot(x, z)
            if rr < r * 0.5:
                continue
            band = smoothstep(y, h * 0.22, h * 0.3) * (1 - smoothstep(y, h * 0.8, h * 0.9))
            k = 1 - amp * band * (0.5 + 0.5 * math.cos(math.atan2(z, x) * flutes))
            p.setX(i, x * k)
            p.setZ(i, z * k)
        g.computeVertexNormals()
        K.weldNormals(g)
    g.rotateX(-math.pi / 2)
    return g


# Moves `geo` vertices: fn(v:Vector3, i) mutates in place. Returns geo (own copy expected).
def warp(geo, fn):
    p = geo.attributes.position
    v = THREE.Vector3()
    for i in range(p.count):
        v.fromBufferAttribute(p, i)
        fn(v, i)
        p.setXYZ(i, v.x, v.y, v.z)
    p.needsUpdate = True
    geo.computeVertexNormals()
    return geo


# Merges the meshes of every animated sub-group (finish() leaves noMerge groups alone).
def mergeParts(root):
    groups = []

    def f(o):
        if o is not root and not getattr(o, 'isMesh', False) and o.userData.noMerge:
            groups.append(o)
    root.traverse(f)
    for gr in groups:
        K.merge(gr)


# finish() + detached sub-rigs (baked separately or not at all) + per-part merges + fresh stats.
def finishRig(game, g, o=None):
    o = o or {}
    detach = o.get('detach', [])
    fin = o.get('finish', {})
    det = [[d, d.parent] for d in detach if d]
    for d, p in det:
        p.remove(d)
    K.finish(game, g, fin)
    for d, p in det:
        p.add(d)
    ensureColors(g)
    mergeParts(g)

    def f(m):
        if not getattr(m, 'isMesh', False):
            return
        m.receiveShadow = True
        if m.userData.noShadow or m.material.type == 'ShaderMaterial' or m.material.transparent or \
                m.material.type == 'MeshBasicMaterial':
            m.castShadow = False
    g.traverse(f)
    g.userData.stats = K.stats(g)
    return g


def ensureColors(root):
    def f(o):
        if getattr(o, 'isMesh', False) and o.material is not None and getattr(o.material, 'vertexColors', False) \
                and o.geometry.attributes.color is None:
            o.geometry = o.geometry.clone()
            o.geometry.setAttribute('color', THREE.BufferAttribute(
                np.ones((o.geometry.attributes.position.count, 3)), 3))
    root.traverse(f)
    return root


def flagTree(o, flags):
    def f(m):
        if getattr(m, 'isMesh', False):
            m.userData.update(flags)
    o.traverse(f)


# ================================================================================================= TELLY
# Body space: parts.body origin = cabinet bottom center (world y 0.35 at rest). Front faces -z; the viewer's
# right is -x, so the control column (dial, UHF, sunburst grille) sits at negative x.
TL = JSObj(
    legH=0.35, w=1.3, h=1.0, d=0.6,
    sx=0.12, sy=0.55, sw=0.8, sh=0.6,          # screen window (body space)
    cx=-0.43,                                  # control column x
    fz=-0.32,                                  # faceplate front z
    screenZ=-0.105,                            # CRT canvas (back wall of the diorama)
    legSplay=[0.27, 0.19],
    bulge=0.034,                               # pillowy side walls (toy look)
)
TL.legDir = V(math.sin(TL.legSplay[0]), -1, math.sin(TL.legSplay[1])).normalize()
TL.legLen = TL.legH / -TL.legDir.y             # along the splayed axis
TL.extLen = 0.4 / -TL.legDir.y                 # telescoping travel along the axis (+0.4 m of height)
# VHF detents: 2..13 then the blank notch, clockwise from lower-left, blank at 6 o'clock.
TL.dialOrder = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0]
TL.dialStep = TAU / 13
TL.dialAngle = lambda i: i * TL.dialStep - (12 * TL.dialStep - math.pi)   # clockwise-from-top angle (= rotation.z)


def tellyAtlas():
    def draw(ctx, W, H, rand):
        choc = '#4A2A1A'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        # --- VHF ring (0,0)-(256,256)
        c = 128
        grd = ctx.createRadialGradient(c, c - 30, 10, c, c, 128)
        grd.addColorStop(0, '#FBF1D8')
        grd.addColorStop(1, '#E9D6AE')
        ctx.fillStyle = grd
        ctx.beginPath()
        ctx.arc(c, c, 128, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#B8893A'
        ctx.lineWidth = 7
        ctx.beginPath()
        ctx.arc(c, c, 124, 0, TAU)
        ctx.stroke()
        ctx.strokeStyle = 'rgba(90,58,34,0.35)'
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(c, c, 70, 0, TAU)
        ctx.stroke()
        for i, ch in enumerate(TL.dialOrder):
            a = TL.dialAngle(i)
            x, y = c + math.sin(a) * 97, c - math.cos(a) * 97
            if ch == 0:  # the blank notch: an empty slot
                ctx.save()
                ctx.translate(x, y)
                ctx.rotate(a)
                ctx.fillStyle = '#5A3A22'
                ctx.beginPath()
                ctx.roundRect(-10, -14, 20, 28, 8)
                ctx.fill()
                ctx.fillStyle = '#2A1810'
                ctx.beginPath()
                ctx.roundRect(-6, -10, 12, 20, 5)
                ctx.fill()
                ctx.restore()
            else:
                ctx.font = '%dpx "Titan One", "Arial Black", sans-serif' % (27 if ch >= 10 else 31)
                ctx.fillStyle = PAL.channelRed if ch == 13 else choc
                ctx.fillText(str(ch), x, y + 1)
            b = a + TL.dialStep / 2  # tick between detents
            ctx.fillStyle = '#B8893A'
            ctx.beginPath()
            ctx.arc(c + math.sin(b) * 112, c - math.cos(b) * 112, 3.2, 0, TAU)
            ctx.fill()
        # --- grille cloth (256,0)-(512,256): dark woven cloth with gold threads
        ctx.fillStyle = '#3A2418'
        ctx.fillRect(256, 0, 256, 256)
        for i in range(0, 256, 4):
            ctx.fillStyle = 'rgba(150,110,60,0.25)' if i % 8 else 'rgba(210,160,80,0.35)'
            ctx.fillRect(256 + i, 0, 1.5, 256)
            ctx.fillStyle = 'rgba(20,10,6,0.35)' if i % 8 else 'rgba(170,120,60,0.22)'
            ctx.fillRect(256, i, 256, 1.5)
        # --- UHF ring (0,256)-(128,384)
        cx, cy = 64, 320
        ctx.fillStyle = '#EFE0BC'
        ctx.beginPath()
        ctx.arc(cx, cy, 64, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#B8893A'
        ctx.lineWidth = 4
        ctx.beginPath()
        ctx.arc(cx, cy, 61, 0, TAU)
        ctx.stroke()
        ctx.strokeStyle = choc
        ctx.lineWidth = 2.5
        for i in range(21):
            a, ln = -math.pi * 0.8 + (i / 20) * math.pi * 1.6, (6 if i % 5 else 11)
            ctx.beginPath()
            ctx.moveTo(cx + math.sin(a) * 55, cy - math.cos(a) * 55)
            ctx.lineTo(cx + math.sin(a) * (55 - ln), cy - math.cos(a) * (55 - ln))
            ctx.stroke()
        ctx.fillStyle = PAL.channelRed
        ctx.font = '15px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('UHF', cx, cy + 46)
        # --- medallion (128,256)-(256,384): brass "13"
        cx, cy = 192, 320
        grd = ctx.createRadialGradient(cx - 18, cy - 22, 4, cx, cy, 64)
        grd.addColorStop(0, '#FFE7A8')
        grd.addColorStop(0.55, '#D9A441')
        grd.addColorStop(1, '#8A5E1E')
        ctx.fillStyle = grd
        ctx.beginPath()
        ctx.arc(cx, cy, 64, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = PAL.channelRed
        ctx.lineWidth = 7
        ctx.beginPath()
        ctx.arc(cx, cy, 52, 0, TAU)
        ctx.stroke()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(cx, cy, 46, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.font = '50px "Titan One", "Arial Black", sans-serif'
        ctx.fillText('13', cx, cy + 3)
        # --- nameplate (256,256)-(512,320)
        grd = ctx.createLinearGradient(0, 256, 0, 320)
        grd.addColorStop(0, '#F3D58A')
        grd.addColorStop(0.5, '#C8963C')
        grd.addColorStop(1, '#8A6224')
        ctx.fillStyle = grd
        ctx.beginPath()
        ctx.roundRect(256, 256, 256, 64, 14)
        ctx.fill()
        ctx.strokeStyle = '#5A3A18'
        ctx.lineWidth = 3
        ctx.beginPath()
        ctx.roundRect(262, 262, 244, 52, 10)
        ctx.stroke()
        ctx.font = '38px "Shrikhand", "Cooper Black", Georgia, serif'
        ctx.fillStyle = 'rgba(60,30,10,0.45)'
        ctx.fillText('Telly-Vision', 385, 292)
        ctx.fillStyle = '#4A2410'
        ctx.fillText('Telly-Vision', 384, 290)
        # --- back label (256,320)-(512,384)
        ctx.fillStyle = '#F2E6C6'
        ctx.fillRect(256, 320, 256, 64)
        ctx.strokeStyle = '#B5472A'
        ctx.lineWidth = 3
        ctx.strokeRect(259, 323, 250, 58)
        ctx.fillStyle = '#B5472A'
        ctx.beginPath()
        ctx.moveTo(282, 334)
        ctx.lineTo(296, 362)
        ctx.lineTo(268, 362)
        ctx.closePath()
        ctx.fill()
        ctx.fillStyle = '#F2E6C6'
        ctx.font = '16px "Titan One", sans-serif'
        ctx.fillText('!', 282, 353)
        ctx.fillStyle = '#3A2418'
        ctx.font = '13px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('TELLY-VISION  MOD. 13', 400, 338)
        ctx.font = '10px "Titan One", sans-serif'
        ctx.fillText('CAUTION: HIGH VOLTAGE INSIDE', 400, 355)
        ctx.fillText('WZTV CHANNEL 13 · PROPERTY', 400, 370)
        # --- back panel (0,384)-(512,512): hardboard with vent slots
        ctx.fillStyle = '#9C7A52'
        ctx.fillRect(0, 384, 512, 128)
        for i in range(900):
            ctx.fillStyle = 'rgba(%s,0.12)' % ('60,40,20' if rand() < 0.5 else '200,170,120')
            ctx.fillRect(rand() * 512, 384 + rand() * 128, 2, 1)
        ctx.fillStyle = '#3A2616'
        for r in range(3):
            for i in range(14):
                ctx.beginPath()
                ctx.roundRect(40 + i * 31, 404 + r * 34, 12, 24, 6)
                ctx.fill()
    return K.tex.canvas('telly_atlas_v1', 512, 512, draw, {'repeat': False, 'fonts': True})


# The white, puffy, four-fingered cartoon glove. Origin = wrist (top of the cuff); fingers along +Y, palm
# toward -Z, stitch lines on the back (+Z). Returns { glove, hold, fingers:{index,middle,pinky,thumb} }.
def buildGlove(white):
    glove = grp('glove')
    W, SEAM = '#FBF7EE', '#D8CCB6'
    # cuff: flared bell with a rolled lip, below the wrist
    cuff = K.lathe([[0.058, 0.0], [0.064, -0.03], [0.08, -0.07], [0.098, -0.1]], {'seg': 16})
    glove.add(K.m(tinted(cuff, W), white, {'pos': [0, 0, 0]}))
    glove.add(K.m(tinted(K.tube(ringXZ(0.097, 14, -0.1), 0.014, {'seg': 16, 'radial': 5, 'closed': True}), W), white))
    glove.add(K.m(tinted(K.tube(ringXZ(0.059, 12, 0.0), 0.01, {'seg': 14, 'radial': 4, 'closed': True}), W), white))
    # palm: puffy squashed ball
    palm = THREE.SphereGeometry(1, 13, 9)
    palm.scale(0.088, 0.098, 0.056)
    palm.translate(0, 0.088, 0)
    glove.add(K.m(tinted(palm, W), white))
    # three stitch lines on the back of the hand
    for x in [-0.034, 0, 0.034]:
        pts = []
        for i in range(7):
            y = 0.035 + i * 0.017
            nx, ny = x / 0.088, (y - 0.088) / 0.098
            pts.append([x, y, 0.056 * math.sqrt(max(0.02, 1 - nx * nx - ny * ny)) + 0.002])
        glove.add(K.m(tinted(K.tube(pts, 0.0038, {'seg': 5, 'radial': 3}), SEAM), white))
    # fingers: fat sausages pivoting at the knuckles (curl = rotation.x negative, toward the palm)
    fingers = JSObj()
    fdef = [['index', 0.05, 0.078, -0.16], ['middle', 0.0, 0.088, 0.0], ['pinky', -0.05, 0.07, 0.17]]
    for name, x, ln, fan in fdef:
        f = grp('glove_%s' % name, [x, 0.155, 0.0])
        cap = THREE.CapsuleGeometry(0.031, ln, 3, 9)
        cap.translate(0, ln / 2 + 0.012, 0)

        def puffy(v, i, ln=ln):  # puffy middle
            t = clamp(v.y / (ln + 0.04), 0, 1)
            k = 1 + 0.1 * math.sin(t * math.pi)
            v.x *= k
            v.z *= k
        warp(cap, puffy)
        f.add(K.m(tinted(cap, W), white))
        f.rotation.set(-0.12, 0, fan)
        glove.add(f)
        fingers[name] = f
    th = grp('glove_thumb', [0.07, 0.07, -0.018])
    tcap = THREE.CapsuleGeometry(0.033, 0.058, 3, 9)
    tcap.translate(0, 0.045, 0)
    th.add(K.m(tinted(tcap, W), white))
    th.rotation.set(-0.35, 0.2, -0.95)
    glove.add(th)
    fingers.thumb = th
    # hold point: where the presented item rests (on the palm side)
    hold = grp('glove_hold', [0, 0.1, -0.1])
    glove.add(hold)
    return JSObj(glove=glove, hold=hold, fingers=fingers)


# Stretchy ribbed tube arm (dynamic geometry, updated by updateTellyArm).
ARM = JSObj(rings=32, radial=9, r=0.052, ribs=9, restLen=0.6)


def armGeometry():
    n = (ARM.rings + 1) * (ARM.radial + 1)
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.BufferAttribute(np.zeros((n, 3)), 3))
    g.setAttribute('normal', THREE.BufferAttribute(np.zeros((n, 3)), 3))
    g.setAttribute('color', THREE.BufferAttribute(np.ones((n, 3)), 3))
    g.setAttribute('uv', THREE.BufferAttribute(np.zeros((n, 2)), 2))
    idx = []
    for i in range(ARM.rings):
        for j in range(ARM.radial):
            a = i * (ARM.radial + 1) + j
            b = a + ARM.radial + 1
            idx += [a, a + 1, b, a + 1, b + 1, b]
    g.setIndex(idx)
    return g


_a0, _a1, _a2, _p = THREE.Vector3(), THREE.Vector3(), THREE.Vector3(), THREE.Vector3()
_t, _n, _b, _q = THREE.Vector3(), THREE.Vector3(), THREE.Vector3(), THREE.Vector3()
ARM_GOLD, ARM_DARK = THREE.Color('#F2A51E'), THREE.Color('#9A4E0C')


# Rebuilds Telly's arm tube from parts.armRig origin (inside the screen) through parts.armCtrl (curve control)
# to the glove's cuff. Call after moving parts.glove / parts.armCtrl. The tube thins as it stretches and its
# accordion ribs spread out (fixed rib count).
def updateTellyArm(g):
    P = g.userData.parts
    arm, glove, ctrl = P.arm, P.glove, P.armCtrl
    if not arm or not glove:
        return
    glove.updateMatrix()
    _a0.set(0, 0, 0)
    _a1.copy(ctrl.position)
    _a2.set(0, -0.085, 0).applyMatrix4(glove.matrix)   # cuff mouth
    # arc length (coarse)
    L = 0

    def bez(t, out):
        return out.set(0, 0, 0).addScaledVector(_a0, (1 - t) * (1 - t)).addScaledVector(_a1, 2 * (1 - t) * t) \
            .addScaledVector(_a2, t * t)
    prev = THREE.Vector3().copy(_a0)
    for i in range(1, 17):
        bez(i / 16, _p)
        L += _p.distanceTo(prev)
        prev.copy(_p)
    thin = math.sqrt(clamp(ARM.restLen / max(L, 1e-3), 0.45, 1.25))
    pos, nor = arm.geometry.attributes.position, arm.geometry.attributes.normal
    col, uv = arm.geometry.attributes.color, arm.geometry.attributes.uv
    # parallel-transport frame
    _n.set(1, 0, 0)
    c = THREE.Color()
    for i in range(ARM.rings + 1):
        t = i / ARM.rings
        bez(t, _p)
        # tangent
        _t.set(0, 0, 0).addScaledVector(_a0, -2 * (1 - t)).addScaledVector(_a1, 2 - 4 * t).addScaledVector(_a2, 2 * t)
        if _t.lengthSq() < 1e-10:
            _t.set(0, 0, -1)
        _t.normalize()
        _n.sub(_q.copy(_t).multiplyScalar(_n.dot(_t)))
        if _n.lengthSq() < 1e-8:
            _n.set(0, 1, 0).sub(_q.copy(_t).multiplyScalar(_t.y))
        _n.normalize()
        _b.crossVectors(_t, _n)
        rib = 0.5 + 0.5 * math.cos(t * ARM.ribs * TAU)
        r = ARM.r * thin * (0.84 + 0.26 * rib) * (1.08 - 0.2 * t)
        c.copy(ARM_DARK).lerp(ARM_GOLD, 0.35 + 0.65 * rib)
        for j in range(ARM.radial + 1):
            a = (j / ARM.radial) * TAU
            ca, sa = math.cos(a), math.sin(a)
            k = i * (ARM.radial + 1) + j
            nx, ny, nz = _n.x * ca + _b.x * sa, _n.y * ca + _b.y * sa, _n.z * ca + _b.z * sa
            pos.setXYZ(k, _p.x + nx * r, _p.y + ny * r, _p.z + nz * r)
            nor.setXYZ(k, nx, ny, nz)
            col.setXYZ(k, c.r, c.g, c.b)
            uv.setXY(k, j / ARM.radial, t)
    arm.geometry.computeBoundingSphere()
    arm.geometry.computeBoundingBox()


# Legs telescope: t = 0 (rest, top at 1.35 m) .. 1 (standing, +0.4 m). Moves parts.body and every leg's
# chrome tube/foot so the feet stay on the floor.
def setTellyLegs(g, t):
    P = g.userData.parts
    t = clamp(t, 0, 1)
    P.body.position.y = TL.legH + t * 0.4
    for leg in P.legs:
        tube = leg.getObjectByName(leg.userData.tubeName) if leg.userData.tubeName else None
        foot = leg.getObjectByName(leg.userData.footName)
        if tube is not None:
            tube.scale.y = max(1e-3, t)
            tube.visible = t > 0.01
        if foot is not None:
            foot.position.y = -0.14 - t * TL.extLen


# Turns the VHF dial to a channel (2..13, 0 = blank notch); returns the rotation.z used.
def setTellyDial(g, ch):
    i = max(0, TL.dialOrder.index(ch) if ch in TL.dialOrder else -1)
    a = TL.dialAngle(i)
    g.userData.parts.dial.rotation.z = a
    return a


# Glove poses for previews: 'hidden' | 'present' | 'fingerguns' | 'wag'. The machine animates the same parts.
def setTellyGlove(g, pose='present'):
    P = g.userData.parts
    F = P.gloveFingers
    show = pose != 'hidden'
    P.glove.visible = show
    P.arm.visible = show
    if P.glass:
        P.glass.visible = not show           # the membrane has parted while the glove is out
    if not show:
        P.glove.position.set(0, 0, 0.02)
        P.glove.quaternion.identity()
        P.armCtrl.position.set(0, 0, -0.02)
        updateTellyArm(g)
        return
    # item 0.8 m in front of the screen at 1.2 m height (legs at rest): palm up, fingers to the viewer's left
    P.glove.position.set(-0.02, 1.12 - (TL.legH + TL.sy), -0.74)
    P.armCtrl.position.set(0.06, -0.26, -0.34)
    y = V(1, 0.28, -0.3).normalize()
    z = V(0, -1, 0.1)
    z.sub(y.clone().multiplyScalar(z.dot(y))).normalize()
    x = THREE.Vector3().crossVectors(y, z)
    P.glove.quaternion.setFromRotationMatrix(THREE.Matrix4().makeBasis(x, y, z))
    P.gloveHold.quaternion.copy(P.glove.quaternion).invert()   # hold stays aligned with Telly's axes
    curl = {'present': [-0.35, -0.45, -0.55, -0.3], 'fingerguns': [-0.05, -1.9, -2.0, 0.3],
            'wag': [0.05, -1.9, -2.0, -1.2]}.get(pose) or [-0.3, -0.3, -0.3, -0.3]
    F.index.rotation.x = curl[0]
    F.middle.rotation.x = curl[1]
    F.pinky.rotation.x = curl[2]
    F.thumb.rotation.x = curl[3] - 0.35
    if pose == 'fingerguns' or pose == 'wag':
        P.glove.quaternion.setFromEuler(THREE.Euler(-0.25, 0.25, 0.2 if pose == 'wag' else -math.pi / 2 + 0.2))
        P.glove.position.set(0.05, 0.62, -0.62)
    updateTellyArm(g)


def _telly(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('telly')
    kc = {'keepColor': True}
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.42}), **kc})
    plastic = K.mat(game, 'plastic', '#ffffff', {'rough': 0.42, **kc})   # tinted per part (faceplate, knobs, glove, arm)
    brass = K.mat(game, 'brass', '#C8963C', kc)
    chrome = K.mat(game, 'chrome', '#A8B0BA', kc)
    atlas = K.mat(game, 'plastic', '#ffffff', {'map': tellyAtlas(), 'rough': 0.45, **kc})
    glass = game.mats.glass('#E8F4FF', {'opacity': 0.1})
    CREAM, DARK, LINER, KNOB = '#F3E3C0', '#3A2630', '#2E2238', '#4A2C1E'

    body = grp('body', [0, TL.legH, 0])
    g.add(body)
    w, h, d, sx, sy, sw, sh, cx, fz = TL.w, TL.h, TL.d, TL.sx, TL.sy, TL.sw, TL.sh, TL.cx, TL.fz

    # ---- carcass: rounded walnut shell with the diorama opening (one extrude, hole = screen tunnel)
    shape = rrShape(w, h, 0.21, 0, h / 2)
    shape.holes.append(rrPath(sw + 0.05, sh + 0.05, 0.1, sx, sy, 6))

    def pillow(v, i):
        # pillowy toy sides: the outer walls bow out a little at mid height (the window/liner area is untouched)
        yn = (v.y - h / 2) / (h / 2)
        v.x += js_sign(v.x) * TL.bulge * (1 - yn * yn) * smoothstep(abs(v.x), 0.56, 0.66)
        v.z += js_sign(v.z) * 0.018 * (1 - yn * yn) * smoothstep(abs(v.z), 0.24, 0.3)
    carcass = warp(K.extrude(shape, d, {'bevel': 0.05, 'bevelSeg': 2, 'curveSeg': 5}), pillow)
    carcassUV = K.uvBox(carcass, 1.1)
    body.add(K.m(carcassUV, walnut))
    # lid with overhang
    body.add(K.m(K.box(w + 0.06, 0.09, d + 0.06, 0.045, {'uv': 1.1, 'swap': True}), walnut,
                 {'pos': [0, h + 0.036, 0]}))   # puffy toy lid
    # ---- cream faceplate framing screen + control column
    fpW, fpH, fpD = 1.16, 0.76, 0.036
    fp = rrShape(fpW, fpH, 0.17)
    fp.holes.append(rrPath(sw, sh, 0.085, sx, 0, 5))
    body.add(K.m(tinted(K.extrude(fp, fpD, {'bevel': 0.012, 'bevelSeg': 1, 'curveSeg': 5}), CREAM), plastic,
                 {'pos': [0, sy, fz + fpD / 2]}))
    # diorama liner (tunnel walls) and the brass lip around the window
    liner = rrShape(sw + 0.052, sh + 0.052, 0.1)
    liner.holes.append(rrPath(sw, sh, 0.085, 0, 0, 5))
    body.add(K.m(tinted(K.extrude(liner, 0.22, {'bevel': 0.004, 'bevelSeg': 1, 'curveSeg': 5}), LINER), plastic,
                 {'pos': [sx, sy, fz + 0.11]}))
    body.add(K.m(K.tube(rrXY(sw + 0.012, sh + 0.012, 0.09, 0, 4), 0.009, {'seg': 36, 'radial': 4, 'closed': True}),
                 brass, {'pos': [sx, sy, fz - 0.002]}))

    # ---- CRT canvas (rubber glass, scr_telly) at the back of the diorama, weapon slot, front glass
    card = None if ('card' in opts and opts['card'] is None) else getCard(
        opts['card'] if opts.get('card') is not None else 'telly_face',
        {'expr': opts['expr'] if opts.get('expr') is not None else 'idle'})
    scrMat = game.mats.rubberGlass(card, {'w': sw + 0.04, 'h': sh + 0.04, 'bright': 1.05})
    screen = keep(THREE.Mesh(game.mats.screenGeometry(sw + 0.04, sh + 0.04), scrMat))
    screen.name = 'screen'
    screen.rotation.y = math.pi                 # shader bulges along local +z -> world -z (out of the TV)
    screen.position.set(sx, sy, TL.screenZ)
    screen.userData.screenGroup = 'scr_telly'
    screen.castShadow = False
    body.add(screen)
    weaponSlot = grp('weaponSlot', [sx, sy, (TL.screenZ + fz) / 2])
    body.add(weaponSlot)
    glassGeo = THREE.PlaneGeometry(sw + 0.02, sh + 0.02, 12, 9)

    def dome(v, i):
        x, y = v.x / (sw / 2), v.y / (sh / 2)
        v.z = 0.018 * max(0, 1 - 0.5 * x * x - 0.5 * y * y)
    warp(glassGeo, dome)
    glassGeo.rotateY(math.pi)
    glassMesh = keep(K.m(glassGeo, glass, {'pos': [sx, sy, fz + 0.006], 'name': 'glass'}))
    glassMesh.userData.noOcclude = True
    body.add(glassMesh)

    # ---- control column: VHF dial (fist-sized chicken-head knob over a printed ring), UHF knob, sunburst grille
    vy, uy, gy = sy + 0.2, sy - 0.005, sy - 0.215
    body.add(K.m(disc(0.112, 36, [0, 0, 256, 256]), atlas, {'pos': [cx, vy, fz - 0.003]}))
    body.add(K.m(K.tube(ringXY(0.113, 20, 0), 0.0065, {'seg': 24, 'radial': 4, 'closed': True}), brass,
                 {'pos': [cx, vy, fz - 0.003]}))
    dial = grp('dial', [cx, vy, fz - 0.004])
    dial.add(K.m(tinted(knobGeo(0.058, 0.07, {'flutes': 10, 'amp': 0.07, 'seg': 30, 'flange': 1.07}), KNOB), plastic))
    ptrShape = [[0, 0.082], [0.018, 0.042], [0.024, -0.022], [0.015, -0.052], [-0.015, -0.052], [-0.024, -0.022],
                [-0.018, 0.042]]
    dial.add(K.m(tinted(K.extrude(ptrShape, 0.022, {'bevel': 0.007, 'bevelSeg': 2}), CREAM), plastic,
                 {'pos': [0, 0, -0.079]}))
    dial.add(K.m(K.tube([[0, 0.068, -0.0905], [0, 0.0, -0.0905]], 0.004, {'seg': 2, 'radial': 5}),
                 K.glow(game, PAL.channelRed, 1.2)))
    dial.add(K.m(K.cyl(0.018, 0.02, 0.008, {'bevel': 0.003, 'seg': 10}), brass,
                 {'pos': [0, 0, -0.089], 'rot': [-math.pi / 2, 0, 0]}))
    body.add(dial)
    # UHF fine tune
    body.add(K.m(disc(0.045, 28, [0, 256, 128, 384]), atlas, {'pos': [cx, uy, fz - 0.003]}))
    uhf = grp('uhf', [cx, uy, fz - 0.004])
    uhf.add(K.m(tinted(knobGeo(0.024, 0.034, {'seg': 12, 'flange': 0}), KNOB), plastic))
    uhf.add(K.m(K.cyl(0.012, 0.013, 0.004, {'bevel': 0.0015, 'seg': 8}), brass,
                {'pos': [0, 0, -0.034], 'rot': [-math.pi / 2, 0, 0]}))
    uhf.add(K.m(tinted(K.box(0.005, 0.02, 0.006, 0.002), CREAM), plastic, {'pos': [0, 0.012, -0.036]}))
    uhf.rotation.z = 0.5
    body.add(uhf)
    # pilot jewel
    pilot = keep(K.m(THREE.SphereGeometry(0.011, 8, 6), K.glow(game, PAL.onAirRed, 2.2),
                     {'pos': [cx + 0.075, uy + 0.03, fz - 0.004], 'name': 'pilot'}))
    body.add(pilot)
    body.add(K.m(K.cyl(0.016, 0.017, 0.006, {'bevel': 0.002, 'seg': 10}), brass,
                 {'pos': [cx + 0.075, uy + 0.03, fz], 'rot': [-math.pi / 2, 0, 0]}))
    # sunburst speaker grille
    body.add(K.m(disc(0.1, 30, [256, 0, 512, 256]), atlas, {'pos': [cx, gy, fz - 0.002]}))
    body.add(K.m(K.tube(ringXY(0.102, 20, 0), 0.008, {'seg': 24, 'radial': 4, 'closed': True}), brass,
                 {'pos': [cx, gy, fz - 0.004]}))
    rays, star = 16, []
    for i in range(rays * 2):
        a = (i / (rays * 2)) * TAU + math.pi / 2
        r = 0.024 if i % 2 else 0.094
        star.append([math.cos(a) * r, math.sin(a) * r])
    body.add(K.m(K.extrude(star, 0.01, {'bevel': 0}), brass, {'pos': [cx, gy, fz - 0.008]}))
    body.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.028, 0.012], [0.018, 0.02], [0, 0.022]],
                         {'seg': 12, 'round': 0.006, 'steps': 1}), brass,
                 {'pos': [cx, gy, fz - 0.01], 'rot': [-math.pi / 2, 0, 0]}))
    body.add(K.m(disc(0.017, 20, [128, 256, 256, 384]), atlas, {'pos': [cx, gy, fz - 0.0325]}))
    # nameplate on the apron
    body.add(K.m(cellUV(K.box(0.34, 0.064, 0.012, 0.004).clone(), 256, 256, 512, 320), atlas,
                 {'pos': [0.02, 0.09, -d / 2 - 0.004]}))

    # ---- back: hardboard panel with vents, label, cord grommet
    body.add(K.m(cellUV(THREE.PlaneGeometry(1.08, 0.72), 0, 384, 512, 512), atlas, {'pos': [0.06, sy, d / 2 + 0.003]}))
    body.add(K.m(cellUV(THREE.PlaneGeometry(0.26, 0.066), 256, 320, 512, 384), atlas,
                 {'pos': [0.28, sy + 0.24, d / 2 + 0.005]}))
    body.add(K.m(tinted(K.cyl(0.02, 0.022, 0.012, {'bevel': 0.004, 'seg': 12}), DARK), plastic,
                 {'pos': [-0.36, 0.26, d / 2 + 0.006], 'rot': [math.pi / 2, 0, 0]}))

    # ---- cord tail with a plug (named: it can wag)
    cord = grp('cord', [-0.36, 0.26, d / 2 + 0.01])
    fy = -TL.legH - 0.26 + 0.009             # floor in cord space
    cpts = [[0, 0, 0], [-0.02, -0.08, 0.07], [-0.06, -0.36, 0.13], [-0.01, fy + 0.01, 0.2], [0.1, fy, 0.25],
            [0.21, fy, 0.22]]
    cord.add(K.m(tinted(K.tube(cpts, 0.0085, {'seg': 22, 'radial': 5}), '#5A3A22'), plastic))
    plug = THREE.Group()
    plug.position.set(0.235, fy + 0.006, 0.212)
    plug.rotation.set(0, 0.35, 0)
    plug.add(K.m(tinted(K.box(0.05, 0.03, 0.036, 0.011), '#4A3020'), plastic, {'pos': [0, 0.008, 0]}))
    for s in [-1, 1]:
        plug.add(K.m(THREE.BoxGeometry(0.03, 0.012, 0.004), brass, {'pos': [0.038, 0.01, s * 0.009]}))
    cord.add(plug)
    body.add(cord)

    # ---- legs: splayed tapered walnut, brass collar, hidden chrome telescoping tube, brass sabot feet
    legs = []
    corners = [[1, -1], [-1, -1], [1, 1], [-1, 1]]
    for i, (sxx, szz) in enumerate(corners):
        leg = grp('leg%d' % i, [sxx * 0.5, 0.004, szz * 0.19])
        dr = V(sxx * math.sin(TL.legSplay[0]), -1, szz * math.sin(TL.legSplay[1])).normalize()
        leg.quaternion.setFromUnitVectors(V(0, -1, 0), dr)
        leg.add(K.m(K.uvScale(K.cyl(0.058, 0.043, 0.14, {'bevel': 0.012, 'seg': 8}).clone(), 1, 2), walnut,
                    {'pos': [0, -0.14, 0]}))   # chunky toy legs
        leg.add(K.m(K.lathe([[0, 0], [0.048, 0], [0.048, 0.03], [0, 0.03]], {'seg': 10, 'round': 0.009, 'steps': 1}),
                    brass, {'pos': [0, -0.158, 0]}))
        tube = grp('leg%d_tube' % i, [0, -0.14, 0])
        tm = K.m(K.cyl(0.028, 0.028, TL.extLen, {'bevel': 0.004, 'seg': 8}), chrome, {'pos': [0, -TL.extLen, 0]})
        tm.userData.noAO = True
        tm.userData.noOcclude = True
        tube.add(tm)
        leg.add(tube)
        foot = grp('leg%d_foot' % i, [0, -0.14, 0])
        lowLen = TL.legLen - 0.14 - 0.04
        foot.add(K.m(K.uvScale(K.cyl(0.042, 0.032, lowLen, {'bevel': 0.008, 'seg': 8}).clone(), 1, 2), walnut,
                     {'pos': [0, -lowLen, 0]}))
        foot.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.044, 0.018], [0.044, 0.034], [0.032, 0.048], [0, 0.052]],
                             {'seg': 10, 'round': 0.008, 'steps': 1}), brass,
                     {'pos': [0, -lowLen - 0.04, 0]}))   # round brass booties
        leg.add(foot)
        leg.userData.tubeName = tube.name
        leg.userData.footName = foot.name
        body.add(leg)
        legs.append(leg)

    # ---- rabbit ears on a swivel dome (antennas spin about Y like propellers; earL/earR splay/droop)
    antennas = grp('antennas', [0.0, h + 0.05, 0.12])
    antennas.add(K.m(tinted(K.lathe([[0, 0], [0.075, 0], [0.078, 0.014], [0.05, 0.05], [0.02, 0.062], [0, 0.064]],
                                    {'seg': 15, 'round': 0.012, 'steps': 1}), KNOB), plastic))
    antennas.add(K.m(K.tube(ringXZ(0.072, 16, 0.012), 0.005, {'seg': 18, 'radial': 4, 'closed': True}), brass))
    antennas.add(K.m(THREE.SphereGeometry(0.026, 10, 6), brass, {'pos': [0, 0.066, 0]}))
    ears = JSObj()
    for name, s in [['earL', 1], ['earR', -1]]:
        ear = grp(name, [s * 0.014, 0.07, 0])
        y = 0
        for r, ln in [[0.0095, 0.27], [0.0075, 0.25], [0.0058, 0.22]]:
            ear.add(K.m(K.cyl(r, r + 0.0012, ln, {'bevel': 0.0015, 'seg': 6}), chrome, {'pos': [0, y, 0]}))
            y += ln - 0.01
        ear.add(K.m(THREE.SphereGeometry(0.036, 9, 6), chrome, {'pos': [0, y + 0.024, 0]}))   # big bobble tips
        ear.rotation.set(0.06 if s > 0 else 0.2, 0, -s * (0.44 if s > 0 else 0.6))   # a little lopsided = cute
        antennas.add(ear)
        ears[name] = ear
    body.add(antennas)

    # ---- glove + stretchy arm, living inside the diorama (hidden until the machine calls it out)
    armRig = grp('armRig', [sx, sy, TL.screenZ - 0.03])
    armCtrl = grp('armCtrl', [0, -0.2, -0.3])
    armRig.add(armCtrl)
    gl = buildGlove(plastic)
    gl.glove.scale.setScalar(1.35)
    armRig.add(gl.glove)
    armMesh = keep(THREE.Mesh(armGeometry(), plastic))
    armMesh.name = 'arm'
    armMesh.userData.noAO = True
    armMesh.userData.noOcclude = True
    armMesh.frustumCulled = False
    armRig.add(armMesh)
    body.add(armRig)
    # glove gets its own AO bake (puffy crevices between fingers), then is kept out of the main bake
    gl.glove.updateMatrixWorld(True)
    K.bakeAO(gl.glove, {'floor': False, 'height': 0, 'res': 36, 'strength': 0.7})
    flagTree(gl.glove, {'noAO': True, 'noOcclude': True})

    parts = JSObj(
        body=body, screen=screen, glass=glassMesh, weaponSlot=weaponSlot, dial=dial, uhf=uhf, pilot=pilot,
        antennas=antennas, earL=ears.earL, earR=ears.earR, cord=cord,
        legs=legs, armRig=armRig, armCtrl=armCtrl, arm=armMesh, glove=gl.glove, gloveHold=gl.hold,
        gloveFingers=gl.fingers,
    )
    g.userData.parts = parts
    g.userData.screens = [JSObj(mesh=screen, group='scr_telly', id='telly')]
    g.userData.colliders = [{'min': [-0.72, 0, -0.38], 'max': [0.72, 1.42, 0.38]}]
    g.userData.interact = {'point': [sx, TL.legH + sy, -0.55], 'radius': 1.6}
    # Object.fromEntries(...) with channel-number keys: JS objects list integer keys in ascending order
    detents = JSObj()
    for i, ch in sorted(enumerate(TL.dialOrder), key=lambda e: e[1]):
        detents[str(ch)] = TL.dialAngle(i)
    g.userData.rig = {
        'bodyBaseY': TL.legH,
        'screen': {'w': sw, 'h': sh, 'center': [sx, sy, TL.screenZ], 'bulgeMax': 0.35},
        'dial': {'order': list(TL.dialOrder), 'step': TL.dialStep, 'detents': detents},
        'legs': {'travel': 0.4, 'axisTravel': TL.extLen},
        'glove': {'presentWorld': [sx, 1.2, -1.1]},
    }

    finishRig(game, g, {'detach': [antennas, armRig], 'finish': {'ao': {'res': 72, 'strength': 0.9}}})
    setTellyLegs(g, opts['legs'] if opts.get('legs') is not None else 0)
    setTellyDial(g, opts['channel'] if opts.get('channel') is not None else 13)
    setTellyGlove(g, opts['pose'] if opts.get('pose') is not None else 'hidden')
    if opts.get('demo') and opts.get('pose') and opts.get('pose') != 'hidden':
        gl.hold.add(ensureColors(demoRayGun(game)))
    return g


registerProp('telly', _telly,
             {'category': 'machines', 'tags': ['telly', 'machine', 'tv', 'mascot'], 'size': [1.44, 2.05, 0.76],
              'desc': 'Telly, the living walnut console TV (mystery box)', 'hero': True, 'cache': False})


# Placeholder item for previews only (the real weapon models come from the weapons module).
def demoRayGun(game):
    d = THREE.Group()
    teal = K.mat(game, 'plastic', PAL.teal, {'keepColor': True})
    chrome = K.mat(game, 'chrome', '#A8B0BA', {'keepColor': True})
    glowM = K.glow(game, PAL.greenScreen, 2.5)
    d.add(K.m(K.box(0.22, 0.07, 0.07, 0.03), teal, {'pos': [0, 0.02, 0]}))
    d.add(K.m(K.lathe([[0.03, 0], [0.045, 0.04], [0.03, 0.09], [0.05, 0.12], [0.05, 0.13], [0, 0.13]],
                      {'seg': 16, 'round': 0.008}), chrome, {'pos': [-0.11, 0.02, 0], 'rot': [0, 0, math.pi / 2]}))
    d.add(K.m(K.box(0.05, 0.1, 0.05, 0.02), teal, {'pos': [0.06, -0.05, 0], 'rot': [0, 0, -0.3]}))
    d.add(K.m(THREE.SphereGeometry(0.02, 10, 8), glowM, {'pos': [-0.245, 0.02, 0]}))
    for i in range(3):
        d.add(K.m(K.cyl(0.04, 0.04, 0.01, {'bevel': 0.003, 'seg': 14}), chrome,
                  {'pos': [-0.02 - i * 0.03, 0.02, 0], 'rot': [0, 0, math.pi / 2]}))
    d.rotation.set(0, math.pi, 0)
    d.position.set(0.02, 0.05, 0)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = True
    d.traverse(f)
    return d


# ======================================================================================== TELLY'S HOME SET
# Each of the four homes (GDD §10.2): couch facing a rug, a floor lamp, and (when empty) the dust footprint on the
# rug and an unplugged extension cord. "The lamp is on only where Telly lives."

# Lamp levels: 0 = off, ~0.35 = dim amber (before power), 1 = full. Swaps the bulb / lining / shade materials on
# this instance (materials themselves stay shared). The pooled light is the room code's job:
# game.lights.setAnchor(anchorId, { intensity: 1.6 * level }) (see userData.lightAnchors[0].id / opts.anchorId).
def setLampLevel(game, g, level=1):
    P = g.userData.parts
    q = js_round(clamp(level, 0, 1) * 20) / 20
    if P.bulb:
        P.bulb.material = K.glow(game, PAL.gelAmber if q < 0.6 else PAL.tungsten, 0.6 + 3.4 * q) if q > 0 \
            else K.mat(game, 'ceramic', '#E8DCC0')
    if P.lining:
        P.lining.material = K.glow(game, '#FFD9A0', 0.25 + 0.9 * q) if q > 0 else K.mat(game, 'fabric', '#8A6A3A')
    if P.shade:
        P.shade.material = lampShadeMat(game, q)
    g.userData.lampLevel = q


def lampShadeMat(game, q):
    return K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#E9B64A', {'pattern': 'plain', 'scale': 3}),
                                             'side': THREE.DoubleSide, 'emissive': '#FF9A40',
                                             'emissiveIntensity': 0.34 * q})


def _telly_lamp(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('telly_lamp')
    walnut = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.4})})
    brass = K.mat(game, 'brass', '#C8963C')
    trim = K.mat(game, 'fabric', '#B5472A', {'side': THREE.DoubleSide})
    # weighted round base: brass skirt + domed walnut puck
    g.add(K.m(K.lathe([[0, 0], [0.21, 0], [0.215, 0.02], [0.2, 0.034], [0, 0.034]],
                      {'seg': 18, 'round': 0.008, 'steps': 1}), brass))
    g.add(K.m(K.uvScale(K.lathe([[0, 0.03], [0.195, 0.03], [0.18, 0.07], [0.09, 0.09], [0, 0.092]],
                                {'seg': 18, 'round': 0.02, 'steps': 1}).clone(), 3, 1), walnut))
    # chunky turned walnut spindle up to the tray
    spindle = [[0, 0.085], [0.055, 0.085], [0.064, 0.13], [0.044, 0.18], [0.034, 0.3], [0.04, 0.37], [0.058, 0.43],
               [0.038, 0.51], [0.046, 0.58], [0, 0.58]]
    g.add(K.m(K.uvScale(K.lathe(spindle, {'seg': 11, 'round': 0.014, 'steps': 1}).clone(), 2, 2), walnut))
    # tray table with a brass gallery rail
    trayY = 0.6
    g.add(K.m(K.lathe([[0, 0], [0.235, 0], [0.25, 0.016], [0.24, 0.036], [0, 0.036]],
                      {'seg': 20, 'round': 0.01, 'steps': 1}), walnut, {'pos': [0, trayY - 0.02, 0]}))
    g.add(K.m(K.tube(ringXZ(0.236, 16, 0), 0.0075, {'seg': 20, 'radial': 3, 'closed': True}), brass,
              {'pos': [0, trayY + 0.05, 0]}))
    for i in range(6):
        a = (i / 6) * TAU + 0.3
        g.add(K.m(THREE.CylinderGeometry(0.005, 0.005, 0.05, 5, 1, True), brass,
                  {'pos': [math.cos(a) * 0.236, trayY + 0.028, math.sin(a) * 0.236]}))
    # upper stem + coupling + brass rod
    g.add(K.m(K.uvScale(K.cyl(0.024, 0.03, 0.4, {'bevel': 0.008, 'seg': 10}).clone(), 1, 3), walnut,
              {'pos': [0, trayY + 0.016, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.034, 0], [0.034, 0.05], [0, 0.05]], {'seg': 10, 'round': 0.01, 'steps': 1}), brass,
              {'pos': [0, trayY + 0.4, 0]}))
    g.add(K.m(K.cyl(0.013, 0.013, 0.34, {'bevel': 0.004, 'seg': 8}), brass, {'pos': [0, trayY + 0.44, 0]}))
    # socket + bulb (named part)
    bulbY = 1.5
    g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.06], [0.018, 0.074], [0, 0.074]],
                      {'seg': 9, 'round': 0.006, 'steps': 1}), brass, {'pos': [0, bulbY - 0.13, 0]}))
    bulb = keep(K.m(K.lathe([[0, 0], [0.018, 0.004], [0.04, 0.045], [0.046, 0.076], [0.031, 0.112], [0, 0.122]],
                            {'seg': 9, 'round': 0.012, 'steps': 1}), K.glow(game, PAL.tungsten, 4),
                    {'pos': [0, bulbY - 0.06, 0], 'name': 'bulb', 'cast': False}))
    bulb.userData.noOcclude = True
    g.add(bulb)
    # pleated bell shade (named part), glowing lining, piping and a scalloped fringe band
    y0, y1, rb, rt = 1.34, 1.72, 0.34, 0.17
    bell = []
    for i in range(6):
        t = i / 5
        bell.append(THREE.Vector2(lerp(rb, rt, t) + math.sin(t * math.pi) * 0.03 - t * t * 0.02, t * (y1 - y0)))

    def pleat(v, i):
        k = 1 + 0.035 * abs(math.cos(math.atan2(v.z, v.x) * 16))
        v.x *= k
        v.z *= k
    shadeGeo = warp(THREE.LatheGeometry(bell, 48), pleat)
    K.uvScale(shadeGeo, 12, 1.2)
    shade = keep(K.m(shadeGeo, lampShadeMat(game, 1), {'pos': [0, y0, 0], 'name': 'shade'}))
    g.add(shade)
    lining = keep(K.m(THREE.LatheGeometry(list(reversed([THREE.Vector2(p.x - 0.008, p.y) for p in bell])), 18),
                      K.glow(game, '#FFD9A0', 1.15), {'pos': [0, y0, 0], 'name': 'lining', 'cast': False}))
    lining.userData.noOcclude = True
    g.add(lining)
    g.add(K.m(K.tube(ringXZ(rb * 1.05, 24, 0), 0.015, {'seg': 30, 'radial': 4, 'closed': True}), trim,
              {'pos': [0, y0, 0]}))
    g.add(K.m(K.tube(ringXZ(rt * 1.04, 14, 0), 0.011, {'seg': 18, 'radial': 3, 'closed': True}), trim,
              {'pos': [0, y1, 0]}))

    def scallop(v, i):
        if v.y < -0.01:
            v.y = -0.052 + 0.024 * (1 - abs(math.cos(math.atan2(v.z, v.x) * 15)))  # round scallops
    band = warp(THREE.LatheGeometry([THREE.Vector2(rb * 1.06, -0.05), THREE.Vector2(rb * 1.05, 0)], 60), scallop)
    g.add(K.m(band, trim, {'pos': [0, y0, 0]}))
    for i in range(3):
        a = (i / 3) * TAU + 0.5
        g.add(K.m(K.tube([[0, bulbY + 0.12, 0], [math.sin(a) * rt * 0.6, y1 - 0.01, math.cos(a) * rt * 0.6],
                          [math.sin(a) * rt, y1, math.cos(a) * rt]], 0.005, {'seg': 5, 'radial': 3}), brass))
    g.add(K.m(K.lathe([[0, 0], [0.014, 0], [0.022, 0.02], [0.016, 0.038], [0, 0.046]],
                      {'seg': 7, 'round': 0.006, 'steps': 1}), brass, {'pos': [0, y1 + 0.005, 0]}))
    g.add(K.m(K.tube([[0.03, bulbY - 0.09, 0], [0.036, bulbY - 0.24, -0.01]], 0.002, {'seg': 3, 'radial': 3}), brass))
    g.add(K.m(THREE.SphereGeometry(0.009, 6, 5), brass, {'pos': [0.036, bulbY - 0.25, -0.01]}))

    g.userData.parts = JSObj(bulb=bulb, lining=lining, shade=shade)
    anchor = JSObj(pos=[0, 1.62, 0], color=PAL.tungsten, intensity=1.6, distance=4.5)
    if opts.get('anchorId'):
        anchor.id = opts['anchorId']
    g.userData.lightAnchors = [anchor]
    g.userData.colliders = [{'min': [-0.22, 0, -0.22], 'max': [0.22, 1.74, 0.22]}]
    finishRig(game, g)
    setLampLevel(game, g, opts['level'] if opts.get('level') is not None else 1)
    if (opts['level'] if opts.get('level') is not None else 1) <= 0:
        anchor.intensity = 0
    return g


registerProp('telly_lamp', _telly_lamp,
             {'category': 'machines', 'tags': ['telly_home', 'lamp', 'light', 'living'], 'size': [0.74, 1.77, 0.74],
              'desc': 'Telly home floor lamp (tray table, bell shade; bulb part + light anchor)'})


# Braided oval rag rug (origin = where Telly stands; the rug runs toward the couch, -z). parts.dust = the
# 'dust_rect' footprint decal aligned with Telly's feet (visible when opts.dust or when the machine shows it).
def _telly_rug(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('telly_rug')
    RW, RD, cz, rings, seg = 2.5, 2.1, -0.4, 11, 48

    def draw_braid(ctx, W, H, rand):
        cols = ['#5A3A22', '#E3662B', '#E8A92E', '#8C9A3A', '#B5472A', '#F2DDB0', '#D9602B', '#6B3A6E', '#E8A92E',
                '#5A3A22', '#B07A45']
        band = H / rings
        for r in range(rings):
            ctx.fillStyle = cols[r % len(cols)]
            ctx.fillRect(0, r * band, W, band)
            x = -band
            while x < W + band:   # chevron braid strands
                for dy, s in [[0, 1], [band / 2, -1]]:
                    ctx.fillStyle = 'rgba(%s,%s)' % ('255,255,255' if s > 0 else '0,0,0', js_str(0.1 + rand() * 0.06))
                    ctx.beginPath()
                    ctx.moveTo(x, r * band + dy)
                    ctx.lineTo(x + band * 0.3, r * band + dy + band * 0.25)
                    ctx.lineTo(x + band * 0.55, r * band + dy)
                    ctx.lineTo(x + band * 0.3, r * band + dy + band * 0.5 - 2)
                    ctx.closePath()
                    ctx.fill()
                x += band * 0.55
            gr = ctx.createLinearGradient(0, r * band, 0, (r + 1) * band)
            gr.addColorStop(0, 'rgba(40,20,10,0.35)')
            gr.addColorStop(0.18, 'rgba(0,0,0,0)')
            gr.addColorStop(0.82, 'rgba(0,0,0,0)')
            gr.addColorStop(1, 'rgba(40,20,10,0.35)')
            ctx.fillStyle = gr
            ctx.fillRect(0, r * band, W, band)
        for i in range(3000):
            ctx.fillStyle = 'rgba(255,240,210,0.12)' if rand() < 0.5 else 'rgba(30,15,5,0.12)'
            ctx.fillRect(rand() * W, rand() * H, 1.5, 1.5)
    braid = K.tex.canvas('telly_rug_braid', 512, 512, draw_braid)
    rugMat = K.mat(game, 'fabric', '#ffffff', {'map': braid, 'rim': 0.14, 'wrap': 0.55})
    # concentric braided rings: radial grid (v = ring), each ring a soft bump, rolled-down edge
    pos, uv, idx = [], [], []
    steps = rings * 2
    for i in range(steps + 1):
        t = i / steps
        ringPhase = math.fmod(t * rings, 1)
        hgt = 0.012 + 0.0035 * math.sin(ringPhase * math.pi) - (((t - 0.97) / 0.03) * 0.01 if t > 0.97 else 0)
        for j in range(seg + 1):
            a = (j / seg) * TAU
            pos += [math.cos(a) * t * RW / 2, hgt, cz + math.sin(a) * t * RD / 2]
            uv += [(j / seg) * 8, 1 - t]
    for i in range(steps):
        for j in range(seg):
            a = i * (seg + 1) + j
            b = a + seg + 1
            idx += [a, a + 1, b, a + 1, b + 1, b]
    rg = THREE.BufferGeometry()
    rg.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    rg.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    rg.setIndex(idx)
    rg.computeVertexNormals()
    g.add(K.m(rg, rugMat, {'cast': False}))
    edge = []
    for j in range(48):
        a = (j / 48) * TAU
        edge.append([math.cos(a) * RW / 2, 0.008, cz + math.sin(a) * RD / 2])
    g.add(K.m(tinted(K.tube(edge, 0.015, {'seg': 48, 'radial': 5, 'closed': True}), '#5A3A22'),
              K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#ffffff', {'pattern': 'tweed', 'scale': 3}),
                                                'rim': 0.14, 'wrap': 0.55})))
    # dust footprint decal: the card's leg dots (22%/78% x 20%/80%) sit under Telly's feet (x +-0.593, z +-0.256)
    fx, fz = 0.593, 0.256
    dw, dd = ((2 * fx) / 0.56) * 1.15, ((2 * fz) / 0.6) * 1.8   # card drawn at 1/1.15 x 1/1.8 of the canvas

    def draw_dust(ctx, W, H, rand):
        # own take on the 'dust_rect' card: a soft oval of grey dust with the crisp clean TV footprint + four leg dots
        cw, ch = 512 / 1.15, 512 / 1.8
        ox, oy = (512 - cw) / 2, (512 - ch) / 2
        img = ctx.createImageData(512, 512)
        n = 512 * 512
        vals = np.empty((n, 4))
        for i in range(n):
            v = rand()
            vals[i, 0] = 158 + v * 40
            vals[i, 1] = 150 + v * 36
            vals[i, 2] = 140 + v * 32
            vals[i, 3] = (0.64 + rand() * rand() * 0.34) * 255
        # Uint8ClampedArray stores: clamp + round half to even
        img.data[:] = np.rint(np.clip(vals, 0, 255)).astype(np.uint8).reshape(-1)
        ctx.putImageData(img, 0, 0)
        for i in range(260):  # lint and fuzz flecks
            ctx.fillStyle = 'rgba(235,228,214,0.55)' if rand() < 0.5 else 'rgba(150,140,128,0.4)'
            ctx.beginPath()
            ctx.ellipse(rand() * 512, rand() * 512, 1 + rand() * 3, 0.6 + rand() * 1.5, rand() * 3, 0, TAU)
            ctx.fill()
        ctx.save()                         # dust piles up along the TV's edge
        ctx.filter = 'blur(3px)'
        ctx.strokeStyle = 'rgba(96,86,76,0.75)'
        ctx.lineWidth = 9
        ctx.beginPath()
        ctx.roundRect(ox + cw * 0.25, oy + ch * 0.27, cw * 0.5, ch * 0.46, 14)
        ctx.stroke()
        ctx.restore()
        ctx.save()
        ctx.globalCompositeOperation = 'destination-out'
        ctx.filter = 'blur(2px)'
        ctx.beginPath()
        ctx.roundRect(ox + cw * 0.25 + 3, oy + ch * 0.27 + 3, cw * 0.5 - 6, ch * 0.46 - 6, 12)
        ctx.fill()
        ctx.filter = 'blur(1.5px)'
        for x, y in [[0.22, 0.2], [0.78, 0.2], [0.22, 0.8], [0.78, 0.8]]:
            ctx.beginPath()
            ctx.arc(ox + cw * x, oy + ch * y, 8, 0, TAU)
            ctx.fill()
        ctx.restore()
        ctx.save()
        ctx.globalCompositeOperation = 'destination-in'
        ctx.translate(256, 256)
        ctx.scale(1, 0.66)
        gr = ctx.createRadialGradient(0, 0, 170, 0, 0, 250)
        gr.addColorStop(0, 'rgba(0,0,0,1)')
        gr.addColorStop(1, 'rgba(0,0,0,0)')
        ctx.fillStyle = gr
        ctx.fillRect(-256, -400, 512, 800)
        ctx.restore()
    dustTex = K.tex.canvas('telly_dust_v4', 512, 512, draw_dust, {'repeat': False})
    dustMat = game.mats.toon('#F4EEE4', {'map': dustTex, 'transparent': True, 'depthWrite': False, 'rough': 1,
                                         'rim': 0})
    dust = keep(K.m(THREE.PlaneGeometry(dw, dd).rotateX(-math.pi / 2), dustMat,
                    {'pos': [0, 0.0175, 0], 'name': 'dust', 'cast': False}))
    dust.userData.noAO = True
    dust.userData.noOcclude = True
    dust.renderOrder = 1
    g.add(dust)
    g.userData.parts = JSObj(dust=dust)
    g.userData.colliders = []
    finishRig(game, g, {'finish': {'ao': {'strength': 0.4, 'height': 0.02, 'heightStrength': 0.2}}})
    dust.visible = bool(opts.get('dust'))
    return g


registerProp('telly_rug', _telly_rug,
             {'category': 'machines', 'tags': ['telly_home', 'rug', 'living'], 'size': [2.53, 0.03, 1.93],
              'desc': 'Telly home braided oval rug (dust footprint decal part)'})


# Unplugged extension cord: wall outlet plate (back at z = 0, place against a wall), the pulled plug on the
# floor, the brown cord snaking toward -z and a cube tap where Telly's own cord would go.
def _telly_cord(game, opts=None):
    g = K.prop('telly_cord')
    plastic = K.mat(game, 'plastic', '#ffffff')
    brass = K.mat(game, 'brass', '#C8963C')
    IVORY, BROWN = '#EFE3C6', '#5A3A22'
    # outlet plate with a surprised little face (two sockets + ground hole)
    g.add(K.m(tinted(K.box(0.08, 0.125, 0.012, 0.005), IVORY), plastic, {'pos': [0, 0.3, -0.006]}))
    for y in [0.33, 0.27]:
        g.add(K.m(tinted(K.box(0.05, 0.036, 0.006, 0.012), '#E6D8B8'), plastic, {'pos': [0, y, -0.013]}))
        for x in [-0.011, 0.011]:
            g.add(K.m(tinted(THREE.BoxGeometry(0.004, 0.012, 0.004), '#2A1C14'), plastic,
                      {'pos': [x, y + 0.003, -0.0165]}))
        g.add(K.m(tinted(THREE.CylinderGeometry(0.004, 0.004, 0.004, 8).rotateX(math.pi / 2), '#2A1C14'), plastic,
                  {'pos': [0, y - 0.01, -0.0165]}))
    g.add(K.m(K.cyl(0.004, 0.004, 0.003, {'bevel': 0.001, 'seg': 8}), brass,
              {'pos': [0, 0.3, -0.013], 'rot': [-math.pi / 2, 0, 0]}))
    # cord: from the plug lying near the wall, snaking out to the cube tap
    fy = 0.009
    pts = [[0.22, fy, -0.14], [0.34, fy, -0.3], [0.2, fy, -0.52], [-0.06, fy, -0.62], [-0.22, fy, -0.82],
           [-0.08, fy, -1.05], [0.18, fy, -1.14], [0.3, fy, -1.26]]
    g.add(K.m(tinted(K.tube(pts, 0.0085, {'seg': 60, 'radial': 6}), BROWN), plastic))
    plug = THREE.Group()
    plug.position.set(0.19, 0.012, -0.1)
    plug.rotation.set(0, 0.95, 0.18)
    plug.add(K.m(tinted(K.box(0.055, 0.03, 0.038, 0.012), '#4A3020'), plastic, {'pos': [0, 0.012, 0]}))
    for s in [-1, 1]:
        plug.add(K.m(THREE.BoxGeometry(0.032, 0.013, 0.004), brass, {'pos': [0.042, 0.014, s * 0.01]}))
    g.add(plug)
    tap = THREE.Group()
    tap.position.set(0.33, 0.028, -1.3)
    tap.rotation.y = 0.5
    tap.add(K.m(tinted(K.box(0.056, 0.056, 0.056, 0.012), BROWN), plastic))
    for x, y, z, ry in [[0, 0, -0.029, 0], [0.029, 0, 0, math.pi / 2], [0, 0.029, 0, 0]]:
        face = THREE.Group()
        face.position.set(x, y, z)
        face.rotation.y = ry
        if y:
            face.rotation.x = -math.pi / 2
        for sx in [-0.009, 0.009]:
            face.add(K.m(tinted(THREE.BoxGeometry(0.004, 0.012, 0.004), '#1A100A'), plastic, {'pos': [sx, 0, 0]}))
        tap.add(face)
    g.add(tap)
    g.userData.colliders = []
    return finishRig(game, g, {'finish': {'ao': {'strength': 0.6}}})


registerProp('telly_cord', _telly_cord,
             {'category': 'machines', 'tags': ['telly_home', 'cord', 'clutter'], 'size': [0.6, 0.37, 1.35],
              'desc': 'unplugged extension cord + wall outlet (empty Telly home)'})

registerScene('telly_home', {
    'floor': 'shag', 'wall': 'panel', 'room': [5.2, 3.8],
    'items': [
        {'id': 'telly_rug', 'pos': [0.1, 0.45], 'rotY': 0},
        {'id': 'telly', 'pos': [0.1, 0.45], 'rotY': 0},
        {'id': 'telly_lamp', 'pos': [-1.35, 1.0], 'rotY': 0.4},
        {'id': 'telly_cord', 'pos': [1.25, 1.9], 'rotY': 0},
    ],
    'cam': {'pos': [0.9, 1.6, -2.9], 'target': [0, 0.75, 0.5], 'fov': 50},
})
registerScene('telly_home_empty', {
    'floor': 'shag', 'wall': 'panel', 'room': [5.2, 3.8],
    'items': [
        {'id': 'telly_rug', 'pos': [0.1, 0.45], 'rotY': 0, 'opts': {'dust': True}},
        {'id': 'telly_lamp', 'pos': [-1.35, 1.0], 'rotY': 0.4, 'opts': {'level': 0}},
        {'id': 'telly_cord', 'pos': [0.75, 1.9], 'rotY': 0},
    ],
    'cam': {'pos': [0.6, 1.9, -2.4], 'target': [0, 0.2, 0.6], 'fov': 50},
})


# ========================================================================================= SIGN-ON LEVER
# Master Control power switch (GDD §10.1): waist-high red knife switch under a hinged red safety hood, with a big
# ON AIR lamp on a mast. Floor-standing (anchor sign_on_lever, operator on the -z side).
#   parts.cover  hood, hinge at its back edge: rotation.x 0 = closed .. rig.coverOpen (flipped back)
#   parts.lever  knife-switch blades + red handle, hinge axis: rotation.x rig.leverOff (raised) .. 0 (ON, slammed)
#   parts.lamp   ON AIR face (setOnAirLamp swaps its glow level; pulse it every 2 s before power)
#   parts.jewels indicator lamps (setOnAirLamp lights them with the lamp)
SO = JSObj(slope=0.3, deckY=0.93, w=0.64, d=0.5, h=0.86)


def setOnAirLamp(game, g, level=1):
    P = g.userData.parts
    q = js_round(clamp(level, 0, 1) * 10) / 10
    if P.lamp:
        P.lamp.material = K.glow(game, '#ffffff', 0.35 + 1.5 * q, {'map': getCard('on_air', {'lit': True})}) \
            if q > 0 else K.mat(game, 'plastic', '#ffffff', {'map': getCard('on_air', {'lit': False})})
    if P.jewels:
        P.jewels.material = K.glow(game, '#FFB347', 0.5 + 2 * q) if q > 0 else K.mat(game, 'plastic', '#7A4A2A')
    g.userData.lampLevel = q


def signOnAtlas():
    def draw(ctx, W, H, rand):
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        # two gauges (0,0)-(128,128) KILOVOLTS, (128,0)-(256,128) PLATE mA
        for label, ox in [['KILOVOLTS', 0], ['PLATE mA', 128]]:
            cx, cy = ox + 64, 64
            ctx.fillStyle = '#F4ECD6'
            ctx.beginPath()
            ctx.arc(cx, cy, 64, 0, TAU)
            ctx.fill()
            ctx.strokeStyle = '#2A2230'
            ctx.lineWidth = 3
            ctx.beginPath()
            ctx.arc(cx, cy + 14, 44, math.pi * 1.15, math.pi * 1.85)
            ctx.stroke()
            ctx.strokeStyle = '#E23B3B'
            ctx.lineWidth = 6
            ctx.beginPath()
            ctx.arc(cx, cy + 14, 44, math.pi * 1.7, math.pi * 1.85)
            ctx.stroke()
            ctx.strokeStyle = '#2A2230'
            ctx.lineWidth = 2
            for i in range(11):
                a, ln = math.pi * 1.15 + (i / 10) * math.pi * 0.7, (6 if i % 5 else 11)
                ctx.beginPath()
                ctx.moveTo(cx + math.cos(a) * 44, cy + 14 + math.sin(a) * 44)
                ctx.lineTo(cx + math.cos(a) * (44 - ln), cy + 14 + math.sin(a) * (44 - ln))
                ctx.stroke()
            ctx.fillStyle = '#2A2230'
            ctx.font = '11px "Bungee", "Arial Black", sans-serif'
            ctx.fillText(label, cx, cy + 34)
        # plate (256,0)-(512,64): SIGN-ON / MAIN POWER
        ctx.fillStyle = '#2A2230'
        ctx.beginPath()
        ctx.roundRect(256, 0, 256, 64, 10)
        ctx.fill()
        ctx.strokeStyle = '#C8C8C8'
        ctx.lineWidth = 3
        ctx.beginPath()
        ctx.roundRect(261, 5, 246, 54, 8)
        ctx.stroke()
        ctx.fillStyle = '#F4F1E8'
        ctx.font = '26px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('SIGN-ON', 384, 26)
        ctx.fillStyle = '#FFB347'
        ctx.font = '11px "Titan One", sans-serif'
        ctx.fillText('MAIN TRANSMITTER POWER', 384, 48)
        # hazard stripes (256,64)-(512,128)
        ctx.save()
        ctx.beginPath()
        ctx.rect(256, 64, 256, 64)
        ctx.clip()
        ctx.fillStyle = '#F4C81E'
        ctx.fillRect(256, 64, 256, 64)
        ctx.fillStyle = '#231A22'
        for x in range(200, 560, 40):
            ctx.beginPath()
            ctx.moveTo(x, 128)
            ctx.lineTo(x + 20, 128)
            ctx.lineTo(x + 84, 64)
            ctx.lineTo(x + 64, 64)
            ctx.closePath()
            ctx.fill()
        ctx.restore()
        # warning label (0,128)-(256,192)
        ctx.fillStyle = '#F4C81E'
        ctx.beginPath()
        ctx.roundRect(0, 128, 256, 64, 8)
        ctx.fill()
        ctx.fillStyle = '#231A22'
        ctx.beginPath()
        ctx.moveTo(34, 138)
        ctx.lineTo(56, 182)
        ctx.lineTo(12, 182)
        ctx.closePath()
        ctx.fill()
        ctx.fillStyle = '#F4C81E'
        ctx.font = '22px "Titan One", sans-serif'
        ctx.fillText('!', 34, 170)
        ctx.fillStyle = '#231A22'
        ctx.font = '17px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('DANGER', 150, 148)
        ctx.font = '12px "Titan One", sans-serif'
        ctx.fillText('10,000 VOLTS  ·  KEEP COVER SHUT', 150, 172)
        # lever tag (256,128)-(512,192): ON / OFF arrow
        ctx.fillStyle = '#F4F1E8'
        ctx.beginPath()
        ctx.roundRect(256, 128, 256, 64, 8)
        ctx.fill()
        ctx.fillStyle = '#E23B3B'
        ctx.font = '22px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('ON', 300, 162)
        ctx.fillStyle = '#2A2230'
        ctx.fillText('OFF', 468, 162)
        ctx.beginPath()
        ctx.moveTo(340, 160)
        ctx.lineTo(420, 160)
        ctx.lineWidth = 5
        ctx.strokeStyle = '#2A2230'
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(334, 160)
        ctx.lineTo(350, 150)
        ctx.lineTo(350, 170)
        ctx.closePath()
        ctx.fill()
        # brushed panel (0,192)-(512,256)
        ctx.fillStyle = '#B9BEC6'
        ctx.fillRect(0, 192, 512, 64)
        for i in range(500):
            ctx.fillStyle = 'rgba(255,255,255,0.25)' if rand() < 0.5 else 'rgba(40,40,50,0.18)'
            ctx.fillRect(rand() * 512, 192 + rand() * 64, 20 + rand() * 80, 1)
    return K.tex.canvas('signon_atlas_v1', 512, 256, draw, {'repeat': False, 'fonts': True})


def _sign_on_lever(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('sign_on_lever')
    paint = K.mat(game, 'lacquer', '#ffffff')        # tinted: slate enamel, red handle, porcelain, cable
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    copper = K.mat(game, 'brass', '#C8784A')
    atlas = K.mat(game, 'plastic', '#ffffff', {'map': signOnAtlas()})
    hood = game.mats.glass('#FF3A2E', {'opacity': 0.38})
    SLATE, SLATE_D, RED, PORC, BLACK = '#5479A8', '#34496A', '#E23B3B', '#F2EEE4', '#262028'
    w, d, h, slope = SO.w, SO.d, SO.h, SO.slope
    # pedestal: rounded enamel cabinet on a darker kick base, chrome corner trims
    g.add(K.m(tinted(K.box(w + 0.04, 0.09, d + 0.04, 0.03), SLATE_D), paint, {'pos': [0, 0.045, 0]}))
    g.add(K.m(cellUV(K.box(w + 0.045, 0.05, 0.006, 0.003).clone(), 256, 64, 512, 128, 512, 256), atlas,
              {'pos': [0, 0.05, -(d + 0.04) / 2 - 0.002]}))
    cab = K.box(w, h - 0.09, d, 0.06)
    g.add(K.m(tinted(cab, SLATE), paint, {'pos': [0, 0.09 + (h - 0.09) / 2, 0]}))
    for sx in [-1, 1]:
        g.add(K.m(K.box(0.02, h - 0.14, 0.02, 0.008), chrome,
                  {'pos': [sx * (w / 2 - 0.004), 0.09 + (h - 0.09) / 2, -d / 2 + 0.004]}))
    # sloped deck (rises toward the back): a cap wedge + inset brushed panel
    deck = THREE.Group()
    deck.position.set(0, SO.deckY, 0)
    deck.rotation.x = -(math.pi / 2 + slope)               # local +y = toward the operator (down-slope), +z = deck normal
    g.add(deck)
    # sloped cap: a wedge from the cabinet top up to the deck plane (profile in -z/y, extruded along x)
    ft, bt = SO.deckY - (d / 2) * math.sin(slope), SO.deckY + (d / 2) * math.sin(slope)
    wedge = K.extrude([[d / 2 + 0.01, h - 0.04], [-d / 2 - 0.01, h - 0.04], [-d / 2 - 0.01, bt], [d / 2 + 0.01, ft]],
                      w + 0.02, {'bevel': 0.02, 'round': 0.02, 'bevelSeg': 2})
    wedge.rotateY(math.pi / 2)
    g.add(K.m(tinted(wedge, SLATE), paint))
    # front: gauges, jewel lamps, nameplate, warning label
    fz = -d / 2 - 0.002
    for x, cell in [[-0.14, [0, 0, 128, 128]], [0.14, [128, 0, 256, 128]]]:
        g.add(K.m(K.tube(ringXY(0.072, 20, 0), 0.01, {'seg': 24, 'radial': 5, 'closed': True}), chrome,
                  {'pos': [x, 0.68, fz - 0.004]}))
        g.add(K.m(disc(0.07, 24, cell, 512, 256), atlas, {'pos': [x, 0.68, fz - 0.003]}))
        needle = K.m(tinted(THREE.BoxGeometry(0.003, 0.05, 0.003), '#E23B3B'), paint,
                     {'pos': [x - 0.012, 0.685, fz - 0.008], 'rot': [0, 0, 0.5 - (0.4 if x > 0 else 0)]})
        g.add(needle)
        g.add(K.m(THREE.CircleGeometry(0.07, 20).rotateY(math.pi), game.mats.glass('#DDEEFF', {'opacity': 0.12}),
                  {'pos': [x, 0.68, fz - 0.012]}))
    g.add(K.m(cellUV(K.box(0.4, 0.1, 0.012, 0.005).clone(), 256, 0, 512, 64, 512, 256), atlas,
              {'pos': [0, 0.5, fz - 0.004]}))
    g.add(K.m(cellUV(THREE.PlaneGeometry(0.3, 0.075).rotateY(math.pi), 0, 128, 256, 192, 512, 256), atlas,
              {'pos': [0, 0.33, fz - 0.001]}))
    jewelGeo = []
    for i in range(4):
        x = -0.15 + i * 0.1
        g.add(K.m(K.cyl(0.022, 0.024, 0.012, {'bevel': 0.004, 'seg': 12}), chrome,
                  {'pos': [x, 0.58, fz], 'rot': [-math.pi / 2, 0, 0]}))
        j = THREE.SphereGeometry(0.016, 10, 6, 0, TAU, 0, math.pi / 2).rotateX(-math.pi / 2)
        j.translate(x, 0.58, fz - 0.012)
        jewelGeo.append(j)
    jewels = keep(THREE.Mesh(K.tint(mergeGeos(jewelGeo), '#ffffff'), K.glow(game, '#FFB347', 2)))
    jewels.name = 'jewels'
    jewels.userData.noOcclude = True
    g.add(jewels)
    # side vents
    for sx in [-1, 1]:
        for i in range(4):
            g.add(K.m(tinted(K.box(0.008, 0.02, 0.16, 0.006), SLATE_D), paint,
                      {'pos': [sx * (w / 2 + 0.001), 0.36 + i * 0.05, 0.05]}))

    # ---- knife switch on the deck (deck-local: +y toward the operator, +z up from the deck)
    deck.add(K.m(tinted(K.box(0.4, 0.34, 0.03, 0.01), PORC), paint, {'pos': [0, 0, 0.018]}))
    deck.add(K.m(cellUV(THREE.PlaneGeometry(0.2, 0.05), 256, 128, 512, 192, 512, 256), atlas,
                 {'pos': [0, 0.145, 0.0335]}))
    hingeY, jawY, bladeX, bladeLen = -0.1, 0.12, 0.075, 0.26
    for sx in [-1, 1]:
        # hinge posts + jaw clips (copper on porcelain insulators)
        deck.add(K.m(K.box(0.03, 0.03, 0.05, 0.006), copper, {'pos': [sx * bladeX, hingeY, 0.058]}))
        deck.add(K.m(K.box(0.012, 0.03, 0.06, 0.004), copper, {'pos': [sx * bladeX - 0.014, jawY, 0.062]}))
        deck.add(K.m(K.box(0.012, 0.03, 0.06, 0.004), copper, {'pos': [sx * bladeX + 0.014, jawY, 0.062]}))
        deck.add(K.m(tinted(K.cyl(0.02, 0.024, 0.02, {'bevel': 0.005, 'seg': 12}), PORC), paint,
                     {'pos': [sx * bladeX, jawY, 0.03], 'rot': [math.pi / 2, 0, 0]}))
        deck.add(K.m(tinted(K.cyl(0.02, 0.024, 0.02, {'bevel': 0.005, 'seg': 12}), PORC), paint,
                     {'pos': [sx * bladeX, hingeY, 0.03], 'rot': [math.pi / 2, 0, 0]}))
    deck.add(K.m(K.cyl(0.008, 0.008, 2 * bladeX + 0.05, {'bevel': 0.003, 'seg': 8}), chrome,
                 {'pos': [-(bladeX + 0.025), hingeY, 0.07], 'rot': [0, 0, -math.pi / 2]}))
    lever = grp('lever', [0, hingeY, 0.07])
    for sx in [-1, 1]:
        lever.add(K.m(K.box(0.018, bladeLen, 0.034, 0.006), copper, {'pos': [sx * bladeX, bladeLen / 2, 0]}))
    lever.add(K.m(tinted(K.box(2 * bladeX + 0.05, 0.03, 0.03, 0.012), BLACK), paint,
                  {'pos': [0, bladeLen - 0.02, 0.008]}))
    lever.add(K.m(tinted(K.cyl(0.018, 0.02, 0.07, {'bevel': 0.008, 'seg': 12}), RED), paint,
                  {'pos': [0, bladeLen - 0.02, 0.02], 'rot': [math.pi / 2, 0, 0]}))
    lever.add(K.m(tinted(THREE.SphereGeometry(0.034, 14, 10), RED), paint, {'pos': [0, bladeLen - 0.02, 0.1]}))
    lever.rotation.x = 1.2
    deck.add(lever)
    # hinged red safety hood (hinge at its back edge)
    cover = grp('cover', [0, -0.19, 0.035])
    hw, hl, hh = 0.44, 0.4, 0.42

    def flat_bottom(v, i):
        if v.z < -hh / 2 + 0.001:
            v.z = -hh / 2
    hoodGeo = warp(K.box(hw, hl, hh, 0.045).clone(), flat_bottom)
    hoodGeo.translate(0, hl / 2, hh / 2)
    hoodMesh = K.m(hoodGeo, hood, {'cast': False})
    hoodMesh.userData.noOcclude = True
    cover.add(hoodMesh)
    cover.add(K.m(tinted(K.tube(rrXY(hw + 0.01, hl + 0.01, 0.05, 0, 3), 0.009,
                                {'seg': 32, 'radial': 5, 'closed': True}), RED), paint, {'pos': [0, hl / 2, 0.006]}))
    cover.add(K.m(tinted(K.box(0.1, 0.02, 0.03, 0.01), RED), paint, {'pos': [0, hl + 0.01, hh * 0.35]}))
    cover.add(K.m(K.cyl(0.008, 0.008, hw - 0.04, {'bevel': 0.003, 'seg': 8}), chrome,
                  {'pos': [-(hw - 0.04) / 2, 0, 0], 'rot': [0, 0, -math.pi / 2]}))
    deck.add(cover)

    # ---- ON AIR lamp on a chrome mast at the back
    # chrome goalpost frame at the back corners (the hood flips back between the posts)
    mastTop, mz = 1.8, d / 2 - 0.03
    for sx in [-1, 1]:
        g.add(K.m(K.cyl(0.019, 0.022, mastTop - 0.8, {'bevel': 0.006, 'seg': 10}), chrome,
                  {'pos': [sx * (w / 2 - 0.02), 0.8, mz]}))
        g.add(K.m(K.cyl(0.036, 0.04, 0.03, {'bevel': 0.008, 'seg': 12}), chrome,
                  {'pos': [sx * (w / 2 - 0.02), bt - 0.02, mz]}))
    g.add(K.m(K.cyl(0.016, 0.016, w - 0.04, {'bevel': 0.005, 'seg': 10}), chrome,
              {'pos': [-(w / 2 - 0.02), mastTop - 0.02, mz], 'rot': [0, 0, -math.pi / 2]}))
    box = THREE.Group()
    box.position.set(0, mastTop + 0.1, mz)
    box.rotation.x = 0.12
    box.add(K.m(tinted(K.box(0.56, 0.24, 0.13, 0.05), '#2A2230'), paint))
    box.add(K.m(tinted(K.tube(rrXY(0.54, 0.22, 0.05, 0, 3), 0.01, {'seg': 32, 'radial': 5, 'closed': True}), RED),
                paint, {'pos': [0, 0, -0.066]}))
    for sx in [-1, 1]:
        box.add(K.m(K.cyl(0.018, 0.018, 0.06, {'bevel': 0.006, 'seg': 8}), chrome, {'pos': [sx * 0.18, -0.15, 0]}))
    lamp = keep(K.m(THREE.PlaneGeometry(0.48, 0.18).rotateY(math.pi),
                    K.glow(game, '#ffffff', 1.6, {'map': getCard('on_air', {'lit': True})}),
                    {'pos': [0, 0, -0.067], 'name': 'lamp', 'cast': False}))
    lamp.userData.noOcclude = True
    box.add(lamp)
    g.add(box)
    # cable into the floor
    g.add(K.m(tinted(K.tube([[0.2, 0.25, d / 2 - 0.02], [0.24, 0.12, d / 2 + 0.08], [0.26, 0.012, d / 2 + 0.26],
                             [0.2, 0.012, d / 2 + 0.5]], 0.018, {'seg': 16, 'radial': 6}), BLACK), paint))

    g.userData.parts = JSObj(lever=lever, cover=cover, lamp=lamp, jewels=jewels, deck=deck)
    g.userData.rig = {'leverOff': 1.2, 'leverOn': 0, 'coverClosed': 0, 'coverOpen': 1.95, 'axis': 'x'}
    lampWorld = box.position.clone()
    anchor = JSObj(pos=[lampWorld.x, lampWorld.y, lampWorld.z - 0.2], color=PAL.onAirRed, intensity=2.2, distance=5)
    if opts.get('anchorId'):
        anchor.id = opts['anchorId']
    g.userData.lightAnchors = [anchor]
    g.userData.colliders = [{'min': [-w / 2 - 0.03, 0, -d / 2 - 0.03], 'max': [w / 2 + 0.03, 1.25, d / 2 + 0.03]}]
    g.userData.interact = {'point': [0, 1.0, -d / 2 - 0.25], 'radius': 1.4}
    finishRig(game, g)
    if opts.get('on'):
        lever.rotation.x = 0
        cover.rotation.x = 1.95
    if opts.get('cover') == 'open':
        cover.rotation.x = 1.95
    setOnAirLamp(game, g, opts['lamp'] if opts.get('lamp') is not None else 1)
    return g


registerProp('sign_on_lever', _sign_on_lever,
             {'category': 'machines', 'tags': ['sign_on', 'machine', 'master_control', 'lever'],
              'size': [0.7, 1.95, 0.8], 'desc': 'Sign-On knife-switch lever with red hood and ON AIR lamp', 'hero': True})


def mergeGeos(lst):
    out = []
    for gg in lst:
        c = gg.toNonIndexed() if gg.index is not None else gg
        out.append(c)
    total = sum(gg.attributes.position.count for gg in out)
    pos, nor, uv = np.zeros((total, 3)), np.zeros((total, 3)), np.zeros((total, 2))
    o = 0
    for gg in out:
        n = gg.attributes.position.count
        pos[o:o + n] = np.asarray(gg.attributes.position, dtype=np.float64)
        nor[o:o + n] = np.asarray(gg.attributes.normal, dtype=np.float64)
        if gg.attributes.uv is not None:
            uv[o:o + n] = np.asarray(gg.attributes.uv, dtype=np.float64)
        o += n
    r = THREE.BufferGeometry()
    r.setAttribute('position', THREE.BufferAttribute(pos, 3))
    r.setAttribute('normal', THREE.BufferAttribute(nor, 3))
    r.setAttribute('uv', THREE.BufferAttribute(uv, 2))
    return r


registerScene('sign_on', {
    'floor': 'tile', 'wall': 'plain', 'room': [4.4, 3.4], 'tileA': '#3A4658', 'tileB': '#2A3242',
    'items': [
        {'id': 'sign_on_lever', 'pos': [0.4, 0.3], 'rotY': 0.35},
        {'id': 'sign_on_lever', 'pos': [-1.1, 0.8], 'rotY': -0.3, 'opts': {'on': True, 'lamp': 1}},
    ],
    'cam': {'pos': [0.2, 1.7, -2.4], 'target': [-0.2, 0.9, 0.5], 'fov': 50},
})


# ============================================================================================ THE UPLINK
# Transmitter Yard (GDD §10.4). Anchors: uplink_dish (the dish), uplink_cradle (feed-horn clamp, y 1.3),
# uplink_crank (crank wheel, hub y 1.0); the booth and the satellite are extra props. All face -z locally.
UP_DISH = JSObj(R=2.5, depth=0.85, pivotY=3.3, hub=0.75, bulbs=40, droop=-0.33, aligned=0.95)
UP_DISH.f = (UP_DISH.R * UP_DISH.R) / (4 * UP_DISH.depth)

# Rim chaser helper: t = seconds, on = bool, speed = bulbs per second (chase), lit fraction every 4th bulb.
_cc = THREE.Color()


def setUplinkChase(g, t=0, o=None):
    o = o or {}
    on, speed, color = o.get('on', True), o.get('speed', 12), o.get('color', PAL.marqueeGold)
    inst = g.userData.parts.rimBulbs
    if not inst:
        return
    n, head = inst.count, int(math.floor(t * speed))
    for i in range(n):
        k = ((i - head) % 4 + 4) % 4
        v = (1 if k == 0 else 0.35 if k == 1 else 0.12) if on else 0.1
        _cc.set(color).multiplyScalar(v)
        inst.setColorAt(i, _cc)


# Pose: tilt = elevation in radians (rig.droop .. rig.aligned), yaw = turntable angle.
def setUplinkPose(g, o=None):
    o = o or {}
    P = g.userData.parts
    if o.get('tilt') is not None:
        P.tilt.rotation.x = o['tilt']
    if o.get('yaw') is not None:
        P.yaw.rotation.y = o['yaw']


def dishTextures():
    def draw_face(ctx, W, H, rand):
        # u = around (12 petals), v = center (bottom row) -> rim (top row)
        g = ctx.createLinearGradient(0, 0, 0, H)
        g.addColorStop(0, '#F2F0EA')
        g.addColorStop(1, '#E4E1D8')
        ctx.fillStyle = g
        ctx.fillRect(0, 0, W, H)
        for i in range(12):  # petal tint variation
            c = '255,255,250' if rand() < 0.5 else '200,196,186'
            ctx.fillStyle = 'rgba(%s,%s)' % (c, js_str(0.12 + rand() * 0.1))
            ctx.fillRect((i / 12) * W, 0, W / 12, H)
        # painted station stripes near the rim (top): blue + red racing bands
        ctx.fillStyle = PAL.wztvBlue
        ctx.fillRect(0, H * 0.075, W, H * 0.05)
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(0, H * 0.14, W, H * 0.03)
        # seams + painted rivet heads
        ctx.strokeStyle = 'rgba(90,86,96,0.55)'
        ctx.lineWidth = 2
        for i in range(12):
            x = (i / 12) * W + 0.5
            ctx.beginPath()
            ctx.moveTo(x, 0)
            ctx.lineTo(x, H)
            ctx.stroke()
        for v in [0.34, 0.62]:
            ctx.beginPath()
            ctx.moveTo(0, H * v)
            ctx.lineTo(W, H * v)
            ctx.stroke()
        for i in range(12):
            for j in range(16):
                x, y = (i / 12) * W + 4, (j / 16) * H + 8
                ctx.fillStyle = 'rgba(120,116,126,0.7)'
                ctx.beginPath()
                ctx.arc(x, y, 2.2, 0, TAU)
                ctx.fill()
                ctx.fillStyle = 'rgba(255,255,255,0.7)'
                ctx.beginPath()
                ctx.arc(x - 0.6, y - 0.6, 1, 0, TAU)
                ctx.fill()
        for v in [0.34, 0.62]:
            for i in range(48):
                x, y = (i / 48) * W + 5, H * v + 4
                ctx.fillStyle = 'rgba(120,116,126,0.7)'
                ctx.beginPath()
                ctx.arc(x, y, 2.2, 0, TAU)
                ctx.fill()
        # weathering: a few drips and scuffs (soft), scratches around the dent (u ~ 0.11)
        for i in range(40):
            ctx.fillStyle = 'rgba(110,100,90,%s)' % js_str(0.04 + rand() * 0.05)
            x, y = rand() * W, rand() * H
            ctx.fillRect(x, y, 1.5, 6 + rand() * 30)
        ctx.strokeStyle = 'rgba(80,70,64,0.35)'
        ctx.lineWidth = 1.2
        for i in range(9):
            x = W * 0.11 + (rand() - 0.5) * 40
            y = H * 0.32 + (rand() - 0.5) * 50
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.lineTo(x + (rand() - 0.5) * 30, y + (rand() - 0.5) * 20)
            ctx.stroke()
    face = K.tex.canvas('uplink_dish_face_v1', 512, 512, draw_face)

    def draw_atlas(ctx, W, H, rand):
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        # (0,0)-(256,256): station "13" badge for the dish center
        ctx.fillStyle = '#F2F0EA'
        ctx.fillRect(0, 0, 256, 256)
        ctx.fillStyle = PAL.channelRed
        ctx.beginPath()
        ctx.arc(128, 128, 118, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.beginPath()
        ctx.arc(128, 128, 104, 0, TAU)
        ctx.fill()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(128, 128, 96, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.font = '118px "Titan One", "Arial Black", sans-serif'
        ctx.fillText('13', 128, 136)
        ctx.fillStyle = PAL.harvestGold
        ctx.font = '22px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('WZTV', 128, 56)
        # (256,0)-(512,128): concrete with hazard band (plinth side)
        ctx.fillStyle = '#9A958E'
        ctx.fillRect(256, 0, 256, 128)
        for i in range(1500):
            ctx.fillStyle = 'rgba(60,56,52,0.25)' if rand() < 0.5 else 'rgba(220,214,204,0.25)'
            ctx.fillRect(256 + rand() * 256, rand() * 128, 1.5, 1.5)
        ctx.save()
        ctx.beginPath()
        ctx.rect(256, 40, 256, 48)
        ctx.clip()
        ctx.fillStyle = '#F4C81E'
        ctx.fillRect(256, 40, 256, 48)
        ctx.fillStyle = '#231A22'
        for x in range(220, 540, 36):
            ctx.beginPath()
            ctx.moveTo(x, 88)
            ctx.lineTo(x + 18, 88)
            ctx.lineTo(x + 66, 40)
            ctx.lineTo(x + 48, 40)
            ctx.closePath()
            ctx.fill()
        ctx.restore()
        # (256,128)-(512,192): motor box label
        ctx.fillStyle = '#23324A'
        ctx.beginPath()
        ctx.roundRect(256, 128, 256, 64, 8)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.font = '24px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('UPLINK 13', 384, 152)
        ctx.fillStyle = '#FFB347'
        ctx.font = '11px "Titan One", sans-serif'
        ctx.fillText('AZ-EL DRIVE · DO NOT CLIMB', 384, 177)
        # (256,192)-(512,256): pedestal door (danger)
        ctx.fillStyle = '#F4C81E'
        ctx.beginPath()
        ctx.roundRect(256, 192, 256, 64, 8)
        ctx.fill()
        ctx.fillStyle = '#231A22'
        ctx.font = '20px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('DANGER', 384, 214)
        ctx.font = '11px "Titan One", sans-serif'
        ctx.fillText('HIGH-POWER MICROWAVE · STAND CLEAR', 384, 238)
    atlas = K.tex.canvas('uplink_atlas_v1', 512, 512, draw_atlas, {'repeat': False, 'fonts': True})
    return JSObj(face=face, atlas=atlas)


def _uplink_dish(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('uplink_dish')
    tx = dishTextures()
    face, atlas = tx.face, tx.atlas
    paint = K.mat(game, 'paint', '#ffffff', {'rough': 0.5})                 # tinted: white, WZTV blue, steel
    dishMat = K.mat(game, 'paint', '#ffffff', {'map': face, 'rough': 0.45})
    atl = K.mat(game, 'paint', '#ffffff', {'map': atlas, 'rough': 0.55})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    WHITE, BLUE, STEEL, DARK = '#F1EFE9', '#3E67C8', '#5A5E6E', '#3A3A48'
    R, depth, pivotY, hub, f = UP_DISH.R, UP_DISH.depth, UP_DISH.pivotY, UP_DISH.hub, UP_DISH.f

    def zOf(r):
        return -(hub + (r * r) / (4 * f))                              # dish front surface (tilt space)
    SEG = 48

    # ---- plinth (concrete + hazard band), bolted steel collar, blue pedestal column
    plinth = K.lathe([[0, 0], [1.3, 0], [1.3, 0.25], [0, 0.25]], {'seg': 28, 'round': 0.05, 'steps': 2}).clone()
    cellUV(plinth, 256, 0, 512, 128)
    g.add(K.m(plinth, atl))
    g.add(K.m(tinted(K.lathe([[0, 0.24], [0.72, 0.24], [0.74, 0.3], [0.6, 0.34], [0, 0.34]],
                             {'seg': 20, 'round': 0.02, 'steps': 1}), STEEL), paint))
    for i in range(10):
        a = (i / 10) * TAU
        g.add(K.m(tinted(THREE.CylinderGeometry(0.034, 0.04, 0.05, 6), DARK), paint,
                  {'pos': [math.cos(a) * 0.66, 0.32, math.sin(a) * 0.66]}))
    g.add(K.m(tinted(K.lathe([[0, 0.3], [0.55, 0.3], [0.5, 0.6], [0.42, 1.9], [0.5, 1.98], [0, 1.98]],
                             {'seg': 18, 'round': 0.04, 'steps': 1}), BLUE), paint))
    # access door + danger plate on the front
    g.add(K.m(tinted(K.box(0.4, 0.8, 0.04, 0.03), '#3558A8'), paint, {'pos': [0, 0.95, -0.49], 'rot': [0.06, 0, 0]}))
    g.add(K.m(cellUV(THREE.PlaneGeometry(0.34, 0.085).rotateY(math.pi), 256, 192, 512, 256), atl,
              {'pos': [0, 1.2, -0.515], 'rot': [0.06, 0, 0]}))
    g.add(K.m(chromeHandle(), chrome, {'pos': [0.14, 0.9, -0.52], 'rot': [0.06, 0, 0]}))
    # ladder on the +x side
    for s in [-1, 1]:
        g.add(K.m(THREE.CylinderGeometry(0.018, 0.018, 1.75, 6).translate(0, 0.875, 0), chrome,
                  {'pos': [0.56, 0.3, s * 0.17]}))
    for i in range(7):
        g.add(K.m(THREE.CylinderGeometry(0.013, 0.013, 0.34, 6), chrome,
                  {'pos': [0.56, 0.5 + i * 0.24, 0], 'rot': [math.pi / 2, 0, 0]}))
    # bull gear ring on top of the pedestal
    teeth = []
    nT, rG = 28, 0.72
    for i in range(nT * 2):
        a, r = (i / (nT * 2)) * TAU, (rG if i % 2 else rG + 0.05)
        teeth.append([math.cos(a) * r, math.sin(a) * r])
    gearShape = THREE.Shape([THREE.Vector2(x, y) for x, y in teeth])
    gearShape.holes.append(THREE.Path([THREE.Vector2(x, y) for x, y, _z in ringXY(0.4, 20)]))
    gear = K.extrude(gearShape, 0.1, {'bevel': 0.012, 'bevelSeg': 1, 'curveSeg': 4})
    gear.rotateX(-math.pi / 2)
    g.add(K.m(tinted(gear, STEEL), paint, {'pos': [0, 2.03, 0]}))

    # ---- yaw head: platform, yoke arms, bearings, motor box, elevation pinion
    yaw = grp('yaw', [0, 2.08, 0])
    yaw.add(K.m(tinted(K.lathe([[0, 0], [0.8, 0], [0.82, 0.06], [0.76, 0.14], [0, 0.14]],
                               {'seg': 24, 'round': 0.03, 'steps': 1}), BLUE), paint))
    armH = pivotY - 2.08 - 0.12
    for s in [-1, 1]:
        arm = K.extrude([[-0.3, 0], [0.3, 0], [0.2, armH], [-0.2, armH]], 0.13,
                        {'bevel': 0.03, 'round': 0.05, 'bevelSeg': 2})
        arm.rotateY(math.pi / 2)
        yaw.add(K.m(tinted(arm, BLUE), paint, {'pos': [s * 0.66, 0.12, 0]}))
        yaw.add(K.m(tinted(K.cyl(0.19, 0.19, 0.16, {'bevel': 0.03, 'seg': 14}), STEEL), paint,
                    {'pos': [s * 0.74 - 0.08, pivotY - 2.08, 0], 'rot': [0, 0, -math.pi / 2]}))
        yaw.add(K.m(tinted(K.cyl(0.1, 0.1, 0.05, {'bevel': 0.015, 'seg': 10}), WHITE), paint,
                    {'pos': [s * 0.82 + (0 if s > 0 else -0.05), pivotY - 2.08, 0], 'rot': [0, 0, -math.pi / 2]}))
    yaw.add(K.m(tinted(K.box(0.5, 0.36, 0.42, 0.06), '#2F4F9E'), paint, {'pos': [0, 0.32, 0.46]}))
    yaw.add(K.m(cellUV(THREE.PlaneGeometry(0.4, 0.1), 256, 128, 512, 192), atl, {'pos': [0, 0.34, 0.672]}))
    for i in range(4):
        yaw.add(K.m(tinted(K.box(0.42, 0.018, 0.02, 0.008), '#243E80'), paint, {'pos': [0, 0.2 + i * 0.05, 0.265]}))
    yaw.add(K.m(tinted(K.tube([[0.2, 0.3, 0.68], [0.3, 0.12, 0.72], [0.44, -0.3, 0.58], [0.48, -0.6, 0.5]], 0.028,
                              {'seg': 10, 'radial': 5}), DARK), paint))
    yaw.add(K.m(tinted(K.cyl(0.13, 0.13, 0.08, {'bevel': 0.02, 'seg': 12}), STEEL), paint,
                {'pos': [0.3, pivotY - 2.08 - 0.95, 0.12], 'rot': [0, 0, -math.pi / 2]}))
    g.add(yaw)

    # ---- tilt: the dish (tilt space: pivot at origin, dish axis toward -z)
    tilt = grp('tilt', [0, pivotY - 2.08, 0])
    yaw.add(tilt)
    dent = JSObj(a=0.72, r=1.6, rad=0.45, amt=0.16)

    def dentK(x, y):            # x, y in the dish plane (tilt space, before any axial offset)
        ang, rr = math.atan2(y, x), math.hypot(x, y)
        da = math.atan2(math.sin(ang - dent.a), math.cos(ang - dent.a)) * rr
        d2 = da * da + (rr - dent.r) * (rr - dent.r)
        return math.exp(-d2 / (dent.rad * dent.rad * 0.5)), da, rr - dent.r
    # profiles in lathe space [r, h] (h = height toward the dish opening); front = concave skin (normals up),
    # back = convex skin 0.08 behind (normals down), lip = rolled rim joining them
    N, rs = 12, []
    for i in range(N + 1):
        rs.append((i / N) ** 0.8 * (R - 0.03))
    front = list(reversed([[r, (r * r) / (4 * f)] for r in rs]))       # rim -> center: normals face the opening
    backP = [[r, (r * r) / (4 * f) - 0.08] for r in rs]                # center -> rim: normals face the back
    lip = [[R - 0.03, depth - 0.08 + 0.001], [R + 0.03, depth - 0.07], [R + 0.05, depth - 0.02],
           [R + 0.02, depth + 0.012], [R - 0.03, depth - 0.001]]

    def dent_warp(v, i):
        k, da, dr = dentK(v.x, v.y)
        v.z += dent.amt * k * (1 + 0.3 * math.sin(da * 28) * math.sin(dr * 22))

    def toGeo(pts, dentIt):
        gg = THREE.LatheGeometry([THREE.Vector2(x, y) for x, y in pts], SEG)
        gg.rotateX(-math.pi / 2)                                          # lathe +y -> tilt -z
        if dentIt:
            warp(gg, dent_warp)
        gg.translate(0, 0, -hub)
        return gg
    frontGeo = toGeo(front, True)
    uv = frontGeo.attributes.uv           # v = 0 at the center .. 1 at the rim
    for i in range(uv.count):
        uv.setY(i, 1 - uv.getY(i))

    def dent_tint(x, y, z=None):
        k, da, dr = dentK(x, y)
        c = 1 - 0.3 * k - 0.12 * k * math.sin(da * 28) * math.sin(dr * 22)
        return THREE.Color(c, c, c * 1.04)
    K.tint(frontGeo, dent_tint)
    tilt.add(K.m(frontGeo, dishMat))
    tilt.add(K.m(tinted(toGeo(backP, True), WHITE), paint))
    tilt.add(K.m(tinted(toGeo(lip, False), WHITE), paint))
    # center badge conformed to the paraboloid, 6 mm in front of the surface
    badge = THREE.CircleGeometry(0.8, 28)
    cellUV(badge, 0, 0, 256, 256)

    def conform(v, i):
        v.z = (v.x * v.x + v.y * v.y) / (4 * f) + 0.012
    warp(badge, conform)
    badge.rotateY(math.pi)
    badge.translate(0, 0, -hub)
    tilt.add(K.m(badge, atl))
    # rivet ring on the rim band
    rivet = THREE.SphereGeometry(0.026, 5, 2, 0, TAU, 0, math.pi / 2)
    rivets = []
    for i in range(40):
        a, r = (i / 40) * TAU, R - 0.12
        rg2 = rivet.clone()
        rg2.rotateX(-math.pi / 2 + 0.55)
        rg2.rotateZ(a - math.pi / 2)
        rg2.translate(math.cos(a) * r, math.sin(a) * r, zOf(r) - 0.004)
        rivets.append(rg2)
    tilt.add(K.m(tinted(mergeGeos(rivets), '#D4D0C6'), paint))
    # chrome bulb rail + instanced chaser bulbs (setUplinkChase)
    rail = []
    for i in range(48):
        a = (i / 48) * TAU
        rail.append([math.cos(a) * (R + 0.035), math.sin(a) * (R + 0.035), -(hub + depth) - 0.02])
    tilt.add(K.m(K.tube(rail, 0.022, {'seg': 64, 'radial': 4, 'closed': True}), chrome))
    bulbs = THREE.InstancedMesh(THREE.SphereGeometry(0.055, 6, 4), K.glow(game, '#ffffff', 2.4), UP_DISH.bulbs)
    m4 = THREE.Matrix4()
    for i in range(UP_DISH.bulbs):
        a = (i / UP_DISH.bulbs) * TAU
        m4.makeTranslation(math.cos(a) * (R + 0.035), math.sin(a) * (R + 0.035), -(hub + depth) - 0.07)
        bulbs.setMatrixAt(i, m4)
        bulbs.setColorAt(i, _cc.set(PAL.marqueeGold).multiplyScalar(0.1))
    bulbs.name = 'rimBulbs'
    bulbs.userData.noMerge = True
    bulbs.castShadow = False
    tilt.add(bulbs)
    # back ribs (radial trusses), hub drum, pivot shaft, counterweight
    for k in range(6):
        pts = []
        for i in range(8):
            r = 0.3 + (i / 7) * 1.95
            pts.append([r, zOf(r) + 0.08])
        for i in range(7, -1, -1):
            r = 0.3 + (i / 7) * 1.95
            pts.append([r, zOf(r) + 0.08 + lerp(0.36, 0.05, i / 7)])
        rib = K.extrude(pts, 0.05, {'bevel': 0.012, 'bevelSeg': 1})
        rib.rotateX(math.pi / 2)                                                 # shape y -> tilt z, thickness -> tangential
        rib.rotateZ((k / 6) * TAU + TAU / 12)
        tilt.add(K.m(tinted(rib, WHITE), paint))
    tilt.add(K.m(tinted(K.cyl(0.34, 0.34, hub + 0.2, {'bevel': 0.05, 'seg': 16}), WHITE), paint,
                 {'pos': [0, 0, 0.2], 'rot': [-math.pi / 2, 0, 0]}))
    tilt.add(K.m(tinted(K.cyl(0.13, 0.13, 1.3, {'bevel': 0.02, 'seg': 10}), STEEL), paint,
                 {'pos': [-0.65, 0, 0], 'rot': [0, 0, -math.pi / 2]}))
    tilt.add(K.m(tinted(K.box(0.42, 0.34, 0.3, 0.06), STEEL), paint, {'pos': [0, 0.05, 0.4]}))
    # elevation sector gear (rides with the dish)
    sec = []
    a0, a1, nt = -math.pi / 2 - 0.6, -math.pi / 2 + 1.25, 22
    for i in range(nt * 2 + 1):
        a, r = lerp(a0, a1, i / (nt * 2)), (0.95 if i % 2 else 1.0)
        sec.append([math.cos(a) * r, math.sin(a) * r])
    for i in range(6, -1, -1):
        a = lerp(a0, a1, i / 6)
        sec.append([math.cos(a) * 0.62, math.sin(a) * 0.62])
    secGeo = K.extrude([[-zz, y] for zz, y in sec], 0.06, {'bevel': 0.01, 'bevelSeg': 1})
    secGeo.rotateY(math.pi / 2)
    tilt.add(K.m(tinted(secGeo, STEEL), paint, {'pos': [0.3, 0, 0]}))
    # feed struts to the focal feed (white body, red horn facing the dish)
    fz = -(hub + f)
    for k in range(4):
        a = (k / 4) * TAU + math.pi / 4
        tilt.add(rod([math.cos(a) * (R - 0.15), math.sin(a) * (R - 0.15), zOf(R - 0.15) - 0.02],
                     [math.cos(a) * 0.12, math.sin(a) * 0.12, fz - 0.05], 0.035, paint,
                     {'tint': WHITE, 'seg': 7, 'r2': 0.028}))
    feed = grp('feed', [0, 0, fz])
    feed.add(K.m(tinted(K.cyl(0.14, 0.16, 0.34, {'bevel': 0.04, 'seg': 12}), WHITE), paint,
                 {'pos': [0, 0, -0.34], 'rot': [math.pi / 2, 0, 0]}))
    feed.add(K.m(tinted(K.lathe([[0.06, 0], [0.14, 0.02], [0.24, 0.24], [0.22, 0.26], [0.1, 0.06], [0, 0.06]],
                                {'seg': 14, 'round': 0.02, 'steps': 1}), PAL.channelRed), paint,
                 {'pos': [0, 0, 0.0], 'rot': [math.pi / 2, 0, 0]}))
    tilt.add(feed)

    g.userData.parts = JSObj(yaw=yaw, tilt=tilt, rimBulbs=bulbs, feed=feed)
    g.userData.rig = {'droop': UP_DISH.droop, 'aligned': UP_DISH.aligned, 'pivotY': pivotY, 'radius': R,
                      'bulbs': UP_DISH.bulbs}
    g.userData.colliders = [
        {'min': [-1.3, 0, -1.3], 'max': [1.3, 0.34, 1.3]},
        {'min': [-0.62, 0, -0.62], 'max': [0.62, 2.2, 0.62]},
        {'min': [-1.9, 0, -2.3], 'max': [1.9, 1.5, -1.0], 'opts': {'tag': 'uplink_droop'}},   # under the drooped rim; drop after alignment
    ]
    g.userData.interact = None
    tilt.rotation.x = 0.45                              # bake pose (dish up: no floor darkening on the rim)
    finishRig(game, g, {'finish': {'ao': {'res': 64, 'strength': 0.7, 'dist': 0.5}}})
    setUplinkPose(g, {'tilt': opts['tilt'] if opts.get('tilt') is not None else
                      (UP_DISH.aligned if opts.get('aligned') else UP_DISH.droop),
                      'yaw': opts['yaw'] if opts.get('yaw') is not None else 0})
    setUplinkChase(g, 0, {'on': bool(opts.get('lit'))})
    return g


registerProp('uplink_dish', _uplink_dish,
             {'category': 'machines', 'tags': ['uplink', 'machine', 'yard', 'dish'], 'size': [5.3, 5.8, 5.2],
              'desc': 'THE UPLINK: 5 m white satellite dish on an az-el turntable', 'hero': True})


def chromeHandle():
    return K.tube([[0, 0.06, 0], [0, 0.07, -0.03], [0, -0.07, -0.03], [0, -0.06, 0]], 0.009, {'seg': 10, 'radial': 5})


registerScene('uplink', {
    'floor': '#4A4652', 'wall': '#1E2344', 'room': [14, 12], 'wallH': 7, 'hemi': 0.75,
    'items': [
        {'id': 'uplink_dish', 'pos': [0, 2.2], 'rotY': 0, 'opts': {'aligned': True, 'lit': True}},
    ],
    'cam': {'pos': [5.5, 3.4, -6.5], 'target': [0, 2.6, 1.5], 'fov': 50},
})


# ---------------------------------------------------------------------------------------------- cradle
# Feed-horn cradle (anchor uplink_cradle: the gun sits at y 1.3). The horn hangs above-behind the clamp and aims
# its R/G/B lamps down at the weapon. parts.jawF/jawB rotate about x (rig.jawOpen .. 0 closed); parts.gunSlot.
def setCradleLamps(game, g, level=1):
    P = g.userData.parts
    q = js_round(clamp(level, 0, 1) * 10) / 10
    for k, c in [['lampR', PAL.hotMic], ['lampG', PAL.laughTrack], ['lampB', PAL.coldOpen]]:
        if P[k]:
            P[k].material = K.glow(game, c, 0.6 + 2.6 * q) if q > 0 else K.mat(game, 'plastic', '#3A3440')


def yardAtlas():
    def draw(ctx, W, H, rand):
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'

        def plate(x, y, w, h, bg, fg, t1, t2, acc=None):
            ctx.fillStyle = bg
            ctx.beginPath()
            ctx.roundRect(x, y, w, h, 8)
            ctx.fill()
            ctx.strokeStyle = acc or 'rgba(255,255,255,0.5)'
            ctx.lineWidth = 3
            ctx.beginPath()
            ctx.roundRect(x + 4, y + 4, w - 8, h - 8, 6)
            ctx.stroke()
            ctx.fillStyle = fg
            ctx.font = '%spx "Bungee", "Arial Black", sans-serif' % js_str(js_round(h * 0.42))
            ctx.fillText(t1, x + w / 2, y + h * (0.4 if t2 else 0.52))
            if t2:
                ctx.fillStyle = acc or fg
                ctx.font = '%spx "Titan One", sans-serif' % js_str(js_round(h * 0.18))
                ctx.fillText(t2, x + w / 2, y + h * 0.76)
        plate(0, 0, 256, 64, '#23324A', '#F4F1E8', 'FEED HORN', 'UPLINK 13 · KU BAND', '#FFB347')
        plate(256, 0, 256, 64, '#F4F1E8', '#23324A', 'ALIGN DISH', 'CRANK CLOCKWISE  >>>', '#E23B3B')
        plate(0, 64, 512, 64, '#E23B3B', '#F4F1E8', 'UPLINK CONTROL', 'WZTV CHANNEL 13 · AUTHORIZED CREW ONLY',
              '#FFD23A')
        plate(0, 128, 256, 64, '#3A4A3E', '#F4F1E8', 'WZTV 50 kW', 'TRANSMITTER · FINAL AMP', '#9CFF57')
        # gauge faces (0,192)-(128,320) elevation, (128,192)-(256,320) plate volts, (256,192)-(384,320) spare
        for label, ox, lock in [['ELEVATION', 0, True], ['PLATE KV', 128, False], ['SIGNAL', 256, False]]:
            cx, cy = ox + 64, 256
            ctx.fillStyle = '#F4ECD6'
            ctx.beginPath()
            ctx.arc(cx, cy, 63, 0, TAU)
            ctx.fill()
            ctx.lineWidth = 7
            ctx.strokeStyle = '#52D24A' if lock else '#E23B3B'
            ctx.beginPath()
            ctx.arc(cx, cy + 10, 44, math.pi * 1.7 if lock else math.pi * 1.72, math.pi * 1.86)
            ctx.stroke()
            ctx.strokeStyle = '#2A2230'
            ctx.lineWidth = 2.5
            ctx.beginPath()
            ctx.arc(cx, cy + 10, 44, math.pi * 1.14, math.pi * 1.86)
            ctx.stroke()
            for i in range(11):
                a, ln = math.pi * 1.14 + (i / 10) * math.pi * 0.72, (6 if i % 5 else 11)
                ctx.beginPath()
                ctx.moveTo(cx + math.cos(a) * 44, cy + 10 + math.sin(a) * 44)
                ctx.lineTo(cx + math.cos(a) * (44 - ln), cy + 10 + math.sin(a) * (44 - ln))
                ctx.stroke()
            ctx.fillStyle = '#2A2230'
            ctx.font = '11px "Bungee", "Arial Black", sans-serif'
            ctx.fillText(label, cx, cy + 32)
            if lock:
                ctx.fillStyle = '#2E9A3A'
                ctx.font = '10px "Titan One", sans-serif'
                ctx.fillText('LOCK', cx + 30, cy - 36)
        # corrugated wall (384,192)-(512,320) (repeat-free strip): cream with vertical ribs
        for x in range(384, 512, 16):
            gr = ctx.createLinearGradient(x, 0, x + 16, 0)
            gr.addColorStop(0, '#CFC6B0')
            gr.addColorStop(0.5, '#F2EAD6')
            gr.addColorStop(1, '#CFC6B0')
            ctx.fillStyle = gr
            ctx.fillRect(x, 192, 16, 128)
        # interior console glow (0,320)-(256,448): dark panel with lit buttons and a tiny scope
        ctx.fillStyle = '#1A2230'
        ctx.fillRect(0, 320, 256, 128)
        cols = ['#FF3B30', '#FFD23A', '#52E04A', '#7FE7FF', '#FF8A2A']
        for j in range(3):
            for i in range(9):
                ctx.fillStyle = cols[(i * 3 + j * 7) % 5]
                ctx.globalAlpha = 0.5 + rand() * 0.5
                ctx.beginPath()
                ctx.roundRect(16 + i * 18, 340 + j * 18, 11, 9, 3)
                ctx.fill()
        ctx.globalAlpha = 1
        ctx.fillStyle = '#0E2A1A'
        ctx.beginPath()
        ctx.roundRect(186, 334, 56, 44, 6)
        ctx.fill()
        ctx.strokeStyle = '#52E04A'
        ctx.lineWidth = 2
        ctx.beginPath()
        for x in range(49):
            y = 356 + math.sin(x * 0.5) * 10 * math.exp(-x / 40)
            if x:
                ctx.lineTo(190 + x, y)
            else:
                ctx.moveTo(190, y)
        ctx.stroke()
        ctx.fillStyle = '#7FE7FF'
        ctx.globalAlpha = 0.7
        ctx.fillRect(16, 404, 224, 6)
        ctx.globalAlpha = 1
        # solar cells (256,320)-(512,448): blue grid with silver bus lines
        ctx.fillStyle = '#1E3A8A'
        ctx.fillRect(256, 320, 256, 128)
        for j in range(4):
            for i in range(8):
                gx, gy = 260 + i * 31.5, 324 + j * 31
                gr = ctx.createLinearGradient(gx, gy, gx + 28, gy + 28)
                gr.addColorStop(0, '#3E6BD6')
                gr.addColorStop(1, '#1B3478')
                ctx.fillStyle = gr
                ctx.fillRect(gx, gy, 28, 27)
                ctx.fillStyle = 'rgba(200,210,230,0.5)'
                ctx.fillRect(gx, gy + 13, 28, 1.5)
        # gold foil (0,448)-(256,512)
        ctx.fillStyle = '#D9A63A'
        ctx.fillRect(0, 448, 256, 64)
        for i in range(90):
            ctx.fillStyle = 'rgba(255,236,160,0.45)' if rand() < 0.5 else 'rgba(120,80,20,0.35)'
            ctx.beginPath()
            x, y = rand() * 256, 448 + rand() * 64
            ctx.moveTo(x, y)
            ctx.lineTo(x + 6 + rand() * 18, y + (rand() - 0.5) * 10)
            ctx.lineTo(x + rand() * 10, y + 6 + rand() * 10)
            ctx.closePath()
            ctx.fill()
        # satellite band (256,448)-(512,512): white with SKYLARK-13
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(256, 448, 256, 64)
        ctx.fillStyle = PAL.wztvBlue
        ctx.font = '26px "Bungee", "Arial Black", sans-serif'
        ctx.fillText('SKYLARK-13', 384, 482)
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(256, 450, 256, 5)
        ctx.fillRect(256, 505, 256, 5)
    return K.tex.canvas('yard_atlas_v1', 512, 512, draw, {'repeat': False, 'fonts': True})


def _uplink_cradle(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('uplink_cradle')
    paint = K.mat(game, 'paint', '#ffffff', {'rough': 0.45})
    atl = K.mat(game, 'paint', '#ffffff', {'map': yardAtlas(), 'rough': 0.5})
    alu = K.mat(game, 'metal', '#C9CED6', {'map': K.tex.brushed('#C9CED6')})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    BLUE, WHITE, RED, RUBBER, STEEL = '#3E67C8', '#F1EFE9', '#D93A34', '#2A2430', '#5A5E6E'
    slotY = 1.3
    # foot + column + band + plate
    g.add(K.m(tinted(K.lathe([[0, 0], [0.34, 0], [0.35, 0.04], [0.27, 0.09], [0.12, 0.12], [0, 0.12]],
                             {'seg': 16, 'round': 0.025, 'steps': 1}), BLUE), paint))
    for i in range(6):
        a = (i / 6) * TAU + 0.3
        g.add(K.m(tinted(THREE.CylinderGeometry(0.022, 0.026, 0.03, 6), STEEL), paint,
                  {'pos': [math.cos(a) * 0.27, 0.07, math.sin(a) * 0.27]}))
    g.add(K.m(tinted(K.cyl(0.075, 0.095, 0.78, {'bevel': 0.02, 'seg': 12}), BLUE), paint, {'pos': [0, 0.1, 0]}))
    g.add(K.m(tinted(K.cyl(0.083, 0.086, 0.08, {'bevel': 0.01, 'seg': 12}), WHITE), paint, {'pos': [0, 0.6, 0]}))
    g.add(K.m(cellUV(THREE.PlaneGeometry(0.2, 0.05).rotateY(math.pi), 0, 0, 256, 64), atl, {'pos': [0, 0.42, -0.094]}))
    # the feed horn: a big square aluminium horn opening to the sky, red rim, flange + rivets at the throat
    horn = THREE.Group()
    horn.position.set(0, 0.86, 0.02)
    horn.rotation.x = -0.15                                 # leans toward the player: lamps + gun visible inside
    hornProf = [[0.1, 0], [0.12, 0.04], [0.16, 0.12], [0.3, 0.38], [0.42, 0.56], [0.43, 0.6], [0.4, 0.6], [0.29, 0.4],
                [0.14, 0.13], [0.09, 0.06]]
    HX = 1.2                                                # wider along x (the gun lies across the mouth)
    hornGeo = K.lathe(hornProf, {'seg': 4, 'round': 0.025, 'steps': 1}).clone()
    hornGeo.rotateY(math.pi / 4).scale(HX, 1, 1)
    K.uvScale(hornGeo, 2, 1)
    horn.add(K.m(hornGeo, alu))
    rimGeo = K.lathe([[0.415, 0.575], [0.45, 0.585], [0.45, 0.63], [0.41, 0.63]],
                     {'seg': 4, 'round': 0.012, 'steps': 1}).clone()
    rimGeo.rotateY(math.pi / 4).scale(HX, 1, 1)
    horn.add(K.m(tinted(rimGeo, RED), paint))
    flange = K.lathe([[0.1, -0.02], [0.17, -0.02], [0.17, 0.05], [0.1, 0.05]],
                     {'seg': 4, 'round': 0.01, 'steps': 1}).clone()
    flange.rotateY(math.pi / 4).scale(HX, 1, 1)
    horn.add(K.m(tinted(flange, STEEL), paint))

    def wallR(y):
        return (lerp(0.12, 0.16, y / 0.12) if y < 0.12 else lerp(0.16, 0.3, (y - 0.12) / 0.26) if y < 0.38
                else lerp(0.3, 0.42, (y - 0.38) / 0.18)) * math.sqrt(0.5)
    for k in range(4):   # rivet rows up the face centres
        for j in range(3):
            y, a = 0.2 + j * 0.13, (k / 4) * TAU
            r = wallR(y) + 0.006
            horn.add(K.m(THREE.SphereGeometry(0.013, 5, 3), chrome, {'pos': [math.sin(a) * r * HX, y, math.cos(a) * r]}))
    # R/G/B lamps on the inner walls near the throat, aimed at the gun
    lamps = JSObj()
    for k, c, a in [['lampR', PAL.hotMic, math.pi / 2], ['lampG', PAL.laughTrack, 0], ['lampB', PAL.coldOpen, -math.pi / 2]]:
        y, wr, sx, sz = 0.26, wallR(0.26), math.sin(a), math.cos(a)
        rot = [-math.pi / 2, 0, 0] if sz > 0.5 else [0, 0, math.pi / 2 if sx > 0 else -math.pi / 2]
        horn.add(K.m(K.cyl(0.036, 0.04, 0.03, {'bevel': 0.008, 'seg': 8}), chrome,
                     {'pos': [sx * wr * HX * 0.93, y, sz * wr * 0.93], 'rot': rot}))
        lm = keep(K.m(THREE.SphereGeometry(0.036, 8, 6), K.glow(game, c, 2.4),
                      {'pos': [sx * wr * HX * 0.76, y, sz * wr * 0.76], 'name': k, 'cast': False}))
        lm.userData.noOcclude = True
        horn.add(lm)
        lamps[k] = lm
    g.add(horn)
    # clamp arm rising through the throat to a padded C-clamp holding the gun across the mouth (along x)
    g.add(K.m(tinted(K.cyl(0.035, 0.045, slotY - 0.95, {'bevel': 0.01, 'seg': 10}), STEEL), paint,
              {'pos': [0, 0.9, 0.0]}))
    g.add(K.m(tinted(K.box(0.3, 0.06, 0.12, 0.014), BLUE), paint, {'pos': [0, slotY - 0.08, 0]}))
    for sx in [-1, 1]:
        g.add(K.m(tinted(K.box(0.05, 0.08, 0.11, 0.012), RUBBER), paint, {'pos': [sx * 0.12, slotY - 0.03, 0]}))
    # U-bracket yoke with pivot bolts on the horn's sides (reads as an aimed antenna mount)
    g.add(K.m(tinted(K.tube([[-0.25, 1.07, 0], [-0.25, 0.92, 0], [-0.12, 0.85, 0], [0.12, 0.85, 0], [0.25, 0.92, 0],
                             [0.25, 1.07, 0]], 0.028, {'seg': 16, 'radial': 6}), BLUE), paint))
    for sx in [-1, 1]:
        g.add(K.m(tinted(K.cyl(0.045, 0.045, 0.1, {'bevel': 0.012, 'seg': 10}), STEEL), paint,
                  {'pos': [sx * 0.3, 1.07, 0], 'rot': [0, 0, sx * math.pi / 2]}))
    gunSlot = grp('gunSlot', [0, slotY, 0])
    g.add(gunSlot)
    jaws = JSObj()
    for name, s in [['jawF', -1], ['jawB', 1]]:
        jaw = grp(name, [0, slotY - 0.07, s * 0.06])
        for sx in [-1, 1]:
            jaw.add(K.m(tinted(K.tube([[0, 0, 0], [0, 0.07, s * 0.05], [0, 0.14, s * 0.02], [0, 0.16, -s * 0.03]],
                                      0.018, {'seg': 8, 'radial': 5}), RED), paint, {'pos': [sx * 0.12, 0, 0]}))
        jaw.add(K.m(tinted(K.box(0.3, 0.04, 0.05, 0.012), RUBBER), paint, {'pos': [0, 0.16, -s * 0.035]}))
        jaw.rotation.x = s * 0.5
        g.add(jaw)
        jaws[name] = jaw
    # cable down the back toward the dish (+z)
    g.add(K.m(tinted(K.tube([[0.1, 0.95, 0.12], [0.12, 0.6, 0.12], [0.13, 0.08, 0.2], [0.12, 0.012, 0.8]], 0.02,
                            {'seg': 14, 'radial': 5}), RUBBER), paint))

    g.userData.parts = JSObj(gunSlot=gunSlot, jawF=jaws.jawF, jawB=jaws.jawB, **lamps, horn=horn)
    g.userData.rig = {'slotY': slotY, 'jawOpenF': -0.5, 'jawOpenB': 0.5, 'jawClosed': 0, 'beamFrom': [0, 1.5, 0.08],
                      'beamDir': [0, math.cos(0.12), math.sin(0.12)]}
    g.userData.colliders = [{'min': [-0.46, 0, -0.44], 'max': [0.46, 1.5, 0.5]}]
    g.userData.interact = {'point': [0, slotY, -0.55], 'radius': 1.3}
    finishRig(game, g)
    if opts.get('closed'):
        jaws.jawF.rotation.x = 0
        jaws.jawB.rotation.x = 0
    setCradleLamps(game, g, opts['lamps'] if opts.get('lamps') is not None else 0)
    return g


registerProp('uplink_cradle', _uplink_cradle,
             {'category': 'machines', 'tags': ['uplink', 'machine', 'yard'], 'size': [0.92, 1.5, 0.95],
              'desc': 'Uplink feed-horn cradle: sky-facing horn with a gun clamp and R/G/B lamps inside', 'hero': True})


# ----------------------------------------------------------------------------------------------- crank
# Alignment crank (anchor uplink_crank: wheel hub at y 1.0, wheel facing the operator). parts.wheel spins about z,
# parts.handle = glowing grip (setCrankGlow), parts.needle = elevation gauge (rig.needleMin droop .. needleMax lock).
def setCrankGlow(game, g, level=1):
    P = g.userData.parts
    q = js_round(clamp(level, 0, 1) * 10) / 10
    if P.handle:
        P.handle.material = K.glow(game, PAL.marqueeGold, 0.5 + 2.5 * q) if q > 0 else K.mat(game, 'plastic', '#B89A5A')


def _uplink_crank(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('uplink_crank')
    paint = K.mat(game, 'paint', '#ffffff', {'rough': 0.45})
    atl = K.mat(game, 'paint', '#ffffff', {'map': yardAtlas(), 'rough': 0.5})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    BLUE, RED, STEEL, DARK = '#3E67C8', '#D93A34', '#5A5E6E', '#2E2A36'
    hubY = 1.0
    # cast bell base + column + gearbox
    g.add(K.m(tinted(K.lathe([[0, 0], [0.3, 0], [0.31, 0.04], [0.2, 0.12], [0.1, 0.22], [0.08, 0.3], [0, 0.3]],
                             {'seg': 14, 'round': 0.03, 'steps': 1}), BLUE), paint))
    g.add(K.m(tinted(K.cyl(0.075, 0.085, 0.55, {'bevel': 0.02, 'seg': 12}), BLUE), paint, {'pos': [0, 0.28, 0.02]}))
    g.add(K.m(tinted(K.box(0.3, 0.3, 0.3, 0.045), BLUE), paint, {'pos': [0, hubY, 0.08]}))
    g.add(K.m(tinted(K.cyl(0.13, 0.13, 0.05, {'bevel': 0.015, 'seg': 16}), STEEL), paint,
              {'pos': [0.151, hubY, 0.08], 'rot': [0, 0, -math.pi / 2]}))
    for i in range(3):
        g.add(K.m(tinted(K.box(0.24, 0.016, 0.02, 0.007), '#2F4F9E'), paint,
                  {'pos': [0, hubY - 0.08 + i * 0.05, 0.235]}))
    # elevation gauge on a tilted pod on top
    pod = THREE.Group()
    pod.position.set(0, hubY + 0.44, 0.1)
    g.add(K.m(tinted(K.cyl(0.035, 0.045, 0.3, {'bevel': 0.01, 'seg': 10}), BLUE), paint, {'pos': [0, hubY + 0.12, 0.1]}))
    pod.rotation.x = 0.55
    pod.add(K.m(tinted(K.cyl(0.11, 0.12, 0.07, {'bevel': 0.02, 'seg': 14}), BLUE), paint,
                {'rot': [-math.pi / 2, 0, 0]}))
    pod.add(K.m(K.tube(ringXY(0.1, 20, 0), 0.01, {'seg': 24, 'radial': 4, 'closed': True}), chrome,
                {'pos': [0, 0, -0.072]}))
    pod.add(K.m(disc(0.095, 24, [0, 192, 128, 320]), atl, {'pos': [0, 0, -0.071]}))
    needle = grp('needle', [0, -0.012, -0.075])
    needle.add(K.m(tinted(THREE.BoxGeometry(0.006, 0.075, 0.004).translate(0, 0.036, 0), RED), paint))
    needle.add(K.m(K.cyl(0.01, 0.01, 0.006, {'bevel': 0.002, 'seg': 8}), chrome, {'rot': [-math.pi / 2, 0, 0]}))
    pod.add(needle)
    g.add(pod)
    g.add(K.m(cellUV(THREE.PlaneGeometry(0.28, 0.07).rotateY(math.pi), 256, 0, 512, 64), atl,
              {'pos': [0, 0.66, -0.066]}))
    # the handwheel: red rim, 5 swept spokes, chrome hub, glowing grip (spins with the wheel)
    wheel = grp('wheel', [0, hubY, -0.1])
    rw = 0.34
    wheel.add(K.m(tinted(K.tube(ringXY(rw, 24, 0), 0.03, {'seg': 32, 'radial': 6, 'closed': True}), RED), paint))
    for i in range(5):
        a = (i / 5) * TAU
        pts = []
        for k in range(5):
            t = k / 4
            aa, r = a + t * 0.45, lerp(0.06, rw - 0.015, t)
            pts.append([math.cos(aa) * r, math.sin(aa) * r, -0.02 * math.sin(t * math.pi)])
        wheel.add(K.m(tinted(K.tube(pts, 0.017, {'seg': 6, 'radial': 4}), RED), paint))
    wheel.add(K.m(K.lathe([[0, 0], [0.08, 0], [0.085, 0.03], [0.06, 0.07], [0.03, 0.09], [0, 0.09]],
                          {'seg': 12, 'round': 0.012, 'steps': 1}), chrome,
                  {'rot': [-math.pi / 2, 0, 0], 'pos': [0, 0, 0.04]}))
    wheel.add(K.m(K.cyl(0.02, 0.02, 0.1, {'bevel': 0.006, 'seg': 8}), chrome,
                  {'pos': [rw, 0, 0], 'rot': [-math.pi / 2, 0, 0]}))
    handle = keep(K.m(K.lathe([[0, 0], [0.034, 0.01], [0.04, 0.05], [0.036, 0.1], [0.03, 0.125], [0, 0.13]],
                              {'seg': 10, 'round': 0.012, 'steps': 1}), K.glow(game, PAL.marqueeGold, 2.4),
                      {'pos': [rw, 0, -0.06], 'rot': [-math.pi / 2, 0, 0], 'name': 'handle', 'cast': False}))
    handle.userData.noOcclude = True
    wheel.add(handle)
    wheel.rotation.z = 0.3
    g.add(wheel)
    # conduit to the dish
    g.add(K.m(tinted(K.tube([[0, 0.9, 0.22], [0.02, 0.6, 0.3], [0.03, 0.05, 0.34], [0.03, 0.015, 0.8]], 0.03,
                            {'seg': 14, 'radial': 6}), DARK), paint))

    g.userData.parts = JSObj(wheel=wheel, handle=handle, needle=needle)
    g.userData.rig = {'hubY': hubY, 'needleMin': -1.05, 'needleMax': 1.05}
    g.userData.colliders = [{'min': [-0.32, 0, -0.28], 'max': [0.32, 1.45, 0.32]}]
    g.userData.interact = {'point': [0, hubY, -0.55], 'radius': 1.2}
    finishRig(game, g)
    needle.rotation.z = -1.05 if opts.get('aligned') else 1.05
    setCrankGlow(game, g, opts['glow'] if opts.get('glow') is not None else 1)
    return g


registerProp('uplink_crank', _uplink_crank,
             {'category': 'machines', 'tags': ['uplink', 'machine', 'yard'], 'size': [0.76, 1.6, 0.9],
              'desc': 'Uplink alignment crank wheel with a glowing handle + elevation gauge', 'hero': True})


# ----------------------------------------------------------------------------------------------- booth
# Small uplink control booth: corrugated kiosk with a lit console behind the window and a blinking lamp panel.
# setBoothLamps(g, t) drives parts.lamps (instanced); parts.beacon = roof beacon mesh.
BOOTH_COLS = ['#FF3B30', '#FFD23A', '#52E04A', '#7FE7FF', '#FF8A2A']


def setBoothLamps(g, t=0):
    inst = g.userData.parts.lamps
    if not inst:
        return
    for i in range(inst.count):
        ph = math.sin(i * 12.9898 + 78.233) * 43758.5453
        rate = 0.7 + (ph - math.floor(ph)) * 2.2
        on = math.sin(t * rate * TAU + i * 1.7) > -0.1
        _cc.set(BOOTH_COLS[i % 5]).multiplyScalar(1 if on else 0.12)
        inst.setColorAt(i, _cc)


def _uplink_booth(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('uplink_booth')
    paint = K.mat(game, 'paint', '#ffffff', {'rough': 0.5})
    atl = K.mat(game, 'paint', '#ffffff', {'map': yardAtlas(), 'rough': 0.5})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    glass = game.mats.glass('#BFE6FF', {'opacity': 0.18})
    CREAM, BLUE, RED, DARK = '#EFE6D0', '#3E67C8', '#D93A34', '#2E2A36'
    W, H, D = 1.5, 2.25, 1.25

    # body: corrugated walls (atlas strip, repeated by UV) with a blue skirt
    def draw_corr(ctx, w, h, rand):
        for x in range(0, w, 16):
            gr = ctx.createLinearGradient(x, 0, x + 16, 0)
            gr.addColorStop(0, '#CBBFA6')
            gr.addColorStop(0.5, '#F4ECDA')
            gr.addColorStop(1, '#CBBFA6')
            ctx.fillStyle = gr
            ctx.fillRect(x, 0, 16, h)
        for i in range(40):
            ctx.fillStyle = 'rgba(120,96,70,%s)' % js_str(0.04 + rand() * 0.05)
            ctx.fillRect(rand() * w, rand() * h, 1.5, 4 + rand() * 20)
    corr = K.tex.canvas('booth_corrugated', 128, 128, draw_corr)
    wallMat = K.mat(game, 'paint', '#ffffff', {'map': corr, 'rough': 0.5})
    g.add(K.m(K.box(W, H - 0.25, D, 0.045, {'uv': 0.62}), wallMat, {'pos': [0, 0.12 + (H - 0.25) / 2, 0]}))
    g.add(K.m(tinted(K.box(W + 0.03, 0.26, D + 0.03, 0.04), BLUE), paint, {'pos': [0, 0.13, 0]}))
    # roof: overhanging red slab, beacon, whip antenna
    g.add(K.m(tinted(K.box(W + 0.24, 0.1, D + 0.28, 0.045), RED), paint,
              {'pos': [0, H - 0.08, 0.02], 'rot': [0.05, 0, 0]}))
    g.add(K.m(tinted(K.cyl(0.08, 0.09, 0.06, {'bevel': 0.015, 'seg': 12}), DARK), paint, {'pos': [0.4, H - 0.03, 0.2]}))
    beacon = keep(K.m(THREE.SphereGeometry(0.075, 12, 8, 0, TAU, 0, math.pi / 2), K.glow(game, PAL.onAirRed, 2.6),
                      {'pos': [0.4, H + 0.03, 0.2], 'name': 'beacon', 'cast': False}))
    beacon.userData.noOcclude = True
    g.add(beacon)
    g.add(K.m(THREE.CylinderGeometry(0.006, 0.01, 0.9, 5).translate(0, 0.45, 0), chrome,
              {'pos': [-0.5, H - 0.03, 0.3]}))
    g.add(K.m(THREE.SphereGeometry(0.02, 6, 4), chrome, {'pos': [-0.5, H + 0.88, 0.3]}))
    # sign band
    g.add(K.m(cellUV(K.box(1.2, 0.15, 0.03, 0.012).clone(), 0, 64, 512, 128), atl,
              {'pos': [0, H - 0.26, -D / 2 - 0.02]}))
    # window: chrome frame, glass, lit console inside
    winY, ww, wh = 1.45, 0.95, 0.5
    g.add(K.m(K.tube(rrXY(ww, wh, 0.07, 0, 3), 0.02, {'seg': 36, 'radial': 5, 'closed': True}), chrome,
              {'pos': [0, winY, -D / 2 - 0.012]}))
    g.add(K.m(tinted(THREE.PlaneGeometry(ww, wh).rotateY(math.pi), '#10141E'), paint,
              {'pos': [0, winY, -D / 2 + 0.02]}))
    con = keep(K.m(cellUV(THREE.PlaneGeometry(ww * 0.86, wh * 0.5).rotateY(math.pi), 0, 320, 256, 448),
                   K.glow(game, '#ffffff', 1.1, {'map': yardAtlas()}),
                   {'pos': [0, winY - 0.1, -D / 2 + 0.012], 'rot': [-0.5, 0, 0], 'name': 'console', 'cast': False}))
    g.add(con)
    g.add(K.m(THREE.PlaneGeometry(ww, wh).rotateY(math.pi), glass, {'pos': [0, winY, -D / 2 - 0.006], 'cast': False}))
    # exterior lamp panel below the window: plate + instanced jewel lamps + two meters + toggles
    panelY = 0.88
    g.add(K.m(tinted(K.box(1.0, 0.44, 0.05, 0.025), '#3A4A66'), paint, {'pos': [0, panelY, -D / 2 - 0.02]}))
    cols, rows = 6, 3
    lamps = THREE.InstancedMesh(THREE.SphereGeometry(0.026, 7, 3, 0, TAU, 0, math.pi / 2).rotateX(-math.pi / 2),
                                K.glow(game, '#ffffff', 2.2), cols * rows)
    m4 = THREE.Matrix4()
    for j in range(rows):
        for i in range(cols):
            k = j * cols + i
            m4.makeTranslation(-0.43 + i * 0.075, panelY + 0.12 - j * 0.075, -D / 2 - 0.046)
            lamps.setMatrixAt(k, m4)
            lamps.setColorAt(k, _cc.set(BOOTH_COLS[k % 5]))
    lamps.name = 'lamps'
    lamps.userData.noMerge = True
    lamps.castShadow = False
    g.add(lamps)
    for x, cell in [[0.16, [128, 192, 256, 320]], [0.35, [256, 192, 384, 320]]]:
        g.add(K.m(K.tube(ringXY(0.075, 16, 0), 0.01, {'seg': 20, 'radial': 4, 'closed': True}), chrome,
                  {'pos': [x, panelY + 0.05, -D / 2 - 0.05]}))
        g.add(K.m(disc(0.072, 20, cell), atl, {'pos': [x, panelY + 0.05, -D / 2 - 0.047]}))
    for i in range(5):
        g.add(K.m(K.cyl(0.008, 0.01, 0.05, {'bevel': 0.003, 'seg': 6}), chrome,
                  {'pos': [0.08 + i * 0.07, panelY - 0.15, -D / 2 - 0.045], 'rot': [-math.pi / 2 - 0.4, 0, 0]}))
    # side door (+x wall) with porthole + handle
    g.add(K.m(tinted(K.box(0.05, 1.7, 0.72, 0.03), '#E4DAC0'), paint, {'pos': [W / 2 + 0.01, 0.97, 0.05]}))
    g.add(K.m(K.tube([[0, x, z] for x, y, z in ringXZ(0.12, 16, 0)], 0.018, {'seg': 20, 'radial': 4, 'closed': True}),
              chrome, {'pos': [W / 2 + 0.04, 1.45, 0.05]}))
    g.add(K.m(tinted(THREE.CircleGeometry(0.12, 16).rotateY(math.pi / 2), '#141A26'), paint,
              {'pos': [W / 2 + 0.037, 1.45, 0.05]}))
    g.add(K.m(chromeHandle(), chrome, {'pos': [W / 2 + 0.04, 1.0, -0.22], 'rot': [0, -math.pi / 2, 0]}))
    # step + conduit
    g.add(K.m(tinted(K.box(0.3, 0.12, 0.8, 0.03), '#5A5E6E'), paint, {'pos': [W / 2 + 0.18, 0.06, 0.05]}))
    g.add(K.m(tinted(K.tube([[-W / 2 + 0.1, 0.4, D / 2], [-W / 2 + 0.1, 0.1, D / 2 + 0.12],
                             [-W / 2 + 0.1, 0.015, D / 2 + 0.5]], 0.035, {'seg': 10, 'radial': 6}), DARK), paint))

    g.userData.parts = JSObj(lamps=lamps, beacon=beacon, console=con)
    anchor = JSObj(pos=[0, 1.2, -D / 2 - 0.6], color='#7FE7FF', intensity=1.2, distance=4)
    g.userData.lightAnchors = [] if opts.get('light') is False else [anchor]
    g.userData.colliders = [{'min': [-W / 2 - 0.02, 0, -D / 2 - 0.08], 'max': [W / 2 + 0.12, H, D / 2 + 0.02]}]
    finishRig(game, g)
    setBoothLamps(g, opts['t'] if opts.get('t') is not None else 0.37)
    return g


registerProp('uplink_booth', _uplink_booth,
             {'category': 'machines', 'tags': ['uplink', 'yard', 'booth'], 'size': [1.9, 2.4, 1.6],
              'desc': 'little uplink control booth with blinking lamps', 'hero': True})


# --------------------------------------------------------------------------------------------- Skylark
# The satellite Skylark-13 (GDD §10.4): chunky gold-foil drum, blue solar wings, downward dish, beacon on top.
# Local -y faces Earth. setSkylarkBeacon(game, g, 'red'|'green'|'flare'|'off').
def setSkylarkBeacon(game, g, state='red'):
    P = g.userData.parts
    c = PAL.laughTrack if state == 'green' else '#FFFFFF' if state == 'flare' else PAL.onAirRed
    P.beacon.material = K.mat(game, 'plastic', '#5A2A2A') if state == 'off' else \
        K.glow(game, c, 6 if state == 'flare' else 3)


def _skylark_13(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('skylark_13')
    paint = K.mat(game, 'plastic', '#ffffff', {'keepColor': True})
    atl = K.mat(game, 'plastic', '#ffffff', {'map': yardAtlas(), 'keepColor': True})
    foil = K.mat(game, 'brass', '#ffffff', {'map': yardAtlas(), 'keepColor': True, 'rough': 0.35})
    chrome = K.mat(game, 'chrome', '#A8B0BA', {'keepColor': True})
    WHITE = '#F4F1E8'
    cy = 0.0
    # body: octagonal gold-foil drum with a white name band, white caps
    drum = K.lathe([[0, -0.3], [0.3, -0.3], [0.34, -0.22], [0.34, 0.22], [0.3, 0.3], [0, 0.3]],
                   {'seg': 8, 'round': 0.05, 'steps': 1}).clone()
    cellUV(drum, 0, 448, 256, 512)
    g.add(K.m(drum, foil, {'pos': [0, cy, 0], 'rot': [0, math.pi / 8, 0]}))
    band = K.lathe([[0.352, -0.075], [0.352, 0.075]], {'seg': 8}).clone()
    cellUV(band, 256, 448, 512, 512)
    g.add(K.m(band, atl, {'pos': [0, cy, 0], 'rot': [0, math.pi / 8, 0]}))
    g.add(K.m(tinted(K.lathe([[0, 0], [0.26, 0], [0.24, 0.06], [0.12, 0.1], [0, 0.1]],
                             {'seg': 16, 'round': 0.03, 'steps': 1}), WHITE), paint, {'pos': [0, cy + 0.29, 0]}))
    g.add(K.m(tinted(K.lathe([[r, -y] for r, y in [[0, 0], [0.26, 0], [0.24, -0.06], [0.1, -0.09], [0, -0.09]]],
                             {'seg': 16, 'round': 0.03, 'steps': 1}), WHITE), paint,
              {'pos': [0, cy - 0.29, 0], 'rot': [math.pi, 0, 0]}))
    # solar wings on chrome booms
    panels = grp('panels', [0, cy, 0])
    for s in [-1, 1]:
        panels.add(K.m(K.cyl(0.018, 0.018, 0.3, {'bevel': 0.005, 'seg': 8}), chrome,
                       {'pos': [s * 0.32, 0, 0], 'rot': [0, 0, -s * math.pi / 2]}))
        panels.add(K.m(tinted(K.box(0.66, 0.035, 0.34, 0.017), '#C9CED6'), paint, {'pos': [s * 0.96, 0, 0]}))
        cells = cellUV(THREE.PlaneGeometry(0.6, 0.29).rotateX(-math.pi / 2), 256, 320, 512, 448)
        panels.add(K.m(cells, atl, {'pos': [s * 0.96, 0.019, 0]}))
        under = cellUV(THREE.PlaneGeometry(0.6, 0.29).rotateX(math.pi / 2), 256, 320, 512, 448)
        panels.add(K.m(under, atl, {'pos': [s * 0.96, -0.019, 0]}))
    g.add(panels)
    # Earth-facing dish + feed, thrusters
    dishG = K.lathe([[0, 0], [0.12, 0.012], [0.22, 0.05], [0.235, 0.06], [0.225, 0.07], [0.12, 0.03], [0, 0.02]],
                    {'seg': 16, 'round': 0.01, 'steps': 1}).clone()
    dishG.rotateX(math.pi)
    g.add(K.m(tinted(dishG, WHITE), paint, {'pos': [0, cy - 0.46, 0]}))
    g.add(K.m(K.cyl(0.03, 0.035, 0.1, {'bevel': 0.01, 'seg': 8}), chrome, {'pos': [0, cy - 0.46, 0]}))
    for k in range(3):
        g.add(rod([math.cos(k * 2.1) * 0.18, cy - 0.52, math.sin(k * 2.1) * 0.18], [0, cy - 0.66, 0], 0.006, chrome,
                  {'seg': 5}))
    g.add(K.m(tinted(THREE.SphereGeometry(0.025, 8, 6), PAL.channelRed), paint, {'pos': [0, cy - 0.67, 0]}))
    for x, z in [[0.2, 0.2], [-0.2, 0.2], [0.2, -0.2], [-0.2, -0.2]]:
        g.add(K.m(K.lathe([[0.02, 0], [0.045, -0.07], [0.05, -0.075], [0.03, -0.01]], {'seg': 8}), chrome,
                  {'pos': [x, cy - 0.3, z]}))
    # beacon cage + whip antenna on top
    beacon = keep(K.m(THREE.SphereGeometry(0.05, 12, 8), K.glow(game, PAL.onAirRed, 3),
                      {'pos': [0, cy + 0.46, 0], 'name': 'beacon', 'cast': False}))
    beacon.userData.noOcclude = True
    g.add(beacon)
    for k in range(4):
        g.add(rod([math.cos(k * TAU / 4) * 0.06, cy + 0.39, math.sin(k * TAU / 4) * 0.06], [0, cy + 0.53, 0], 0.005,
                  chrome, {'seg': 5}))
    g.add(K.m(THREE.CylinderGeometry(0.004, 0.008, 0.55, 5).translate(0, 0.275, 0), chrome,
              {'pos': [0.15, cy + 0.36, 0.1], 'rot': [0.2, 0, -0.3]}))
    g.add(K.m(THREE.SphereGeometry(0.015, 6, 4), chrome, {'pos': [0.15 + 0.155, cy + 0.36 + 0.505, 0.1 + 0.1]}))

    g.userData.parts = JSObj(beacon=beacon, panels=panels)
    g.userData.colliders = []
    g.userData.lightAnchors = []
    finishRig(game, g, {'finish': {'ao': {'floor': False, 'height': 0}}})
    # the prop's floor is y = 0: lift it so it previews above the ground (the game flies it on its own path)
    for c in list(g.children):
        c.position.y += 0.7
    setSkylarkBeacon(game, g, opts['beacon'] if opts.get('beacon') is not None else 'red')
    return g


registerProp('skylark_13', _skylark_13,
             {'category': 'machines', 'tags': ['uplink', 'sky', 'satellite'], 'size': [2.6, 1.3, 0.6],
              'desc': 'the satellite Skylark-13 (gold drum, solar wings, blinking beacon)'})


# ------------------------------------------------------------------------------------------- hut tubes
# Transmitter-hut window tubes (GDD §2/§13): four big orange-glowing transmitting tubes and the sickly green
# Perpetua-Tube in the middle, on the final-amp chassis (opts.base = false -> just a steel shelf).
def _hut_tubes(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('hut_tubes')
    paint = K.mat(game, 'paint', '#ffffff', {'rough': 0.5})
    atl = K.mat(game, 'paint', '#ffffff', {'map': yardAtlas(), 'rough': 0.5})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    ceramic = K.mat(game, 'ceramic', '#ffffff')

    def clearGlass(c, o):
        return game.mats.toon(c, {'rough': 0.05, 'transparent': True, 'opacity': o, 'rim': 0.28, 'rimColor': '#FFF4E0',
                                  'rimPower': 3, 'env': 0.5, 'depthWrite': False, 'side': THREE.DoubleSide,
                                  'keepColor': True})
    glassO = clearGlass('#FFC890', 0.14)
    glassG = clearGlass('#B8FF8A', 0.18)
    HAMMER, DARK = '#6C8474', '#2E2A36'
    base = opts.get('base') is not False
    topY = 0.95 if base else 0.06
    if base:
        g.add(K.m(tinted(K.box(1.34, 0.9, 0.48, 0.04), HAMMER), paint, {'pos': [0, 0.47, 0]}))
        g.add(K.m(tinted(K.box(1.38, 0.08, 0.5, 0.03), DARK), paint, {'pos': [0, 0.04, 0]}))
        g.add(K.m(cellUV(K.box(0.42, 0.1, 0.012, 0.005).clone(), 0, 128, 256, 192), atl, {'pos': [-0.36, 0.78, -0.245]}))
        for x, cell in [[0.08, [128, 192, 256, 320]], [0.3, [256, 192, 384, 320]], [0.52, [0, 192, 128, 320]]]:
            g.add(K.m(K.tube(ringXY(0.075, 14, 0), 0.011, {'seg': 16, 'radial': 3, 'closed': True}), chrome,
                      {'pos': [x, 0.72, -0.25]}))
            g.add(K.m(disc(0.072, 20, cell), atl, {'pos': [x, 0.72, -0.246]}))
        for i in range(4):
            g.add(K.m(tinted(knobGeo(0.03, 0.035, {'seg': 10, 'flange': 0}), DARK), paint,
                      {'pos': [-0.5 + i * 0.16, 0.52, -0.24]}))
        for i in range(4):
            g.add(K.m(tinted(THREE.BoxGeometry(0.9, 0.018, 0.012), '#4E6356'), paint,
                      {'pos': [0.08, 0.2 + i * 0.05, -0.243]}))
        g.add(K.m(tinted(K.box(1.3, 0.04, 0.46, 0.015), '#8A9A8E'), paint, {'pos': [0, topY - 0.02, 0]}))
    else:
        g.add(K.m(tinted(K.box(1.3, 0.05, 0.36, 0.015), '#8A9A8E'), paint, {'pos': [0, 0.035, 0]}))
    # five tubes: sockets, glass envelopes, anodes, glow cores, top caps
    xs = [-0.5, -0.25, 0, 0.25, 0.5]
    glowO, glowG = [], []
    for i, x in enumerate(xs):
        green = i == 2
        s = 1.22 if green else 1
        g.add(K.m(tinted(K.lathe([[r * s, y] for r, y in [[0, 0], [0.085, 0], [0.09, 0.02], [0.075, 0.05], [0, 0.05]]],
                                 {'seg': 10}), '#F2EEE4'), ceramic, {'pos': [x, topY, 0]}))
        env = [[r * s, y * s] for r, y in [[0.055, 0], [0.062, 0.04], [0.095, 0.12], [0.1, 0.24], [0.088, 0.36],
                                           [0.05, 0.42], [0.03, 0.44], [0, 0.445]]]
        glassMesh = K.m(K.lathe(env, {'seg': 12}), glassG if green else glassO,
                        {'pos': [x, topY + 0.045, 0], 'cast': False})
        glassMesh.userData.noOcclude = True
        g.add(glassMesh)
        g.add(K.m(tinted(K.cyl(0.052 * s, 0.056 * s, 0.22 * s, {'bevel': 0.01, 'seg': 8}), '#3C3A44'), paint,
                  {'pos': [x, topY + 0.09 * s, 0]}))
        g.add(K.m(tinted(THREE.CylinderGeometry(0.066 * s, 0.066 * s, 0.012, 10, 1, True), '#6A6872'), paint,
                  {'pos': [x, topY + 0.305 * s, 0]}))
        core = K.lathe([[r * s, y * s] for r, y in [[0, 0], [0.058, 0], [0.058, 0.035], [0, 0.035]]],
                       {'seg': 10}).clone()
        core.translate(x, topY + 0.31 * s, 0)
        (glowG if green else glowO).append(core)
        g.add(K.m(THREE.CylinderGeometry(0.026 * s, 0.03 * s, 0.035, 8).translate(0, 0.0175, 0), chrome,
                  {'pos': [x, topY + 0.045 + 0.435 * s, 0]}))
        g.add(K.m(THREE.CylinderGeometry(0.004, 0.004, 0.2, 4).translate(0, 0.1, 0), chrome,
                  {'pos': [x, topY + 0.045 + 0.47 * s, 0], 'rot': [0, 0, 0.9 if green else 1.2]}))
    glowOrange = keep(THREE.Mesh(mergeGeos(glowO), K.glow(game, '#FF7A1A', 2.2)))
    glowOrange.name = 'glowOrange'
    glowOrange.userData.noOcclude = True
    glowGreen = keep(THREE.Mesh(mergeGeos(glowG), K.glow(game, PAL.perpetua, 2.8)))
    glowGreen.name = 'glowGreen'
    glowGreen.userData.noOcclude = True
    g.add(glowOrange, glowGreen)
    # Perpetua tag on a string from the green tube's cap
    tag = cellUV(THREE.PlaneGeometry(0.12, 0.16).rotateY(math.pi), 0, 0, 1, 1, 1, 1)
    tagMat = K.mat(game, 'plastic', '#ffffff', {'map': getCard('perpetua_ad'), 'side': THREE.DoubleSide})
    g.add(K.m(tag, tagMat, {'pos': [0.1, topY + 0.34, -0.14], 'rot': [0.1, -0.35, 0.12]}))
    g.add(K.m(K.tube([[0.03, topY + 0.6, -0.02], [0.08, topY + 0.5, -0.1], [0.1, topY + 0.42, -0.14]], 0.0025,
                     {'seg': 6, 'radial': 3}), chrome))
    g.userData.parts = JSObj(glowOrange=glowOrange, glowGreen=glowGreen)
    g.userData.lightAnchors = [
        {'pos': [-0.3, topY + 0.55, -0.8], 'color': '#FF9A40', 'intensity': 1.2, 'distance': 4, 'flicker': 0.15},
        {'pos': [0.1, topY + 0.6, -0.8], 'color': PAL.perpetua, 'intensity': 1.0, 'distance': 3.5, 'flicker': 0.3},
    ]
    g.userData.colliders = [{'min': [-0.7, 0, -0.26], 'max': [0.7, topY + 0.6, 0.26]}]
    finishRig(game, g)
    return g


registerProp('hut_tubes', _hut_tubes,
             {'category': 'machines', 'tags': ['yard', 'hut', 'tubes', 'perpetua'], 'size': [1.4, 1.62, 0.52],
              'desc': 'transmitter-hut tube rack: 4 orange tubes + the green Perpetua-Tube', 'hero': True})

registerScene('uplink_yard', {
    'floor': '#4A4652', 'wall': '#1E2344', 'room': [14, 12], 'wallH': 7, 'hemi': 0.7,
    'items': [
        {'id': 'uplink_dish', 'pos': [0, 2.5], 'rotY': 0, 'opts': {'tilt': 0.3, 'lit': True}},
        {'id': 'uplink_cradle', 'pos': [0, -0.4], 'rotY': 0, 'opts': {'lamps': 1}},
        {'id': 'uplink_crank', 'pos': [2.1, -1.1], 'rotY': -0.3},
        {'id': 'uplink_booth', 'pos': [-3.6, 0.2], 'rotY': math.pi / 2 + 0.3},
        {'id': 'hut_tubes', 'pos': [4.2, 1.8], 'rotY': -0.4},
        {'id': 'skylark_13', 'pos': [-3.4, 3.2, 0.8], 'rotY': 0.6},
    ],
    'cam': {'pos': [2.2, 2.6, -7.2], 'target': [0, 1.8, 1.0], 'fov': 55},
})
