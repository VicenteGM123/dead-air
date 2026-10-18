"""Cuerpos por especie, poses (quieto / caminar) y cabezas con anclas para el generador 64x96.

Estilo Octopath Traveler (HD-2D): unas 2,5 cabezas de alto. Un adulto mide 66-72 px con una cabeza (con pelo)
de 25-29 px, tan ancha como los hombros; torso corto (el cinturón a ~60 % desde arriba), piernas cortas y firmes
(~30 % del alto) con botas grandes. Enanos, medianos, gnomos y niños: 46-58 px y cabeza aún más grande.
Vista 3/4 de frente mirando a la derecha: el lado cercano (hombro, pierna) queda a la izquierda.

Postura (quieto): nadie está de pie como una columna. Cada personaje elige una 'stance' (peso en una pierna,
cadera inclinada, la otra rodilla suelta, pies separados con las puntas hacia fuera) y poses de brazos con nombre.
Caminar: 4 cuadros (contacto, paso, contacto, paso) con zancada de verdad, brazos contrarios y 1 px de rebote.
"""
import math
from c64core import *

GROUND = 91      # última fila de las suelas (pie cercano)
CX = 32          # centro del cuerpo (la mitad del cuadro)

# ------------------------------------------------------------------ especies
# h: suelo -> cima del cráneo (el pelo suma 3-4 px), head: plantilla de cabeza, neck: alto del cuello,
# sw/ww/hw: ancho de hombros / cintura / cadera, leg: alto de la articulación de la cadera sobre el suelo,
# waist: dónde cae la cintura entre hombros (0) y cadera (1), ua/fa: brazo y antebrazo, ar: radio del brazo,
# tr/sr: radios de muslo / canilla, foot: largo del pie, hipx: media separación de las caderas, chest: busto
SPECIES = {
    # pasada 4: adultos de 60-64 px (cabeza con pelo de 22-24 px de alto y ~20 de ancho), cuerpos delgados:
    # hombros del ancho de la cabeza, brazos de 3 px, piernas de 3-4 px.
    'human_f': dict(h=59, head='adult_f', neck=1, sw=12, ww=9, hw=11, leg=18, waist=0.70, ua=6.5, fa=6.0, ar=1.6,
                    tr=1.9, sr=1.6, foot=6, hipx=2.4, chest=1),
    'human_m': dict(h=61, head='adult_m', neck=1, sw=14, ww=11, hw=12, leg=19, waist=0.70, ua=7.0, fa=6.5, ar=1.8,
                    tr=2.1, sr=1.8, foot=7, hipx=2.7, chest=0),
    'elf_f':   dict(h=60, head='adult_f', neck=1, sw=11.5, ww=8.5, hw=10.5, leg=19, waist=0.70, ua=6.5, fa=6.0, ar=1.5,
                    tr=1.8, sr=1.5, foot=6, hipx=2.3, chest=1),
    'elf_s':   dict(h=56, head='adult_f', neck=1, sw=11, ww=8.5, hw=10, leg=17, waist=0.70, ua=6.0, fa=5.5, ar=1.5,
                    tr=1.8, sr=1.5, foot=6, hipx=2.2, chest=0),
    'dwarf':   dict(h=45, head='dwarf', neck=0, sw=17, ww=15, hw=14, leg=11, waist=0.66, ua=5.5, fa=5.0, ar=2.0,
                    tr=2.4, sr=2.1, foot=7, hipx=2.9, chest=1),
    'halfling': dict(h=44, head='child', neck=0, sw=11, ww=9.5, hw=10.5, leg=12, waist=0.66, ua=5.5, fa=5.0, ar=1.5,
                     tr=1.8, sr=1.6, foot=5, hipx=2.1, chest=0),
    'child':   dict(h=42, head='child', neck=0, sw=10.5, ww=9, hw=10, leg=12, waist=0.66, ua=5.0, fa=5.0, ar=1.4,
                    tr=1.7, sr=1.5, foot=5, hipx=2.0, chest=0),
    'gnome':   dict(h=40, head='gnome', neck=0, sw=11, ww=11, hw=11, leg=9, waist=0.62, ua=5.0, fa=4.5, ar=1.6,
                    tr=1.9, sr=1.7, foot=5, hipx=2.1, chest=1),
    'orc':     dict(h=66, head='orc', neck=1, sw=18, ww=16, hw=15, leg=20, waist=0.68, ua=8.0, fa=7.5, ar=2.3,
                    tr=2.6, sr=2.3, foot=8, hipx=3.2, chest=2),
    'wolf':    dict(h=63, head='adult_m', neck=1, sw=15, ww=11, hw=12, leg=20, waist=0.70, ua=7.5, fa=7.0, ar=1.9,
                    tr=2.2, sr=1.9, foot=7, hipx=2.8, chest=1),
}

# ------------------------------------------------------------------ cabezas
# K piel; anclas (también piel): 1 ojo cercano (columna clara, primera fila del ojo), 2 ojo lejano (ídem), 3 boca,
# 6 oreja, 7 nariz. El párpado va en la fila de encima de 1 y 2 (queda bajo el flequillo).
# Pasada 4: cráneos chicos (16-19 px de ancho) con la cara grande respecto de la cabeza: ojos al ~60 % del alto,
# separados 3 px, la cara visible de ~11 px de ancho.
HEADS = {}


def _head(name, art):
    rows = art.strip('\n').split('\n')
    anchors = {}
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch.isdigit():
                anchors[int(ch)] = (x, y)
    HEADS[name] = dict(art='\n'.join(r.translate(str.maketrans('1234567', 'KKKKKKK')) for r in rows),
                       w=max(len(r) for r in rows), h=len(rows), a=anchors)


# 3/4 de frente mirando a la derecha: cráneo redondo, barbilla a la derecha del centro.
_head('adult_f', """
.....KKKKKK.....
...KKKKKKKKKK...
..KKKKKKKKKKKK..
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKK6KKK1KKKK2KKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
.KKKKKKKKKK7KKKK
.KKKKKKKKKKKKKK.
..KKKKKKKK3KKKK.
....KKKKKKKKKK..
......KKKKKKK...
""")

_head('adult_m', """
.....KKKKKKK.....
...KKKKKKKKKKK...
..KKKKKKKKKKKKK..
.KKKKKKKKKKKKKKK.
.KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKK6KKK1KKKK2KKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
.KKKKKKKKKK7KKKKK
.KKKKKKKKKKKKKKKK
..KKKKKKKK3KKKKK.
....KKKKKKKKKKKK.
......KKKKKKKK...
""")

_head('child', """
.....KKKKKK.....
...KKKKKKKKKK...
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKK.
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
KKK6KKK1KKKK2KKK
KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKK
.KKKKKKKKK7KKKKK
.KKKKKKKKK3KKKK.
...KKKKKKKKKKK..
.....KKKKKKKK...
""")

_head('dwarf', """
.....KKKKKKK.....
...KKKKKKKKKKK...
.KKKKKKKKKKKKKKK.
.KKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKK6KKK1KKKK2KKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKK
KKKKKKKKKKKK7KKKK
KKKKKKKKKKKKKKKKK
.KKKKKKKKKK3KKKKK
..KKKKKKKKKKKKKK.
....KKKKKKKKKK...
""")

_head('gnome', """
....KKKKKKK....
..KKKKKKKKKKK..
.KKKKKKKKKKKKK.
.KKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
KKK6KK1KKKK2KKK
KKKKKKKKKKKKKKK
KKKKKKKKKKKKKKK
.KKKKKKKKK7KKKK
.KKKKKKKKK3KKK.
...KKKKKKKKKK..
.....KKKKKKK...
""")

_head('orc', """
......KKKKKKK......
....KKKKKKKKKKK....
..KKKKKKKKKKKKKKK..
.KKKKKKKKKKKKKKKKK.
.KKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
KKK6KKKK1KKKK2KKKKK
KKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKK
.KKKKKKKKKKKK7KKKKK
.KKKKKKKKKKKKKKKKKK
..KKKKKKKKKK3KKKKK.
...KKKKKKKKKKKKKKK.
.....KKKKKKKKKKKK..
.......KKKKKKKK....
""")


# ------------------------------------------------------------------ posturas (quieto)
# an/af: x del tobillo cercano / lejano respecto de su cadera; ln/lf: tobillo levantado (px; talón al aire);
# tn/tf: hacia dónde apunta el pie (+1 derecha, -1 izquierda, 0 de frente); kn/kf: hacia dónde se dobla la rodilla
# (+1 derecha, -1 izquierda); tilt: cadera cercana más alta (+) o lejana (-); lean: hombros desplazados en x;
# sway: cadera desplazada en x (el peso se va hacia la pierna de apoyo).
STANCES = {
    # --- R3 ART3: los pies quietos van SIEMPRE apoyados (nada de talón levantado: se leía como una cuña rara) y la
    # punta es continua (-1..1): el pie cercano apunta casi a la cámara (corto, redondo), el lejano hacia la derecha.
    # peso en la pierna cercana; la lejana suelta, rodilla hacia dentro y el pie abierto a la derecha
    'easy':   dict(an=0.5, af=4.0, ln=0, lf=0, tn=-0.45, tf=0.75, kn=1, kf=-1, tilt=1, lean=-0.5, sway=-0.5),
    # peso en la pierna lejana; la cercana suelta y adelantada, pie abierto a la izquierda
    'easy_f': dict(an=-3.5, af=0.0, ln=0, lf=0, tn=-0.6, tf=0.7, kn=1, kf=1, tilt=-1, lean=0.5, sway=0.5),
    # firme, pies bien separados (guerreros, guardias)
    'wide':   dict(an=-3.5, af=4.0, ln=0, lf=0, tn=-0.7, tf=0.85, kn=-1, kf=1, tilt=0, lean=0, sway=0),
    # recogida (faldas largas, gente mayor): pies algo separados, puntas abiertas
    'prim':   dict(an=-1.5, af=2.5, ln=0, lf=0, tn=-0.35, tf=0.6, kn=-1, kf=1, tilt=0, lean=0, sway=0),
    # un pie adelante hacia la derecha (en marcha, decidida)
    'step':   dict(an=3.5, af=-1.0, ln=0, lf=0, tn=0.85, tf=0.6, kn=1, kf=1, tilt=0, lean=0.5, sway=0.5),
    # niño inquieto: piernas abiertas, una rodilla doblada
    'kid':    dict(an=-3.0, af=3.5, ln=0, lf=0, tn=-0.6, tf=0.8, kn=-1, kf=-1, tilt=1, lean=0, sway=0),
    # estocada agachada: pie lejano adelante (derecha), cercano atrás, cadera baja, rodillas dobladas, torso adelante
    'lunge':  dict(an=-5.5, af=5.0, ln=1, lf=0, tn=-0.8, tf=0.9, kn=-1, kf=1, tilt=0, lean=2.5, sway=0.5, crouch=4, kmax=3.2),
    # agachada / al acecho: pies abiertos, rodillas afuera
    'crouch': dict(an=-4.0, af=4.0, ln=0, lf=0, tn=-0.7, tf=0.8, kn=-1, kf=1, tilt=0, lean=1.0, sway=0, crouch=3, kmax=2.6),
}


# ------------------------------------------------------------------ pose
# gestos de la pose quieta que al caminar se sueltan (el brazo se balancea; lo que tenga en la mano va con ella)
WALK_FREE = ('wave', 'raise_flask', 'chin', 'shade', 'point', 'swing', 'hand_out', 'brim', 'fist')


class Pose:
    """kind 'idle' (2 cuadros: respira) o 'walk' (4 cuadros: contacto, paso, contacto, paso)."""

    def __init__(self, kind, i):
        self.kind, self.i = kind, i
        if kind == 'idle':
            self.bob = 0                  # las piernas y la cadera quietas
            self.breath = [0, 1][i]       # +1 = hombros, pecho y cabeza bajan 1 px
            self.step = None
            self.swing = 0.0
            self.lag = [0, 1][i]          # puntas de pelo / tela: se mecen
            self.sway = 0
        else:
            self.bob = [0, -1, 0, -1][i]  # en el paso el cuerpo sube 1 px
            self.breath = 0
            self.step = i
            self.swing = [-1.0, 0.0, 1.0, 0.0][i]   # brazo cercano: -1 atrás, +1 adelante
            self.lag = [0, 1, 0, 1][i]
            self.sway = -1                           # al caminar el pelo y la capa van hacia atrás


class Body:
    def __init__(self, spec, pose):
        d = dict(SPECIES[spec['species']])
        d.update(spec.get('body', {}))
        self.d = d
        self.pose = pose
        self.spec = spec
        st = dict(STANCES[spec.get('stance', 'easy')])
        st.update(spec.get('stance_mod', {}))
        if pose.kind == 'walk':
            st.update(lean=0.5, sway=0.0, tilt=0)
        self.st = st
        self.G = GROUND
        hd = HEADS[d['head']]
        self.head = hd
        hunch = d.get('hunch', 0)
        bob, br = pose.bob, pose.breath
        self.cx = CX + d.get('dx', 0)                     # centro de la cadera
        self.cx_sh = self.cx + st['lean'] + hunch * 0.5     # centro de los hombros
        top = GROUND - d['h'] + 1
        self.crouch = crouch = st.get('crouch', 0) if pose.kind == 'idle' else 0
        self.top = top + bob + br + crouch
        self.hx = int(round(self.cx_sh - hd['w'] / 2.0 + d.get('hdx', 0.5) + hunch))
        self.hy = self.top
        self.chin = self.hy + hd['h'] - 1
        self.y_sh = self.chin + 1 + d['neck']
        self.hip_y = GROUND - d['leg'] + bob + crouch
        self.y_w = self.y_sh + (self.hip_y - self.y_sh) * d.get('waist', 0.7)
        if br:
            self.y_w += 0.5
        # giro del cuerpo hacia la derecha (3/4): 0 = de frente, 1 = muy girado. El hombro y la cadera lejanos
        # se esconden detrás del torso, que se ve un poco más angosto.
        turn = st.get('turn', spec.get('turn', d.get('turn', 0.45)))
        if pose.kind == 'walk':
            turn = max(turn, 0.6)
        self.turn = turn
        sw, ww, hw = d['sw'] * (1 - 0.10 * turn), d['ww'] * (1 - 0.06 * turn), d['hw'] * (1 - 0.06 * turn)
        self.sw, self.ww, self.hw = sw, ww, hw
        cs = self.cx_sh
        # hombros: el cercano (izquierda) delante, el lejano (derecha) detrás y algo escondido
        self.sh_n = (cs - sw / 2 + 1.6, self.y_sh + 1.8)
        self.sh_f = (cs + sw / 2 - 1.4 - 2.4 * turn, self.y_sh + 1.8 + 0.4 * turn)
        cxh = self.cx + st['sway']
        self.cx_hip = cxh
        tilt = st['tilt']
        hx_ = d['hipx'] * (0.6 if pose.kind == 'walk' else 1.0)
        self.hip_n = (cxh - hx_, self.hip_y - 0.5 * tilt)
        self.hip_f = (cxh + hx_ * (1 - 0.30 * turn), self.hip_y + 0.5 * tilt)
        self._legs(pose)
        self._arms(pose, spec)

    # -- piernas
    def _legs(self, pose):
        d = self.d
        st = self.st
        G = self.G
        ah = 2.5                                   # alto del tobillo sobre la suela
        hn, hf = self.hip_n, self.hip_f
        rest = (G - ah) - (GROUND - d['leg'])      # distancia cadera -> tobillo de pie y quieto
        self.l1 = rest * 0.5 + 0.35
        self.l2 = rest * 0.5 + 0.35
        s = max(2.0, round(d['leg'] * 0.20))       # media zancada
        lift = max(2.0, round(d['leg'] * 0.13))
        if pose.step is None:
            # (x del tobillo, suelo de ese pie, levantado, punta, rodilla)
            an = (hn[0] + st['an'], G, st['ln'], st['tn'], st['kn'])
            af = (hf[0] + st['af'], G - 1, st['lf'], st['tf'], st['kf'])
        else:
            # al caminar el cuerpo se ve más de perfil: los pies se mueven a lo largo de x alrededor del centro
            k = pose.step
            c = self.cx_hip
            s = max(3.0, round(d['leg'] * 0.25))      # media zancada: pies a 2*s en el contacto
            lift = max(2.0, round(d['leg'] * 0.15))
            if k == 0:     # contacto: pierna cercana adelante (talón), lejana atrás (punta)
                an = (c + s - 0.5, G, 0, 1, 1)
                af = (c - s + 0.5, G - 1, 2, 1, 1)
            elif k == 1:   # paso: cercana apoyada debajo, lejana pasa levantada con la rodilla adelante
                an = (c - 1.0, G, 0, 1, 1)
                af = (c + 1.5, G - 1, lift, 1, 1)
            elif k == 2:   # contacto: lejana adelante, cercana atrás
                af = (c + s + 0.5, G - 1, 0, 1, 1)
                an = (c - s - 0.5, G, 2, 1, 1)
            else:          # paso: lejana apoyada, cercana pasa levantada
                af = (c - 0.5, G - 1, 0, 1, 1)
                an = (c + 1.0, G, lift, 1, 1)
        self.leg = {}
        for side, hip, a in (('n', hn, an), ('f', hf, af)):
            ax, gy, lifted, toe, kdir = a
            ank = (ax, gy - ah - lifted)
            knee = self._knee(hip, ank, kdir, hmax=(3.0 if pose.kind == 'walk' and lifted >= 2 else st.get('kmax', 1.4)))
            self.leg[side] = dict(hip=hip, knee=knee, ank=ank, ground=gy, lift=lifted, toe=toe,
                                  heel=(0 if lifted == 0 else (1 if lifted <= 2 else 2)))
        # --- R3 ART3: en el contacto del paso, el pie de delante apoya el talón (la punta un poco arriba)
        if pose.step == 0:
            self.leg['n']['strike'] = True
        elif pose.step == 2:
            self.leg['f']['strike'] = True

    def _knee(self, hip, ank, kdir=1, hmax=1.6):
        l1, l2 = self.l1, self.l2
        dx, dy = ank[0] - hip[0], ank[1] - hip[1]
        dist = math.hypot(dx, dy)
        mx, my = (hip[0] + ank[0]) / 2, (hip[1] + ank[1]) / 2
        if dist >= l1 + l2 - 0.05:
            return (mx, my)
        # en una vista casi de frente la rodilla doblada apenas se desplaza: se limita el desvío
        h = min(hmax, math.sqrt(max(0.0, l1 * l1 - (dist / 2) ** 2)))
        nx, ny = -dy / dist, dx / dist
        if nx * kdir < 0:
            nx, ny = -nx, -ny
        return (mx + nx * h, my + ny * h)

    # -- brazos
    def _arms(self, pose, spec):
        d = self.d
        ua, fa = d['ua'], d['fa']
        self.arm = {}
        named = dict(spec.get('arms', {}))
        holds = dict(spec.get('hold', {}))
        for side, (sh) in (('n', self.sh_n), ('f', self.sh_f)):
            sw = pose.swing if side == 'n' else -pose.swing
            name = named.get(side)
            h = holds.get(side)
            if pose.kind == 'walk' and (side in spec.get('free_walk', ()) or name in WALK_FREE):
                name, h = None, None
            target = None
            if name is not None:
                target = self._named(side, name, sh)
            elif h is not None:
                target = (sh[0] + h[0], sh[1] + h[1], h[2] if len(h) > 2 else 'back')
            if target is not None:
                tx, ty, elbow = target
                if pose.kind == 'walk':
                    tx += 0.6 * sw
                if elbow == 'hang':
                    el = (sh[0] + (0.6 if side == 'n' else -0.4), sh[1] + ua * 0.85)
                elif isinstance(elbow, tuple):
                    el = (sh[0] + elbow[0], sh[1] + elbow[1])
                else:
                    el = self._elbow(sh, (tx, ty), ua, fa, elbow, side)
                self.arm[side] = dict(sh=sh, el=el, hand=(tx, ty), held=True, name=name)
                continue
            # brazo suelto: cuelga un poco separado del cuerpo, el codo algo doblado; al caminar se balancea
            base = -10.0 if side == 'n' else 12.0
            ang = math.radians(base + 24.0 * sw)
            bend = math.radians(10.0 + (18.0 if sw > 0 else 0.0))
            if side == 'f':
                bend = -bend * 0.6
            el = (sh[0] + math.sin(ang) * ua, sh[1] + math.cos(ang) * ua)
            hand = (el[0] + math.sin(ang + bend) * fa, el[1] + math.cos(ang + bend) * fa)
            self.arm[side] = dict(sh=sh, el=el, hand=hand, held=False, name=None)

    def _named(self, side, name, sh):
        """Poses de brazo con nombre -> (x, y) absolutos de la mano y cómo va el codo. Los desplazamientos desde el
        hombro y los codos se escalan con el largo del brazo (k = 1 para un brazo de 8 px)."""
        n = side == 'n'
        k = self.d['ua'] / 8.0
        cs, cx = self.cx_sh, self.cx_hip
        ysh, yw, yh = self.y_sh, self.y_w, self.hip_y

        def S(dx, dy, el):
            """mano a (dx, dy) del hombro; codo el (tupla relativa al hombro) o un modo."""
            if isinstance(el, tuple):
                el = (el[0] * k, el[1] * k)
            return (sh[0] + dx * k, sh[1] + dy * k, el)

        def A(x, y, el):
            """mano en un punto absoluto del cuerpo."""
            if isinstance(el, tuple):
                el = (el[0] * k, el[1] * k)
            return (x, y, el)

        if name == 'hip':          # mano en la cadera, codo bien afuera (la silueta se abre)
            if n:
                return A(cx - self.hw / 2 + 0.5, yw + 1.0, (-5.5, 4.5))
            return A(cx + self.hw / 2 - 0.5, yw + 1.0, (5.5, 4.5))
        if name == 'hilt':         # mano cercana sobre la empuñadura de la espada (cadera cercana)
            return A(cx - self.hw / 2 + 2.0, yw - 2.0, (-5.0, 5.0))
        if name == 'raise_flask':  # frasco en alto junto a la cara, mirándolo: brazo separado del cuerpo
            hx = self.hx + self.head['w']
            if n:
                return A(self.hx - 2.5, self.hy + 10.0, (-6.0, 2.5))
            return A(hx + 3.0, self.hy + 12.5, (6.0, 4.0))
        if name == 'hand_out':     # mano tendida hacia delante / afuera, palma arriba (ofreciendo)
            return S(-6.5, (yw - 1.0 - sh[1]) / k, (-3.0, 6.0)) if n else S(9.0, (yw - 2.0 - sh[1]) / k, (3.5, 6.5))
        if name == 'staff_out':    # vara apoyada en el suelo, separada del cuerpo, brazo casi extendido
            return S(-5.5, 9.0, (-3.0, 5.0)) if n else S(6.0, 8.0, (3.0, 5.0))
        if name == 'lean_on':      # se apoya en lo alto de una herramienta plantada (la mano a la altura del pecho)
            return S(-4.0, 3.0, (-4.5, 4.0)) if n else S(6.0, 2.0, (5.0, 5.0))
        if name == 'chin':         # mano en la barbilla (pensativo)
            a = self.head['a'][3]
            return (A(self.hx + a[0] - 1.0, self.hy + a[1] + 2.0, (-1.5, 7.0)) if n else
                    A(self.hx + a[0] + 1.5, self.hy + a[1] + 2.0, (1.0, 7.0)))
        if name == 'shade':        # mano de visera sobre la frente (mirando a lo lejos)
            hx = self.hx + self.head['w'] * 0.5
            return (A(hx - 1.0, self.hy + self.head['a'][1][1] - 3.0, (-5.0, 0.5)) if n else
                    A(hx + 3.0, self.hy + self.head['a'][1][1] - 3.0, (4.5, 0.5)))
        if name == 'point':        # señalando adelante (a la derecha), brazo casi estirado a la altura del hombro
            return S(9.0, 0.5, (4.5, 1.5)) if n else S(10.5, -0.5, (5.5, 0.8))
        if name == 'wave':         # mano levantada saludando, brazo afuera
            return S(-6.0, -9.0, (-6.5, 0.0)) if n else S(7.0, -9.0, (6.5, 0.0))
        if name == 'swing':        # brazo adelantado y arriba (blandiendo algo)
            return S(6.5, -3.0, (2.0, 5.0)) if n else S(7.0, -2.0, (2.5, 5.0))
        if name == 'fist':         # puño cerrado al frente, a la altura de la cintura (decidido)
            return S(4.0, (yw - 1.0 - sh[1]) / k, (-2.5, 6.0)) if n else S(4.5, (yw - 1.5 - sh[1]) / k, (2.0, 6.0))
        if name == 'flask':        # frasco levantado a la altura del hombro, codo abajo
            return S(3.0, 2.0, (-1.0, 6.5)) if n else S(2.5, 1.5, (1.0, 6.5))
        if name == 'chest':        # sostiene algo delante del pecho
            return A(cs + 2.0, ysh + 6.5, 'hang') if n else A(cs + 1.0, ysh + 5.5, (-1.0, 6.5))
        if name == 'book':         # libro / cuaderno apretado contra el pecho (antebrazo cruzado, mano bajo el libro)
            return A(cs + 1.0, ysh + 6.5, (-1.0, 7.0)) if n else A(cs + 1.0, ysh + 7.0, (1.0, 6.5))
        if name == 'waist':        # sostiene algo a la altura de la cintura, por delante
            return A(cs + 1.5, yw + 1.0, 'hang') if n else A(cs + 2.0, yw + 0.5, (-1.0, 7.0))
        if name == 'staff':        # mano al costado sujetando una vara larga apoyada en el suelo
            return S(-2.5, 10.0, 'down') if n else S(3.5, 9.5, 'down')
        if name == 'staff_hi':     # vara más alta, mano a la altura del hombro
            return S(-2.0, 5.0, 'down') if n else S(3.5, 5.0, 'down')
        if name == 'shoulder':     # arma / herramienta apoyada en el hombro
            return S(2.5, 1.5, (-1.5, 6.0)) if n else S(-1.0, 1.0, (1.5, 6.0))
        if name == 'brim':         # mano en el ala del sombrero (saludo), codo afuera
            if n:
                return A(self.hx - 2.5, self.hy + 4.0, (-6.0, 1.5))
            return A(self.hx + self.head['w'] + 1.0, self.hy + 4.0, (5.0, 1.5))
        if name == 'raise':        # mano levantada (saludo)
            return S(-4.0, -7.0, (-5.0, -1.0)) if n else S(5.0, -7.0, (5.0, -1.0))
        if name == 'cross':        # brazos cruzados
            return A(cs + 3.0, ysh + 5.5, (-1.5, 6.0)) if n else A(cs - 2.0, ysh + 4.5, (1.5, 6.0))
        if name == 'basket':       # cesta colgada del antebrazo (codo doblado, mano al frente)
            return S(3.5, (yw + 1.0 - sh[1]) / k, (-0.5, 7.5)) if n else S(1.5, (yw + 1.0 - sh[1]) / k, (0.5, 7.5))
        if name == 'front':        # brazo algo adelantado y relajado
            return S(3.0, (yh + 0.5 - sh[1]) / k, 'back') if n else S(2.0, (yh + 0.5 - sh[1]) / k, 'back')
        if name == 'behind':       # mano a la espalda
            return S(1.5, (yw + 2.0 - sh[1]) / k, (-1.5, 7.0)) if n else S(-1.0, (yw + 2.0 - sh[1]) / k, (1.0, 7.0))
        if name == 'parasol':      # --- R3 ART3: sombrilla al hombro: mano delante del pecho, codo abajo y afuera
            if n:
                return A(cs - 2.2, ysh + 5.0, (-3.0, 5.5))
            return A(cs + 3.0, ysh + 5.0, (3.0, 5.5))
        if name == 'clasp':        # --- R3 ART3: manos sueltas juntas por delante, a la altura del cinturón (tranquila)
            if n:
                return A(cx + 0.2, yw - 0.5, 'back')
            return A(cx + 1.8, yw - 1.0, 'out')
        if name == 'lantern':      # brazo estirado hacia delante y abajo (farol, cuchara)
            return S(4.5, (yw + 4.0 - sh[1]) / k, 'back') if n else S(3.5, (yw + 3.5 - sh[1]) / k, 'back')
        raise KeyError(name)

    def _elbow(self, sh, hand, ua, fa, mode='back', side='n'):
        dx, dy = hand[0] - sh[0], hand[1] - sh[1]
        dist = math.hypot(dx, dy)
        mx, my = (sh[0] + hand[0]) / 2, (sh[1] + hand[1]) / 2
        if dist >= ua + fa - 0.05:
            return (mx, my)
        h = math.sqrt(max(0.0, ua * ua - (dist / 2) ** 2))
        nx, ny = -dy / dist, dx / dist
        if mode == 'out':
            want = -1 if side == 'n' else 1
            if nx * want < 0:
                nx, ny = -nx, -ny
        elif mode == 'down':
            if ny < 0:
                nx, ny = -nx, -ny
        else:
            if nx > 0:
                nx, ny = -nx, -ny
        return (mx + nx * h, my + ny * h)
