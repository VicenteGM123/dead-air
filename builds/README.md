# DEAD AIR — descargas de escritorio (versión Godot)

Builds de **DEAD AIR** para Windows y Linux (Godot 4.7.2, con multijugador online 1-4). Cada ZIP está partido en
trozos de menos de 95 MB porque GitHub no admite archivos de más de 100 MB: descarga **todos los trozos** de tu
sistema en la misma carpeta y únelos.

| Sistema | Trozos | ZIP unido |
|---|---|---|
| Windows 10/11 (64 bits) | [DeadAir-windows.zip.001](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.001) + [DeadAir-windows.zip.002](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.002) | 167 MB |
| Linux x86_64 | [DeadAir-linux.zip.001](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.001) + [DeadAir-linux.zip.002](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.002) | 157 MB |

## Unir los trozos

- **Windows:** pon `UNIR-windows.bat` ([descargar](https://github.com/VicenteGM123/dead-air/raw/main/builds/UNIR-windows.bat))
  junto a los trozos y haz doble clic, o en una consola (`cmd`) en esa carpeta:
  `copy /b DeadAir-windows.zip.001+DeadAir-windows.zip.002 DeadAir-windows.zip`
  (7-Zip también abre directamente el `.001`).
- **Linux / macOS:** `cat DeadAir-linux.zip.0* > DeadAir-linux.zip` (o `sh unir-linux.sh`).

Luego descomprime el ZIP y lee el `LEEME.txt`: en Windows ejecuta `DeadAir.exe` (si SmartScreen avisa: **Más
información → Ejecutar de todas formas**); en Linux `./DeadAir.x86_64`. Multijugador: puerto **UDP 31313** en el
anfitrión, o una red virtual tipo Tailscale / ZeroTier.

SHA-256 de los ZIP unidos:
- `DeadAir-windows.zip`: `f084f6d74ae736a3748999d320d8138a371dfcd28dd03602f289a3e90677d53e`
- `DeadAir-linux.zip`: `f3937eca39a3e58745d6712b5f3fbee544eb4b511c25fe80a6b1161b0316e903`

Se generan con los presets "Windows Desktop" y "Linux" de `godot/export_presets.cfg`
(`godot --export-release "Windows Desktop" DeadAir.exe`, con las plantillas de exportación de Godot 4.7.2). Los presets
llevan el *shader baker* activado (shaders Vulkan precompilados dentro del ejecutable): hay que exportar con el editor
usando una GPU / Vulkan (sin `--headless`, que no los precompila) y borrando antes `godot/.godot/exported`.
