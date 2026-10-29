"""Secondhand Stars · genera TODO el audio del juego (18 archivos .ogg, 44.1 kHz estéreo) y lo copia al juego.
  música     music_title, music_shop, music_market               (music_audio.py)
  ambiente   amb_wind, amb_port                                  (amb_audio.py)
  efectos    sfx_bell, sfx_whistle, sfx_blip1..3, sfx_ratchet, sfx_sizzle, sfx_coins, sfx_pod, sfx_good, sfx_bad,
             sfx_takeoff, sfx_tea                                (sfx_audio.py)
Todo sale de ss_audio.py (síntesis propia, sin muestras externas). Determinista: las semillas son fijas.
Uso:  python3 make_audio.py [carpeta_audio_del_juego]
      sin argumento deja los .ogg en tools/arte/salida/audio; con argumento los copia también allí
      (p. ej. python3 make_audio.py ../../audio  desde game/tools/arte).
Tarda ~2 min. Después: importar el proyecto (godot --headless --import) para crear los .import.
"""
import os, sys, shutil, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music_audio, amb_audio, sfx_audio
from ss_audio import OUT
from levels import measure

FILES = ['music_title', 'music_shop', 'music_market', 'amb_wind', 'amb_port',
         'sfx_bell', 'sfx_whistle', 'sfx_blip1', 'sfx_blip2', 'sfx_blip3', 'sfx_ratchet', 'sfx_sizzle', 'sfx_coins',
         'sfx_pod', 'sfx_good', 'sfx_bad', 'sfx_takeoff', 'sfx_tea']
LOOPS = FILES[:5]


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else None
    t0 = time.time()
    for f in (music_audio.music_title, music_audio.music_shop, music_audio.music_market,
              amb_audio.amb_wind, amb_audio.amb_port):
        f(OUT)
    for name in sfx_audio.ALL:
        getattr(sfx_audio, f'sfx_{name}')(OUT)
    print(f'== generado en {time.time() - t0:.0f} s -> {OUT}')
    for n in FILES:
        print(measure(os.path.join(OUT, n + '.ogg'), loop=n in LOOPS))
    if dest:
        os.makedirs(dest, exist_ok=True)
        for n in FILES:
            shutil.copy(os.path.join(OUT, n + '.ogg'), os.path.join(dest, n + '.ogg'))
        print('== copiado a', dest)


if __name__ == '__main__':
    main()
