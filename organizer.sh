#!/usr/bin/env bash

### ================= CONFIG =================

WATCH_DIR="$HOME/Downloads"
LOG_FILE="$HOME/.smart_sorter.log"
DRY_RUN=false
OVERWRITE=false
USB_GCODE="/run/media/$USER/3DPrinter"  # si tu veux copier automatiquement le gcode

# Optimisation / options
SCAN_INTERVAL=10           # scan fallback toutes les X secondes
FILE_STABLE_SECONDS=12     # ignore les fichiers modifiés il y a < X sec
LOG_ENABLED=true
NOTIFY_ENABLED=true

# Fichier de config (JSON)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.json}"

# Dossiers cibles
DIR_PICTURES="$HOME/Pictures"
DIR_VIDEOS="$HOME/Videos"
DIR_MUSIC="$HOME/Music"
DIR_MODELS="$HOME/Models3D"
DIR_GCODE="$HOME/Gcode"
DIR_ARCHIVES="$HOME/Archives"
DIR_DOCS="$HOME/Documents"
DIR_APPS="$HOME/Applications"
DIR_MISC="$HOME/Misc"

### ==========================================

### ===== Fonctions utilitaires =====

expand_path() {
    # Expansion safe sans eval: ~, $HOME, ${HOME}
    local p="$1"
    if [[ "$p" == "~" || "$p" == "~/"* ]]; then
        p="$HOME${p:1}"
    fi
    p="${p//\$HOME/$HOME}"
    p="${p//\$\{HOME\}/$HOME}"
    echo "$p"
}

load_config_json() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    command -v python3 >/dev/null 2>&1 || {
        log "Config JSON ignorée (python3 introuvable) → $CONFIG_FILE"
        return 0
    }

    # Charge le JSON et sort des assignations bash sûres (quotées)
    # shellcheck disable=SC1090
    source <(
        python3 - "$CONFIG_FILE" <<'PY'
import json, shlex, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)

def emit(name, value):
    if value is None:
        return
    if isinstance(value, bool):
        print(f"{name}={'true' if value else 'false'}")
    elif isinstance(value, (int, float)):
        print(f"{name}={value}")
    else:
        print(f"{name}={shlex.quote(str(value))}")

emit('WATCH_DIR', cfg.get('watch_dir'))
emit('LOG_FILE', cfg.get('log_file'))
emit('DRY_RUN', cfg.get('dry_run'))
emit('OVERWRITE', cfg.get('overwrite'))
emit('USB_GCODE', cfg.get('usb_gcode'))

emit('SCAN_INTERVAL', cfg.get('scan_interval_seconds'))
emit('FILE_STABLE_SECONDS', cfg.get('file_stable_seconds'))
emit('LOG_ENABLED', cfg.get('log_enabled'))
emit('NOTIFY_ENABLED', cfg.get('notify_enabled'))

paths = cfg.get('paths') or {}
emit('DIR_PICTURES', paths.get('pictures'))
emit('DIR_VIDEOS', paths.get('videos'))
emit('DIR_MUSIC', paths.get('music'))
emit('DIR_MODELS', paths.get('models3d'))
emit('DIR_GCODE', paths.get('gcode'))
emit('DIR_ARCHIVES', paths.get('archives'))
emit('DIR_DOCS', paths.get('docs'))
emit('DIR_APPS', paths.get('apps'))
emit('DIR_MISC', paths.get('misc'))
PY
    )

    # Expand les chemins après chargement
    WATCH_DIR="$(expand_path "$WATCH_DIR")"
    LOG_FILE="$(expand_path "$LOG_FILE")"
    USB_GCODE="$(expand_path "$USB_GCODE")"
    DIR_PICTURES="$(expand_path "$DIR_PICTURES")"
    DIR_VIDEOS="$(expand_path "$DIR_VIDEOS")"
    DIR_MUSIC="$(expand_path "$DIR_MUSIC")"
    DIR_MODELS="$(expand_path "$DIR_MODELS")"
    DIR_GCODE="$(expand_path "$DIR_GCODE")"
    DIR_ARCHIVES="$(expand_path "$DIR_ARCHIVES")"
    DIR_DOCS="$(expand_path "$DIR_DOCS")"
    DIR_APPS="$(expand_path "$DIR_APPS")"
    DIR_MISC="$(expand_path "$DIR_MISC")"
}

load_config_json

mkdir -p "$DIR_PICTURES" "$DIR_VIDEOS" "$DIR_MUSIC" "$DIR_MODELS" \
         "$DIR_GCODE" "$DIR_ARCHIVES" "$DIR_DOCS" "$DIR_APPS" "$DIR_MISC"

LOG_FD_OPENED=false
init_log_fd() {
    $LOG_ENABLED || return 0
    [[ "$LOG_FD_OPENED" == true ]] && return 0
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    exec 3>>"$LOG_FILE"
    LOG_FD_OPENED=true
}

log() {
    $LOG_ENABLED || return 0
    init_log_fd
    local line="[$(date '+%F %T')] $1"
    echo "$line"
    printf '%s\n' "$line" >&3
}

run() {
    if $DRY_RUN; then
        echo "[DRY] $*"
    else
        eval "$@"
    fi
}

run_cmd() {
    if $DRY_RUN; then
        printf '[DRY] '
        printf '%q ' "$@"
        echo
    else
        "$@"
    fi
}

run_quiet_cmd() {
    if $DRY_RUN; then
        printf '[DRY] '
        printf '%q ' "$@"
        echo ' (quiet)'
    else
        "$@" >/dev/null 2>&1
    fi
}

notify() {
    local msg="$1"
    $NOTIFY_ENABLED || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    run_cmd notify-send "SmartSorter" "$msg"
}

sanitize_name() {
    local name="$1"
    # fast-path: déjà safe
    if [[ "$name" =~ ^[[:alnum:]._-]+$ ]]; then
        echo "$name"
        return 0
    fi
    # supprimer caractères spéciaux, emojis et espace multiple
    name=$(echo "$name" | iconv -f UTF-8 -t ASCII//TRANSLIT | tr -cd '[:alnum:]._-')
    echo "$name"
}

safe_move() {
    local src="$1"
    local dst="$2"

    # détecte doublon sans hash (cmp + taille)
    if [[ -f "$dst" ]]; then
        local src_size dst_size
        src_size=$(stat -c %s -- "$src" 2>/dev/null) || src_size=""
        dst_size=$(stat -c %s -- "$dst" 2>/dev/null) || dst_size=""

        if [[ -n "$src_size" && -n "$dst_size" && "$src_size" == "$dst_size" ]] && cmp -s -- "$src" "$dst"; then
            log "Doublon détecté, suppression → $src"
            run_cmd rm -f "$src"
            return
        elif [[ "$OVERWRITE" = false ]]; then
            log "EXISTE déjà → $dst (ignoré)"
            return
        fi
    fi

    mkdir -p "$(dirname "$dst")"
    run_cmd mv -f "$src" "$dst"
}

convert_image() {
    local f="$1"
    local base="$(sanitize_name "$(basename "${f%.*}")")"
    local out="$DIR_PICTURES/$base.jpg"
    local out_existed=false
    [[ -e "$out" ]] && out_existed=true

    if run_cmd magick "$f" "$out"; then
        run_cmd rm -f "$f"
        notify "Image convertie → $out"
    else
        log "Conversion image échouée, fichier conservé → $f"
        if [[ "$out_existed" = false && -f "$out" ]]; then
            run_cmd rm -f "$out"
        fi
        # fallback : classer sans conversion pour éviter de le retenter en boucle
        safe_move "$f" "$DIR_PICTURES/$(sanitize_name "$(basename "$f")")"
    fi
}

convert_audio() {
    local f="$1"
    local base="$(sanitize_name "$(basename "${f%.*}")")"
    local out="$DIR_MUSIC/$base.mp3"
    local out_existed=false
    [[ -e "$out" ]] && out_existed=true

    if run_quiet_cmd ffmpeg -y -i "$f" -ab 320k "$out"; then
        run_cmd rm -f "$f"
        notify "Audio converti → $out"
    else
        log "Conversion audio échouée, fichier conservé → $f"
        if [[ "$out_existed" = false && -f "$out" ]]; then
            run_cmd rm -f "$out"
        fi
        safe_move "$f" "$DIR_MUSIC/$(sanitize_name "$(basename "$f")")"
    fi
}

convert_video() {
    local f="$1"
    local base="$(sanitize_name "$(basename "${f%.*}")")"
    local out="$DIR_VIDEOS/$base.mp4"
    local out_existed=false
    [[ -e "$out" ]] && out_existed=true

    if run_quiet_cmd ffmpeg -y -i "$f" -c:v libx264 -preset slow -crf 22 -c:a aac "$out"; then
        run_cmd rm -f "$f"
        notify "Vidéo convertie → $out"
    else
        log "Conversion vidéo échouée, fichier conservé → $f"
        if [[ "$out_existed" = false && -f "$out" ]]; then
            run_cmd rm -f "$out"
        fi
        safe_move "$f" "$DIR_VIDEOS/$(sanitize_name "$(basename "$f")")"
    fi
}

process_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return

    local ext="${file##*.}"
    ext="${ext,,}"  # minuscule

    local base_name safe_name
    base_name="$(basename -- "$file")"
    safe_name="$(sanitize_name "$base_name")"

    log "Traitement: $file"

    case "$ext" in
        png|jpeg|webp|bmp|tiff)
            convert_image "$file"
            ;;
        jpg)
            safe_move "$file" "$DIR_PICTURES/$safe_name"
            ;;
        wav|flac|ogg|m4a)
            convert_audio "$file"
            ;;
        mp3)
            safe_move "$file" "$DIR_MUSIC/$safe_name"
            ;;
        mkv|avi|webm|mov)
            convert_video "$file"
            ;;
        mp4)
            safe_move "$file" "$DIR_VIDEOS/$safe_name"
            ;;
        stl|obj|step|stp|3mf|ply)
            safe_move "$file" "$DIR_MODELS/$safe_name"
            ;;
        gcode|gc)
            local gcode_dst="$DIR_GCODE/$safe_name"
            safe_move "$file" "$gcode_dst"
            # si USB branché, copier pour l'imprimante
            if [[ -d "$USB_GCODE" ]]; then
                run_cmd cp -u "$gcode_dst" "$USB_GCODE/"
                notify "Gcode copié vers imprimante → $USB_GCODE"
            fi
            ;;
        zip|rar|7z|tar|gz|xz)
            safe_move "$file" "$DIR_ARCHIVES/$safe_name"
            ;;
        pdf|docx|odt|txt)
            safe_move "$file" "$DIR_DOCS/$safe_name"
            ;;
        appimage|run)
            run_cmd chmod +x "$file"
            safe_move "$file" "$DIR_APPS/$safe_name"
            ;;
        *)
            safe_move "$file" "$DIR_MISC/$safe_name"
            ;;
    esac
}

scan_watch_dir() {
    # Scan “fallback” pour les évènements inotify manqués.
    # On évite les fichiers temporaires de téléchargement et on ne traite
    # que les fichiers qui n'ont pas été modifiés récemment (réduit les erreurs
    # sur fichiers encore en cours d'écriture).
    compgen -G "$WATCH_DIR/*" >/dev/null 2>&1 || return 0

    local now mtime
    now=$(date +%s)

    shopt -s nullglob
    for f in "$WATCH_DIR"/*; do
        [[ -f "$f" ]] || continue
        case "$f" in
            *.part|*.crdownload|*.tmp) continue ;;
        esac

        mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        (( now - mtime < FILE_STABLE_SECONDS )) && continue
        process_file "$f"
    done
    shopt -u nullglob
}

### ===== MODE MANUEL =====
if [[ "$1" == "--once" ]]; then
    for f in "$WATCH_DIR"/*; do
        process_file "$f"
    done
    exit 0
fi

### ===== MODE AUTO (inotify) =====
log "Surveillance de $WATCH_DIR"
notify "SmartSorter actif dans $WATCH_DIR"

# Scan périodique toutes les 10 secondes (fallback si inotify rate un évènement)
(
    while true; do
        sleep "$SCAN_INTERVAL"
        scan_watch_dir
    done
) &

inotifywait -m -e close_write -e moved_to --format "%w%f" "$WATCH_DIR" | while IFS= read -r f; do
    process_file "$f"
done