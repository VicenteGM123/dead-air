# DEAD AIR — descargas de escritorio (versión Godot)

Builds de **DEAD AIR** para Windows y Linux (Godot 4.7.2, con multijugador online 1-4). Cada ZIP está partido en
trozos de menos de 95 MB porque GitHub no admite archivos de más de 100 MB: descarga **todos los trozos** de tu
sistema en la misma carpeta y únelos.

| Sistema | Trozos | ZIP unido |
|---|---|---|
| Windows 10/11 (64 bits) | [DeadAir-windows.zip.001](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.001) + [DeadAir-windows.zip.002](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.002) | 169 MB |
| Linux x86_64 | [DeadAir-linux.zip.001](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.001) + [DeadAir-linux.zip.002](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.002) | 159 MB |

## Unir los trozos

- **Windows:** pon `UNIR-windows.bat` ([descargar](https://github.com/VicenteGM123/dead-air/raw/main/builds/UNIR-windows.bat))
  junto a los trozos y haz doble clic, o en una consola (`cmd`) en esa carpeta:
  `copy /b DeadAir-windows.zip.001+DeadAir-windows.zip.002 DeadAir-windows.zip`
  (7-Zip también abre directamente el `.001`).
- **Linux / macOS:** `cat DeadAir-linux.zip.0* > DeadAir-linux.zip` (o `sh unir-linux.sh`).

Luego descomprime el ZIP y lee el `LEEME.txt`: en Windows ejecuta `DeadAir.exe` (si SmartScreen avisa: **Más
información → Ejecutar de todas formas**); en Linux `./DeadAir.x86_64`. Multijugador: **ONLINE · CODE** (por defecto) con un código de
sala, sin abrir puertos y compatible con la versión del navegador; o **DIRECT IP · LAN** (puerto **UDP 31313** en el
anfitrión, o una red virtual tipo Tailscale / ZeroTier). Cada ZIP incluye la librería WebRTC
(`libwebrtc_native...dll/.so`, extensión oficial godotengine/webrtc-native): déjala junto al ejecutable.

SHA-256 de los ZIP unidos:
- `DeadAir-windows.zip`: `4d6f2f1ed469b6713e245163e3b72ad51312ca1be79de3cffa22e93d00d2e6f6`
- `DeadAir-linux.zip`: `1529e709c8f9d2f5e573554935ccf908108601310cf89417fe9b48549258f39d`

Se generan con los presets "Windows Desktop" y "Linux" de `godot/export_presets.cfg`
(`godot --export-release "Windows Desktop" DeadAir.exe`, con las plantillas de exportación de Godot 4.7.2). Los presets
llevan el *shader baker* activado (shaders Vulkan precompilados dentro del ejecutable): hay que exportar con el editor
usando una GPU / Vulkan (sin `--headless`, que no los precompila) y borrando antes `godot/.godot/exported`.
