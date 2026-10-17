#!/usr/bin/env python3
"""Every animation of Heracles as labelled GIFs for the client: one GIF per category (the blows spread over several), a
grid of tiles, each tile one animation playing in real time and looping on its own length (held 4-6 frames on its last
pose first), the blows also seen from the gameplay camera; plus indice.jpg, a contact sheet of every GIF and what is in it.

usage: python3 tools/anim_gifs.py <out dir> [--only 05,07b] [--godot godot] [--sun 110,35] [--keep] [--compose-only]
                                  [--plan-only]
       (tools/anim_gifs.sh wraps it; run from anywhere: the Godot project is this file's parent folder)
Frame rates: moving, idles, guard, drawing and sheathing, jumps, the spear and the rest at 15 fps (the gait cycles loop
without a seam); the blows, the draw into a blow, the dodges, the block, the parry and the hits at 30 fps (a cut lasts 3-6
frames of the game's 60: at 15 fps the blade jumps). Every GIF plays in real time: a frame lasts 1/fps (GIF delays are in
1/100 s, so 30 fps alternates 30 and 40 ms and 15 fps 70 and 60 ms: the right time on average).
Steps per GIF: Godot measures each one-shot clip (tools/anim_gifs.gd mode=measure: how long it lasts by itself and, for the
GIFs at a fixed hero size, what it needs on screen per view); the GIF's length L is chosen so that every one-shot tile loops
a whole number of times in it, each loop held 4-6 frames on its last pose (a tile whose action is short of that plays on a
few frames after it: the hero living on, settling), and every gait spreads a whole number of its cycles over it; Godot
renders every clip once (one rig living through it in real time, the cameras following it); the strips are sliced and
composed with the titles, labels and progress bars; ffmpeg makes the GIF (one palette per GIF, no dithering).
Framing: a GIF with `hero_px` (the blows, the dodges, the hits) fixes the hero's size, hero_px tall standing in every tile and
view, and sizes its tiles to hold all that its clips show over all their frames (the long blade's whole swing, the cloak),
the aim centred on it; the others fit their fixed tiles with one zoom per GIF and view.
Needs xvfb-run, godot 4.7 (software GL is fine), ffmpeg, PIL. About 12-13 minutes for all seventeen GIFs on 4 shared cores
(one Godot process at a time). Writes nothing into the project.
"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
FPS = 15
FAST = 30
HERO_PX = 240
MAX_W = 1200
PAD = 10
GAP = 6
LABEL_H = 44
BAR_H = 6
TITLE_H = 64
VIEW_GAP = 4
MIN_HOLD = 4
MAX_HOLD = 6
MIN_L_S = 2.0
MIN_TILE_W = 260
# The toon edge pass's lines and rim fade out from half this distance (m): all that is filmed is within ~10 m; the flat ground
# seen low past ~10 m got the rim everywhere, a bright band under the horizon with a slanted end in the bigger tiles.
LINE_FAR = 18.0
BG = (28, 25, 23)
FG = (246, 238, 226)
DIM = (190, 178, 162)
ACC = (226, 170, 84)
BAR_BG = (58, 52, 46)
BAR_HOLD = (120, 104, 84)
VIEW_NAMES = {"tq": "frente-lado", "tql": "frente-izquierda", "side": "de lado", "sidel": "lado izquierdo", "front": "de frente",
              "back": "de espaldas", "tqb": "desde atrás", "game": "cámara del juego"}

# --- the catalog ------------------------------------------------------------------------------------------------------------
# A tile: key, label, sub (second line), setup / events / cap (tools/anim_gifs.gd's clip spec), kind: "shot" (plays once,
# held, loops on its own length), "gait" / "swim" (a whole number of cycles spread over the GIF's whole length) or "live"
# (an idle in real time over half the GIF, then played backwards: the breathing and the sway loop without a seam), view
# (single-view GIFs), minf (minimum GIF length, frames at 15 fps), group (one zoom for the group's tiles), follow, sun.
# A GIF: id, title, sub, cols, tiles, and views (rows of views per tile), aspect (tile h / w), fps (15), hero_px (a fixed hero
# size: the tiles sized from what the clips need).
ARMED = {"armed": 1, "ready": 1}
STOWED = {"armed": 0}
FAST_SUB = "En tiempo real, a 30 imágenes por segundo."
BLOWS = {"fps": FAST, "hero_px": HERO_PX, "min_s": 1.0, "views": ["tq", "game"]}
REACTS = {"fps": FAST, "hero_px": HERO_PX, "min_s": 1.0}


def T(key, label, sub="", setup=None, events=(), cap=None, kind="shot", view=None, minf=0, group=None, follow=None, sun=None):
    return {"key": key, "label": label, "sub": sub, "setup": dict(setup or {}), "events": [list(e) for e in events],
            "cap": dict(cap or {}), "kind": kind, "view": view, "minf": minf, "group": group, "follow": follow, "sun": sun}


def gait(key, label, sub, speed, heading=0, view="tq", **setup):
    s = dict(setup)
    s.update({"speed": speed, "heading": heading})
    return T(key, label, sub, s, kind="gait", view=view)


GIFS = [
    {"id": "01_moverse_sin_armas", "title": "Moverse sin armas",
     "sub": "Espada envainada y escudo a la espalda. Todo en tiempo real.", "cols": 4, "tiles": [
        T("reposo", "Reposo", "a ratos apoya la mano en el pomo", {"armed": 0, "pre": 2.4, "set": {"_idle_next": 99.0}},
          kind="live", minf=60),
        gait("caminar", "Caminar", "2,2 m/s", 2.2, armed=0),
        gait("correr", "Correr", "6,2 m/s", 6.2, view="side", armed=0),
        gait("esprintar", "Esprintar", "9 m/s", 9.0, view="side", armed=0),
    ]},
    {"id": "02_moverse_armado", "title": "Moverse con la espada y el escudo",
     "sub": "Armado. Sin enemigos cerca la espada cuelga baja; con uno cerca, postura de combate.", "cols": 3, "tiles": [
        T("reposo_armado", "Reposo armado", "la espada cuelga baja", {"armed": 1, "ready": 0}, kind="live", minf=45),
        T("listo", "Listo para pelear", "con un enemigo cerca", {"armed": 1, "ready": 1}, kind="live"),
        gait("caminar_armado", "Caminar armado", "2,2 m/s", 2.2, armed=1),
        gait("correr_armado", "Correr armado", "6,2 m/s", 6.2, view="side", armed=1),
        gait("esprintar_armado", "Esprintar armado", "9 m/s", 9.0, view="side", armed=1),
    ]},
    {"id": "03_guardia", "title": "Guardia y movimiento en combate",
     "sub": "Con el escudo arriba (2,6 m/s) y fijado a un enemigo (5 m/s).", "cols": 3, "tiles": [
        T("guardia", "Guardia", "detrás del escudo", {"armed": 1, "ready": 1, "guard": 1}, kind="live"),
        gait("guardia_avanzar", "Guardia: avanzar", "", 2.6, armed=1, ready=1, guard=1),
        gait("guardia_lado", "Guardia: de lado", "hacia su derecha", 2.6, heading=90, armed=1, ready=1, guard=1),
        gait("guardia_atras", "Guardia: retroceder", "", 2.6, heading=180, armed=1, ready=1, guard=1),
        gait("fijado_lado", "Fijado: de lado", "rodeando al enemigo", 5.0, heading=-90, armed=1, ready=1),
        gait("fijado_atras", "Fijado: retroceder", "", 5.0, heading=180, armed=1, ready=1),
    ]},
    {"id": "04_desenvainar_envainar", "title": "Sacar y guardar las armas",
     "sub": "La espada sale de la vaina de la cadera y el escudo de la espalda. Atacar con la espada envainada: en el 04b.",
     "cols": 3, "tiles": [
        T("desenvainar", "Desenvainar", "espada y escudo", STOWED, [[0.25, "play", "draw", 1, 1]], {"tail": 0.35}),
        T("envainar", "Envainar", "espada y escudo", {"armed": 1, "ready": 0}, [[0.25, "play", "sheathe", 1, 1]],
          {"tail": 0.35}),
        T("sacar_espada", "Sacar la espada", "", STOWED, [[0.25, "play", "draw_sword", 1, 1]], {"tail": 0.45}),
        T("sacar_escudo", "Sacar el escudo", "", STOWED, [[0.25, "play", "draw_shield", 1, 1]], {"tail": 0.45}),
        T("guardar_espada", "Guardar la espada", "", {"armed": 1, "ready": 0}, [[0.25, "play", "sheathe_sword", 1, 1]],
          {"tail": 0.35}),
        T("guardar_escudo", "Guardar el escudo", "", {"armed": 1, "ready": 0}, [[0.25, "play", "sheathe_shield", 1, 1]],
          {"tail": 0.35}),
    ]},
    dict(BLOWS, **{"id": "04b_desenvainar_y_golpear", "title": "Atacar con la espada envainada",
                   "sub": "Sale la espada y con ella el golpe (esprintando: en el 07b). " + FAST_SUB +
                          " La barra marca el impacto.", "cols": 2, "tiles": [
        T("desenvainar_golpe", "Desenvainar y golpear", "quieto: sale el golpe A1", STOWED, [[0.25, "entry", "a1"]],
          {"tail": 0.15}),
        T("desenvainar_trote", "Desenvainar trotando", "sale el golpe B1", {"armed": 0, "speed": 4.5},
          [[0.3, "entry", "b1"]], {"tail": 0.15}),
    ]}),
    dict(BLOWS, **{"id": "05a_combo_A_golpes_1_2", "title": "Combo A (atacar estando quieto): golpes A1 y A2",
                   "sub": FAST_SUB + " Cada golpe como sale en el combo (A2 empieza donde A1 se encadena). "
                          "La barra marca el impacto.", "cols": 2, "tiles": [
        T("a1", "A1 · diagonal", "de arriba a abajo", ARMED, [[0.0, "chain", "a1"]], {"tail": 0}),
        T("a2", "A2 · revés", "de abajo hacia arriba", ARMED, [[0.0, "chain", "a1,a2"]], {"t0": "blow:1", "tail": 0}),
    ]}),
    dict(BLOWS, **{"id": "05b_combo_A_golpes_3_4", "title": "Combo A: golpes A3 y A4 (el remate)",
                   "sub": FAST_SUB + " Cada golpe como sale en el combo (desde donde se encadena el anterior). "
                          "La barra marca el impacto.", "cols": 2, "tiles": [
        T("a3", "A3 · horizontal", "barrido a la altura del pecho", ARMED, [[0.0, "chain", "a1,a2,a3"]],
          {"t0": "blow:2", "tail": 0}),
        T("a4", "A4 · tajo al suelo", "remate por encima de la cabeza", ARMED, [[0.0, "chain", "a1,a2,a3,a4"]],
          {"t0": "blow:3", "tail": 0}),
    ]}),
    dict(BLOWS, **{"id": "06a_combo_B_golpes_1_2",
                   "title": "Combo B (atacar en movimiento o justo después del combo A): golpes B1 y B2",
                   "sub": FAST_SUB + " Cada golpe como sale en el combo. La barra marca el impacto.", "cols": 2, "tiles": [
        T("b1", "B1 · diagonal baja", "sube desde la guardia baja", ARMED, [[0.0, "chain", "b1"]], {"tail": 0}),
        T("b2", "B2 · revés", "de arriba a abajo", ARMED, [[0.0, "chain", "b1,b2"]], {"t0": "blow:1", "tail": 0}),
    ]}),
    dict(BLOWS, **{"id": "06b_combo_B_golpe_3", "title": "Combo B: golpe B3 (el remate)",
                   "sub": FAST_SUB + " La barra marca el impacto.", "cols": 1, "tiles": [
        T("b3", "B3 · estocada", "a fondo, remate", ARMED, [[0.0, "chain", "b1,b2,b3"]], {"t0": "blow:2", "tail": 0}),
    ]}),
    dict(BLOWS, **{"id": "07a_combos_completos", "title": "Combos completos",
                   "sub": "Encadenados a la velocidad del juego (pulsando a tiempo). " + FAST_SUB +
                          " La barra marca cada impacto.", "cols": 2, "tiles": [
        T("combo_a", "Combo A completo", "A1 A2 A3 A4", ARMED, [[0.0, "chain", "a1,a2,a3,a4"]], {"tail": 0}),
        T("combo_b", "Combo B completo", "B1 B2 B3", ARMED, [[0.0, "chain", "b1,b2,b3"]], {"tail": 0}),
    ]}),
    dict(BLOWS, **{"id": "07b_ataque_en_carrera", "title": "Ataque en carrera: armado y con la espada envainada",
                   "sub": "Atacar esprintando (9 m/s). " + FAST_SUB + " La barra marca el impacto.", "cols": 2, "tiles": [
        T("carrera", "Ataque en carrera", "con la espada en la mano", {"armed": 1, "speed": 9.0},
          [[0.35, "blow", "dash"]], {"t0": 0.1, "tail": 0}),
        T("desenvainar_carrera", "Desenvainar esprintando", "sale el ataque en carrera", {"armed": 0, "speed": 9.0},
          [[0.3, "entry", "dash"]], {"tail": 0.15}),
    ]}),
    dict(BLOWS, **{"id": "07c_giro_cargado", "title": "Golpe cargado: el giro",
                   "sub": FAST_SUB + " La barra marca el impacto.", "cols": 1, "tiles": [
        T("giro", "Giro cargado", "mantener el ataque y soltar", ARMED, [[0.1, "heavy", 0.55]], {"tail": 0}),
    ]}),
    dict(REACTS, **{"id": "08a_esquivar_bloquear_parar", "title": "Esquivar, bloquear y parar",
                    "sub": FAST_SUB, "cols": 2, "tiles": [
        T("voltereta", "Voltereta", "4 m hacia delante", ARMED, [[0.15, "roll"]], {"tail": 0.3}),
        T("paso_atras", "Paso atrás", "sin dirección: esquiva atrás", ARMED, [[0.15, "backstep"]], {"tail": 0.3}),
        T("bloquear", "Bloquear", "un golpe en el escudo", {"armed": 1, "ready": 1, "guard": 1},
          [[0.35, "impact", 1.0], [1.0, "guard", 1]], {"tail": 0.1}),
        T("parada", "Parada", "golpe de escudo a tiempo", {"armed": 1, "ready": 1, "guard": 1},
          [[0.2, "play", "parry", 1, 1]], {"tail": 0.3}),
    ]}),
    dict(REACTS, **{"id": "08b_golpes_recibidos", "title": "Golpe rechazado y golpes recibidos",
                    "sub": "Lo que pasa cuando le dan. " + FAST_SUB, "cols": 2, "tiles": [
        T("rechazado", "Golpe rechazado", "la espada rebota", ARMED,
          [[0.0, "blow", "a1"], [0.16, "play", "recoil"], [0.16, "knock", 3.0]], {"tail": 0.25}),
        T("golpe", "Golpe recibido", "", ARMED, [[0.2, "play", "hit"], [0.2, "knock", 3.0]], {"tail": 0.3}),
        T("golpe_fuerte", "Golpe fuerte recibido", "", ARMED, [[0.2, "play", "hit_heavy"], [0.2, "knock", 6.0]],
          {"tail": 0.3}),
        T("muerte", "Muerte", "", ARMED, [[0.2, "play", "death"]], {"tail": 0.6}),
    ]}),
    {"id": "09_salto_trepar_nadar", "title": "Saltar, trepar, colgarse, tirolesa y nadar",
     "sub": "La tirolesa y el colgarse van con la cadena de la lanza clavada en una anilla.", "cols": 4, "tiles": [
        T("salto", "Salto", "", STOWED, [[0.2, "jump"]], {"tail": 0.25}, group="saltos"),
        T("salto_corriendo", "Salto corriendo", "", {"armed": 0, "speed": 6.2}, [[0.15, "jump"]], {"tail": 0.25},
          view="side", group="saltos"),
        T("caida", "Aterrizaje", "cayendo desde 3 m", {"armed": 0, "state": "air", "y": 3.0, "vy": 0.0},
          [[0.0, "fall"]], {"tail": 0.35}, follow="xyz", group="saltos"),
        T("trepar", "Trepar a un saliente", "", {"armed": 0, "props": ["ledge"]},
          [[0.25, "climb", 0.8]], {"tail": 0.35}, view="tqb", group="saltos"),
        T("colgarse", "Colgarse de la cadena", "", {"armed": 0, "state": "hang", "loco": 0.0, "spear": 0,
                                                     "props": ["chainup", "deep"]}, kind="live", minf=45),
        T("tirolesa", "Tirolesa", "por la cadena hasta la anilla", {"armed": 0, "state": "zip", "vel": [0.0, 6.0, -18.0],
                                                                    "spear": 0, "props": ["chain", "deep"]},
          kind="live", view="side"),
        T("nadar", "Nadar", "", {"armed": 0, "state": "swim", "speed": 2.8, "props": ["water"]}, kind="swim"),
        T("flotar", "Flotar", "", {"armed": 0, "state": "swim", "speed": 0.0, "props": ["water"]}, kind="swim"),
    ]},
    {"id": "10_lanza_cadena", "title": "La lanza con cadena",
     "sub": "Lanzar (sin armas la saca de encima del escudo), tirar, arrastrar y recogerla cuando vuelve.", "cols": 3,
     "tiles": [
        # (the flying spear and its chain are the game's ChainSpear, not in this preview: the tiles say so)
        T("lanzar", "Lanzar la lanza", "(la lanza en vuelo no aparece aquí)", STOWED, [[0.25, "throw"]], {"tail": 0.35},
          group="lanzar"),
        T("lanzar_armado", "Lanzar armado", "(la lanza en vuelo no aparece aquí)", {"armed": 1, "ready": 1},
          [[0.25, "throw"]], {"tail": 0.35}, group="lanzar"),
        T("tirar", "Tirar de la cadena", "arrancar o atraer", {"armed": 0, "spear": 0}, [[0.25, "play", "pull", 1.15]],
          {"tail": 0.3}),
        T("arrastrar", "Arrastrar con la cadena", "andando hacia atrás",
          {"armed": 0, "spear": 0, "speed": 2.0, "heading": 180},
          [[0.0, "play", "pull", 1.0, 1], [0.0, "hold", 0.5]], {"t0": 0.6}, kind="gait"),
        T("recoger", "Recoger la lanza", "vuelve a la mano y a la espalda", {"armed": 0, "spear": 0},
          [[0.3, "catch"]], {"tail": 0.35}),
        T("recoger_armado", "Recoger la lanza armado", "", {"armed": 1, "ready": 1, "spear": 0}, [[0.3, "catch"]],
          {"tail": 0.35}),
    ]},
    {"id": "11_otros", "title": "Otras acciones",
     "sub": "Usar, acariciar, la piel del león, la victoria y la lucha a brazo partido.", "cols": 4, "tiles": [
        T("interactuar", "Interactuar", "abrir, empujar, recoger", STOWED, [[0.25, "play", "interact"]], {"tail": 0.35}),
        T("acariciar", "Acariciar", "a un animal", STOWED, [[0.25, "play", "pet"]], {"tail": 0.35}),
        T("piel_leon", "Ponerse la piel del león", "", STOWED, [[0.25, "play", "don_skin"]], {"tail": 0.4}),
        T("victoria", "Victoria", "la espada en alto", {"armed": 1, "ready": 0}, [[0.25, "play", "victory"]],
          {"tail": 0.35}, group="victoria"),
        T("lucha", "Lucha cuerpo a cuerpo", "deja las armas y forcejea", ARMED,
          [[0.25, "aside", 1], [0.25, "play", "grapple_start"], [0.75, "play", "grapple_loop"],
           [2.35, "play", "grapple_end"], [3.05, "aside", 0]], {"tail": 0.3}),
        T("trigo", "Caminar por el trigo", "baja la mano libre a las espigas",
          {"armed": 0, "speed": 1.8, "brush": 1.0, "brushh": 1.06}, kind="gait", view="tql", sun=[-110.0, 35.0]),
        T("leon_correr", "Correr con la piel del león", "después del primer trabajo",
          {"armed": 0, "outfit": "lion", "speed": 6.2}, kind="gait", view="side"),
    ]},
]


# --- Godot ----------------------------------------------------------------------------------------------------------------

def godot_run(args, spec, out_dir, mode, log_path):
    cmd = ["timeout", "1800", "xvfb-run", "-a", "-s", "-screen 0 1280x720x24", args.godot, "--path", GAME,
           "--rendering-driver", "opengl3", "--resolution", "160x120", "res://tools/preview.tscn", "--",
           "script=res://tools/anim_gifs.gd", "fns=clips", "spec=" + spec, "out=" + out_dir, "tod=" + args.tod,
           "sun_azim=" + args.sun.split(",")[0], "sun_elev=" + args.sun.split(",")[1], "msaa=1", "settle=1"]
    if mode:
        cmd.append("mode=" + mode)
    with open(log_path, "w") as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=False)
    text = open(log_path, errors="replace").read()
    bad = [l for l in text.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|SHADER ERROR", l)]
    if bad or "CLIPS done" not in text:
        sys.exit("Godot failed (%s): %s\n%s" % (log_path, mode or "render", "\n".join(bad[:10])))
    return text


def fps_of(gif):
    """The GIF's frame rate: 30 for the blows and the reactions (a swing shows its path, not a jump), 15 otherwise."""
    return gif.get("fps", FPS)


def at_fps(gif, frames15):
    """Frames given at 15 fps (minimum lengths) at the GIF's own frame rate."""
    return int(round(frames15 * fps_of(gif) / 15.0))


def views_of(gif, tile):
    """The views a tile is filmed from, one row each (a single-view GIF: the tile's own view)."""
    return gif.get("views") or [tile["view"] or "tq"]


def scaled(gif):
    return bool(gif.get("hero_px"))


def clip_spec(gif, tile, n=None, measure=False):
    multi = len(gif.get("views") or []) > 1
    cap = dict(tile["cap"])
    cap["fps"] = fps_of(gif)
    if n is not None:
        cap["n"] = n
        if tile["kind"] in ("gait", "swim"):
            cap["cyclic"] = tile["kind"]
    views = views_of(gif, tile)
    group = gif["id"] + ("/" + tile["group"] if tile["group"] else "")
    if scaled(gif):
        # the hero's size fixed: each view's zoom (vertical field of view) from its focal length and its row's height
        group = gif["id"] + "__" + tile["key"]
        if not measure:
            tw, th = gif["_tw"], gif["_th"]
            views = [{"name": v, "tile": [tw, th[j]],
                      "fov": math.degrees(2.0 * math.atan(th[j] / (2.0 * gif["_focal"][v])))}
                     for j, v in enumerate(views)]
    # (one zoom per GIF and view; a single-view GIF has one zoom whatever its tiles' views: the heroes the same size)
    c = {"id": gif["id"] + "__" + tile["key"], "tile": [gif.get("_tw", 300), (gif.get("_th") or [360])[0]],
         "views": views, "setup": tile["setup"], "events": tile["events"], "cap": cap, "group": group,
         "one_zoom": not multi and not scaled(gif), "margin": 0.06, "line_far": LINE_FAR}
    if measure and scaled(gif):
        c["extent"] = True
    if tile["follow"]:
        c["follow"] = tile["follow"]
    if tile["sun"]:
        c["sun"] = tile["sun"]
    return c


def plan(gif, durs):
    """The GIF's length L (frames) and, per one-shot tile, its loops: q loops of its action (n frames) plus `extra` frames
    played on after it (the hero living on), each loop held MIN_HOLD..MAX_HOLD frames on its last pose, filling L exactly:
    q (n + extra + MIN_HOLD) <= L <= q (n + extra + MAX_HOLD). Every L works with enough extra frames; the one chosen needs
    the fewest (a tile's action, then its short hold and again), then is the shortest."""
    fps = fps_of(gif)
    shots = [t for t in gif["tiles"] if t["kind"] == "shot"]
    lo = max([durs[t["key"]] + MIN_HOLD for t in shots] + [at_fps(gif, t["minf"]) for t in gif["tiles"]] +
             [int(round(gif.get("min_s", MIN_L_S) * fps))])
    best = None
    for L in range(lo, 2 * lo + 1):
        loops = {}
        extra = 0
        for t in shots:
            n = durs[t["key"]]
            q = L // (n + MIN_HOLD)
            e = max(0, -(-(L - q * (n + MAX_HOLD)) // q))
            tot = L - q * (n + e)
            holds = [tot // q + (1 if j < tot % q else 0) for j in range(q)]
            assert all(MIN_HOLD <= h <= MAX_HOLD for h in holds), (gif["id"], t["key"], L, n, q, e, holds)
            loops[t["key"]] = {"extra": e, "holds": holds}
            extra += e
        score = extra + 0.15 * L
        if best is None or score < best[0] - 1e-9:
            best = (score, L, loops)
    return best[1], best[2]


def tile_frames(t, n, L, loop):
    """A tile's picture at every frame of the GIF: [(frame of its strip, held)] (n: the frames rendered for it)."""
    if t["kind"] == "shot":
        seq = []
        for h in loop["holds"]:
            seq += [(k, False) for k in range(n)] + [(n - 1, True)] * h
        return seq
    if t["kind"] == "live":
        # forwards, then backwards (n = L/2 + 1 rendered frames)
        return [((f if f < n else max(2 * (n - 1) - f, 0)), False) for f in range(L)]
    return [(f % n, False) for f in range(L)]


# --- composing ------------------------------------------------------------------------------------------------------------

def font(size, weight="SemiBold"):
    for path in ("/usr/share/fonts/opentype/inter/Inter-%s.otf" % weight, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def text_w(d, s, f):
    b = d.textbbox((0, 0), s, font=f)
    return b[2] - b[0]


def layout(gif):
    """Fixed tiles (the GIFs without hero_px): as wide as the columns allow (300 px at most), `aspect` tall."""
    n = len(gif["tiles"])
    cols = min(gif.get("cols", 4), n)
    tw = min(gif.get("tile_max", 300), (MAX_W - 2 * PAD - (cols - 1) * GAP) // cols) // 2 * 2
    th = int(round(tw * gif.get("aspect", 1.2))) // 2 * 2
    nv = len(gif.get("views") or [None])
    gif["_cols"] = cols
    gif["_tw"] = tw
    gif["_th"] = [th] * nv


def layout_scaled(gif, ext):
    """Tiles holding all that their clips need at the fixed hero size: per view the focal length (pixels per unit of
    tangent) that makes the standing hero hero_px tall; the tiles' width the widest need over the GIF's tiles and views, each
    row of views as tall as its tallest need."""
    n = len(gif["tiles"])
    cols = min(gif.get("cols", 4), n)
    nv = len(gif.get("views") or [None])
    focal = {}
    tw, th = MIN_TILE_W, [0] * nv
    for t in gif["tiles"]:
        for j, v in enumerate(views_of(gif, t)):
            kx, ky, h = ext[t["key"]][v]
            f = gif["hero_px"] / h
            focal[v] = f
            tw = max(tw, 2.0 * f * kx)
            th[j] = max(th[j], 2.0 * f * ky)
    # (+4 px: the render measures its clips again, a hair off the measure pass's numbers)
    gif["_cols"] = cols
    gif["_tw"] = int(math.ceil((tw + 4) / 2.0)) * 2
    gif["_th"] = [int(math.ceil((x + 4) / 2.0)) * 2 for x in th]
    gif["_focal"] = focal


def cell_h(gif):
    return LABEL_H + sum(gif["_th"]) + (len(gif["_th"]) - 1) * VIEW_GAP + BAR_H


def wrap(d, text, f, width):
    words, line, lines = text.split(), "", []
    for w in words:
        if line and text_w(d, line + " " + w, f) > width:
            lines.append(line)
            line = w
        else:
            line = (line + " " + w).strip()
    return lines + [line]


def header(gif):
    """The title and the subtitle wrapped to the GIF's width (a one-column GIF is narrow): ([title lines], [sub lines])."""
    d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    width = 2 * PAD + gif["_cols"] * gif["_tw"] + (gif["_cols"] - 1) * GAP - 2 * PAD - 4
    return wrap(d, gif["title"], font(23, "Bold"), width), wrap(d, gif["sub"], font(14, "Medium"), width)


def title_h(gif):
    tl, sl = header(gif)
    return TITLE_H + 31 * (len(tl) - 1) + 18 * (len(sl) - 1)


def canvas(gif):
    cols = gif["_cols"]
    rows = (len(gif["tiles"]) + cols - 1) // cols
    return 2 * PAD + cols * gif["_tw"] + (cols - 1) * GAP, title_h(gif) + rows * cell_h(gif) + (rows - 1) * GAP + PAD


def tile_xy(gif, i):
    """Top-left of tile i's cell (its label); a last row with fewer tiles is centred."""
    tw = gif["_tw"]
    cols = gif["_cols"]
    n = len(gif["tiles"])
    r, c = divmod(i, cols)
    in_row = min(cols, n - r * cols)
    x = PAD + c * (tw + GAP) + (cols - in_row) * (tw + GAP) // 2
    return x, title_h(gif) + r * (cell_h(gif) + GAP)


def compose(gif, work, L, loops, events, out_gif):
    tw, ths = gif["_tw"], gif["_th"]
    fps = fps_of(gif)
    tiles = gif["tiles"]
    W, H = canvas(gif)
    f_title, f_sub = font(23, "Bold"), font(14, "Medium")
    f_lab, f_lsub, f_tag = font(16, "SemiBold"), font(12, "Medium"), font(11, "SemiBold")
    base = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(base)
    tl, sl = header(gif)
    for i, ln in enumerate(tl):
        d.text((PAD + 2, 9 + 31 * i), ln, font=f_title, fill=FG)
    for i, ln in enumerate(sl):
        d.text((PAD + 2, 40 + 31 * (len(tl) - 1) + 18 * i), ln, font=f_sub, fill=DIM)
    # every tile's frames, sliced from its strips, and what it shows at each frame of the GIF
    frames = {}
    seqs = {}
    for t in tiles:
        frames[t["key"]] = []
        for j, v in enumerate(views_of(gif, t)):
            strip = Image.open(os.path.join(work, "%s__%s@%s.png" % (gif["id"], t["key"], v))).convert("RGB")
            n = strip.width // tw
            frames[t["key"]].append([strip.crop((k * tw, 0, (k + 1) * tw, ths[j])) for k in range(n)])
        seqs[t["key"]] = tile_frames(t, len(frames[t["key"]][0]), L, loops.get(t["key"]))
        assert len(seqs[t["key"]]) == L, (gif["id"], t["key"], len(seqs[t["key"]]), L)
    places = {}
    for i, t in enumerate(tiles):
        x, y = tile_xy(gif, i)
        places[t["key"]] = (x, y)
        lab = t["label"]
        d.text((x + (tw - text_w(d, lab, f_lab)) / 2, y + 4), lab, font=f_lab, fill=FG)
        if t["sub"]:
            d.text((x + (tw - text_w(d, t["sub"], f_lsub)) / 2, y + 25), t["sub"], font=f_lsub, fill=DIM)
    out = []
    for f in range(L):
        im = base.copy()
        dd = ImageDraw.Draw(im, "RGBA")
        for t in tiles:
            x, y = places[t["key"]]
            n = len(frames[t["key"]][0])
            k, held = seqs[t["key"]][f]
            ty = y + LABEL_H
            for j, v in enumerate(views_of(gif, t)):
                im.paste(frames[t["key"]][j][k], (x, ty))
                tag = VIEW_NAMES.get(v, v)
                tg = text_w(dd, tag, f_tag)
                dd.rectangle((x, ty, x + tg + 10, ty + 17), fill=(20, 16, 14, 150))
                dd.text((x + 5, ty + 2), tag, font=f_tag, fill=(240, 230, 214, 255))
                ty += ths[j] + VIEW_GAP
            by = ty - VIEW_GAP + 1
            if t["kind"] == "shot":
                dd.rectangle((x, by, x + tw - 1, by + BAR_H - 2), fill=BAR_BG)
                fill = tw if held else int(round(tw * (k + 1) / n))
                dd.rectangle((x, by, x + fill - 1, by + BAR_H - 2), fill=BAR_HOLD if held else ACC)
                span = max((n - 1) / fps, 1e-3)
                for nm, at in events.get(t["key"], []):
                    if nm == "impact" and 0.0 <= at <= span + 1e-3:
                        px = x + int(round((tw - 3) * at / span))
                        dd.rectangle((px, by - 1, px + 2, by + BAR_H - 1), fill=(255, 255, 255))
        out.append(im)
    tmp = out_gif + ".frames"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    for i, im in enumerate(out):
        im.save(os.path.join(tmp, "f%04d.png" % i))
    encode(tmp, out_gif, fps)
    shutil.rmtree(tmp, ignore_errors=True)
    return out


def encode(frames_dir, out_gif, fps=FPS, colors=256):
    pal = os.path.join(frames_dir, "palette.png")
    src = os.path.join(frames_dir, "f%04d.png")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", src, "-vf",
                    "palettegen=max_colors=%d:stats_mode=full" % colors, pal], check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", src, "-i", pal, "-lavfi",
                    "paletteuse=dither=none:diff_mode=rectangle", "-loop", "0", out_gif], check=True)


# --- the index ------------------------------------------------------------------------------------------------------------

def index_sheet(made, out_path):
    """indice.jpg: per GIF its file name, title and one picture of each animation in it, with its label."""
    tw, gap, lab_h = 132, 8, 34
    f_t, f_s, f_l = font(19, "Bold"), font(13, "Medium"), font(12, "SemiBold")
    blocks = []
    for gif, thumbs in made:
        cols = 8
        rows = (len(thumbs) + cols - 1) // cols
        th = int(tw * thumbs[0][1].height / thumbs[0][1].width)
        h = 52 + rows * (th + lab_h + gap)
        im = Image.new("RGB", (16 + cols * (tw + gap), h), BG)
        d = ImageDraw.Draw(im)
        d.text((10, 6), "%s.gif" % gif["id"], font=f_t, fill=ACC)
        d.text((10, 30), gif["title"], font=f_s, fill=FG)
        for i, (lab, pic) in enumerate(thumbs):
            r, c = divmod(i, cols)
            x, y = 10 + c * (tw + gap), 52 + r * (th + lab_h + gap)
            im.paste(pic.resize((tw, th), Image.LANCZOS), (x, y))
            words, line, lines = lab.split(), "", []
            for w in words:
                if text_w(d, (line + " " + w).strip(), f_l) > tw:
                    lines.append(line)
                    line = w
                else:
                    line = (line + " " + w).strip()
            lines.append(line)
            for j, ln in enumerate(lines[:2]):
                d.text((x, y + th + 3 + j * 14), ln, font=f_l, fill=FG)
        blocks.append(im)
    W = max(b.width for b in blocks)
    head = Image.new("RGB", (W, 60), BG)
    d = ImageDraw.Draw(head)
    d.text((10, 8), "Heracles: todas las animaciones (índice de los GIF)", font=font(24, "Bold"), fill=FG)
    d.text((10, 38), "Cada GIF reproduce sus animaciones en tiempo real y en bucle (los golpes, las esquivas y los golpes "
                     "recibidos a 30 imágenes por segundo).", font=font(14, "Medium"), fill=DIM)
    H = head.height + sum(b.height + 6 for b in blocks)
    sheet = Image.new("RGB", (W, H), BG)
    sheet.paste(head, (0, 0))
    y = head.height
    for b in blocks:
        sheet.paste(b, (0, y))
        y += b.height + 6
    sheet.save(out_path, quality=88)


# --- main -----------------------------------------------------------------------------------------------------------------

def selected(gif_id, only):
    """--only: a GIF's whole id, or its number with or without its letter (05 is 05a and 05b; 05a only 05a)."""
    num = gif_id.split("_")[0]
    return not only or any(o == gif_id or o == num or o == num.rstrip("abcdefgh") for o in only)


def measure(args, gif, work):
    """Godot's measure pass: per one-shot tile how many frames it lasts and, at a fixed hero size, per tile and view what
    it needs on screen ({key: {view: (kx, ky, h)}})."""
    tiles = [t for t in gif["tiles"] if t["kind"] == "shot" or scaled(gif)]
    durs, ext = {}, {}
    if not tiles:
        return durs, ext
    clips = [clip_spec(gif, t, None if t["kind"] == "shot" else int(round(2.0 * fps_of(gif))), measure=True)
             for t in tiles]
    spec = os.path.join(work, gif["id"] + ".measure.json")
    json.dump({"clips": clips}, open(spec, "w"), indent=1)
    log = godot_run(args, spec, work, "measure", os.path.join(work, gif["id"] + ".measure.log"))
    for m in re.finditer(r"DUR (\S+)__(\S+) n=(\d+)", log):
        durs[m.group(2)] = int(m.group(3))
    for m in re.finditer(r"EXT (\S+)__(\S+) (\S+) kx=(\S+) ky=(\S+) h=(\S+)", log):
        ext.setdefault(m.group(2), {})[m.group(3)] = (float(m.group(4)), float(m.group(5)), float(m.group(6)))
    return {k: v for k, v in durs.items() if any(t["key"] == k and t["kind"] == "shot" for t in tiles)}, ext


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--only", default="", help="GIF ids or their numbers, comma separated (05 = 05a and 05b; 07b)")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--tod", default="golden")
    ap.add_argument("--sun", default="110,35", help="sun azimuth,elevation (deg): lights his front-right")
    ap.add_argument("--keep", action="store_true", help="keep the strips and logs (out/work)")
    ap.add_argument("--compose-only", action="store_true", help="reuse the strips in out/work")
    ap.add_argument("--plan-only", action="store_true", help="measure and plan (lengths, tiles, sizes); render nothing")
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    work = os.path.join(out, "work")
    os.makedirs(work, exist_ok=True)
    only = [s for s in args.only.split(",") if s]
    gifs = [g for g in GIFS if selected(g["id"], only)]
    if not gifs:
        sys.exit("no GIF matches --only " + args.only)
    made = []
    t_all = time.time()
    for gif in gifs:
        t0 = time.time()
        plan_path = os.path.join(work, gif["id"] + ".plan.json")
        if args.compose_only and os.path.exists(plan_path):
            p = json.load(open(plan_path))
            L, loops, durs, events = p["L"], p["loops"], p["durs"], p["events"]
            gif.update({k: p[k] for k in ("_cols", "_tw", "_th", "_focal") if k in p})
        else:
            if not scaled(gif):
                layout(gif)
            durs, ext = measure(args, gif, work)
            if scaled(gif):
                layout_scaled(gif, ext)
            L, loops = plan(gif, durs)
            W, H = canvas(gif)
            fps = fps_of(gif)
            print("%s: plan L=%d (%.2f s at %d fps), tiles %dx%s, GIF %dx%d; %s" % (
                gif["id"], L, L / fps, fps, gif["_tw"], "/".join(str(x) for x in gif["_th"]), W, H,
                ", ".join("%s %d+%d x%d hold %s" % (k, durs[k], v["extra"], len(v["holds"]), ",".join(map(str, v["holds"])))
                          for k, v in loops.items())), flush=True)
            if args.plan_only:
                continue
            spec = os.path.join(work, gif["id"] + ".render.json")
            clips = []
            for t in gif["tiles"]:
                if t["kind"] == "shot":
                    n = durs[t["key"]] + loops[t["key"]]["extra"]
                else:
                    n = L // 2 + 1 if t["kind"] == "live" else L
                clips.append(clip_spec(gif, t, n))
            json.dump({"clips": clips}, open(spec, "w"), indent=1)
            log = godot_run(args, spec, work, "", os.path.join(work, gif["id"] + ".render.log"))
            for ln in log.splitlines():
                if "TIGHT" in ln:
                    print("  " + ln.strip(), flush=True)
            events = {}
            for m in re.finditer(r"EVENTS (\S+)__(\S+) (.*)", log):
                events[m.group(2)] = json.loads(m.group(3))
            json.dump({"L": L, "loops": loops, "durs": durs, "events": events, "_cols": gif["_cols"], "_tw": gif["_tw"],
                       "_th": gif["_th"], "_focal": gif.get("_focal")}, open(plan_path, "w"))
        out_gif = os.path.join(out, gif["id"] + ".gif")
        frames = compose(gif, work, L, loops, events, out_gif)
        # the index's pictures: each tile at its first impact (blows) or in the middle of its action
        thumbs = []
        tw, th = gif["_tw"], gif["_th"][0]
        for i, t in enumerate(gif["tiles"]):
            x, y = tile_xy(gif, i)
            y += LABEL_H
            n = durs.get(t["key"], L)
            imp = [at for nm, at in events.get(t["key"], []) if nm == "impact" and at >= 0.0]
            k = min(int(round(imp[0] * fps_of(gif))), n - 1) if imp else n // 2
            thumbs.append((t["label"], frames[k].crop((x, y, x + tw, y + th))))
        made.append((gif, thumbs))
        size = os.path.getsize(out_gif) / 1e6
        print("%s: %d frames (%.2f s at %d fps), %d tiles, %dx%d, %.1f MB, %.0f s" % (
            gif["id"], L, L / fps_of(gif), fps_of(gif), len(gif["tiles"]), frames[0].width, frames[0].height, size,
            time.time() - t0), flush=True)
    if made and not only:
        index_sheet(made, os.path.join(out, "indice.jpg"))
        print("indice.jpg")
    if not args.keep and not args.compose_only and not args.plan_only and not only:
        shutil.rmtree(work, ignore_errors=True)
    print("done in %.0f s" % (time.time() - t_all))


if __name__ == "__main__":
    main()
