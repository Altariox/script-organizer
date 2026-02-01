# SmartSorter

SmartSorter automatically sorts files from a watch directory (default: `~/Downloads`) into target folders based on file extension.

It runs in **watch mode** (inotify + a fallback scan every 10 seconds) or in **one-shot mode**.

## Features

- Sorts common types: images, audio, video, documents, archives, 3D models, GCode, AppImages, etc.
- Optional conversions:
  - Images (png/webp/… → jpg) via ImageMagick
  - Audio (wav/flac/… → mp3) via ffmpeg
  - Video (mkv/avi/… → mp4 h264/aac) via ffmpeg
- Duplicate handling (size + `cmp`): deletes true duplicates, skips otherwise unless overwrite is enabled
- Low CPU: uses inotify events and a lightweight periodic scan
- Configurable via `config.json`

## Requirements

- Bash
- `inotifywait` (package: `inotify-tools`)
- `python3` (used to read `config.json`)
- Optional (only if you want conversions/notifications):
  - `imagemagick` (`magick`)
  - `ffmpeg`
  - `libnotify` (`notify-send`)

## Configuration

Edit `config.json`. Paths can include `~`, `$HOME`, `${HOME}`.

Key options:
- `watch_dir`, `paths.*` (target folders)
- `scan_interval_seconds` (fallback scan)
- `file_stable_seconds` (ignore freshly modified files)
- `dry_run`, `overwrite`
- `log_enabled`, `notify_enabled`

You can also override the config path:

```bash
CONFIG_FILE=/path/to/config.json bash organizer.sh
```

## Usage

One-shot (sort everything currently in the watch folder):

```bash
bash organizer.sh --once
```

Watch mode (recommended):

```bash
bash organizer.sh
```

## Notes

- If a conversion fails, the original file is **not deleted**; it will be moved to the corresponding target folder instead.
