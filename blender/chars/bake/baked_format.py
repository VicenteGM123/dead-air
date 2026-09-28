"""Reader for the JS baked character container assets/baked/<id>.bin (src/art/bakedFormat.js), used to verify
the Python bake against the JS one. Layout: 'DAC1' | u32 headerBytes | header JSON (utf8, padded to 4) | buffers."""
import json
import struct
import numpy as np

TYPES = {'f32': np.float32, 'u16': np.uint16, 'u32': np.uint32, 'i16': np.int16, 'u8': np.uint8, 'i8': np.int8}


def decodeBaked(data):
    if data[:4] != b'DAC1':
        raise ValueError('bakedFormat: bad magic')
    hb = struct.unpack('<I', data[4:8])[0]
    header = json.loads(data[8:8 + hb].decode('utf-8'))
    base = 8 + hb
    arrays = {}
    for e in header['buffers']:
        T = TYPES[e['type']]
        a = np.frombuffer(data, dtype=T, count=e['byteLength'] // np.dtype(T).itemsize, offset=base + e['offset'])
        if e['itemSize'] > 1:
            a = a.reshape(-1, e['itemSize'])
        arrays[e['name']] = a
    return header, arrays


def load(path):
    with open(path, 'rb') as f:
        return decodeBaked(f.read())


def positions(header, arrays, prefix='', qbox=None):
    q = arrays[prefix + 'pos'].astype(float)
    qb = qbox or header['qbox']
    return np.array(qb[:3]) + q / 65535 * np.array(qb[3:])
