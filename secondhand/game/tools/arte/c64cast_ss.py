"""Secondhand Stars: el elenco para el kit c64 (chars64.py). --- SS SEED: FICHAS DE RELLENO.

Son siluetas provisionales hechas con el kit tal cual (gente de ropa de trabajo, colores del puerto del desierto),
para que la semilla y CORE tengan personajes que caminen mientras ART dibuja los diseños reales del brief (Hornback,
Quill de cuatro brazos, Glimmerfolk, Burrower, Dune Raker, los bots...). ART reemplaza este archivo (o las hojas de
assets/chars) con los mismos ids. Kettle no sale de aquí: el kit solo hace humanoides; su relleno lo dibuja
ss_placeholders.py.

Cómo se escribe una ficha: ver c64cast_mc.py (los de Midnight Cauldron) y el docstring de chars64.py.
"""
from c64core import *
from c64body import *
from c64parts import *
from c64hair import *
from c64acc import *
from c64hat import *

SHEET_TITLE = 'Secondhand Stars · SEED placeholder cast (64x96 frames, idle, x%d)'
CAST = {}

# ---------------- Nell (jugadora): mecánica joven, coleta, gafas de taller en la frente, peto naranja óxido
CAST['nell'] = dict(
    name='Nell', species='human_f', skin='#e8b48c', hc='#4a2e26', eyes='#4f7a52', stance='easy',
    face=dict(eye='cute', mouth='smile', blush=True, freckles=True),
    hair=dict(kind='ponytail', bangs='swept', locks=1, lock=15, tail_len=18, tail_w=2.2, tie='leather', volume=1.6),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='overall'), feet=dict(kind='boots', mat='boots', h=0.7),
    over=[(apron, dict(mat='overall', y_hem='hip', width=0.95, pockets=True)), (belt, dict(mat='belt', buckle='brass'))],
    head=[(goggles, dict(mat='brass', lens='lens'))],
    arms={'n': 'hip', 'f': 'hip'}, free_walk=('n', 'f'),
    mats={'shirt': '#e6dcc4', 'overall': '#c0643a', 'boots': ('#5a3c2a', 'leather'), 'lens': '#7cc4d8'},
    accent=('overall',),
)

# ---------------- Gorrum (relleno de un Hornback grande): cuerpo grande, poncho polvoriento
CAST['gorrum'] = dict(
    name='Gorrum', species='orc', skin='#9a8a74', hc='#3a3030', eyes='#c89a40',
    face=dict(eye='man', mouth=None, brow='thick', blush=False),
    hair=dict(kind='short', bangs='none', locks=0, volume=0.8, hairline=3.0),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.25, folds=2),
    sleeves=dict(kind='long', mat='tunic'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(capelet, dict(mat='poncho', trim='poncho_t', length=11.0))],
    stance='wide', turn=0.4, arms={'n': 'hip', 'f': 'hip'},
    mats={'tunic': '#6a5a48', 'pants': '#4a4038', 'boots': '#3a2a22', 'poncho': '#b08a5a', 'poncho_t': '#8a4a3a'},
)

# ---------------- Zib (relleno de un Quill): alto y flaco, chaleco de mensajero, gafas
CAST['zib'] = dict(
    name='Zib', species='elf_s', skin='#c8b07a', hc='#2a6a7a', eyes='#e0a030', ears='human',
    face=dict(eye='man', mouth='small', brow='man', blush=False),
    hair=dict(kind='short', bangs='swept', locks=1, lock=14, spikes=3, spike_big=0.8),
    top=dict(kind='tunic', mat='vest', length='hip', flare=0.2, folds=0, front='brass'),
    sleeves=dict(kind='long', mat='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.8),
    over=[(belt, dict(mat='belt', buckle='steel')), (scarf, dict(mat='scarf'))],
    head=[(goggles, dict(mat='brass', lens='lens'))],
    stance='step', turn=0.5, arms={'n': 'hip', 'f': 'hand_out'}, far_front=True,
    mats={'vest': '#2f7a86', 'shirt': '#e8dcc0', 'pants': '#4a4058', 'boots': '#3a2a22', 'scarf': '#e0a030', 'lens': '#f0c060'},
)

# ---------------- Mother Oona (relleno de una Glimmerfolk): túnica larga y elegante
CAST['oona'] = dict(
    name='Mother Oona', species='elf_f', skin='#d8c8e8', hc='#9a8ad0', eyes='#6ac0c8', ears='human',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='parted', locks=0, lock=17, hairline=5.5, volume=1.0),
    top=dict(kind='dress', mat='robe', length='floor', flare=0.35, folds=4, trim='trim', neck='collar', neck_mat='trim'),
    sleeves=dict(kind='wide', mat='robe', cuff='trim'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    stance='prim', turn=0.45, arms={'n': 'chest', 'f': 'chest'}, far_front=True,
    mats={'robe': '#5a4a8a', 'trim': '#e0c070', 'shoes': '#3a2e44'}, accent=('trim',),
)

# ---------------- Pipip (relleno de un Burrower): pequeño minero, casco con lámpara, gafas
CAST['pipip'] = dict(
    name='Pipip', species='gnome', skin='#a88a70', hc='#5a4438', eyes='#2a2a30',
    face=dict(eye='kid', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='none', locks=0, volume=1.0),
    top=dict(kind='tunic', mat='overall', length='hip', flare=0.3, folds=1),
    sleeves=dict(kind='long', mat='shirt'),
    legs=dict(kind='pants', mat='overall'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(belt, dict(mat='belt', buckle='brass', h=1))],
    head=[(helmet, dict(mat='hat', kind='kettle')), (goggles, dict(mat='brass', lens='lens'))],
    stance='kid', turn=0.45, arms={'n': 'hip', 'f': 'wave'}, far_front=True,
    mats={'overall': '#7a6a4a', 'shirt': '#c8a070', 'boots': '#3a2a22', 'hat': ('#e0b030', 'metal'), 'lens': '#f8e0a0'},
)

# ---------------- Rook Varga: piloto curtido, chaqueta de vuelo
CAST['rook'] = dict(
    name='Rook Varga', species='human_m', skin='#c89070', hc='#5a4a40', eyes='#4a6a8a', ears='human',
    face=dict(eye='man', mouth='small', brow='man', blush=False),
    hair=dict(kind='short', bangs='swept', locks=1, lock=15, volume=1.4),
    top=dict(kind='tunic', mat='jacket', length='hip', flare=0.2, folds=1, front='brass', neck='collar', neck_mat='collar'),
    sleeves=dict(kind='long', mat='jacket', cuff='collar'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.8),
    over=[(belt, dict(mat='belt', buckle='steel'))],
    head=[(beard, dict(kind='short'))],
    stance='wide', turn=0.45, arms={'n': 'hip', 'f': 'hip'},
    mats={'jacket': ('#7a4a2e', 'leather'), 'collar': '#d8c8a8', 'pants': '#3e4a5a', 'boots': '#2e2420'},
)

# ---------------- Clatter (relleno de un bot de servicio alto): todo de metal gastado
CAST['clatter'] = dict(
    name='Clatter', species='human_m', body=dict(sw=12.5, ww=9.5, hw=10.5), skin='#9aa0a4', hc='#5a6066', hair_kind='silver',
    eyes='#f0c040', ears='human',
    face=dict(eye='man', mouth=None, brow='man', blush=False),
    hair=dict(kind='short', bangs='none', locks=0, volume=0.6, hairline=6.0),
    top=dict(kind='tunic', mat='plate', length='hip', flare=0.1, folds=0),
    sleeves=dict(kind='armor', mat='plate'),
    legs=dict(kind='pants', mat='plate2'), feet=dict(kind='greaves', mat='plate', h=0.9),
    head=[(helmet, dict(mat='shade', kind='kettle'))],
    stance='prim', turn=0.45, arms={'n': 'hip', 'f': 'hip'},
    mats={'plate': ('#a8a29a', 'metal'), 'plate2': ('#7a766e', 'metal'), 'shade': ('#c87a3a', 'metal')},
)

# ---------------- Raker (relleno de un Dune Raker): sombrero de ala ancha, delantal de herramientas, mochila de chatarra
CAST['raker'] = dict(
    name='Raker', species='human_m', skin='#8aa070', hc='#4a4030', eyes='#e0c040', ears='human',
    face=dict(eye='smile', mouth='grin', brow='man', blush=False),
    hair=dict(kind='short', bangs='none', locks=0, volume=0.8),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron', y_hem='hip', width=0.9, pockets=True))],
    head=[(straw_hat, dict(mat='hat', band='band'))],
    back=[(backpack, dict(mat='pack', strap='leather', rolled='rug', pot='pot'))],
    stance='easy', turn=0.45, arms={'n': 'hip', 'f': 'wave'}, far_front=True,
    mats={'shirt': '#c8b890', 'pants': '#5a4a3a', 'boots': '#3a2a22', 'apron': '#7a5a3a', 'hat': '#b0905a', 'band': '#5a3a2a',
          'pack': '#6a5a48', 'rug': '#9a6a3a', 'pot': ('#a8a29a', 'metal')},
)

# ---------------- Mags: vendedora de piezas, robusta, visor de soldar levantado (casco), delantal de cuero
CAST['mags'] = dict(
    name='Mags', species='dwarf', skin='#dca07e', hc='#8a3a2a', eyes='#4a6a5a',
    face=dict(eye='soft', mouth='smile', brow='thick', blush=True),
    hair=dict(kind='short', bangs='none', hairline=4.5, volume=1.0),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.25, folds=1),
    sleeves=dict(kind='rolled', mat='tunic'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron_l', width=0.9, bib=True))],
    head=[(helmet, dict(mat='visor', kind='kettle'))],
    stance='wide', turn=0.45, arms={'n': 'hip', 'f': 'hip'},
    mats={'tunic': '#4a6a7a', 'pants': '#3e3a36', 'boots': '#2e2420', 'apron_l': ('#6a4a32', 'leather'), 'visor': ('#5a5e66', 'metal')},
)

ORDER = ['nell', 'gorrum', 'zib', 'oona', 'pipip', 'rook', 'clatter', 'raker', 'mags']
TITLES = {
    'nell': ('Nell', 'the player (placeholder)'), 'gorrum': ('Gorrum', 'Hornback (placeholder)'),
    'zib': ('Zib', 'Quill (placeholder)'), 'oona': ('Mother Oona', 'Glimmerfolk (placeholder)'),
    'pipip': ('Pipip', 'Burrower (placeholder)'), 'rook': ('Rook Varga', 'pilot (placeholder)'),
    'clatter': ('Clatter', 'service bot (placeholder)'), 'raker': ('Raker', 'Dune Raker (placeholder)'),
    'mags': ('Mags', 'parts seller (placeholder)'),
}
WALKERS = ('nell', 'zib')
