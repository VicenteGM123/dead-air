"""Secondhand Stars · elenco (cuadros de 64x96, estilo HD-2D del Caldero Nocturno).

Usa el kit de personajes del Caldero (c64core / c64body / c64parts / c64hair / c64acc / c64hat / chars64) sin
cambiarlo: aquí se agregan especies, cabezas y piezas nuevas (alienígenas de un puerto del desierto, herramientas,
visor de soldar, poncho, cuatro brazos...) y dos robots dibujados a mano sobre el mismo lienzo (Kettle y Clatter).

Uso (desde cualquier carpeta):
    python3 ss_chars.py [ids...] [--out DIR] [--sheet hoja.png]
      -> DIR/chars/<id>_idle.png (2 cuadros de 64x96) y <id>_walk.png (4 cuadros), DIR/props/tortoise.png
Todos miran a la derecha, pies en la fila 91 (como actor.gd espera).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math
import numpy as np
from PIL import Image
from c64core import *
from c64core import _norm
from c64body import *
from c64body import _head
from c64parts import *
from c64hair import *
from c64acc import *
from c64hat import *
import chars64
from chars64 import make_pal, frames, draw

from ss_parts import *


# ================================================================== elenco
SS = {}

# ---------------- Nell (jugadora): mecánica joven, mono verde azulado gastado, pañuelo ámbar, antiparras, llave
SS['nell'] = dict(
    name='Nell', species='human_f', body=dict(h=58), skin='#e8b48c', hc='#6e3426', eyes='#3f6a5a', stance='easy',
    accent=('suit',), turn=0.5, stance_mod=dict(lean=0.5),
    face=dict(eye='std', mouth='small', blush=True), blush_col='#e09078',
    hair=dict(kind='short', bangs='swept', locks=1, lock=14.0, volume=1.3),
    back=[(high_ponytail, dict(tie='scarf', length=14.0, width=2.8))],
    top=dict(kind='shirt', mat='suit', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='suit'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.4),
    over=[(tool_belt, dict(mat='belt', pouch_mat='pouch')), (scarf, dict(mat='scarf', tail=False)),
          (patch, dict(mat='patch'))],
    head=[(goggles_up, dict(mat='brass', lens='lens'))],
    arms={'n': 'front', 'f': 'hip'}, near=[(wrench, dict(mat='steel'))], free_walk=('f',),
    mats={'suit': '#47908a', 'pants': '#c4a676', 'boots': ('#6e4a32', 'leather'), 'belt': ('#6a4630', 'leather'), 'pouch': ('#8a6040', 'leather'),
          'scarf': '#d6923a', 'patch': '#e0b04a', 'handle': ('#c8402e', 'gem'), 'brass': ('#c99d48', 'metal'),
          'lens': ('#6ab8c0', 'gem'), 'steel': ('#a4a8b4', 'metal'), 'strap': ('#4a3428', 'leather')},
)

# ---------------- Rook Varga: piloto curtido, chaqueta de vuelo con cuello de borrego, canas, llaves de la nave
SS['rook'] = dict(
    name='Rook Varga', species='human_m', body=dict(h=62), skin='#c48a62', hc='#8c8680', hair_kind='hair', eyes='#4a5a6a',
    ears='human', stance='easy', turn=0.5, stance_mod=dict(lean=0.5),
    face=dict(eye='stern', mouth='flat', brow='thick', blush=False),
    hair=dict(kind='short', bangs='swept', locks=0, volume=1.0, side_len=10.6),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='long', mat='jacket', cuff='jacket2'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(belt, dict(mat='belt', buckle='steel')), (bomber, dict(mat='jacket', rib='jacket2')),
          (scarf, dict(mat='scarf', tail=True)), (flight_collar, dict(mat='shearling'))],
    head=[(beard, dict(kind='stubble', mat='beard'))],
    arms={'n': 'hand_out', 'f': 'hip'}, near=[(keyring, dict(mat='brass', tag='keytag'))], free_walk=('n',),
    beard_col='#9a948c',
    mats={'jacket': ('#7a4c32', 'leather'), 'jacket2': ('#5e3a28', 'leather'), 'shirt': '#6a6e58', 'pants': '#5a5a4e',
          'boots': ('#3e2e26', 'leather'), 'belt': ('#3a2a22', 'leather'), 'shearling': ('#e6d8bc', 'white'),
          'keytag': ('#d05a3a', 'gem'), 'brass': ('#c99d48', 'metal'), 'steel': ('#a4a8b4', 'metal'),
          'scarf': '#b4482e'},
)

# ---------------- Mags: vendedora de repuestos, corpulenta, visor de soldar levantado, delantal de cuero, brazos cruzados
SS['mags'] = dict(
    name='Mags', species='human_f', body=dict(h=58, sw=15.5, ww=13.5, hw=13.5, leg=17, ua=6.5, fa=6.2, ar=2.1, tr=2.3, sr=2.0,
                                              foot=7, hipx=2.8, chest=1),
    skin='#a26a48', hc='#2e2424', eyes='#5a3a2a', stance='wide', turn=0.45,
    face=dict(eye='man', mouth='flat', brow='thick', blush=False),
    hair=dict(kind='short', bangs='short', locks=0, volume=0.9, side_len=10.0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='round'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron2, dict(mat='apron', width=1.2, y_hem='thigh', trim='apron_t', pockets=True))],
    head=[(visor_up, dict(mat='visor', glass='vglass'))],
    arms={'n': 'cross', 'f': 'cross'}, far_front=True, gloves='glove',
    accent=('visor',),
    mats={'shirt': '#b8583a', 'pants': '#4a4650', 'boots': ('#3a2c24', 'leather'), 'apron': ('#7a5236', 'leather'),
          'apron_t': ('#5a3a28', 'leather'),
          'visor': ('#d29a3a', 'metal'), 'vframe': ('#4a4448', 'metal'), 'vglass': ('#264a4c', 'gem'),
          'glove': ('#c8a070', 'leather'), 'steel': ('#a4a8b4', 'metal'), 'strap': ('#3a2c26', 'leather')},
)

# ---------------- Gorrum: comerciante Hornback enorme, cuernos, hocico, poncho polvoriento, brazos cruzados (terco)
SS['gorrum'] = dict(
    name='Gorrum', species='hornback', skin='#7e8a9a', hc='#3a3640', eyes='#e8a840', stance='wide', turn=0.4,
    face=dict(eye='deep', mouth=None, blush=False, nose=False),
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0),
    sleeves=dict(kind='rolled', mat='poncho'),
    legs=dict(kind='baggy', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.45, cuff='wrap'),
    back=[(back_horns, dict(mat='horn'))],
    over=[(poncho, dict(mat='poncho', stripe='stripe', stripe2='stripe2', fringe='fringe'))],
    head=[(hornback_face, dict(horn='horn', muzzle='muzzle'))],
    arms={'n': 'cross', 'f': 'cross'}, far_front=True,
    mats={'shirt': '#4a3a34', 'poncho': '#c49a5a', 'stripe': '#a8442e', 'stripe2': ('#e8dcc0', 'white'),
          'fringe': '#9a7444', 'pants': '#5a4a3e', 'boots': ('#4a3a2e', 'leather'), 'wrap': '#b8a888',
          'horn': ('#e2d4b2', 'white'), 'muzzle': ('#9aa4b0', 'skin'),
          'gold': ('#d8a840', 'metal')},
)

# ---------------- Zib: mensajero Quill, flaco, cuatro brazos (los de arriba cruzados, los de abajo en la cintura:
# apurado), cresta de púas, antiparras ámbar, chaleco y bandolera
SS['zib'] = dict(
    name='Zib', species='quill', skin='#9cb48c', hc='#3a3640', eyes='#e8a030', stance='step', turn=0.5,
    face=dict(eye='none', mouth='small', blush=False, nose=False), mouth_col='#6a7a5a',
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='shirt', mat='vest', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='long', mat='vest', cuff='vest2'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.75),
    back2=[(lower_arm_far, {})],
    over=[(belt, dict(mat='belt', buckle='brass', h=1)), (strap_bag, dict(mat='bag', strap='strap2', flap='bag2')),
          (scarf, dict(mat='scarf', tail=True))],
    head=[(quill_crest, dict(mats=('quill1', 'quill2'), tip='quill2')), (goggles_eyes, dict(mat='brass', lens='glens'))],
    front=[(lower_arm_near, {})],
    arms={'n': 'cross', 'f': 'cross'}, far_front=True,
    mats={'vest': '#45487e', 'vest2': '#2e3058', 'pants': '#5a4a3a', 'boots': ('#4a3a30', 'leather'), 'belt': ('#5a4030', 'leather'),
          'bag': ('#8a5a3a', 'leather'), 'bag2': ('#6a4430', 'leather'), 'strap2': ('#4a3428', 'leather'),
          'scarf': '#d8a040', 'quill1': '#e0704a', 'quill2': '#d8a040', 'quilltip': ('#f0e2c4', 'white'),
          'brass': ('#c99d48', 'metal'), 'glens': ('#f0a838', 'gem'), 'strap': ('#3a2c26', 'leather'),
          'parcel': '#c8a46a', 'string': ('#e8dcc0', 'flat'), 'label': ('#e8dcc0', 'white')},
)

# ---------------- Mother Oona: Glimmerfolk, cabeza de medusa translúcida con pensamientos que brillan, túnica elegante
SS['oona'] = dict(
    name='Mother Oona', species='glimmer', skin='#b2a4d8', hc='#3a3640', eyes='#3a3060', stance='prim', turn=0.45,
    face=dict(eye='none', mouth=None, nose=False, blush=False),
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='dress', mat='robe', length='floor', flare=0.55, folds=3, trim='trim', neck='high', neck_mat='collar'),
    sleeves=dict(kind='wide', mat='robe', cuff='trim'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    over=[(stole, dict(mat='stole', trim='trim'))],
    head=[(jelly_dome, dict(mat='jelly', core='jcore', glow=('glow', 'glow2'), rim='jrim'))],
    arms={'n': 'clasp', 'f': 'clasp'}, far_front=True,
    accent=('jelly',),
    mats={'robe': '#5c3e70', 'trim': ('#d4aa52', 'metal'), 'collar': ('#e8dcc0', 'white'), 'stole': ('#e6dcc2', 'white'),
          'shoes': ('#4a3a40', 'leather'), 'jelly': ('#a4b2ee', 'gem'), 'jcore': ('#7c66c4', 'gem'), 'jrim': ('#8a8ad8', 'gem'),
          'glow': ('#ffd66a', 'flat'), 'glow2': ('#ffa0c8', 'flat'), 'eyed': ('#2c2456', 'flat')},
)

# ---------------- Pipip: minero Burrower chiquito (topo), casco con lámpara, antiparras enormes, peto naranja, tímido
SS['pipip'] = dict(
    name='Pipip', species='burrower', skin='#b09078', hc='#3a3640', eyes='#2a2a30', stance='prim', turn=0.45,
    tex={'skin': 'fur'},
    face=dict(eye='none', mouth=None, nose=False, blush=False),
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0),
    sleeves=dict(kind='long', mat='shirt'),
    legs=dict(kind='pants', mat='overall'), feet=dict(kind='boots', mat='boots', h=0.5),
    over=[(apron2, dict(mat='overall', width=1.0, y_hem=None, bib=True, pockets=False))],
    head=[(mole_snout, dict(nose='nose', whisk='whisker')), (big_goggles, dict(mat='brass', lens='glens')),
          (hard_hat, dict(mat='hat', lamp='lamp', glow='glow'))],
    arms={'n': 'waist', 'f': 'chest'}, far_front=True, near=[(coin_pouch, dict(mat='pouch2'))], free_walk=('n', 'f'),
    mats={'shirt': '#cbb68a', 'overall': '#d8702e', 'boots': ('#4a3a30', 'leather'), 'nose': ('#e89aa0', 'skin'),
          'whisker': ('#3a3034', 'flat'), 'brass': ('#c99d48', 'metal'), 'glens': ('#2e5a64', 'gem'),
          'strap': ('#3a2c26', 'leather'), 'hat': ('#e0b040', 'metal'), 'lamp': ('#8a8a90', 'metal'),
          'glow': ('#fff0b0', 'flat'), 'pouch2': ('#8a6a4a', 'leather'), 'string': ('#d8c8a0', 'flat')},
)

# ---------------- Raker: chatarrero Dune Raker (salamandra sonriente, cara descubierta), sombrero ancho, delantal de
# herramientas y una mochila enorme de chatarra; saluda con la mano
SS['raker'] = dict(
    name='Raker', species='raker', skin='#e8a07a', hc='#3a3640', eyes='#2a2024', stance='easy', turn=0.45,
    face=dict(eye='bead', mouth=None, nose=False, blush=False),
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='round'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='bare'),
    back=[(lizard_tail, dict(mat='skin', spot='spot')), (junk_pack, {})],
    over=[(tool_apron, dict(mat='apron', tool='steel', handle='handle')), (scarf, dict(mat='kerchief', tail=False))],
    head=[(axolotl_face, dict(gill='gill', spot='spot', belly='belly')),
          (straw_hat, dict(mat='straw', band='band', brim=15.0, h=5.0))],
    arms={'n': 'hip', 'f': 'hand_out'}, far_front=True, far=[(pod_hand, {})],
    mats={'shirt': '#5c7c94', 'pants': '#8a7a5a', 'apron': ('#7a5236', 'leather'), 'kerchief': '#3e8a86',
          'gill': '#ec5f7c', 'podshell': ('#8aa0a4', 'metal'), 'podband': '#c0603a', 'podlight': ('#ffd36a', 'flat'), 'spot': '#a8603e', 'belly': ('#f0d0a0', 'skin'), 'straw': '#d0aa62', 'band': '#a8442e',
          'packwood': '#8a6040', 'crate': '#b08048', 'hose': '#2e4a4a', 'dish': ('#c0c4c8', 'metal'),
          'pipe': ('#a86a44', 'metal'), 'gear': ('#c07a3a', 'metal'), 'tarp': '#c8b890', 'tarp2': '#a8442e',
          'steel': ('#a4a8b4', 'metal'), 'handle': ('#c8402e', 'gem')},
)

ORDER = ['nell', 'kettle', 'gorrum', 'zib', 'oona', 'pipip', 'rook', 'clatter', 'raker', 'mags']
TITLES = {
    'nell': ('Nell', 'the player · mechanic'), 'kettle': ('Kettle', 'sidekick bot'),
    'gorrum': ('Gorrum', 'Hornback trader'), 'zib': ('Zib', 'Quill courier'), 'oona': ('Mother Oona', 'Glimmerfolk'),
    'pipip': ('Pipip', 'Burrower miner'), 'rook': ('Rook Varga', 'pilot'), 'clatter': ('Clatter', 'old service bot'),
    'raker': ('Raker', 'Dune Raker scavenger'), 'mags': ('Mags', 'parts seller'),
}

BOTS = {}   # id -> función que devuelve (idle[2], walk[4]) (se llenan en ss_bots)

# paleta de puerto al sol: las telas se apagan menos que en el Caldero (que es de noche): saturación x0.74, valor x0.92
for _sp in SS.values():
    _sp.setdefault('mute_s', 0.74)
    _sp.setdefault('mute_v', 0.92)


def build_one(cid):
    if cid in BOTS:
        return BOTS[cid]()
    return frames(SS[cid])


def build(ids, out):
    os.makedirs(os.path.join(out, 'chars'), exist_ok=True)
    res = {}
    for cid in ids:
        idle, walk = build_one(cid)
        Image.fromarray(np.concatenate(idle, axis=1), 'RGBA').save(os.path.join(out, 'chars', f'{cid}_idle.png'))
        Image.fromarray(np.concatenate(walk, axis=1), 'RGBA').save(os.path.join(out, 'chars', f'{cid}_walk.png'))
        res[cid] = (idle, walk)
    return res


def cast_sheet(res, path, scale=3, walkers=None, title='Secondhand Stars · cast (64x96 frames, x3) · idle 1-2, walk 1-4'):
    """Hoja del elenco: por personaje una fila con los 2 cuadros quietos y los 4 de caminar a x3, más el cuadro a
    tamaño de juego (x1) sobre un fondo de arena y uno de taller."""
    from PIL import ImageDraw, ImageFont
    fdir = '/home/user/dead-air/caldero/game/assets/fonts'
    f_name = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Bold.ttf'), 22)
    f_small = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Medium.ttf'), 16)
    f_title = ImageFont.truetype(os.path.join(fdir, 'AlegreyaSC-Bold.ttf'), 30)
    ids = [i for i in ORDER if i in res] + [i for i in res if i not in ORDER]
    cw, chh = 64 * scale, 96 * scale
    rowh = chh + 10
    left = 190
    W = left + 6 * (cw + 4) + 140
    Hh = 56 + len(ids) * rowh + 10
    im = Image.new('RGBA', (W, Hh), (46, 38, 34, 255))
    d = ImageDraw.Draw(im)
    d.text((14, 12), title, font=f_title, fill=(240, 206, 140))
    for r, cid in enumerate(ids):
        y = 56 + r * rowh
        name, sub = TITLES.get(cid, (cid, ''))
        d.text((14, y + chh // 2 - 26), name, font=f_name, fill=(246, 232, 200))
        d.text((14, y + chh // 2), sub, font=f_small, fill=(196, 176, 150))
        idle, walk = res[cid]
        for i, fr in enumerate(list(idle) + list(walk)):
            x = left + i * (cw + 4)
            bg = (64, 54, 48, 255) if i < 2 else (58, 50, 56, 255)
            d.rectangle((x, y, x + cw - 1, y + chh - 1), fill=bg)
            d.rectangle((x, y + chh - 14, x + cw - 1, y + chh - 1), fill=(84, 70, 58, 255))
            big = Image.fromarray(fr, 'RGBA').resize((cw, chh), Image.NEAREST)
            im.alpha_composite(big, (x, y))
        # tamaño de juego: sobre arena (calle) y sobre madera oscura (taller)
        x = left + 6 * (cw + 4) + 8
        for k, bgc in enumerate(((214, 176, 120, 255), (70, 52, 40, 255))):
            yy = y + 20 + k * 120
            d.rectangle((x, yy, x + 64 * 2 - 1, yy + 96 + 4), fill=bgc)
            fr = Image.fromarray(idle[0], 'RGBA')
            im.alpha_composite(fr, (x + 2, yy + 2))
            im.alpha_composite(Image.fromarray(walk[1], 'RGBA'), (x + 62, yy + 2))
    im.save(path)
    return path


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    sheet = None
    if '--out' in args:
        k = args.index('--out')
        out = args[k + 1]
        del args[k:k + 2]
    if '--sheet' in args:
        k = args.index('--sheet')
        sheet = args[k + 1]
        del args[k:k + 2]
    import ss_bots   # Kettle, Clatter y la tortuga
    BOTS.update(ss_bots.REG)
    ids = args or [i for i in ORDER if i in SS or i in BOTS]
    res = build([i for i in ids if i in SS or i in BOTS], out)
    os.makedirs(os.path.join(out, 'props'), exist_ok=True)
    if not args or 'kettle' in args or 'kettle_react' in args:
        for name, fn in ss_bots.PROPS_CHARS.items():
            Image.fromarray(fn(), 'RGBA').save(os.path.join(out, 'chars', name + '.png'))
    for name, fn in ss_bots.PROPS.items():
        if not args or name in args:
            Image.fromarray(fn(), 'RGBA').save(os.path.join(out, 'props', name + '.png'))
    if sheet:
        cast_sheet(res, sheet)
    print('ok', ids)
