#!/usr/bin/env bash
# === backup_rotate_3-2.2.sh ===
# Tar backup av Darktable-konfiguration med rotation.
# Behåller de 3 senaste versionerna i old/.
# Autodetekterar darktable-config för snap / flatpak / native.
# Identisk detection-logik som restore_darktable-2.2.sh.

set -euo pipefail
export PAGER=cat   # Hindrar less/more

KEEP=3
BASE_DIR="~/bup_darktable"
LOG_FILE="~/bup_darktable/backup_rotate.log"

# ----- DRY-RUN -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRYRUN=true
    echo "=== DRY RUN (inga ändringar görs) ==="
fi

# ----- Hjälpfunktioner -----
expand_tilde() {
    case "$1" in
        "~"|"~/"*) printf "%s%s" "$HOME" "${1#\~}" ;;
        *) printf "%s" "$1" ;;
    esac
}

abspath_or_die() {
    cd "$1" 2>/dev/null && pwd || { echo "Fel: katalog finns ej: $1"; exit 1; }
}

log() { printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }

# ----- AUTO-DETEKTERA DARKTABLE-KONFIG -----

detect_darktable_config() {
    # Snap aktuell
    if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
        echo "snap (current)|$HOME/snap/darktable/current/.config/darktable"
        return 0
    fi

    # Snap revision
    if [[ -d "$HOME/snap/darktable" ]]; then
        local rev
        rev=$(ls -1 "$HOME/snap/darktable" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)
        if [[ -n "$rev" ]] && [[ -d "$HOME/snap/darktable/$rev/.config/darktable" ]]; then
            echo "snap (rev $rev)|$HOME/snap/darktable/$rev/.config/darktable"
            return 0
        fi
    fi

    # Flatpak
    if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
        echo "flatpak|$HOME/.var/app/org.darktable.Darktable/config/darktable"
        return 0
    fi

    # Native / APT / AppImage
    if [[ -d "$HOME/.config/darktable" ]]; then
        echo "native (~/.config/darktable)|$HOME/.config/darktable"
        return 0
    fi

    return 1
}

# ----- Init loggning -----

LOG_FILE="$(expand_tilde "$LOG_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log "------------------------------------------------------------"
log "Startar backup_rotate_3-2.2.sh"

# ----- Autodetektera config -----

DT_MODE="okänd"
SOURCE_DIR=""

if DETECT_OUT=$(detect_darktable_config); then
    DT_MODE="${DETECT_OUT%%|*}"
    SOURCE_DIR="${DETECT_OUT#*|}"
else
    log "⚠️ Kunde inte hitta Darktable-config. Använder ~/.config/darktable"
    DT_MODE="fallback"
    SOURCE_DIR="$HOME/.config/darktable"
fi

SOURCE_DIR="$(expand_tilde "$SOURCE_DIR")"

if [[ ! -d "$SOURCE_DIR" ]]; then
    log "❌ Fel: SOURCE_DIR saknas: $SOURCE_DIR"
    exit 1
fi

SOURCE_DIR="$(abspath_or_die "$SOURCE_DIR")"

# ----- Skapa basmappar -----

BASE_DIR="$(expand_tilde "$BASE_DIR")"
mkdir -p "$BASE_DIR"
BASE_DIR="$(abspath_or_die "$BASE_DIR")"

NEW_DIR="$BASE_DIR/new"
CURRENT_DIR="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"
LOCKFILE="$BASE_DIR/.backup_rotate.lock"

log "Identifierad installation: $DT_MODE"
log "Källa (SOURCE_DIR):       $SOURCE_DIR"
log "Backupbas (BASE_DIR):     $BASE_DIR"
log "Behåller (KEEP):          $KEEP"

# ----- Lås -----

exec 9>"$LOCKFILE"
cleanup() { exec 9>&- || true; rm -f "$LOCKFILE" || true; }
trap cleanup EXIT

flock -n 9 || { log "❌ Ett annat backupjobb körs. Avbryter."; exit 1; }

# ----- Skapa kataloger -----

mkdir -p "$OLD_BASE"
mkdir -p "$NEW_DIR"

# ----- Skapa ny backup -----

log "Skapar ny backup → $NEW_DIR"

if $DRYRUN; then
    rsync -a --delete --dry-run "$SOURCE_DIR/" "$NEW_DIR/"
else
    rsync -a --delete "$SOURCE_DIR/" "$NEW_DIR/"
fi

log "Backup klar."

# ----- Rotation -----

TS="$(date +%Y%m%d-%H%M%S)"

if [[ -d "$CURRENT_DIR" ]]; then
    DEST="$OLD_BASE/$TS"
    log "Flyttar current → $DEST"
    $DRYRUN || mv "$CURRENT_DIR" "$DEST"
else
    log "Ingen current fanns – hoppar över."
fi

log "Flyttar new → current"
$DRYRUN || mv "$NEW_DIR" "$CURRENT_DIR"

# ----- linkss-dump (snap-info) -----

LINK_SRC="$HOME/snap/darktable"
LINK_DST="$CURRENT_DIR/linkss"

if [[ -d "$LINK_SRC" ]]; then
    log "Sparar ls-info från $LINK_SRC"
    if $DRYRUN; then
        log "(dry-run) skulle skriva ls → $LINK_DST"
    else
        ls -l "$LINK_SRC" >"$LINK_DST" 2>&1
    fi
else
    log "Ingen snap-installation hittad. Hoppar över linkss."
fi

# ----- Rensa gamla versioner -----

log "Rensar gamla backuper (behåller $KEEP)..."

mapfile -t ALL < <(find "$OLD_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
    | grep -E '^[0-9]{8}-[0-9]{6}$' || true)

IFS=$'\n' ALL=($(printf "%s\n" "${ALL[@]}" | sort -r))

if (( ${#ALL[@]} > KEEP )); then
    for ((i=KEEP; i<${#ALL[@]}; i++)); do
        TARGET="$OLD_BASE/${ALL[$i]}"
        log "Tar bort: $TARGET"
        $DRYRUN || rm -rf "$TARGET"
    done
else
    log "Inget att ta bort."
fi

# ----- Verifiering -----

if $DRYRUN; then
    log "Verifiering hoppad (dry-run)."
else
    log "Verifierar backup…"

    files_src=$(find "$SOURCE_DIR" -type f | wc -l)
    files_cur=$(find "$CURRENT_DIR" -type f | wc -l)
    bytes_src=$(du -sb "$SOURCE_DIR" | cut -f1)
    bytes_cur=$(du -sb "$CURRENT_DIR" | cut -f1)

    log "Filer: källa=$files_src current=$files_cur"
    log "Bytes: källa=$bytes_src current=$bytes_cur"

    if [[ "$files_src" == "$files_cur" && "$bytes_src" == "$bytes_cur" ]]; then
        log "Verifiering OK."
    else
        log "⚠️ Verifiering MISSLYCKADES."
    fi
fi

log "Backup rotation klar."
log "------------------------------------------------------------"
echo "Backup färdig."

