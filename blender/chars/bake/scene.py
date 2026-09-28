"""Loads a character definition and builds its SDF trees (port of tools/bake/scene.mjs)."""
from ..jsutil import O
from ..sdf import createSculptor, compileTree, indexLeaves, Group, _call
from ..rig_build import buildRig, jointFrames
from ..defs import load_def

loadDef = load_def


def buildTree(d, ctx, expr, sculptFn=None):
    sd = createSculptor(joints=ctx.J, materials=d.materials, expr=expr)
    c = O(ctx)
    c.expr = expr
    _call(sculptFn or d.sculpt, sd, c)
    compileTree(sd.root)
    sd.leaves = indexLeaves(sd.root)
    return sd


def buildScene(d):
    R = buildRig(d)
    frames, segments = jointFrames(R)
    ctx = O(J=O(frames), dims=R.rig.dims, spec=R.rig.spec, R=R, segments=segments)
    if d.anchors:
        ctx.A = _call(d.anchors, ctx)
    sd = buildTree(d, ctx, None)
    partSds = {}
    for name, p in (d.parts or {}).items():
        partSds[name] = buildTree(d, ctx, None, p.sculpt)
    ao = Group('ao')
    ao.op = 'add'
    ao.k = 0
    for s in [sd] + list(partSds.values()):
        ao.children.append(_as_add(s.root))
    compileTree(ao)
    return O(d=d, R=R, ctx=ctx, sd=sd, partSds=partSds, aoRoot=ao, segments=segments)


def _as_add(root):
    """{ ...root, op: 'add', k: 0 } — a shallow copy sharing children."""
    g = Group(root.name, root.offset, root.shell)
    g.children = root.children
    g.op = 'add'
    g.k = 0
    g.gk = root.gk
    g.box = root.box
    return g


def exprTree(scene, name):
    return buildTree(scene.d, scene.ctx, name).root
