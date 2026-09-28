"""Character baker (port of tools/bake/bake.mjs): SDF sculpt (blender/chars/defs/<id>.py) -> smooth skinned mesh.

Pipeline (docs/CHARKIT.md): sculpt -> block-sparse surface nets (+Newton projection) -> attribute sampling -> crisp
material/pattern borders (bisection cuts) -> pattern coords -> skin weights (joint blend + diffusion) -> seam-
preserving quadric simplification -> SDF normals, AO, cavity -> morph targets -> rigid parts -> stitches.
Returns the same data as the JS .bin (header + per-vertex arrays), consumed by chars/build.py (GLB export).
"""
import math
import time
import numpy as np

from ..jsutil import O, jsround
from ..sdf import makeSampler, FullEvaluator, linear_to_srgb, srgb_to_linear
from .scene import buildScene, buildTree
from .mesher import surfaceNets
from .attrib import sampleMesh, cutBorders, patternCoords
from .skin import computeSkin
from .simplify import simplify
from .finish import makeRegionTrees, shadeVertices, triWeights, morphTarget, projectStitches, stitchChunks

VERSION = 4


def _toSRGB(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def _lin(c8):
    c = c8 / 255.0
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def _jr(x):
    return np.floor(np.asarray(x, float) + 0.5)


def bakeTree(sd, d, o):
    """Bake one SDF tree into a compact mesh. o.skin: O(R, segments) or None (rigid part)."""
    log = o.log
    t0 = time.time()
    root = sd.root
    voxel = o.voxel
    mesh = surfaceNets(root, voxel, root.box, log=log)
    ms = mesh.stats
    log('  surface nets: %d verts, %d tris, %d blocks, %.2fM evals, %d ms (plan %d, blocks %d, lazy %d)' % (
        ms.verts, ms.tris, ms.cand, ms.evals / 1e6, ms.ms, ms.candMs, ms.blockMs, ms.lazy))
    sampler = makeSampler(d.materials)
    S = O(sampler=sampler, treeAt=mesh.treeAt, voxel=voxel, tree=root)
    t = time.time()
    V, I0 = sampleMesh(mesh, S)
    tS = time.time() - t
    I, ncut = cutBorders(V, I0, S)
    pc = patternCoords(V, I, sd.frames, d.materials)
    log('  attributes: %d verts, %d border cuts, %d seam wraps, %d ms (sample %d)' % (V.n, ncut, pc.wraps, (time.time() - t) * 1000, tS * 1000))
    t = time.time()
    skin = None
    if o.skin:
        skin = computeSkin(V, I, o.skin.R, o.skin.segments, O(smooth=(d.bake or {}).get('skinSmooth', 10)))
        log('  skin: %d welded verts, %d ms' % (skin.welded, (time.time() - t) * 1000))
    # Simplify
    t = time.time()
    n0 = V.n
    attrs = np.concatenate([V.nrm, V.col], 1)
    target = min(len(I) * 3, int(math.floor(o.tris)) * 3)
    w = (d.bake or {}).get('simplifyWeights') or [0.35, 0.35, 0.35, 0.6, 0.6, 0.6]
    simp, err = simplify(I, V.pos, attrs, w, target, o.error if o.error is not None else 0.05, log=None)
    keep, index = np.unique(simp.reshape(-1), return_inverse=True)
    # JS order: vertices in first-use order of the simplified index buffer
    flat = simp.reshape(-1)
    _, firstUse = np.unique(flat, return_index=True)
    orderKeep = np.argsort(firstUse, kind='stable')
    keep = keep[orderKeep]
    remap = np.full(n0, -1, np.int64)
    remap[keep] = np.arange(len(keep))
    index = remap[flat].reshape(-1, 3)
    n = len(keep)
    log('  simplify: %d -> %d tris (err %.4f), %d verts, %d ms' % (len(I), len(index), err, n, (time.time() - t) * 1000))
    # Final shading data
    t = time.time()
    pos = V.pos[keep].astype(np.float32).astype(float)
    B = d.bake or {}
    rt = o.aoTrees
    sh = shadeVertices(pos, rt, O(aoStrength=B.get('aoStrength', 1), aoReach=B.get('aoReach', 0.16),
                                 cavScale=B.get('cavScale', 0.005), cavGain=B.get('cavGain', 0.008)))
    frameIds = V.frame[keep]
    pw = triWeights(sh.nrm, frameIds, sd.frames)
    log('  shade (normals/AO/cavity): %d ms' % ((time.time() - t) * 1000))
    col = _jr(np.clip(_toSRGB(V.col[keep]), 0, 1) * 255).astype(np.uint8)
    pco = V.pco[keep].astype(np.float32)
    nrm8 = _jr(sh.nrm * 127).astype(np.int8)
    flow = np.zeros((n, 4), np.int8)
    flow[:, :3] = _jr(V.flow[keep] * 127).astype(np.int8)
    aux = np.zeros((n, 4), np.uint8)
    aux[:, 0] = _jr(sh.ao * 255).astype(np.uint8)
    aux[:, 1] = _jr(128 + sh.cav * 127).astype(np.uint8)
    aux[:, 2] = np.maximum(0, V.mat[keep]).astype(np.uint8)
    aux[:, 3] = V.pmode[keep].astype(np.uint8)
    skinIndex = skinWeight = None
    if skin is not None:
        skinIndex = skin.skinIndex[keep]
        skinWeight = skin.skinWeight[keep]
    mn = pos.min(0)
    mx = pos.max(0)
    sc = np.maximum(1e-6, mx - mn)
    qpos = _jr((pos - mn) / sc * 65535).astype(np.uint16)
    return O(n=n, index=index, pos=pos, nrm=sh.nrm, qpos=qpos, qbox=[*map(float, mn), *map(float, sc)], nrm8=nrm8,
             col=col, aux=aux, pco=pco, pw=pw, flow=flow, skinIndex=skinIndex, skinWeight=skinWeight,
             stats=O(tris=len(index), verts=n, rawTris=len(I), ms=int((time.time() - t0) * 1000)))


def bakeChar(d, log=print, voxel=None, tris=None, quick=False):
    """Bake one character definition. Returns O(header, body, parts{name: mesh}, morphs{name: O(ids,dp,dn,dc)})."""
    T0 = time.time()
    B = d.bake or {}
    voxel = voxel or (B.get('voxel', 0.005) * (1.6 if quick else 1))
    tris = tris or B.get('tris', 20000)
    log('%s: baking (voxel %.1f mm, budget %d tris)' % (d.id, voxel * 1000, tris))
    scene = buildScene(d)
    log('  scene: %d ms' % ((time.time() - T0) * 1000))
    R, sd, partSds, segments = scene.R, scene.sd, scene.partSds, scene.segments
    aoTrees = makeRegionTrees(scene.aoRoot, 0.08, B.get('aoReach', 0.16))
    body = bakeTree(sd, d, O(voxel=voxel, tris=tris, log=log, skin=O(R=R, segments=segments), aoTrees=aoTrees))
    # Morph targets (expressions): vertices mostly bound to the morph bone.
    morphs = []
    morphData = {}
    boneIdx = R.bones.index(d.morphBone or 'head') if (d.morphBone or 'head') in R.bones else -1
    if d.expressions and boneIdx >= 0:
        wsum = np.zeros(body.n)
        for k in range(4):
            wsum += np.where(body.skinIndex[:, k] == boneIdx, body.skinWeight[:, k].astype(float), 0)
        mask = wsum > 128
        lin = _lin(body.col.astype(float))
        sampler = makeSampler(d.materials)
        bt = makeRegionTrees(sd.root, 0.08, 0.06)
        for ex in d.expressions:
            t = time.time()
            vt = buildTree(d, scene.ctx, ex).root
            rt = makeRegionTrees(vt, 0.08, 0.06)
            mt = morphTarget(body.pos, body.nrm, rt, mask, B.get('morphMax', 0.03), bt, lin, sampler)
            dp = _jr(mt.dp * 20000).astype(np.int16)
            dn = np.clip(_jr(mt.dn * 63), -127, 127).astype(np.int8)
            dc = np.clip(_jr(mt.dc * 32767), -32767, 32767).astype(np.int16)
            nc = int((mt.dc != 0).any(1).sum())
            morphData[ex] = O(ids=mt.ids, dp=dp, dn=dn, dc=dc if nc else None)
            morphs.append(ex)
            log("  morph '%s': %d verts (%d recolored), %d ms" % (ex, len(mt.ids), nc, (time.time() - t) * 1000))
    stitches = projectStitches(sd.stitches, FullEvaluator(sd.root))
    parts = {}
    partMeshes = {}
    for name, p in (d.parts or {}).items():
        log(" part '%s':" % name)
        m = bakeTree(partSds[name], d, O(voxel=p.voxel or voxel * 0.8, tris=p.tris or 600, log=log, skin=None, aoTrees=aoTrees))
        partMeshes[name] = m
        c = [m.qbox[k] + m.qbox[k + 3] / 2 for k in range(3)]
        parts[name] = O(bone=p.bone or 'head', qbox=m.qbox, pivot=p.pivot or c, tris=m.stats.tris)
    header = O(
        id=d.id, version=VERSION, kind=d.kind or 'hero', bones=R.bones, parents=R.parents, bindPose=R.bindPose,
        rig=R.rig.spec if R.humanoid else d.rig, humanoid=R.humanoid,
        materials=d.materials, matNames=list(d.materials.keys()), qbox=body.qbox, morphs=morphs, parts=parts,
        stitches=[[*s.a, *s.b, s.t0, s.width, s.dash, s.duty, s.color, s.mats] for s in stitches],
        stitchChunks=stitchChunks(stitches),
        stats=O(tris=body.stats.tris + sum(p.tris for p in parts.values()), bodyTris=body.stats.tris, verts=body.n,
                rawTris=body.stats.rawTris, voxel=voxel, bakeMs=int((time.time() - T0) * 1000), stitchSegs=len(stitches)),
    )
    log('%s: done in %.1f s -> %d tris (%d verts)' % (d.id, time.time() - T0, header.stats.tris, body.n))
    return O(header=header, body=body, parts=partMeshes, morphs=morphData, scene=scene)
