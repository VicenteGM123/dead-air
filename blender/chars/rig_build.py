"""Rig construction for the character pipeline — port of src/art/rigBuild.js + the joint layout of
src/core/rig.js createRig (dims, joint positions; the Animator is runtime code, ported on the Godot side).

    buildRig(def) -> R = O(rig, bones, joints, humanoid, bindPose, skin, def, parents)
    jointFrames(R) -> (frames {name: O(matrix=4x4 bind world, pos=[x,y,z])}, segments {name: O(a, b)})
Humanoids use createRig(def.rig); custom rigs: def.rig = { custom: True, joints: [{name, parent, pos, tail, blend,
gate}], bindPose }. Bind pose: Euler XYZ rotations per joint applied on top of rest (default A-pose arms).
"""
import numpy as np

from . import m4
from .jsutil import O, nz

HUMANOID_JOINTS = ['hips', 'spine', 'chest', 'neck', 'head', 'shoulderL', 'elbowL', 'handL', 'shoulderR', 'elbowR',
                   'handR', 'hipL', 'kneeL', 'footL', 'hipR', 'kneeR', 'footR']

DEFAULT_BIND = {'shoulderL': [0, 0, -0.62], 'shoulderR': [0, 0, 0.62]}

# Joint blend half-width (m) with the parent bone, and gate radius for the parent-side blend (see CHARKIT.md).
HUMANOID_SKIN = {
    'hips': O(blend=0, gate=0.3),
    'spine': O(blend=0.07, gate=0.35),
    'chest': O(blend=0.08, gate=0.35),
    'neck': O(blend=0.035, gate=0.085),
    'head': O(blend=0.03, gate=0.12),
    'shoulderL': O(blend=0.06, gate=0.1), 'shoulderR': O(blend=0.06, gate=0.1),
    'elbowL': O(blend=0.05, gate=0.08), 'elbowR': O(blend=0.05, gate=0.08),
    'handL': O(blend=0.03, gate=0.065), 'handR': O(blend=0.03, gate=0.065),
    'hipL': O(blend=0.07, gate=0.13), 'hipR': O(blend=0.07, gate=0.13),
    'kneeL': O(blend=0.06, gate=0.1), 'kneeR': O(blend=0.06, gate=0.1),
    'footL': O(blend=0.035, gate=0.09), 'footR': O(blend=0.035, gate=0.09),
}


class Joint:
    """Minimal THREE.Object3D stand-in: position + Euler XYZ rotation, parent/children."""

    def __init__(self, name):
        self.name = name
        self.position = [0.0, 0.0, 0.0]
        self.rotation = [0.0, 0.0, 0.0]
        self.parent = None
        self.children = []

    def add(self, *objs):
        for o in objs:
            o.parent = self
            self.children.append(o)

    def local(self):
        return m4.euler_matrix(*self.rotation, 'XYZ', pos=tuple(self.position))

    def world(self):
        m = self.local()
        p = self.parent
        while p is not None:
            m = p.local() @ m
            p = p.parent
        return m


def createRig(spec=None):
    """src/core/rig.js createRig: joint layout + dims (feet at y=0, facing -z)."""
    s = O(height=1.7, headScale=1.0, shoulderW=0.42, hipW=0.26, armLen=0.62, legLen=0.78, torsoLen=0.5)
    s.update(spec or {})
    headH = 0.44 * s.headScale
    neckH, ankle, hipDrop = 0.05, 0.07, 0.03
    k = max(0.5, (s.height - headH - neckH - ankle) / (s.legLen + s.torsoLen))
    leg = s.legLen * k
    torso = s.torsoLen * k
    arm = s.armLen * min(1, k * 1.05)
    dims = O(height=s.height, headH=headH, neckH=neckH, ankle=ankle, torso=torso, leg=leg, hipsY=leg + ankle,
             upperLeg=(leg - hipDrop) * 0.5, lowerLeg=(leg - hipDrop) * 0.5,
             upperArm=arm * 0.48, foreArm=arm * 0.52, shoulderW=s.shoulderW, hipW=s.hipW,
             shoulderY=torso * 0.55 - 0.06)
    j = {n: Joint(n) for n in HUMANOID_JOINTS}
    root = Joint('rig')
    root.add(j['hips'])
    j['hips'].position = [0, dims.hipsY, 0]
    j['hips'].add(j['spine'], j['hipL'], j['hipR'])
    j['spine'].position = [0, 0.02, 0]
    j['spine'].add(j['chest'])
    j['chest'].position = [0, torso * 0.45, 0]
    j['chest'].add(j['neck'], j['shoulderL'], j['shoulderR'])
    j['neck'].position = [0, torso * 0.55 - 0.02, 0]
    j['neck'].add(j['head'])
    j['head'].position = [0, neckH, 0]
    for side in ('L', 'R'):
        sx = -1 if side == 'L' else 1
        sh, el, ha = j['shoulder' + side], j['elbow' + side], j['hand' + side]
        sh.position = [sx * s.shoulderW / 2, dims.shoulderY, 0]
        sh.add(el)
        el.position = [0, -dims.upperArm, 0]
        el.add(ha)
        ha.position = [0, -dims.foreArm, 0]
        hp, kn, ft = j['hip' + side], j['knee' + side], j['foot' + side]
        hp.position = [sx * s.hipW / 2, -hipDrop, 0]
        hp.add(kn)
        kn.position = [0, -dims.upperLeg, 0]
        kn.add(ft)
        ft.position = [0, -dims.lowerLeg, 0]
    return O(root=root, joints=j, dims=dims, spec=s)


def buildRig(d):
    spec = d.get('rig') or {}
    skin = {}
    if not spec.get('custom'):
        rig = createRig(spec)
        bones = list(HUMANOID_JOINTS)
        humanoid = True
        skin.update(HUMANOID_SKIN)
        skin.update(d.get('skin') or {})
    else:
        humanoid = False
        joints = {}
        root = Joint('rig')
        bones = []
        for jd in spec['joints']:
            o = Joint(jd['name'])
            o.position = list(jd.get('pos') or [0, 0, 0])
            (joints[jd['parent']] if jd.get('parent') else root).add(o)
            joints[jd['name']] = o
            bones.append(jd['name'])
            skin[jd['name']] = O(blend=nz(jd.get('blend'), 0.05), gate=nz(jd.get('gate'), 0.1))
        rig = O(root=root, joints=joints, dims=spec.get('dims') or {}, spec=spec)
    bindPose = spec.get('bindPose') or d.get('bindPose') or (DEFAULT_BIND if humanoid else {})
    R = O(rig=rig, bones=bones, joints=rig.joints, humanoid=humanoid, bindPose=bindPose, skin=skin, d=d)
    R.parents = {}
    for n in bones:
        p = rig.joints[n].parent
        R.parents[n] = p.name if (p is not None and p.name in bones) else None
    return R


def applyBindPose(R):
    for n in R.bones:
        R.joints[n].rotation = [0.0, 0.0, 0.0]
    for n, e in R.bindPose.items():
        if n in R.joints:
            R.joints[n].rotation = [e[0], e[1], e[2]]


def resetPose(R):
    for n in R.bones:
        R.joints[n].rotation = [0.0, 0.0, 0.0]


def jointFrames(R):
    """Bind-pose world frames and bone segments [P0, P1] used for skinning."""
    applyBindPose(R)
    out = {}
    for n in R.bones:
        M = R.joints[n].world()
        out[n] = O(matrix=M, pos=[float(M[0, 3]), float(M[1, 3]), float(M[2, 3])])
    seg = {}

    def P(n):
        return np.array(out[n].pos)

    def local(n, t):
        return np.array(m4.apply(out[n].matrix, t))
    if R.humanoid:
        D = R.rig.dims
        hipsP = P('hips')
        seg['hips'] = [hipsP + np.array([0, -0.1, 0]), P('spine')]
        seg['spine'] = [P('spine'), P('chest')]
        seg['chest'] = [P('chest'), P('neck')]
        seg['neck'] = [P('neck'), P('head')]
        seg['head'] = [P('head'), local('head', [0, D.headH * 0.75, 0])]
        for s in ('L', 'R'):
            seg['shoulder' + s] = [P('shoulder' + s), P('elbow' + s)]
            seg['elbow' + s] = [P('elbow' + s), P('hand' + s)]
            seg['hand' + s] = [P('hand' + s), local('hand' + s, [0, -0.12, 0])]
            seg['hip' + s] = [P('hip' + s), P('knee' + s)]
            seg['knee' + s] = [P('knee' + s), P('foot' + s)]
            seg['foot' + s] = [P('foot' + s), local('foot' + s, [0, -0.05, -0.15])]
    else:
        js = R.d['rig']['joints']
        for j in js:
            kids = [c for c in js if c.get('parent') == j['name']]
            if j.get('tail'):
                tail = local(j['name'], j['tail'])
            elif kids:
                tail = P(kids[0]['name'])
            else:
                tail = local(j['name'], [0, 0.1, 0])
            seg[j['name']] = [P(j['name']), tail]
    segments = {n: O(a=[float(v) for v in a], b=[float(v) for v in b]) for n, (a, b) in seg.items()}
    resetPose(R)
    return out, segments


def jointTable(R):
    """{name: {parent, pos (rest offset in the parent frame), bind (Euler XYZ)}} for the Godot runtime."""
    t = {}
    for n in R.bones:
        j = R.joints[n]
        b = R.bindPose.get(n)
        t[n] = {'parent': R.parents[n], 'pos': [float(v) for v in j.position],
                'bind': [float(v) for v in b] if b else [0.0, 0.0, 0.0]}
    return t


def bindWorld(R):
    applyBindPose(R)
    w = {n: R.joints[n].world() for n in R.bones}
    resetPose(R)
    return w
