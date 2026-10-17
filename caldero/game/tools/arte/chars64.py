"""Personajes de Caldero Nocturno (cuadros de 64x96), estilo HD-2D tipo Octopath Traveler: adultos de 60-64 px.

Generador modular: especie (cuerpo) x ropa x pelo x accesorios x paleta.
  - c64core.py  lienzo por partes, máscaras, render cel con contorno
  - c64body.py  especies, poses (quieto / caminar) y cabezas con anclas
  - c64parts.py cara, orejas, ropa y calzado
  - c64hair.py  pelo y barbas por mechones grandes (reemplaza a las funciones de pelo de c64parts)
  - c64acc.py   sombreros, cascos y objetos
Cada personaje es un diccionario en CAST (abajo). Miran a la derecha, pies en la fila 91.

Uso (desde una carpeta FUERA del proyecto de Godot; luego copiar a assets/chars y assets/props/cat.png):
      python3 chars64.py [ids...]   -> ./salida/chars/<id>_idle.png (2 cuadros) y <id>_walk.png (4 cuadros)
      python3 chars64.py --cast-sheet hoja.png   -> además la hoja del elenco
      python3 chars64.py --sheet    -> además ./prev_cast64.png (hoja de todo el elenco)
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from c64core import *
from c64body import *
from c64parts import *
from c64hair import *
from c64acc import *
import c64cat

OUT = './salida/chars'
OUT_PROPS = './salida/props'

# brillo puntual (ojos de objetos, gemas): crema, nunca blanco puro
WHITE = [(118, 116, 140), (150, 148, 170), (186, 184, 200), (214, 212, 220), (232, 228, 226), (244, 240, 230), (252, 248, 238)]

# materiales que casi todos comparten (se pueden sobrescribir en 'mats')
COMMON = {
    'gold': ('#c99d48', 'metal'), 'steel': ('#9aa2b2', 'metal'), 'leather': ('#74503a', 'leather'), 'wood': '#8a6040', 'wood2': '#634630',
    'string': ('#d8d0bc', 'flat'), 'glass': '#b4d4dc', 'leaf': '#6a9a4c', 'inner': '#e6a0a6', 'tusk': '#e8dfc8',
    'strap': ('#56402e', 'leather'), 'frame': '#4a3a34', 'lens': '#7cc4d8', 'brass': ('#bc9444', 'metal'), 'glow': '#ffd56a',
    'band': '#d4aa50', 'belt': ('#664632', 'leather'), 'boots': ('#5a3e2e', 'leather'), 'pants': '#4f4660',
}

# paleta terrosa: telas apagadas y algo más oscuras que el color de la ficha (la referencia es baja de valor)
MUTE = {'cloth': (0.56, 0.84), 'wool': (0.56, 0.84), 'leather': (0.66, 0.86), 'hair': (0.78, 0.94), 'skin': (1.0, 1.0),
        'white': (0.75, 0.84), 'silver': (0.72, 0.95), 'metal': (0.85, 0.92), 'gem': (0.92, 0.95)}


def _cream(b):
    """Blancos -> crema / gris cálido."""
    c = mute(b, 1.0, 1.0)
    return tuple(round(x * 0.78 + y * 0.22) for x, y in zip(c, (226, 214, 190)))


def make_pal(spec):
    """Rampas de 7 tonos por material y el tipo de cada material (para la textura).
    Las telas se apagan (menos saturación y valor: paleta terrosa); unos pocos acentos quedan saturados
    (los materiales 'gem', y lo que la ficha marque con 'accent')."""
    pal, kinds = {}, {}
    accents = set(spec.get('accent', ()))

    def add(k, v, default_kind='cloth'):
        base, kind = (v if isinstance(v, tuple) else (v, default_kind))
        b = hexrgb(base) if isinstance(base, str) else tuple(base)
        if kind == 'white':
            b = _cream(b)
        sm, vm = MUTE.get(kind, (1.0, 1.0))
        if k in accents:
            sm, vm = min(1.0, sm + 0.30), min(1.0, vm + 0.08)
        sm = spec.get('mute_s', sm) if kind in ('cloth', 'wool') else sm
        vm = spec.get('mute_v', vm) if kind in ('cloth', 'wool') else vm
        if kind == 'hair':
            sm = spec.get('hair_mute', sm)
        b = mute(b, sm, vm)
        pal[k] = ramp7(b, 'cloth' if kind == 'wool' else kind)
        kinds[k] = kind

    for k, v in COMMON.items():
        add(k, v)
    add('skin', (spec['skin'], 'skin'))
    add('hair', (spec['hc'], spec.get('hair_kind', 'hair')))
    add('beard', (spec.get('beard_col', spec['hc']), spec.get('hair_kind', 'hair')))
    add('brow', (spec.get('brow_col', tone(hexrgb(spec['hc']), 260, 20, 0.62, 0, 0.08)), 'hair'))
    add('iris', (spec['eyes'], 'gem'))
    # blanco del ojo teñido por el iris (la columna clara del ojo Octopath): gris claro con el color del iris
    ir = hexrgb(spec['eyes'])
    ew = tuple(round(0.66 * a + 0.34 * b) for a, b in zip((222, 220, 220), ir))
    pal['eyew'] = [dark(ew, 0.50, 0.3), dark(ew, 0.64, 0.3), dark(ew, 0.80, 0.25), ew, light(ew, 0.04, 0.1),
                   light(ew, 0.07, 0.15), light(ew, 0.10, 0.2)]
    kinds['eyew'] = 'flat'
    pal['white'] = WHITE
    kinds['white'] = 'flat'
    add('lash', (spec.get('lash', '#2c1e2a'), 'hair'))
    add('mouth', (spec.get('mouth_col', '#b87868'), 'skin'))
    add('blush', (spec.get('blush_col', '#e8a090'), 'flat'))
    for k, v in spec.get('mats', {}).items():
        add(k, v)
    return pal, kinds


def _call(fn, cv, B, sp, pose, kw, side=None):
    if side is None:
        return fn(cv, B, sp, pose, **kw)
    return fn(cv, B, sp, side, pose, **kw)


def draw(sp, pose):
    pal, kinds = make_pal(sp)
    cv = Cv(pal, kinds=kinds, tex=sp.get('tex', {}))
    B = Body(sp, pose)
    cv.vgrad = (B.y_w, GROUND, sp.get('vgrad', 0.9))
    hs = sp.get('hair', {})
    kind = hs.get('kind', 'short')
    # 1. fondo: capas, colas, mochilas, pelo largo
    for fn, kw in sp.get('back', []):
        _call(fn, cv, B, sp, pose, kw)
    if kind == 'long':
        hair_long_back(cv, B, sp, pose)
    if kind == 'wavy':
        hair_wavy_back(cv, B, sp, pose)
    if kind == 'bob':
        hair_bob(cv, B, sp, pose)
    if kind == 'shaggy':
        hair_shaggy_back(cv, B, sp, pose)
    if kind == 'twintails':
        if not hs.get('far_tail_front'):
            twin_tail(cv, B, sp, 'f', pose)
        twin_tail(cv, B, sp, 'n', pose)
    if kind == 'ponytail':
        ponytail(cv, B, sp, pose)
    if kind == 'braid_back':
        braid(cv, B, sp, pose, front=False)
    if hs.get('bun') and not hs.get('bun_front'):
        bun(cv, B, sp)
    if kind == 'curly':
        curls_back(cv, B, sp, pose)
    for fn, kw in sp.get('back2', []):
        _call(fn, cv, B, sp, pose, kw)
    if sp.get('ears') == 'elf':
        ear_elf(cv, B, sp, far=True)
    # 2. brazo lejano (+ objeto + mano), salvo que vaya por delante del cuerpo
    def far_arm():
        arm(cv, B, sp, 'f', pose)
        hand(cv, B, sp, 'f', pose)
        for fn, kw in sp.get('far', []):
            _call(fn, cv, B, sp, pose, kw, side='f')
        if sp.get('far') and B.arm['f'].get('held') and not B.arm['f'].get('no_regrip'):
            hand(cv, B, sp, 'f', pose)
    far_front = sp.get('far_front') and not (pose.kind == 'walk' and 'f' in sp.get('free_walk', ()))
    if not far_front:
        far_arm()
    # 3. piernas
    leg(cv, B, sp, 'f', pose)
    leg(cv, B, sp, 'n', pose)
    # 4. cuello y ropa
    draw_neck(cv, B, sp)
    p_top, p_sk = top_garment(cv, B, sp, pose)
    nl = sp.get('top', {}).get('neck')
    if nl:
        neckline(cv, B, sp, p_top, nl, sp.get('top', {}).get('neck_mat'))
    for fn, kw in sp.get('over', []):
        _call(fn, cv, B, sp, pose, kw)
    # 5. pelo de delante de los hombros (mechón y coleta lejanos), cabeza
    if kind == 'twintails' and hs.get('far_tail_front'):
        twin_tail(cv, B, sp, 'f', pose)
    if hs.get('locks', 0) >= 2:
        side_lock(cv, B, sp, 'f', pose=pose)
    draw_head(cv, B, sp)
    for fn, kw in sp.get('face_acc', []):
        _call(fn, cv, B, sp, pose, kw)
    # 6. pelo y orejas
    if kind == 'bald':
        hair_ring(cv, B, sp)
    elif kind != 'none':
        hair_cap(cv, B, sp)
    if hs.get('spikes'):
        hair_spikes(cv, B, sp, pose, n=hs.get('spikes'), big=hs.get('spike_big', 1.0))
    if sp.get('ears') == 'elf':
        ear_elf(cv, B, sp)
    elif sp.get('ears') == 'human':
        ear_human(cv, B, sp)
    if kind not in ('bald', 'none'):
        hair_bangs(cv, B, sp)
    if hs.get('locks', 0) >= 1:
        side_lock(cv, B, sp, 'n', pose=pose)
    if kind == 'braid_front':
        braid(cv, B, sp, pose, front=True)
    if hs.get('ringlets'):
        ringlets(cv, B, sp, pose)
    if hs.get('bun') and hs.get('bun_front'):
        bun(cv, B, sp)
    for fn, kw in sp.get('head', []):
        _call(fn, cv, B, sp, pose, kw)
    if far_front:
        far_arm()
    # 7. brazo cercano (+ objeto + mano) y lo de delante
    arm(cv, B, sp, 'n', pose)
    hand(cv, B, sp, 'n', pose)
    for fn, kw in sp.get('near', []):
        _call(fn, cv, B, sp, pose, kw, side='n')
    if sp.get('near') and B.arm['n'].get('held') and not B.arm['n'].get('no_regrip'):
        hand(cv, B, sp, 'n', pose)
    for fn, kw in sp.get('front', []):
        _call(fn, cv, B, sp, pose, kw)
    for fn, kw in sp.get('post', []):
        _call(fn, cv, B, sp, pose, kw)
    return render(cv)


def frames(sp):
    idle = [draw(sp, Pose('idle', i)) for i in range(2)]
    walk = [draw(sp, Pose('walk', i)) for i in range(4)]
    return idle, walk


# ================================================================== elenco
CAST = {}

# ---------------- la alquimista (jugadora): pelo rojizo, delantal verde, sombrero de bruja verde azulado
CAST['alquimista'] = dict(
    name='La alquimista', species='human_f', skin='#f0cdb0', hc='#a4482e', eyes='#3f7a4e', stance='easy',
    accent=('potion', 'potion2', 'berry', 'hat'),
    stance_mod=dict(lean=1.0, sway=-1.0), turn=0.5,
    face=dict(eye='std', mouth='small'),
    hair=dict(kind='long', bangs='parted', locks=2, length=31, lock=23, width=0, volume=2.0, tips=5),
    top=dict(kind='dress', mat='blouse', skirt='skirt', length='knee', flare=0.55, folds=3, neck='round'),
    sleeves=dict(kind='rolled', mat='blouse'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron', y_hem=None, trim='apron_t', pockets=True)), (belt, dict(mat='belt', buckle='gold')),
          (belt_vial, dict(liquid='potion2'))],
    head=[(witch_hat, dict(mat='hat', band='band', deco=leaf_sprig('leaf', 'berry'), brim_cast=1))],
    arms={'n': 'hip', 'f': 'raise_flask'}, far_front=True, free_walk=('n', 'f'),
    far=[(flask, dict(liquid='potion'))],
    mats={'blouse': '#ece2c8', 'skirt': '#5e3e54', 'apron': '#68904e', 'apron_t': '#46663a', 'tights': '#3a2e44',
          'boots': ('#6a4630', 'leather'), 'hat': '#2e6466', 'band': ('#c8a050', 'metal'), 'berry': ('#d04848', 'gem'),
          'potion2': ('#d86aa8', 'gem'), 'potion': ('#7ad0a0', 'gem'), 'cork': '#9a7048', 'leaf': '#5a8a44'},
)

# ---------------- Lirien: maga elfa (homenaje): coletas bajas plateadas, blanco y oro, capita, bastón con gema roja
CAST['lirien'] = dict(
    name='Lirien', species='elf_s', skin='#f4dccb', hc='#e8e6f0', hair_kind='silver', eyes='#4f9a72', lash='#4a3a52', ears='elf',
    stance='easy_f', stance_mod=dict(lean=1.0), turn=0.45,
    face=dict(eye='calm', mouth='small'), mouth_col='#b87a78',
    hair=dict(kind='twintails', bangs='frieren', locks=2, lock=18.5, tail_len=33, tail_w=1.9, tail_out=3.0, tail_root=15.5,
              tie='gold', volume=2.0, side_len=16.0),
    top=dict(kind='dress', mat='coat', length='knee', flare=0.30, folds=2, trim='gold', front='gold', neck='high', neck_mat='under'),
    sleeves=dict(kind='long', mat='coat', cuff='gold'),
    legs=dict(kind='tights', mat='under'), feet=dict(kind='boots', mat='boots', h=0.55),
    over=[(belt, dict(mat='belt2', buckle='gold', h=1)), (capelet, dict(mat='cape', trim='gold', length=8.0, clasp='gem'))],
    head=[(earrings, dict(mat='gem'))],
    arms={'n': 'book', 'f': 'staff_out'},
    near=[(book, dict(cover='grim', page='page', clasp='gold'))],
    far=[(staff, dict(wood='wood', gem='gem', crown='gold', kind='mage'))],
    mats={'coat': ('#f0ede4', 'white'), 'cape': ('#f6f4ee', 'white'), 'under': '#2a2733', 'boots': ('#5a3e30', 'leather'),
          'gem': ('#d02c44', 'gem'), 'belt2': ('#7a5034', 'leather'), 'wood': '#946538', 'wood2': '#74502e', 'gold': ('#d0a248', 'metal'),
          'grim': '#6a3a40', 'page': '#efe4c8'},
)


# ---------------- Bram: guerrero enano (casco, barba roja, hacha a la espalda)
CAST['bram'] = dict(
    name='Bram', species='dwarf', skin='#eab494', hc='#d2652e', eyes='#4f86c0',
    face=dict(eye='man', mouth=None, brow='thick', blush=False),
    hair=dict(kind='short', bangs='none', hairline=4.0),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.25, folds=2, trim='gold'),
    sleeves=dict(kind='long', mat='mail', cuff='leather'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(belt, dict(mat='belt', buckle='gold', h=3))],
    head=[(beard, dict(kind='full')), (helmet, dict(mat='steel', kind='dwarf', trim='brass'))],
    back2=[(axe_back, {})],
    post=[(chainmail, dict(mat='mail'))],
    mats={'tunic': '#b03e3c', 'mail': ('#9ea6b8', 'metal'), 'pants': '#5a4634', 'boots': '#4a3428', 'fur': '#c8b69a'},
)

# ---------------- Sor Elda: sacerdotisa (velo blanco y azul, libro)
CAST['elda'] = dict(
    name='Sor Elda', species='human_f', skin='#f8dac6', hc='#f2d27c', eyes='#5a80cc',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='parted', locks=2, lock=17, hairline=5.5),
    top=dict(kind='dress', mat='robe', length='floor', flare=0.32, folds=4, trim='blue', front='blue', neck='collar', neck_mat='blue2'),
    sleeves=dict(kind='wide', mat='robe', cuff='blue'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    head=[(veil, dict(mat='veil', band='blue', length=26))],
    hold={'n': (4.5, 9.0)}, near=[(book, dict(cover='book', page='page', clasp='gold'))],
    mats={'robe': ('#f1eee6', 'white'), 'veil': ('#fbfaf6', 'white'), 'blue': '#4a74c4', 'blue2': '#5f8ad6', 'shoes': '#8c6a52',
          'book': '#a04a3a', 'page': '#f3ead2'}, accent=('book', 'blue'),
)

# ---------------- Kit: ladrona mediana (capucha verde, bufanda roja, descalza)
CAST['kit'] = dict(
    name='Kit', species='halfling', skin='#f2c39c', hc='#7a4f36', eyes='#cf8a2c',
    face=dict(eye='kid', mouth='smile', blush=True, freckles=True),
    hair=dict(kind='short', bangs='curly', locks=1, lock=15),
    top=dict(kind='tunic', mat='vest', length='hip', folds=1, front='leather'),
    sleeves=dict(kind='long', mat='shirt'),
    legs=dict(kind='shorts', mat='shorts'), feet=dict(kind='bare', long=1),
    back=[(hood, dict(mat='hood', part='back')), (cape_back, dict(mat='hood', width=2.0))],
    over=[(belt, dict(mat='belt', buckle='steel')), (scarf, dict(mat='scarf'))],
    head=[(hood, dict(mat='hood', part='front'))],
    front=[(dagger_hip, {})],
    mats={'vest': '#86603f', 'shirt': '#e8dcc0', 'shorts': '#4c4560', 'hood': '#3f6b4e', 'scarf': '#cc5640'},
)

# ---------------- Sir Aldric: caballero novato (armadura, sobreveste azul, capa)
CAST['aldric'] = dict(
    name='Sir Aldric', species='human_m', skin='#f3caa8', hc='#efc860', eyes='#4a7ad0', ears='human', stance='wide',
    face=dict(eye='man', mouth='small', brow='man', blush=False),
    hair=dict(kind='short', bangs='swept', locks=1, lock=16, volume=2.2),
    top=dict(kind='tunic', mat='plate', length='thigh', flare=0.2, folds=0),
    sleeves=dict(kind='armor', mat='plate'),
    legs=dict(kind='pants', mat='mail'), feet=dict(kind='greaves', mat='plate', h=0.95),
    over=[(tabard, dict(mat='tabard', trim='gold', emblem='gold')), (belt, dict(mat='belt', buckle='gold'))],
    back=[(cape_back, dict(mat='cape', width=3.5))],
    front=[(sword_hip, dict(hilt='gold', sheath='sheath', side='n'))],
    arms={'n': 'hilt', 'f': 'hip'}, free_walk=('f',),
    gloves='plate',
    mats={'plate': ('#c4ccda', 'metal'), 'mail': ('#8e96a8', 'metal'), 'tabard': '#2f56a0', 'cape': '#3a62b4', 'sheath': '#4a3a5a'},
)

# ---------------- Wren: exploradora (coleta pelirroja, capucha verde, arco y carcaj)
CAST['wren'] = dict(
    name='Wren', species='human_f', skin='#f0c19c', hc='#cc5a2e', eyes='#5e9a4a',
    face=dict(eye='cute', mouth='smile', blush=True, freckles=True),
    hair=dict(kind='ponytail', bangs='swept', locks=1, lock=16, tail_len=22, tail_w=2.4, tie='leather', volume=2.0),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.3, folds=2, trim='trim'),
    sleeves=dict(kind='long', mat='tunic', cuff='leather'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.8),
    over=[(belt, dict(mat='belt', buckle='brass')), (capelet, dict(mat='cowl', length=6.5))],
    back2=[(bow_back, {}), (quiver, dict(mat='leather'))],
    mats={'tunic': '#6a8f4c', 'trim': '#d8b25a', 'pants': '#5a4a3e', 'boots': '#5a3c2a', 'cowl': '#3f6e3c', 'fletch': '#f0ece0'},
)

# ---------------- Tomás: granjero (sombrero de paja, bigote, peto azul)
CAST['granjero'] = dict(
    name='Tomás', species='human_m', skin='#e0a882', hc='#5a4030', eyes='#6a5038', ears='human', stance='easy',
    face=dict(eye='man', mouth='smile', brow='man', blush=True),
    hair=dict(kind='short', bangs='short', locks=1, lock=15, volume=2.0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='denim'), feet=dict(kind='boots', mat='boots', h=0.55),
    over=[(apron, dict(mat='denim', y_hem='hip', width=0.95))],
    head=[(beard, dict(kind='mustache')), (straw_hat, dict(mat='straw', band='band'))],
    arms={'n': 'hip', 'f': 'lean_on'}, free_walk=('n',), stance_mod=dict(lean=1.6, sway=-0.8), turn=0.5,
    far=[(tool_planted, dict(kind='hoe', wood='wood', blade='steel'))],
    mats={'shirt': '#efe8d8', 'denim': '#4a6a9c', 'boots': '#5a3a28', 'straw': '#e8c56c', 'band': '#b04a3a'},
)

# ---------------- Greta: panadera (pañuelo rojo de lunares, delantal, pan)
CAST['panadera'] = dict(
    name='Greta', species='human_f', body=dict(sw=13, ww=11, hw=13), skin='#f2c29c', hc='#7a4a2a', eyes='#8a5a3a',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='parted', locks=1, lock=15, bun=True, bun_x=0.0, bun_y=6.0),
    top=dict(kind='dress', mat='dress', skirt='skirt', length='calf', flare=0.45, folds=3, neck='round'),
    sleeves=dict(kind='rolled', mat='dress'),
    legs=dict(kind='pants', mat='skirt'), feet=dict(kind='shoes', mat='shoes'),
    over=[(apron, dict(mat='apron', width=0.9, trim='apron_t'))],
    head=[(kerchief, dict(mat='kerchief', dots='dots'))],
    hold={'n': (5.0, 8.0)}, near=[(bread, {})],
    mats={'dress': '#db8e60', 'skirt': '#6a4a6a', 'apron': ('#f4eee2', 'white'), 'apron_t': '#d8c8b0', 'kerchief': '#cc483e',
          'dots': '#f6ece0', 'shoes': '#5a3a28', 'bread': ('#b06a30', 'leather')},
)

# ---------------- Don Ruperto: vecino jubilado (calvo, barba blanca, bastón)
CAST['anciano'] = dict(
    name='Don Ruperto', species='human_m', body=dict(h=60, hunch=1), skin='#e4b28e', hc='#e8e6e2', eyes='#6a6a7a', ears='human',
    face=dict(eye='old', mouth=None, brow='old', blush=True),
    hair=dict(kind='bald'), beard_col='#efeeea',
    top=dict(kind='dress', mat='robe', length='ankle', flare=0.25, folds=3),
    sleeves=dict(kind='wide', mat='robe'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    over=[(belt, dict(mat='rope', buckle=None, h=2))],
    head=[(beard, dict(kind='long', len=11))],
    hold={'f': (4.5, 9.0)}, far=[(staff, dict(wood='wood', kind='cane', top=8))],
    mats={'robe': '#7c5c46', 'rope': '#c8a858', 'shoes': '#4a3426'},
)

# ---------------- Sylwen: arquera elfa (trenza rubia, verde y marrón, arco)
CAST['sylwen'] = dict(
    name='Sylwen', species='elf_f', skin='#f6dac4', hc='#f2d48a', eyes='#4f9a5a', ears='elf',
    face=dict(eye='cute', mouth='small', blush=True),
    hair=dict(kind='braid_back', bangs='parted', locks=2, lock=18, braid_len=30, tie='leaf'),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.35, folds=2, trim='trim'),
    sleeves=dict(kind='long', mat='under', cuff='leather'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.85),
    over=[(belt, dict(mat='belt', buckle='gold')), (capelet, dict(mat='cloak', length=6.0, clasp='gold'))],
    back2=[(bow_back, {}), (quiver, dict(mat='leather', fletch='fletch'))],
    head=[(flower_crown, dict(flowers=('leafy', 'leafy2'), leaf='leaf'))],
    mats={'tunic': '#4f8048', 'under': '#7a5232', 'trim': '#d8b25a', 'pants': '#6a4a30', 'boots': '#4a3424', 'cloak': '#3c6a3e',
          'fletch': '#f0ece0', 'leafy': '#8ccf6a', 'leafy2': '#5fae4f'},
)

# ---------------- Nyra: comerciante gata (orejas y cola, pañuelo llamativo)
CAST['nyra'] = dict(
    name='Nyra', species='human_f', skin='#f6d6bc', hc='#e8a052', eyes='#e0b030',
    face=dict(eye='cat', mouth='cat', blush=True),
    hair=dict(kind='short', bangs='parted', locks=2, lock=16),
    top=dict(kind='dress', mat='vest', skirt='skirt', length='thigh', flare=0.55, folds=2, trim='gold', neck='round'),
    sleeves=dict(kind='puff', mat='blouse'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='boots', mat='boots', h=0.6),
    back=[(tail, dict(kind='cat', mat='hair', tip='tip'))],
    over=[(satchel, dict(mat='leather')), (scarf, dict(mat='scarf', stripe='stripe'))],
    head=[(ears_animal, dict(kind='cat'))],
    mats={'vest': '#3a7a8a', 'skirt': '#2e5f70', 'blouse': '#f6efe0', 'tights': '#4a3a50', 'boots': '#6a4430', 'scarf': '#e04880',
          'stripe': '#ffd24a', 'tip': '#fff4e6', 'inner': '#f6b0b0'},
)

# ---------------- Ragnar: mercenario lobo (orejas y cola grises, cuero, mandoble)
CAST['ragnar'] = dict(
    name='Ragnar', species='wolf', skin='#e0b08a', hc='#8f96a6', eyes='#e0a830',
    face=dict(eye='fierce', mouth='flat', brow='thick', blush=False),
    hair=dict(kind='shaggy', bangs='spiky', locks=1, lock=16, length=22),
    top=dict(kind='tunic', mat='leather_a', length='thigh', flare=0.2, folds=2, trim='strap'),
    sleeves=dict(kind='short', mat='leather_a'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.7),
    back=[(tail, dict(kind='wolf', mat='hair', tip='tip'))],
    back2=[(greatsword_back, {})],
    over=[(belt, dict(mat='strap', buckle='steel', h=3)), (scarf, dict(mat='fur', tail=False))],
    head=[(ears_animal, dict(kind='wolf')), (beard, dict(kind='stubble'))],
    mats={'leather_a': '#6e4a32', 'pants': '#3e3a48', 'boots': '#3a2a22', 'fur': '#b8b0a0', 'tip': '#e8e6e0', 'inner': '#c89a9a'},
)

# ---------------- Isolde: capitana (armadura completa, sobreveste azul, penacho)
CAST['isolde'] = dict(
    name='Isolde', species='human_f', body=dict(h=62, sw=13, ww=9.5, hw=11, leg=19), skin='#f4d0b4', hc='#7a3e2c', eyes='#4a78c8',
    face=dict(eye='fierce', mouth='small', brow='thin', blush=False),
    hair=dict(kind='long', bangs='swept', locks=1, lock=18, length=32),
    top=dict(kind='tunic', mat='plate', length='thigh', flare=0.25, folds=0),
    sleeves=dict(kind='armor', mat='plate'),
    legs=dict(kind='pants', mat='plate2'), feet=dict(kind='greaves', mat='plate', h=0.95),
    over=[(tabard, dict(mat='tabard', trim='gold', emblem='gold', length=None)), (belt, dict(mat='belt', buckle='gold'))],
    head=[(helmet, dict(mat='plate', kind='knight', plume='plume', trim='gold'))],
    back2=[(shield_back, dict(mat='tabard', rim='plate', emblem='gold'))],
    front=[(sword_hip, dict(hilt='gold', sheath='sheath'))],
    gloves='plate',
    mats={'plate': ('#c8d0de', 'metal'), 'plate2': ('#a8b0c2', 'metal'), 'tabard': '#2a4f9c', 'plume': '#d03844', 'sheath': '#3a3048'},
)

# ---------------- Roxa: maga viajera (homenaje): trenza azul, gran sombrero, túnica marrón
CAST['roxa'] = dict(
    name='Roxa', species='human_f', body=dict(h=57, sw=10.5, ww=8, hw=10, leg=17), skin='#f6dccc', hc='#4a78d8', eyes='#3f6ad0',
    face=dict(eye='std', mouth='small', blush=True),
    hair=dict(kind='braid_front', bangs='parted', locks=1, lock=16, braid_len=24, tie='ribbon', hairline=5.0),
    top=dict(kind='dress', mat='robe', length='ankle', flare=0.4, folds=3, trim='trim', neck='collar', neck_mat='collar'),
    sleeves=dict(kind='wide', mat='robe', cuff='trim'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='boots', mat='boots', h=0.4),
    over=[(belt, dict(mat='belt', buckle='gold', h=1))],
    head=[(witch_hat, dict(mat='hat', band='hatband', h=19, brim=14.0, bend=-7.0, droop=2.0, crown_w=12.5, brim_cast=1))],
    hold={'f': (3.5, 10.0)}, far=[(staff, dict(wood='wood', gem='gem', crown='gold', kind='orb'))],
    mats={'robe': '#8e6040', 'trim': '#e6d8b8', 'collar': ('#f2ece0', 'white'), 'boots': '#4a3428', 'hat': '#5e4c44',
          'hatband': '#e6d8b8', 'gem': ('#5ab4f0', 'metal'), 'ribbon': '#e8e0d0'},
)

# ---------------- Anselmo: sacerdote anciano (blanco y oro, báculo de sol)
CAST['anselmo'] = dict(
    name='Padre Anselmo', species='human_m', body=dict(h=61, hunch=1), skin='#efc4a4', hc='#f0eee8', hair_kind='white', eyes='#6a7a9a', ears='human',
    face=dict(eye='smile', mouth=None, brow='old', blush=True),
    hair=dict(kind='bald'), beard_col='#f4f2ec',
    top=dict(kind='dress', mat='robe', length='floor', flare=0.3, folds=4, trim='gold', front='gold'),
    sleeves=dict(kind='wide', mat='robe', cuff='gold'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    over=[(scarf, dict(mat='stole', tail=True))],
    head=[(beard, dict(kind='long', len=8))],
    hold={'f': (4.0, 8.0)}, far=[(staff, dict(wood='gold', gem='gem', crown='gold', kind='sun'))],
    mats={'robe': ('#f3f0e8', 'white'), 'stole': '#d6ad55', 'shoes': '#8c6a52', 'gem': ('#ffd86a', 'metal')},
)

# ---------------- Marta: campesina con canasta
CAST['marta'] = dict(
    name='Marta', species='human_f', skin='#ecbe98', hc='#6a4a3a', eyes='#6a5a3a',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='braid_front', bangs='parted', locks=1, lock=15, braid_len=20, tie='kerchief'),
    top=dict(kind='dress', mat='dress', length='calf', flare=0.45, folds=3, neck='round'),
    sleeves=dict(kind='rolled', mat='blouse'),
    legs=dict(kind='pants', mat='dress'), feet=dict(kind='shoes', mat='shoes'),
    over=[(apron, dict(mat='apron', width=0.85, bib=False, y_top=None))],
    head=[(kerchief, dict(mat='kerchief', knot=True))],
    hold={'n': (5.0, 7.0)}, near=[(basket, dict(mat='wicker', goods=('veg1', 'veg2', 'leaf')))],
    mats={'dress': '#8a8a4e', 'blouse': '#efe6d2', 'apron': ('#f0e8d6', 'white'), 'kerchief': '#8ab4d4', 'shoes': '#5a3a28',
          'wicker': '#c8955a', 'veg1': '#ee8a30', 'veg2': '#e04a3a'},
)

# ---------------- Lupo: pescador (sombrero de paja ancho, camisa a rayas, caña)
CAST['lupo'] = dict(
    name='Lupo', species='human_m', skin='#d49a70', hc='#3a2e2a', eyes='#5a4a3a', ears='human',
    face=dict(eye='man', mouth='smile', brow='man', blush=False),
    hair=dict(kind='short', bangs='short', locks=0),
    top=dict(kind='shirt', mat='stripes', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='stripes'),
    legs=dict(kind='shorts', mat='pants'), feet=dict(kind='sandals', mat='leather'),
    over=[(belt, dict(mat='rope', buckle=None))],
    head=[(beard, dict(kind='short')), (straw_hat, dict(mat='straw', band=None, brim=13.0, h=4.5))],
    hold={'n': (4.0, 6.0)}, near=[(fishing_rod, {})],
    post=[(stripes, dict(mat='stripe'))],
    mats={'stripe': '#4a78b0', 'stripes': '#eef2f6', 'pants': '#5a6a7a', 'rope': '#c8a858', 'straw': '#e6c46a', 'fish': ('#9ab8c8', 'metal')},
)

# ---------------- Vianne: dama noble (vestido rosa, encajes, sombrilla)
CAST['vianne'] = dict(
    name='Lady Vianne', species='human_f', skin='#f8dccb', hc='#f2d27e', eyes='#5a8ad8',
    face=dict(eye='cute', mouth='small', blush=True),
    hair=dict(kind='short', bangs='parted', locks=0, bun=True, bun_x=1.0, bun_y=1.0, bun_r=4.2, ringlets=True),
    top=dict(kind='dress', mat='dress', length='floor', flare=0.75, widen=4.0, folds=5, trim='lace', trim_rows=2, neck='round'),
    sleeves=dict(kind='puff_long', mat='dress', cuff='lace'),
    legs=dict(kind='pants', mat='dress'), feet=dict(kind='shoes', mat='shoes'),
    over=[(belt, dict(mat='sash', buckle='gem', h=2))],
    head=[(flower_crown, dict(flowers=('rose', 'lace'), leaf='leaf'))],
    hold={'f': (3.0, 6.0)}, far=[(parasol, dict(mat='lace', trim='rose', pole='wood2'))],
    front=[(parasol_top, dict(mat='lace', trim='rose', pole='wood2'))],
    mats={'dress': '#c8506e', 'lace': ('#fbf4f6', 'white'), 'sash': '#f0c8d4', 'shoes': '#7a3048', 'rose': '#e8708e',
          'gem': ('#7ad0f0', 'metal')},
)

# ---------------- Hassim: mercader viajero (turbante, abrigo largo, mochila enorme)
CAST['hassim'] = dict(
    name='Hassim', species='human_m', skin='#b07a52', hc='#2a2228', eyes='#5a3a2a', ears='human',
    face=dict(eye='man', mouth='smile', brow='thick', blush=False),
    hair=dict(kind='short', bangs='none', locks=0),
    top=dict(kind='dress', mat='coat', length='calf', flare=0.3, folds=3, trim='gold', front='gold'),
    sleeves=dict(kind='long', mat='coat', cuff='gold'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.5),
    over=[(belt, dict(mat='sash', buckle=None, h=3))],
    head=[(beard, dict(kind='short')), (turban, dict(mat='turban', gem='gem'))],
    back=[(backpack, dict(mat='pack', strap='leather', rolled='rug', pot='pot'))],
    mats={'coat': '#2a7280', 'sash': '#c83a3a', 'pants': '#e8dcc0', 'boots': '#6a4430', 'turban': '#f0b040', 'gem': ('#d8304a', 'metal'),
          'pack': '#8a5a34', 'rug': '#b04a4a', 'pot': ('#c88a4a', 'metal')},
)

# ---------------- Pip: niño del pueblo (pelo revuelto, pecas, espada de palo)
CAST['pip'] = dict(
    name='Pip', species='child', skin='#f4c8a4', hc='#d07a3a', eyes='#4a8ac8',
    face=dict(eye='kid', mouth='open', blush=True, freckles=True),
    hair=dict(kind='short', bangs='spiky', locks=0, spikes=4),
    top=dict(kind='tunic', mat='tunic', length='hip', flare=0.3, folds=1),
    sleeves=dict(kind='short', mat='tunic'),
    legs=dict(kind='shorts', mat='shorts'), feet=dict(kind='shoes', mat='shoes'),
    over=[(belt, dict(mat='rope', buckle=None, h=1))],
    hold={'n': (5.0, 4.0)}, near=[(wooden_sword, {})],
    mats={'tunic': '#e8b840', 'shorts': '#7a5a3e', 'rope': '#c8a858', 'shoes': '#6a4430'},
)

# ---------------- Grumm: cocinero semiorco (piel verde, colmillos, delantal, cucharón)
CAST['grumm'] = dict(
    name='Grumm', species='orc', skin='#94b870', hc='#2a2830', eyes='#d0a040',
    face=dict(eye='smile', mouth='grin', brow='thick', blush=True),
    hair=dict(kind='short', bangs='none', locks=0, volume=0.8, side_len=9.0, hairline=3.0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.5),
    over=[(apron, dict(mat='apron', width=0.95, y_hem=None))],
    head=[(tusks, {}), (chef_hat, dict(mat='kerchief'))],
    hold={'n': (6.0, 12.0)}, near=[(ladle, {})],
    mats={'shirt': '#a87850', 'pants': '#4a4058', 'boots': '#3a2a22', 'apron': ('#f2eee4', 'white'), 'kerchief': ('#f4f1ea', 'white')},
)

# ---------------- Zaria: viajera de raza demoníaca (cuernitos, cola, melena azul)
CAST['zaria'] = dict(
    name='Zaria', species='human_f', skin='#f2d8d6', hc='#7a92e0', eyes='#d84a6a',
    face=dict(eye='cute', mouth='small', blush=True),
    hair=dict(kind='bob', bangs='parted', locks=2, lock=17, bob_len=20),
    top=dict(kind='dress', mat='dress', length='knee', flare=0.4, folds=2, trim='trim', neck='high', neck_mat='trim'),
    sleeves=dict(kind='long', mat='dress', cuff='trim'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='boots', mat='boots', h=0.75),
    back=[(tail, dict(kind='demon', mat='tailc', tip='tailc')), (cape_back, dict(mat='cloak', width=3.0))],
    over=[(belt, dict(mat='belt', buckle='gold')), (capelet, dict(mat='cloak', length=7.0, clasp='gem'))],
    head=[(horns, {})],
    mats={'dress': '#5a4a8a', 'trim': '#c8b4e8', 'tights': '#2e2838', 'boots': '#4a3040', 'cloak': '#8a5a8a', 'horn': '#ece2d0',
          'tailc': '#6a5a9a', 'gem': ('#e05a8a', 'metal')},
)

# ---------------- Fizz: alquimista gnomo rival (gafas, nariz grande, frasco)
CAST['fizz'] = dict(
    name='Fizz', species='gnome', skin='#f2c4a0', hc='#e06aa8', eyes='#4ab0a0',
    face=dict(eye='kid', mouth='grin', blush=True, nose=False),
    hair=dict(kind='short', bangs='spiky', locks=0, spikes=5, spike_big=1.2),
    top=dict(kind='dress', mat='coat', length='knee', flare=0.35, folds=2, trim='trim', front='trim', neck='collar', neck_mat='scarf'),
    sleeves=dict(kind='long', mat='coat', cuff='trim'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.5),
    over=[(belt, dict(mat='belt', buckle='brass')), (belt_vial, dict(liquid='potion3'))],
    head=[(big_nose, {}), (goggles, dict(mat='brass', lens='lens'))],
    hold={'n': (5.0, 4.0)}, near=[(flask, dict(liquid='potion'))],
    mats={'nose': '#f4b0a0', 'coat': ('#f2eee2', 'white'), 'trim': '#8a5ac8', 'scarf': '#8a5ac8', 'potion3': ('#f0a040', 'metal'), 'cork': '#a87848', 'pants': '#4a4a5a', 'boots': '#5a3a2a', 'potion': ('#7ae070', 'metal')},
)

# ---------------- Brann: guardia del pueblo (casco, lanza, sobreveste granate)
CAST['brann'] = dict(
    name='Brann', species='human_m', skin='#eab896', hc='#6a4a30', eyes='#5a6a7a', ears='human',
    face=dict(eye='man', mouth='flat', brow='thick', blush=False),
    hair=dict(kind='short', bangs='short', locks=0),
    top=dict(kind='tunic', mat='mail', length='thigh', flare=0.2, folds=0),
    sleeves=dict(kind='long', mat='mail', cuff='leather'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.8),
    over=[(tabard, dict(mat='tabard', trim='gold', emblem='gold2')), (belt, dict(mat='belt', buckle='steel'))],
    head=[(beard, dict(kind='mustache')), (helmet, dict(mat='steel', kind='kettle'))],
    hold={'f': (4.0, 7.0)}, far=[(spear, {})],
    post=[(chainmail, dict(mat='mail'))],
    mats={'mail': ('#8e96a8', 'metal'), 'tabard': '#8a2a3a', 'pants': '#4a3e36', 'boots': '#3e2c24', 'gold2': '#e8c86a'},
)

# ---------------- Borin: joyero enano (barba oscura con cuentas, gorro, delantal, gema)
CAST['borin'] = dict(
    name='Borin', species='dwarf', skin='#e6ac8a', hc='#8a4a2e', eyes='#5a8a6a',
    face=dict(eye='man', mouth=None, brow='thick', blush=True),
    hair=dict(kind='short', bangs='none', hairline=4.5),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.25, folds=2, trim='gold'),
    sleeves=dict(kind='long', mat='tunic', cuff='gold'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron_l', width=0.9, bib=True))],
    head=[(beard, dict(kind='full', len=13)), (cap_soft, dict(mat='cap')), (loupe, dict(mat='gold'))],
    hold={'n': (5.0, 5.0)}, near=[(gem_hold, dict(gem='gem'))],
    mats={'tunic': '#6a3a7a', 'pants': '#4a3a30', 'boots': '#3e2c24', 'cap': '#3c5a8a', 'gem': ('#40c8e0', 'metal'), 'apron_l': '#b08050'},
)

# ---------------- Ilse: herbolaria elfa (corona de flores, pelo ondulado, cesta de hierbas)
CAST['ilse'] = dict(
    name='Ilse', species='elf_f', skin='#f6dccc', hc='#c08a5a', eyes='#5aa070', ears='elf',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='wavy', bangs='parted', locks=2, lock=19, length=36),
    top=dict(kind='dress', mat='dress', length='ankle', flare=0.4, folds=3, trim='trim', neck='round'),
    sleeves=dict(kind='wide', mat='dress', cuff='trim'),
    legs=dict(kind='pants', mat='dress'), feet=dict(kind='shoes', mat='shoes'),
    over=[(apron, dict(mat='apron', width=0.8, bib=False))],
    head=[(flower_crown, dict(flowers=('flower1', 'flower2', 'flower3'), leaf='leaf'))],
    hold={'n': (5.0, 7.0)}, near=[(basket, dict(mat='wicker', goods=('herb1', 'herb2', 'flower1')))],
    mats={'dress': '#88b07c', 'trim': '#f0e6c8', 'apron': ('#f4eee0', 'white'), 'shoes': '#6a4a30', 'flower1': '#f4a8c0',
          'flower2': '#fdf6e8', 'flower3': '#f8d860', 'wicker': '#c8955a', 'herb1': '#5aa04a', 'herb2': '#8ac860'},
)

# ---------------- Tobías: librero y tintero (gafas redondas, chaleco, libro)
CAST['tobias'] = dict(
    name='Tobías', species='human_m', body=dict(sw=12.5, ww=9.5, hw=10.5), skin='#f0c8a8', hc='#4a3a5a', eyes='#5a6aa0', ears='human',
    face=dict(eye='man', mouth='smile', brow='man', blush=False),
    hair=dict(kind='short', bangs='swept', locks=1, lock=13, spikes=3, spike_big=0.6),
    top=dict(kind='tunic', mat='vest', length='hip', flare=0.2, folds=0, front='gold', neck='collar', neck_mat='shirt'),
    sleeves=dict(kind='long', mat='shirt', cuff='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='shoes', mat='shoes'),
    face_acc=[(glasses, dict(mat='frame'))],
    head=[(quill, dict(mat='feather'))],
    hold={'n': (5.0, 7.0)}, near=[(book, dict(cover='book', page='page'))],
    mats={'feather': '#8ad0c8', 'vest': '#7a2a3a', 'shirt': ('#f2eee6', 'white'), 'pants': '#2e3248', 'shoes': '#3a2a22', 'book': '#2a4a7a', 'page': '#f3ead2'},
)

# ---------------- Mabel: anciana de cojines y farolillos (moño blanco, chal, farol)
CAST['mabel'] = dict(
    name='Doña Mabel', species='human_f', body=dict(h=55, hunch=1, sw=12, ww=10.5, hw=12, leg=16), skin='#ecc0a2', hc='#e6e2e6', hair_kind='white', eyes='#7a6a8a',
    face=dict(eye='old', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='none', locks=0, bun=True, bun_x=3.0, bun_y=0.0, bun_r=3.8, hairline=8.0, cap_lines=(4.0, 7.0, 10.0)),
    top=dict(kind='dress', mat='dress', length='ankle', flare=0.4, folds=3, neck='round'),
    sleeves=dict(kind='long', mat='dress'),
    legs=dict(kind='pants', mat='dress'), feet=dict(kind='shoes', mat='shoes'),
    over=[(capelet, dict(mat='shawl', trim='shawl_t', length=9.0))],
    hold={'n': (5.0, 7.0)}, near=[(lantern, dict(mat='brass', glow='glow'))],
    mats={'dress': '#6a4a7a', 'shawl': '#c8643a', 'shawl_t': '#f0c060', 'shoes': '#4a3426'},
)


# ================================================================== poses (personalidad, como la referencia)
# Cada personaje se para a su manera: peso en una pierna, brazos separados del cuerpo haciendo algo suyo, el torso
# girado 3/4 y a veces inclinado. Estas claves pisan las de la ficha (el diseño de cada uno queda igual).
POSES = {
    'bram': dict(stance='wide', turn=0.4, arms={'n': 'shoulder', 'f': 'hip'}, near=[(axe_shoulder, {})], back2=[],
                 stance_mod=dict(lean=-0.5)),
    'elda': dict(stance='prim', turn=0.45, arms={'n': 'wave', 'f': 'book'}, hold={}, near=[], far_front=True,
                 far=[(book, dict(cover='book', page='page', clasp='gold'))]),
    'kit': dict(stance='lunge', turn=0.5, arms={'n': 'hand_out', 'f': 'swing'}, far_front=True, front=[],
                far=[(dagger_hand, {})], free_walk=('n', 'f')),
    'wren': dict(stance='step', turn=0.5, arms={'n': 'hip', 'f': 'point'}, far_front=True, free_walk=('f',),
                 stance_mod=dict(lean=1.0)),
    'panadera': dict(stance='easy', turn=0.45, arms={'n': 'hip', 'f': 'shoulder'}, hold={}, near=[], far_front=True,
                     far=[(bread, {})], stance_mod=dict(lean=-0.5, sway=-0.5)),
    'anciano': dict(stance='prim', turn=0.5, arms={'n': 'behind', 'f': 'lean_on'}, hold={},
                    far=[(staff, dict(wood='wood', kind='cane', top=9))], stance_mod=dict(lean=1.5)),
    'sylwen': dict(stance='easy', turn=0.45, arms={'n': 'staff', 'f': 'hip'}, near=[(bow_hand, {})],
                   back2=[(quiver, dict(mat='leather', fletch='fletch'))]),
    'nyra': dict(stance='easy_f', turn=0.5, arms={'n': 'hand_out', 'f': 'hip'}, near=[(coin_hand, {})],
                 stance_mod=dict(lean=1.0)),
    'ragnar': dict(stance='wide', turn=0.4, arms={'n': 'cross', 'f': 'cross'}, far_front=True, stance_mod=dict(lean=-0.8)),
    'isolde': dict(stance='wide', turn=0.45, arms={'n': 'hilt', 'f': 'fist'}, far_front=True,
                   front=[(sword_hip, dict(hilt='gold', sheath='sheath', side='n'))]),
    'roxa': dict(stance='easy_f', turn=0.5, arms={'n': 'brim', 'f': 'staff_out'}, hold={}, stance_mod=dict(lean=0.8)),
    'anselmo': dict(stance='prim', turn=0.45, arms={'n': 'wave', 'f': 'staff_out'}, hold={}),
    'marta': dict(stance='easy', turn=0.45, arms={'n': 'basket', 'f': 'wave'}, hold={}, stance_mod=dict(lean=-0.5)),
    'lupo': dict(stance='easy', turn=0.45, arms={'n': 'shoulder', 'f': 'hip'}, hold={}, stance_mod=dict(lean=-0.5)),
    'vianne': dict(stance='prim', turn=0.45, arms={'n': 'chin'}),
    'hassim': dict(stance='step', turn=0.5, arms={'n': 'hand_out', 'f': 'chest'}, far_front=True),
    'pip': dict(stance='kid', turn=0.45, arms={'n': 'hip', 'f': 'wave'}, hold={}, far_front=True, near=[],
                far=[(wooden_sword, {})], stance_mod=dict(lean=0.8)),
    'grumm': dict(stance='wide', turn=0.4, arms={'n': 'lantern', 'f': 'hip'}, hold={}),
    'zaria': dict(stance='easy_f', turn=0.5, arms={'n': 'waist', 'f': 'waist'}, far_front=True, stance_mod=dict(lean=0.6)),
    'fizz': dict(stance='step', turn=0.45, arms={'n': 'raise_flask', 'f': 'hip'}, hold={}, stance_mod=dict(lean=0.8)),
    'brann': dict(stance='wide', turn=0.4, arms={'n': 'hip', 'f': 'staff_out'}, hold={}),
    'borin': dict(stance='easy', turn=0.45, arms={'n': 'raise_flask', 'f': 'hip'}, hold={}),
    'ilse': dict(stance='easy', turn=0.45, arms={'n': 'basket', 'f': 'hand_out'}, hold={}, far_front=True,
                 far=[(sprig_hand, dict(flower='flower1'))]),
    'tobias': dict(stance='easy', turn=0.45, arms={'n': 'book', 'f': 'chin'}, hold={}, far_front=True),
    'mabel': dict(stance='prim', turn=0.5, arms={'n': 'lantern', 'f': 'behind'}, hold={}),
}
for _k, _v in POSES.items():
    CAST[_k].update(_v)


# ================================================================== hoja del elenco
ORDER = ['alquimista', 'lirien', 'bram', 'elda', 'kit', 'aldric', 'wren', 'granjero', 'panadera', 'anciano', 'miga',
         'sylwen', 'nyra', 'ragnar', 'isolde', 'roxa', 'anselmo', 'marta', 'lupo', 'vianne', 'hassim', 'pip', 'grumm',
         'zaria', 'fizz', 'brann', 'borin', 'ilse', 'tobias', 'mabel']
TITLES = {
    'alquimista': ('La alquimista', 'la jugadora'), 'lirien': ('Lirien', 'maga elfa'), 'bram': ('Bram', 'guerrero enano'),
    'elda': ('Sor Elda', 'sacerdotisa'), 'kit': ('Kit', 'ladrona mediana'), 'aldric': ('Sir Aldric', 'caballero novato'),
    'wren': ('Wren', 'exploradora'), 'granjero': ('Tomás', 'granjero'), 'panadera': ('Greta', 'panadera'),
    'anciano': ('Don Ruperto', 'vecino jubilado'), 'miga': ('Miga', 'la gata de la tienda'),
    'sylwen': ('Sylwen', 'arquera elfa'), 'nyra': ('Nyra', 'comerciante gata'), 'ragnar': ('Ragnar', 'mercenario lobo'),
    'isolde': ('Isolde', 'capitana'), 'roxa': ('Roxa', 'maga viajera'), 'anselmo': ('Padre Anselmo', 'sacerdote'),
    'marta': ('Marta', 'campesina'), 'lupo': ('Lupo', 'pescador'), 'vianne': ('Lady Vianne', 'dama noble'),
    'hassim': ('Hassim', 'mercader viajero'), 'pip': ('Pip', 'niño del pueblo'), 'grumm': ('Grumm', 'cocinero semiorco'),
    'zaria': ('Zaria', 'viajera demonio'), 'fizz': ('Fizz', 'alquimista gnomo'), 'brann': ('Brann', 'guardia del pueblo'),
    'borin': ('Borin', 'joyero enano'), 'ilse': ('Ilse', 'herbolaria elfa'), 'tobias': ('Tobías', 'librero y tintero'),
    'mabel': ('Doña Mabel', 'cojines y farolillos'),
}


def cast_sheet(res, path, scale=3, cols=10, walkers=('lirien', 'alquimista', 'ragnar', 'miga')):
    from PIL import ImageDraw, ImageFont
    fdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'fonts')
    f_name = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Bold.ttf'), 22)
    f_small = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Medium.ttf'), 16)
    f_title = ImageFont.truetype(os.path.join(fdir, 'AlegreyaSC-Bold.ttf'), 34)
    cw, chh, lab = 64 * scale + 6, 96 * scale, 48
    ids = [i for i in ORDER if i in res]
    rows = (len(ids) + cols - 1) // cols
    head = 64
    walk_rows = (len(walkers) + 1) // 2
    W = cw * cols + 24
    Hh = head + rows * (chh + lab + 8) + 40 + walk_rows * (chh + lab + 8) + 16
    bg = (44, 38, 58, 255)
    im = Image.new('RGBA', (W, Hh), bg)
    d = ImageDraw.Draw(im)
    d.text((14, 12), 'Caldero Nocturno · elenco estilo HD-2D (cuadros de 64x96, quieto, x%d)' % scale, font=f_title, fill=(236, 214, 160))

    def cell(x, y, arr, name=None, sub=None, floor=True):
        d.rectangle((x, y, x + cw - 4, y + chh + lab - 2), fill=(56, 49, 74, 255))
        if floor:
            d.rectangle((x, y + chh - 10, x + cw - 4, y + chh + 2), fill=(66, 58, 86, 255))
        big = Image.fromarray(arr, 'RGBA').resize((64 * scale, 96 * scale), Image.NEAREST)
        im.alpha_composite(big, (x + 1, y))
        if name:
            d.text((x + 6, y + chh + 4), name, font=f_name, fill=(246, 232, 200))
        if sub:
            d.text((x + 6, y + chh + 27), sub, font=f_small, fill=(176, 166, 196))

    for n, cid in enumerate(ids):
        x = 12 + (n % cols) * cw
        y = head + (n // cols) * (chh + lab + 8)
        name, title = TITLES.get(cid, (cid, ''))
        cell(x, y, res[cid][0][0], name, '%s · %s' % (cid, title))
    y0 = head + rows * (chh + lab + 8) + 6
    d.text((14, y0), 'Ciclo de caminar (4 cuadros)', font=f_name, fill=(236, 214, 160))
    y0 += 34
    for k, cid in enumerate(walkers):
        if cid not in res:
            continue
        for i, fr in enumerate(res[cid][1]):
            x = 12 + ((k % 2) * 4 + i) * cw + (k % 2) * 8
            y = y0 + (k // 2) * (chh + lab + 8)
            cell(x, y, fr, TITLES.get(cid, (cid,))[0] if i == 0 else None, 'cuadro %d' % (i + 1))
    im.save(path)
    return path

def build(ids, out=OUT):
    os.makedirs(out, exist_ok=True)
    res = {}
    for cid in ids:
        if cid == 'miga':
            idle, walk = c64cat.frames()
            os.makedirs(OUT_PROPS, exist_ok=True)
            Image.fromarray(c64cat.shop_sheet(), 'RGBA').save(f'{OUT_PROPS}/cat.png')
        else:
            idle, walk = frames(CAST[cid])
        Image.fromarray(np.concatenate(idle, axis=1), 'RGBA').save(f'{out}/{cid}_idle.png')
        Image.fromarray(np.concatenate(walk, axis=1), 'RGBA').save(f'{out}/{cid}_walk.png')
        res[cid] = (idle, walk)
    return res


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--') and not a.endswith('.png')]
    ids = args or (list(CAST) + ['miga'])
    res = build(ids)
    if '--cast-sheet' in sys.argv:
        k = sys.argv.index('--cast-sheet')
        cast_sheet(res, sys.argv[k + 1])
    if '--sheet' in sys.argv:
        frs = []
        for cid in ids:
            frs += res[cid][0][:1]
        sheet(frs, scale=4, cols=8, path='./prev_cast64.png')
        walks = []
        for cid in ids[:4]:
            walks += res[cid][1]
        sheet(walks, scale=4, cols=4, path='./prev_walk64.png')
    print('ok', len(ids))
