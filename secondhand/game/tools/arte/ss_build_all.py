"""Secondhand Stars · regenera TODO el arte y (opcional) lo copia al proyecto de Godot con las rutas del contrato.

    python3 ss_build_all.py --out ../../out [--game ../../game]

  out/chars/<id>_idle.png, <id>_walk.png          -> game/assets/chars/
  out/props/*.png + props.json (tortuga incluida)  -> game/assets/props/
  out/items/*.png + manifest.json                  -> game/assets/items/
  out/parts/*.png                                  -> game/assets/parts/
  out/ui/*.png + ui_kit.json (logo incluido)       -> game/assets/ui/
  out/tex/*.png                                    -> game/assets/tex/
  out/icons/emote_*.png (8 emociones)              -> game/assets/icons/
  out/icon.png (icono de la app, 64x64)            -> game/icon.png
  tools/arte/fonts/*.ttf + OFL                     -> game/assets/fonts/ SOLO con --fonts (el logo ya es PNG)
"""
import sys, os, subprocess, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))


def run(script, *args):
    cmd = [sys.executable, os.path.join(HERE, script)] + list(args)
    print('>>', ' '.join(os.path.basename(c) for c in cmd[1:]))
    subprocess.run(cmd, check=True, cwd=HERE)


def import_presets(game):
    """Píxeles nítidos en 3D (como el Caldero): chars/props/tex sin compresión VRAM ('detect 3D' apagado), lossless;
    las texturas del mundo con mipmaps. Parchea los .import que existan y escribe uno mínimo si falta (Godot completa
    el resto al importar)."""
    n = 0
    for sub, mip in (('chars', False), ('props', False), ('tex', True), ('items', False), ('parts', False),
                     ('icons', False)):
        for png in glob.glob(os.path.join(game, 'assets', sub, '*.png')):
            imp = png + '.import'
            if os.path.exists(imp):
                txt = open(imp).read()
                lines = []
                for ln in txt.split('\n'):
                    if ln.startswith('compress/mode='):
                        ln = 'compress/mode=0'
                    elif ln.startswith('mipmaps/generate='):
                        ln = 'mipmaps/generate=%s' % ('true' if mip else 'false')
                    elif ln.startswith('detect_3d/compress_to='):
                        ln = 'detect_3d/compress_to=0'
                    lines.append(ln)
                new = '\n'.join(lines)
                if new != txt:
                    open(imp, 'w').write(new)
                    n += 1
            else:
                open(imp, 'w').write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                                     'compress/mode=0\nmipmaps/generate=%s\ndetect_3d/compress_to=0\n' % ('true' if mip else 'false'))
                n += 1
    print('import presets:', n, 'files')


def main():
    a = sys.argv[1:]
    out = os.path.abspath(a[a.index('--out') + 1]) if '--out' in a else os.path.abspath(os.path.join(HERE, '..', '..', 'out'))
    game = os.path.abspath(a[a.index('--game') + 1]) if '--game' in a else None
    if '--no-build' not in a:
        run('ss_chars.py', '--out', out)                 # 10 personajes + props/tortoise.png
        run('ss_items.py', '--out', out)                 # piezas, objetos, cápsulas, vistas abiertas, manifest
        run('ss_ui.py', '--out', out)                    # kit de interfaz + iconos + glifos
        run('ss_logo.py', '--out', out)                  # logo
        run('ss_world.py', '--out', out, 'tex')          # texturas
        run('ss_props.py', '--out', out)                 # props del taller y la calle (+ props.json)
        run('ss_emotes.py', '--out', out)                # emociones sobre la cabeza + icono de la app
    if game:
        for sub in ('chars', 'props', 'items', 'parts', 'ui', 'tex', 'icons'):
            src = os.path.join(out, sub)
            dst = os.path.join(game, 'assets', sub)
            os.makedirs(dst, exist_ok=True)
            n = 0
            for f in glob.glob(os.path.join(src, '*')):
                if f.endswith(('.png', '.json')):
                    shutil.copy2(f, dst)
                    n += 1
            print('copied', n, 'files ->', os.path.relpath(dst, game))
        if os.path.exists(os.path.join(out, 'icon.png')):
            shutil.copy2(os.path.join(out, 'icon.png'), os.path.join(game, 'icon.png'))
            print('icon.png -> icon.png')
        # las fuentes del logo (Bungee, Saira Stencil) NO se copian: el logo ya es un PNG y el preset web exporta
        # all_resources (serían ~230 KB más en el .pck sin uso). Si alguien quiere títulos con ellas: --fonts.
        if '--fonts' in a:
            fd = os.path.join(game, 'assets', 'fonts')
            os.makedirs(fd, exist_ok=True)
            for f in glob.glob(os.path.join(HERE, 'fonts', '*')):
                shutil.copy2(f, fd)
            print('fonts ->', os.path.relpath(fd, game))
        import_presets(game)


if __name__ == '__main__':
    main()
