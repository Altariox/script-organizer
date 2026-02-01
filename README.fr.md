# SmartSorter

SmartSorter trie automatiquement les fichiers d’un dossier surveillé (par défaut `~/Downloads`) vers des dossiers cibles selon l’extension.

Il fonctionne en **mode surveillance** (inotify + scan de secours toutes les 10 secondes) ou en **mode manuel** (one-shot).

## Fonctionnalités

- Tri des types courants : images, audio, vidéo, documents, archives, modèles 3D, GCode, AppImages, etc.
- Conversions optionnelles :
  - Images (png/webp/… → jpg) via ImageMagick
  - Audio (wav/flac/… → mp3) via ffmpeg
  - Vidéo (mkv/avi/… → mp4 h264/aac) via ffmpeg
- Gestion des doublons (taille + `cmp`) : supprime uniquement les vrais doublons, sinon ignore (sauf si overwrite)
- Faible conso CPU : inotify + scan périodique léger
- Configuration centralisée dans `config.json`

## Prérequis

- Bash
- `inotifywait` (paquet : `inotify-tools`)
- `python3` (lecture de `config.json`)
- Optionnel (seulement pour conversion/notifications) :
  - `imagemagick` (`magick`)
  - `ffmpeg`
  - `libnotify` (`notify-send`)

## Configuration

Édite `config.json`. Les chemins peuvent contenir `~`, `$HOME`, `${HOME}`.

Options importantes :
- `watch_dir`, `paths.*` (dossiers cibles)
- `scan_interval_seconds` (scan fallback)
- `file_stable_seconds` (ignore les fichiers trop récents)
- `dry_run`, `overwrite`
- `log_enabled`, `notify_enabled`

Tu peux aussi forcer un autre fichier de config :

```bash
CONFIG_FILE=/chemin/vers/config.json bash organizer.sh
```

## Utilisation

Mode manuel (trie tout ce qui est déjà dans Downloads) :

```bash
bash organizer.sh --once
```

Mode surveillance :

```bash
bash organizer.sh
```

## Notes

- Si une conversion échoue, le fichier d’origine n’est **jamais supprimé** ; il est déplacé tel quel vers le dossier cible.
