#!/usr/bin/env python3
"""--- SS SEED: las fuentes de Secondhand Stars (assets/fonts/), recortadas de fuentes libres instaladas en el sistema.

Estilo "taller de futuro usado": letra de interfaz clara y grande (Inter), lecturas de pantalla CRT ámbar en
monoespaciada (Secondhand Mono = Liberation Mono Bold recortada) y las etiquetas de papel escritas a mano (Caveat,
la misma de Midnight Cauldron, sin cambios). Los símbolos ★ ☆ ✓ ✗ ← → ... salen de «Secondhand Symbols» (recorte de
DejaVu Sans Bold), que UIKit.load_fonts() pone de respaldo: en la web no hay fuentes del sistema y sin respaldo
salen como cajitas (lo que pasó en Midnight Cauldron, ronda 5).

Licencias (los textos quedan junto a las fuentes):
  - Inter (The Inter Project Authors): SIL OFL 1.1, sin "Reserved Font Name": el recorte puede llamarse Inter.
  - Liberation Mono (Red Hat / Google): SIL OFL 1.1 con "Reserved Font Name Liberation": el recorte NO puede
    llamarse Liberation, por eso se llama «Secondhand Mono» (sigue bajo OFL 1.1).
  - DejaVu Sans Bold: licencia Bitstream Vera (cambios de DejaVu en dominio público): al modificarla no puede
    llamarse Bitstream ni Vera: «Secondhand Symbols».
  - Caveat (The Caveat Project Authors): SIL OFL 1.1, se copia tal cual desde Midnight Cauldron.

    <venv con fontTools>/bin/python tools/arte/fonts_ss.py
    (en el scratchpad: /tmp/claude-0/-home-user-dead-air/84a550d9-2edd-52f7-8fa3-04790d444022/scratchpad/venv/bin/python)
    luego reimportar: godot --headless --path game --import
"""
import os
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "fonts"))
SYS = "/usr/share/fonts"
CALDERO_FONTS = "/home/user/dead-air/caldero/game/assets/fonts"

# texto en inglés: ASCII, Latin-1, comillas tipográficas, rayas, puntos suspensivos, viñeta, flechas, ×, ™
TEXT_RANGES = [(0x20, 0x7E), (0xA0, 0xFF), (0x2010, 0x2027), (0x2030, 0x203A), (0x2122, 0x2122),
               (0x2190, 0x2193), (0x00D7, 0x00D7), (0x20AC, 0x20AC)]
SYMBOLS = "★☆▲▼◀▶✓✗←→↑↓♥●○◆♪⏎⚙✦"

OFL_HEAD_INTER = "Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)\n\n"
OFL_HEAD_MONO = ("Secondhand Mono (assets/fonts/SecondhandMono-Bold.ttf) is a subset of Liberation Mono Bold made by\n"
                 "tools/arte/fonts_ss.py. It is renamed because \"Liberation\" is a Reserved Font Name.\n\n"
                 "Digitized data copyright (c) 2010 Google Corporation with Reserved Font Arimo, Tinos and Cousine.\n"
                 "Copyright (c) 2012 Red Hat, Inc. with Reserved Font Name Liberation.\n\n")


def _unicodes(ranges):
    out = []
    for a, b in ranges:
        out.extend(range(a, b + 1))
    return out


def _rename(font, family, style="Regular"):
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 16):
            rec.string = family
        elif rec.nameID == 4:
            rec.string = family if style == "Regular" else "%s %s" % (family, style)
        elif rec.nameID == 6:
            rec.string = family.replace(" ", "") + ("" if style == "Regular" else "-" + style)
        elif rec.nameID == 3:
            rec.string = family + " (subset)"
        elif rec.nameID in (2, 17):
            rec.string = style


def _subset(src, dst, unicodes, features=None, rename=None, style="Regular"):
    opts = subset.Options()
    opts.layout_features = features if features is not None else ["kern", "liga", "calt", "tnum", "case", "ccmp", "locl", "mark", "mkmk"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    opts.drop_tables += ["DSIG"]
    font = TTFont(src)
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)
    if rename:
        _rename(font, rename, style)
    font.save(dst)
    cmap = TTFont(dst).getBestCmap()
    return os.path.getsize(dst), cmap


def _ofl_body():
    # el texto de la OFL 1.1 tal como viene con Caveat en Midnight Cauldron (desde la línea del preámbulo)
    txt = open(os.path.join(CALDERO_FONTS, "OFL-Caveat.txt"), encoding="utf-8").read()
    k = txt.find("This Font Software is licensed")
    return txt[k:] if k >= 0 else txt


def main():
    os.makedirs(OUT, exist_ok=True)
    text = _unicodes(TEXT_RANGES)
    rep = []
    for w in ("Medium", "Bold"):
        n, _ = _subset("%s/opentype/inter/Inter-%s.otf" % (SYS, w), os.path.join(OUT, "Inter-%s.otf" % w), text)
        rep.append(("Inter-%s.otf" % w, n))
    n, _ = _subset("%s/truetype/liberation/LiberationMono-Bold.ttf" % SYS, os.path.join(OUT, "SecondhandMono-Bold.ttf"),
                   text, features=["kern", "ccmp", "locl"], rename="Secondhand Mono", style="Bold")
    rep.append(("SecondhandMono-Bold.ttf", n))
    n, cmap = _subset("%s/truetype/dejavu/DejaVuSans-Bold.ttf" % SYS, os.path.join(OUT, "SecondhandSymbols.ttf"),
                      [ord(c) for c in SYMBOLS], features=[], rename="Secondhand Symbols")
    missing = [c for c in SYMBOLS if ord(c) not in cmap]
    rep.append(("SecondhandSymbols.ttf", n))
    # Caveat tal cual (Midnight Cauldron)
    shutil.copyfile(os.path.join(CALDERO_FONTS, "Caveat-VariableFont_wght.ttf"), os.path.join(OUT, "Caveat-VariableFont_wght.ttf"))
    shutil.copyfile(os.path.join(CALDERO_FONTS, "OFL-Caveat.txt"), os.path.join(OUT, "OFL-Caveat.txt"))
    rep.append(("Caveat-VariableFont_wght.ttf", os.path.getsize(os.path.join(OUT, "Caveat-VariableFont_wght.ttf"))))
    body = _ofl_body()
    with open(os.path.join(OUT, "OFL-Inter.txt"), "w", encoding="utf-8") as f:
        f.write(OFL_HEAD_INTER + body)
    with open(os.path.join(OUT, "OFL-SecondhandMono.txt"), "w", encoding="utf-8") as f:
        f.write(OFL_HEAD_MONO + body)
    lic = open(os.path.join(CALDERO_FONTS, "LICENSE-CalderoSymbols.txt"), encoding="utf-8").read()
    k = lic.find("DejaVu fonts:")
    with open(os.path.join(OUT, "LICENSE-SecondhandSymbols.txt"), "w", encoding="utf-8") as f:
        f.write("Secondhand Symbols (assets/fonts/SecondhandSymbols.ttf) is a subset of DejaVu Sans Bold with only these\n"
                "characters: %s (made by tools/arte/fonts_ss.py). It is renamed as the license asks.\n\n" % " ".join(c for c in SYMBOLS if c not in missing))
        f.write(lic[k:])
    for f, n in rep:
        print("  %-30s %8d B" % (f, n))
    print("symbols missing in DejaVu Sans Bold:", "".join(missing) or "none")


if __name__ == "__main__":
    main()
