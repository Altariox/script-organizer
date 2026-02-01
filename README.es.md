# SmartSorter

SmartSorter organiza automáticamente archivos desde una carpeta vigilada (por defecto `~/Downloads`) hacia carpetas destino según la extensión.

Funciona en **modo vigilancia** (inotify + un escaneo de respaldo cada 10 segundos) o en **modo puntual** (one-shot).

## Funcionalidades

- Clasifica tipos comunes: imágenes, audio, vídeo, documentos, archivos comprimidos, modelos 3D, GCode, AppImages, etc.
- Conversiones opcionales:
  - Imágenes (png/webp/… → jpg) con ImageMagick
  - Audio (wav/flac/… → mp3) con ffmpeg
  - Vídeo (mkv/avi/… → mp4 h264/aac) con ffmpeg
- Manejo de duplicados (tamaño + `cmp`): borra solo duplicados reales; si no, lo ignora (salvo overwrite)
- Bajo uso de CPU: eventos inotify + escaneo periódico ligero
- Configurable mediante `config.json`

## Requisitos

- Bash
- `inotifywait` (paquete: `inotify-tools`)
- `python3` (para leer `config.json`)
- Opcional (solo para conversiones/notificaciones):
  - `imagemagick` (`magick`)
  - `ffmpeg`
  - `libnotify` (`notify-send`)

## Configuración

Edita `config.json`. Las rutas pueden contener `~`, `$HOME`, `${HOME}`.

Opciones clave:
- `watch_dir`, `paths.*` (carpetas destino)
- `scan_interval_seconds` (escaneo de respaldo)
- `file_stable_seconds` (ignora archivos recién modificados)
- `dry_run`, `overwrite`
- `log_enabled`, `notify_enabled`

También puedes indicar otro archivo de configuración:

```bash
CONFIG_FILE=/ruta/a/config.json bash organizer.sh
```

## Uso

Modo puntual (organiza lo que ya está en Downloads):

```bash
bash organizer.sh --once
```

Modo vigilancia:

```bash
bash organizer.sh
```

## Notas

- Si una conversión falla, el archivo original **no se elimina**; se moverá tal cual a la carpeta destino correspondiente.
