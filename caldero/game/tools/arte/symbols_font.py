#!/usr/bin/env python3
"""--- R5 MERGE: la fuente de símbolos «Caldero Symbols» (assets/fonts/CalderoSymbols.ttf).

Alegreya y Caveat no tienen ★ ☆ ▲ ▼ ✓ ✗ ← → ♥. En el escritorio Godot los toma de una fuente del sistema, pero en la
web no hay fuentes del sistema y salen como una cajita con el código («25BC»). Esta fuente trae SOLO esos símbolos
(recortados de DejaVu Sans Bold) y UIKit.load_fonts() la pone de respaldo («fallbacks») de las cinco Alegreya; las
Caveat de PaperKit ya caen en Alegreya, así que también la usan.

Licencia: DejaVu = Bitstream Vera (cambios de DejaVu en dominio público). Se puede modificar si el nombre no lleva
«Bitstream» ni «Vera»: por eso se llama «Caldero Symbols». El texto va en assets/fonts/LICENSE-CalderoSymbols.txt.

    python3 tools/arte/symbols_font.py [ruta de DejaVuSans-Bold.ttf]
(necesita fontTools: pip install fonttools; después, reimportar: godot --headless --path game --import)
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "fonts", "CalderoSymbols.ttf")
SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
# los símbolos que usa el juego (y los dos que faltaban de la lista del glosario, por si vuelven)
GLYPHS = "★☆▲▼✓✗←→♥"
FAMILY = "Caldero Symbols"

LICENSE = """Caldero Symbols (assets/fonts/CalderoSymbols.ttf) is a subset of DejaVu Sans Bold with only these
characters: ★ ☆ ▲ ▼ ✓ ✗ ← → ♥ (made by tools/arte/symbols_font.py). It is renamed as the license asks.

DejaVu fonts: https://dejavu-fonts.github.io/
Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
Bitstream Vera is a trademark of Bitstream, Inc.
DejaVu changes are in public domain.

Permission is hereby granted, free of charge, to any person obtaining a copy of the fonts accompanying this license
("Fonts") and associated documentation files (the "Font Software"), to reproduce and distribute the Font Software,
including without limitation the rights to use, copy, merge, publish, distribute, and/or sell copies of the Font
Software, and to permit persons to whom the Font Software is furnished to do so, subject to the following conditions:

The above copyright and trademark notices and this permission notice shall be included in all copies of one or more
of the Font Software typefaces.

The Font Software may be modified, altered, or added to, and in particular the designs of glyphs or characters in the
Fonts may be modified and additional glyphs or characters may be added to the Fonts, only if the fonts are renamed to
names not containing either the words "Bitstream" or the word "Vera".

This License becomes null and void to the extent applicable to Fonts or Font Software that has been modified and is
distributed under the "Bitstream Vera" names.

The Font Software may be sold as part of a larger software package but no copy of one or more of the Font Software
typefaces may be sold by itself.

THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT,
TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL BITSTREAM OR THE GNOME FOUNDATION BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
DEALINGS IN THE FONT SOFTWARE.

Except as contained in this notice, the names of Gnome, the Gnome Foundation, and Bitstream Inc., shall not be used
in advertising or otherwise to promote the sale, use or other dealings in this Font Software without prior written
authorization from the Gnome Foundation or Bitstream Inc., respectively. For further information, contact: fonts at
gnome dot org.
"""


def main() -> None:
    opts = subset.Options()
    opts.layout_features = []      # sin ligaduras ni kerning: son símbolos sueltos
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    font = TTFont(SRC)
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=[ord(c) for c in GLYPHS])
    sub.subset(font)
    # nombre nuevo (la licencia de Bitstream Vera lo pide al modificar la fuente)
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 4, 16):
            rec.string = FAMILY
        elif rec.nameID == 6:
            rec.string = FAMILY.replace(" ", "")
        elif rec.nameID == 3:
            rec.string = FAMILY + " (subset of DejaVu Sans Bold)"
        elif rec.nameID in (2, 17):
            rec.string = "Regular"
    font.save(OUT)
    with open(os.path.join(os.path.dirname(OUT), "LICENSE-CalderoSymbols.txt"), "w", encoding="utf-8") as f:
        f.write(LICENSE)
    cmap = TTFont(OUT).getBestCmap()
    falta = [c for c in GLYPHS if ord(c) not in cmap]
    print("CalderoSymbols.ttf: %d bytes, %d símbolos%s" % (os.path.getsize(OUT), len(GLYPHS) - len(falta),
          (", FALTAN " + "".join(falta)) if falta else ""))


if __name__ == "__main__":
    main()
