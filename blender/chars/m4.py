"""three.js Matrix4 / Quaternion / Euler helpers (numpy, float64, column-vector convention: p' = M @ [p, 1]).

Matrices are 4x4 numpy arrays in three.js coordinates. Everything mirrors THREE's formulas so sculpt frames match.
"""
import math
import numpy as np


def identity():
    return np.eye(4)


def quat_from_euler(x, y, z, order='XYZ'):
    """THREE.Quaternion.setFromEuler -> (x, y, z, w)."""
    c1, c2, c3 = math.cos(x / 2), math.cos(y / 2), math.cos(z / 2)
    s1, s2, s3 = math.sin(x / 2), math.sin(y / 2), math.sin(z / 2)
    if order == 'XYZ':
        return (s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3)
    if order == 'YXZ':
        return (s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 - s1 * s2 * c3, c1 * c2 * c3 + s1 * s2 * s3)
    if order == 'ZXY':
        return (s1 * c2 * c3 - c1 * s2 * s3, c1 * s2 * c3 + s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3)
    if order == 'ZYX':
        return (s1 * c2 * c3 - c1 * s2 * s3, c1 * s2 * c3 + s1 * c2 * s3, c1 * c2 * s3 - s1 * s2 * c3, c1 * c2 * c3 + s1 * s2 * s3)
    if order == 'YZX':
        return (s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 + s1 * c2 * s3, c1 * c2 * s3 - s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3)
    if order == 'XZY':
        return (s1 * c2 * c3 - c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 + s1 * s2 * s3)
    raise ValueError(order)


def compose(pos=(0, 0, 0), quat=(0, 0, 0, 1), scale=(1, 1, 1)):
    """THREE.Matrix4.compose."""
    x, y, z, w = quat
    x2, y2, z2 = x + x, y + y, z + z
    xx, xy, xz = x * x2, x * y2, x * z2
    yy, yz, zz = y * y2, y * z2, z * z2
    wx, wy, wz = w * x2, w * y2, w * z2
    sx, sy, sz = scale
    m = np.eye(4)
    m[0, 0] = (1 - (yy + zz)) * sx
    m[1, 0] = (xy + wz) * sx
    m[2, 0] = (xz - wy) * sx
    m[0, 1] = (xy - wz) * sy
    m[1, 1] = (1 - (xx + zz)) * sy
    m[2, 1] = (yz + wx) * sy
    m[0, 2] = (xz + wy) * sz
    m[1, 2] = (yz - wx) * sz
    m[2, 2] = (1 - (xx + yy)) * sz
    m[0, 3], m[1, 3], m[2, 3] = pos
    return m


def euler_matrix(x, y, z, order='XYZ', pos=(0, 0, 0), scale=(1, 1, 1)):
    return compose(pos, quat_from_euler(x, y, z, order), scale)


def scale_m(sx, sy, sz):
    m = np.eye(4)
    m[0, 0], m[1, 1], m[2, 2] = sx, sy, sz
    return m


def translation(x, y, z):
    m = np.eye(4)
    m[0, 3], m[1, 3], m[2, 3] = x, y, z
    return m


def quat_from_unit_vectors(a, b):
    """THREE.Quaternion.setFromUnitVectors(vFrom, vTo)."""
    EPS = 1e-8
    r = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + 1
    if r < EPS:
        r = 0
        if abs(a[0]) > abs(a[2]):
            q = (-a[1], a[0], 0.0, r)
        else:
            q = (0.0, -a[2], a[1], r)
    else:
        q = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0], r)
    l = math.sqrt(q[0] ** 2 + q[1] ** 2 + q[2] ** 2 + q[3] ** 2)
    return tuple(c / l for c in q) if l else (0, 0, 0, 1)


def quat_rotate(q, v):
    """THREE.Vector3.applyQuaternion."""
    vx, vy, vz = v
    qx, qy, qz, qw = q
    tx = 2 * (qy * vz - qz * vy)
    ty = 2 * (qz * vx - qx * vz)
    tz = 2 * (qx * vy - qy * vx)
    return [vx + qw * tx + qy * tz - qz * ty, vy + qw * ty + qz * tx - qx * tz, vz + qw * tz + qx * ty - qy * tx]


def quat_from_axis_angle(axis, angle):
    h = angle / 2
    s = math.sin(h)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(h))


def apply(m, p):
    """Vector3.applyMatrix4 for one point (list) -> list (with the projective divide like THREE)."""
    x, y, z = p
    w = 1 / (m[3, 0] * x + m[3, 1] * y + m[3, 2] * z + m[3, 3])
    return [(m[0, 0] * x + m[0, 1] * y + m[0, 2] * z + m[0, 3]) * w,
            (m[1, 0] * x + m[1, 1] * y + m[1, 2] * z + m[1, 3]) * w,
            (m[2, 0] * x + m[2, 1] * y + m[2, 2] * z + m[2, 3]) * w]


def apply3(m, v):
    """Vector3.applyMatrix3 with the upper 3x3 of m."""
    return [m[0, 0] * v[0] + m[0, 1] * v[1] + m[0, 2] * v[2],
            m[1, 0] * v[0] + m[1, 1] * v[1] + m[1, 2] * v[2],
            m[2, 0] * v[0] + m[2, 1] * v[1] + m[2, 2] * v[2]]


def apply_pts(m, P):
    """Apply an affine 4x4 to an (N,3) array."""
    return P @ m[:3, :3].T + m[:3, 3]


def inv(m):
    return np.linalg.inv(m)


def decompose(m):
    """THREE.Matrix4.decompose -> (pos, quat(x,y,z,w), scale)."""
    sx = np.linalg.norm(m[:3, 0])
    sy = np.linalg.norm(m[:3, 1])
    sz = np.linalg.norm(m[:3, 2])
    if np.linalg.det(m[:3, :3]) < 0:
        sx = -sx
    R = m[:3, :3] / np.array([sx, sy, sz])
    q = quat_from_rotmat(R)
    return [float(m[0, 3]), float(m[1, 3]), float(m[2, 3])], q, [float(sx), float(sy), float(sz)]


def quat_from_rotmat(R):
    """THREE.Quaternion.setFromRotationMatrix."""
    m11, m12, m13 = R[0]
    m21, m22, m23 = R[1]
    m31, m32, m33 = R[2]
    tr = m11 + m22 + m33
    if tr > 0:
        s = 0.5 / math.sqrt(tr + 1.0)
        return ((m32 - m23) * s, (m13 - m31) * s, (m21 - m12) * s, 0.25 / s)
    if m11 > m22 and m11 > m33:
        s = 2.0 * math.sqrt(1.0 + m11 - m22 - m33)
        return (0.25 * s, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s)
    if m22 > m33:
        s = 2.0 * math.sqrt(1.0 + m22 - m11 - m33)
        return ((m12 + m21) / s, 0.25 * s, (m23 + m32) / s, (m13 - m31) / s)
    s = 2.0 * math.sqrt(1.0 + m33 - m11 - m22)
    return ((m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s)


def euler_from_rotmat(R, order='XYZ'):
    """THREE.Euler.setFromRotationMatrix (XYZ only, what we need)."""
    m11, m12, m13 = R[0]
    m21, m22, m23 = R[1]
    m31, m32, m33 = R[2]
    y = math.asin(max(-1, min(1, m13)))
    if abs(m13) < 0.9999999:
        x = math.atan2(-m23, m33)
        z = math.atan2(-m12, m11)
    else:
        x = math.atan2(m32, m22)
        z = 0
    return [x, y, z]


def look_at_matrix(eye, target, up=(0, 1, 0)):
    """THREE.Matrix4.lookAt(eye, target, up) rotation (Object3D.lookAt for non-cameras uses (target, position))."""
    ex, ey, ez = eye
    tx, ty, tz = target
    z = np.array([ex - tx, ey - ty, ez - tz], float)
    if np.dot(z, z) == 0:
        z[2] = 1
    z /= np.linalg.norm(z)
    upv = np.array(up, float)
    x = np.cross(upv, z)
    if np.dot(x, x) == 0:
        if abs(upv[2]) == 1:
            z[0] += 0.0001
        else:
            z[2] += 0.0001
        z /= np.linalg.norm(z)
        x = np.cross(upv, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    R = np.eye(3)
    R[:, 0], R[:, 1], R[:, 2] = x, y, z
    return R
