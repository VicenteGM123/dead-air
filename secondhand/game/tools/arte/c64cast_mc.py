"""Midnight Cauldron's cast for the c64 kit (64x96, HD-2D), kept as REFERENCE EXAMPLES of character specs.

--- SS SEED: moved verbatim out of chars64.py (Secondhand Stars does not use these characters). They show how a
spec is written: species, palette, hair, clothes, accessories ('over', 'head', 'back', 'near', 'far'...) and the pose
(stance, arms). Build them only to compare:  python3 chars64.py --mc alquimista bram
"""
from c64core import *
from c64body import *
from c64parts import *
from c64hair import *
from c64acc import *
from c64hat import *

# ================================================================== elenco
CAST = {}

# ---------------- la alquimista (jugadora): pelo rojizo, delantal verde, sombrero de bruja verde azulado
CAST['alquimista'] = dict(
    name='La alquimista', species='human_f', skin='#f0cdb0', hc='#a4482e', eyes='#3f7a4e', stance='easy',
    accent=('potion2', 'berry', 'hat'),
    stance_mod=dict(lean=0.5, sway=-0.5), turn=0.5,
    face=dict(eye='std', mouth='small'),
    # --- R3 ART3: el sombrero aplasta el pelo (volumen 1.4); el pelo cae por debajo del ala
    hair=dict(kind='long', bangs='parted', locks=2, length=31, lock=23, width=0, volume=1.4, tips=5),
    top=dict(kind='dress', mat='blouse', skirt='skirt', length='knee', flare=0.55, folds=3, neck='round'),
    sleeves=dict(kind='rolled', mat='blouse'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron', y_hem=None, trim='apron_t', pockets=True)), (belt, dict(mat='belt', buckle='gold')),
          (belt_vial, dict(liquid='potion2'))],
    head=[(witch_hat, dict(mat='hat', band='band', deco=leaf_sprig('leaf', 'berry'), brim_cast=1, brim_h=3.1))],
    # --- R3 ART3: quieta sin la poción en alto: manos sueltas juntas por delante (tranquila, amable)
    arms={'n': 'clasp', 'f': 'clasp'}, far_front=True, free_walk=('n', 'f'),
    far=[],
    mats={'blouse': '#ece2c8', 'skirt': '#5e3e54', 'apron': '#68904e', 'apron_t': '#46663a', 'tights': '#3a2e44',
          'boots': ('#6a4630', 'leather'), 'hat': '#2e6466', 'band': ('#c8a050', 'metal'), 'berry': ('#d04848', 'gem'),
          'potion2': ('#d86aa8', 'gem'), 'potion': ('#7ad0a0', 'gem'), 'cork': '#9a7048', 'leaf': '#5a8a44'},
)

# ---------------- Lirien: maga elfa (homenaje): coletas bajas plateadas, blanco y oro, capita, bastón con gema roja
CAST['lirien'] = dict(
    name='Lirien', species='elf_s', skin='#f4dccb', hc='#e8e6f0', hair_kind='silver', eyes='#4f9a72', lash='#4a3a52', ears='elf',
    ear_len=10, ear_up=3.2,
    stance='easy_f', stance_mod=dict(lean=1.0), turn=0.45,
    face=dict(eye='calm', mouth='small'), mouth_col='#b87a78',
    # --- R3 ART3: pelo liso pegado a la cabeza (volumen 0.7) con raya al medio: la cabeza ya no se ve grande
    hair=dict(kind='twintails', bangs='centre', locks=2, lock=18.0, tail_len=33, tail_w=1.8, tail_out=2.6, tail_root=15.0,
              tie='gold', volume=0.7, side_len=15.0, part=11.4, crown_x=9.6, crown_y=-0.6, bumpy=0.4),
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
    hair=dict(kind='short', bangs='none', hairline=4.0, volume=1.0),
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
    hair=dict(kind='short', bangs='parted', locks=0, lock=17, hairline=5.5, volume=1.0),
    top=dict(kind='dress', mat='robe', length='floor', flare=0.32, folds=4, trim='blue', front='blue', neck='collar', neck_mat='blue2'),
    sleeves=dict(kind='wide', mat='robe', cuff='blue'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    back=[(veil_back, dict(mat='veil', length=27))],
    head=[(veil, dict(mat='veil', band='blue'))],
    hold={'n': (4.5, 9.0)}, near=[(book, dict(cover='book', page='page', clasp='gold'))],
    mats={'robe': ('#f1eee6', 'white'), 'veil': ('#fbfaf6', 'white'), 'blue': '#4a74c4', 'blue2': '#5f8ad6', 'shoes': '#8c6a52',
          'book': '#a04a3a', 'page': '#f3ead2'}, accent=('book', 'blue'),
)

# ---------------- Kit: ladrona mediana (capucha verde, bufanda roja, descalza)
CAST['kit'] = dict(
    name='Kit', species='halfling', skin='#f2c39c', hc='#7a4f36', eyes='#cf8a2c',
    face=dict(eye='kid', mouth='smile', blush=True, freckles=True),
    hair=dict(kind='short', bangs='curly', locks=1, lock=15, volume=1.0),
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
    hair=dict(kind='short', bangs='short', locks=1, lock=15, volume=1.0, side_len=11.0),
    top=dict(kind='shirt', mat='shirt', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='shirt'),
    legs=dict(kind='pants', mat='denim'), feet=dict(kind='boots', mat='boots', h=0.55),
    over=[(apron, dict(mat='denim', y_hem='hip', width=0.95))],
    head=[(beard, dict(kind='mustache')), (straw_hat, dict(mat='straw', band='band'))],
    arms={'n': 'hip', 'f': 'lean_on'}, free_walk=('n',), stance_mod=dict(lean=1.6, sway=-0.8), turn=0.5,
    far=[(tool_planted, dict(kind='hoe', wood='wood', blade='steel'))],
    mats={'shirt': '#efe8d8', 'denim': '#4a6a9c', 'boots': '#5a3a28', 'straw': '#e8c56c', 'band': '#b04a3a'},
)

# ---------------- Greta: panadera (pañuelo rojo de lunares, delantal; sin pan en la mano: brazos sueltos, ver POSES)
CAST['panadera'] = dict(
    name='Greta', species='human_f', body=dict(sw=13, ww=11, hw=13), skin='#f2c29c', hc='#7a4a2a', eyes='#8a5a3a',
    face=dict(eye='soft', mouth='smile', blush=True),
    hair=dict(kind='short', bangs='parted', locks=1, lock=15, volume=1.0),
    top=dict(kind='dress', mat='dress', skirt='skirt', length='calf', flare=0.45, folds=3, neck='round'),
    sleeves=dict(kind='rolled', mat='dress'),
    legs=dict(kind='pants', mat='skirt'), feet=dict(kind='shoes', mat='shoes'),
    over=[(apron, dict(mat='apron', width=0.9, trim='apron_t'))],
    head=[(kerchief, dict(mat='kerchief', dots='dots'))],
    mats={'dress': '#db8e60', 'skirt': '#6a4a6a', 'apron': ('#f4eee2', 'white'), 'apron_t': '#d8c8b0', 'kerchief': '#cc483e',
          'dots': '#f6ece0', 'shoes': '#5a3a28'},
)

# ---------------- Don Ruperto: vecino jubilado (calvo, barba blanca, bastón)
CAST['anciano'] = dict(
    name='Don Ruperto', species='human_m', body=dict(h=60, hunch=1), skin='#e4b28e', hc='#e8e6e2', hair_kind='white',
    eyes='#6a6a7a', ears='human',
    face=dict(eye='old', mouth=None, brow='old', blush=True),
    # --- R3 ART3: barba larga natural por mechones (tipo Osvald), blanca con sombras frías
    hair=dict(kind='bald', ring_base=2), beard_col='#ecebe6',
    top=dict(kind='dress', mat='robe', length='ankle', flare=0.25, folds=3),
    sleeves=dict(kind='wide', mat='robe'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='shoes', mat='shoes'),
    over=[(belt, dict(mat='rope', buckle=None, h=2))],
    head=[(beard, dict(kind='flowing', len=13))],
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
    hair=dict(kind='long', bangs='swept', locks=1, lock=18, length=32, volume=1.0),
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
    hair=dict(kind='braid_front', bangs='parted', locks=1, lock=16, braid_len=24, tie='ribbon', hairline=5.0, volume=1.4),
    top=dict(kind='dress', mat='robe', length='ankle', flare=0.4, folds=3, trim='trim', neck='collar', neck_mat='collar'),
    sleeves=dict(kind='wide', mat='robe', cuff='trim'),
    legs=dict(kind='pants', mat='robe'), feet=dict(kind='boots', mat='boots', h=0.4),
    over=[(belt, dict(mat='belt', buckle='gold', h=1))],
    head=[(witch_hat, dict(mat='hat', band='hatband', h=19, brim=15.5, bend=-7.0, droop=2.2, brim_cast=1, rim=6.4, brim_h=2.8))],
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
    hair=dict(kind='braid_front', bangs='parted', locks=1, lock=15, braid_len=20, tie='kerchief', volume=1.0),
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
    hair=dict(kind='short', bangs='short', locks=0, volume=1.0, side_len=11.0),
    top=dict(kind='shirt', mat='stripes', length='hip', folds=0, neck='v'),
    sleeves=dict(kind='rolled', mat='stripes'),
    legs=dict(kind='shorts', mat='pants'), feet=dict(kind='sandals', mat='leather'),
    over=[(belt, dict(mat='rope', buckle=None))],
    head=[(beard, dict(kind='short')), (straw_hat, dict(mat='straw', band='band', brim=13.0, h=4.2))],
    hold={'n': (4.0, 6.0)}, near=[(fishing_rod, {})],
    post=[(stripes, dict(mat='stripe'))],
    mats={'stripe': '#4a78b0', 'stripes': '#eef2f6', 'pants': '#5a6a7a', 'rope': '#c8a858', 'straw': '#e6c46a', 'fish': ('#9ab8c8', 'metal'),
          'band': '#3a5a8a'},
)

# ---------------- Vianne: dama noble (vestido rosa, encajes, sombrilla)
CAST['vianne'] = dict(
    name='Lady Vianne', species='human_f', skin='#f8dccb', hc='#f2d27e', eyes='#5a8ad8',
    face=dict(eye='cute', mouth='small', blush=True),
    hair=dict(kind='short', bangs='parted', locks=0, bun=True, bun_x=1.0, bun_y=1.0, bun_r=4.2, ringlets=True),
    top=dict(kind='dress', mat='dress', length='floor', flare=0.75, widen=4.0, folds=5, trim='lace', trim_rows=2, neck='round'),
    sleeves=dict(kind='puff_long', mat='dress', cuff='lace'),
    legs=dict(kind='pants', mat='dress'), feet=dict(kind='shoes', mat='shoes'),
    over=[(belt, dict(mat='sash', buckle='gem', h=2)), (parasol_shaft, dict(pole='gold', handle='gold', tilt=-0.46, reach=27.0))],
    head=[(flower_crown, dict(flowers=('rose', 'lace'), leaf='leaf'))],
    # --- R3 ART3: sombrilla grande al hombro (copa detrás de la cabeza, vara visible desde la mano)
    back=[(parasol_canopy, dict(mat='lace', trim='rose', pole='gold', tilt=-0.46, reach=27.0))],
    near=[(parasol_grip, dict(pole='gold', handle='gold', tilt=-0.46, reach=27.0))],
    mats={'dress': '#c8506e', 'lace': ('#fbf4f6', 'white'), 'sash': '#f0c8d4', 'shoes': '#7a3048', 'rose': '#e8708e',
          'gem': ('#7ad0f0', 'metal')},
)

# ---------------- Hassim: mercader viajero (turbante, abrigo largo, mochila enorme)
CAST['hassim'] = dict(
    name='Hassim', species='human_m', skin='#b07a52', hc='#2a2228', eyes='#5a3a2a', ears='human',
    face=dict(eye='man', mouth='smile', brow='thick', blush=False),
    hair=dict(kind='short', bangs='none', locks=0, volume=1.0),
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
    # --- R3 ART3: pelo revuelto prolijo (mechones grandes en la coronilla y la nuca), flequillo hacia la derecha
    hair=dict(kind='short', bangs='swept', locks=1, lock=13.5, volume=1.6, tousle='boy'),
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
    hair=dict(kind='short', bangs='none', locks=0, volume=0.8, side_len=11.0, hairline=3.0),
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
    hair=dict(kind='short', bangs='short', locks=0, volume=1.0, side_len=10.4),
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
    hair=dict(kind='short', bangs='none', hairline=4.5, volume=1.0),
    top=dict(kind='tunic', mat='tunic', length='thigh', flare=0.25, folds=2, trim='gold'),
    sleeves=dict(kind='long', mat='tunic', cuff='gold'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.6),
    over=[(apron, dict(mat='apron_l', width=0.9, bib=True))],
    # --- R3 ART3: barba por mechones con dos cuentas de oro; gorro bien calado
    head=[(beard, dict(kind='flowing', len=12, beads=((7.8, 0.70), (14.6, 0.62)))), (cap_soft, dict(mat='cap', cuff='cap2')),
          (loupe, dict(mat='gold'))],
    hold={'n': (5.0, 5.0)}, near=[(gem_hold, dict(gem='gem'))],
    mats={'tunic': '#6a3a7a', 'pants': '#4a3a30', 'boots': '#3e2c24', 'cap': '#3c5a8a', 'cap2': '#2e4670', 'gem': ('#40c8e0', 'metal'),
          'apron_l': '#b08050'},
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
    # --- R3 ART3: el libro sujeto con las dos manos delante del pecho (sin la mano levantada junto al velo)
    'elda': dict(stance='prim', turn=0.45, arms={'n': 'chest', 'f': 'book'}, hold={}, near=[], far_front=True,
                 far=[(book, dict(cover='book', page='page', clasp='gold'))]),
    'kit': dict(stance='lunge', turn=0.5, arms={'n': 'hand_out', 'f': 'swing'}, far_front=True, front=[],
                far=[(dagger_hand, {})], free_walk=('n', 'f')),
    'wren': dict(stance='step', turn=0.5, arms={'n': 'hip', 'f': 'point'}, far_front=True, free_walk=('f',),
                 stance_mod=dict(lean=1.0)),
    # --- R3 ART3 (seguimiento, cliente: "no entiendo qué agarra, déjala con brazos normales"): sin pan ni nada en las
    # manos. Quieta: los dos brazos sueltos a los costados, apenas doblados; el cercano es el suelto de siempre y el
    # lejano (hold relativo al hombro: mano, codo) baja por delante del costado y la mano asoma junto a la cadera
    # (detrás del cuerpo no se veía: parecía manca). Caminando: los dos brazos se balancean sueltos (free_walk).
    'panadera': dict(stance='easy', turn=0.45, arms={}, hold={'f': (3.2, 12.1, (1.8, 6.25))}, near=[], far=[],
                     far_front=True, free_walk=('n', 'f'), stance_mod=dict(lean=-0.5, sway=-0.5)),
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
    # --- R3 ART3: sin la mano junto a la cara: cesta en el brazo cercano, el lejano suelto
    'marta': dict(stance='easy', turn=0.45, arms={'n': 'basket'}, hold={}, stance_mod=dict(lean=-0.5)),
    'lupo': dict(stance='easy', turn=0.45, arms={'n': 'shoulder', 'f': 'hip'}, hold={}, stance_mod=dict(lean=-0.5)),
    'vianne': dict(stance='prim', turn=0.45, arms={'n': 'parasol', 'f': 'waist'}, far_front=True),
    'hassim': dict(stance='step', turn=0.5, arms={'n': 'hand_out', 'f': 'chest'}, far_front=True),
    'pip': dict(stance='kid', turn=0.45, arms={'n': 'hip', 'f': 'wave'}, hold={}, far_front=True, near=[],
                far=[(wooden_sword, {})], stance_mod=dict(lean=0.8)),
    'grumm': dict(stance='wide', turn=0.4, arms={'n': 'lantern', 'f': 'hip'}, hold={}),
    'zaria': dict(stance='easy_f', turn=0.5, arms={'n': 'waist', 'f': 'waist'}, far_front=True, stance_mod=dict(lean=0.6)),
    'fizz': dict(stance='step', turn=0.45, arms={'n': 'raise_flask', 'f': 'hip'}, hold={}, stance_mod=dict(lean=0.8)),
    'brann': dict(stance='wide', turn=0.4, arms={'n': 'hip', 'f': 'staff_out'}, hold={}),
    # --- R3 ART3: la gema en alto delante del pecho (la mira con la lupa), la otra mano en la cadera
    'borin': dict(stance='easy', turn=0.45, arms={'n': 'hip', 'f': 'flask'}, hold={}, near=[], far_front=True,
                  far=[(gem_hold, dict(gem='gem'))]),
    'ilse': dict(stance='easy', turn=0.45, arms={'n': 'basket', 'f': 'hand_out'}, hold={}, far_front=True,
                 far=[(sprig_hand, dict(flower='flower1'))]),
    'tobias': dict(stance='easy', turn=0.45, arms={'n': 'book', 'f': 'chin'}, hold={}, far_front=True),
    'mabel': dict(stance='prim', turn=0.5, arms={'n': 'lantern', 'f': 'behind'}, hold={}),
}
for _k, _v in POSES.items():
    CAST[_k].update(_v)



ORDER = ['alquimista', 'lirien', 'bram', 'elda', 'kit', 'aldric', 'wren', 'granjero', 'panadera', 'anciano', 'miga',
         'sylwen', 'nyra', 'ragnar', 'isolde', 'roxa', 'anselmo', 'marta', 'lupo', 'vianne', 'hassim', 'pip', 'grumm',
         'zaria', 'fizz', 'brann', 'borin', 'ilse', 'tobias', 'mabel']
# --- R5 EN-UI: la hoja del elenco (solo para el equipo, no se publica) en inglés, con los nombres del glosario
TITLES = {
    'alquimista': ('The alchemist', 'the player'), 'lirien': ('Lirien', 'elf mage'), 'bram': ('Bram', 'dwarf warrior'),
    'elda': ('Sister Elda', 'priestess'), 'kit': ('Kit', 'halfling thief'), 'aldric': ('Sir Aldric', 'rookie knight'),
    'wren': ('Wren', 'explorer'), 'granjero': ('Tomas', 'farmer'), 'panadera': ('Greta', 'baker'),
    'anciano': ('Mr. Ruperto', 'retired neighbor'), 'miga': ('Miga', 'the shop cat'),
    'sylwen': ('Sylwen', 'elf archer'), 'nyra': ('Nyra', 'catfolk merchant'), 'ragnar': ('Ragnar', 'wolf mercenary'),
    'isolde': ('Dame Isolde', 'knight captain'), 'roxa': ('Roxa', 'wandering mage'), 'anselmo': ('Father Anselmo', 'temple priest'),
    'marta': ('Marta', 'mother of five'), 'lupo': ('Lupo', 'fisherman'), 'vianne': ('Lady Vianne', 'noble lady'),
    'hassim': ('Hassim', 'traveling merchant'), 'pip': ('Pip', 'errand boy'), 'grumm': ('Grumm', 'half-orc cook'),
    'zaria': ('Zaria', 'demon-kin traveler'), 'fizz': ('Fizz', 'gnome alchemist'), 'brann': ('Brann', 'town guard'),
    'borin': ('Borin', 'dwarf jeweler'), 'ilse': ('Ilse', 'elf herbalist'), 'tobias': ('Tobias', 'books and inks'),
    'mabel': ('Mrs. Mabel', 'pretty things for the home'),
}


