#!/usr/bin/env bash
# === backup_darktable-4.0.sh ===
# Enkel, robust Darktable-backup utan current/old:
#  - Tar Darktables config-katalog (snap/flatpak/native)
#  - Skapar snapshot:  ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/...
#  - Behåller endast de 3 senaste snapshots
#  - Loggar till ~/bup_darktable/backup.log
#
# Användning:
#   ./backup_darktable-4.0.sh
#   ./backup_darktable-4.0.sh --dry-run

set -euo pipefail
export PAGER=cat

# ----- KONFIG -----
KEEP=3
BASE_DIR="~/bup_darktable"
LOG_FILE="~/bup_darktable/backup_rotate.log"

# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRYRUN=true
  echo "=== DRY-RUN: inga ändringar görs ==="
fi

# ----- Hjälpfunktioner -----
expand_tilde() {
  case "$1" in
    "~"|"~/"*) printf "%s%s" "$HOME" "${1#\~}" ;;
    * )        printf "%s" "$1" ;;
  esac
}

abspath_or_die() {
  cd "$1" 2>/dev/null && pwd || { echo "Fel: katalog finns ej: $1" >&2; exit 1; }
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

detect_darktable_config() {
  # Snap – current
  if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
    echo "snap (current)|$HOME/snap/darktable/current/.config/darktable"
    return 0
  fi

  # Snap – senaste revision
  if [[ -d "$HOME/snap/darktable" ]]; then
    local rev
    rev=$(ls -1 "$HOME/snap/darktable" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)
    if [[ -n "${rev:-}" && -d "$HOME/snap/darktable/$rev/.config/darktable" ]]; then
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
log "Startar backup_darktable-4.0.sh"

# ----- Hitta Darktable-källa -----
DT_MODE="okänd"
SOURCE_DIR=""

if DETECT_OUT=$(detect_darktable_config); then
  DT_MODE="${DETECT_OUT%%|*}"
  SOURCE_DIR="${DETECT_OUT#*|}"
else
  DT_MODE="fallback"
  SOURCE_DIR="$HOME/.config/darktable"
  log "⚠️  Hittade ingen känd profil – använder fallback: $SOURCE_DIR"
fi

SOURCE_DIR="$(expand_tilde "$SOURCE_DIR")"

if [[ ! -d "$SOURCE_DIR" ]]; then
  log "❌ Fel: SOURCE_DIR finns inte: $SOURCE_DIR"
  exit 1
fi

SOURCE_DIR="$(abspath_or_die "$SOURCE_DIR")"

BASE_DIR="$(expand_tilde "$BASE_DIR")"
mkdir -p "$BASE_DIR"
BASE_DIR="$(abspath_or_die "$BASE_DIR")"

log "Installationstyp: $DT_MODE"
log "Källa:           $SOURCE_DIR"
log "Backupbas:       $BASE_DIR"
log "Behåll snapshot: $KEEP st"

# ----- Skapa snapshot-katalog -----
TS="$(date +%Y%m%d-%H%M%S)"
SNAP_DIR="$BASE_DIR/$TS"
DATA_DIR="$SNAP_DIR/darktable"

log "Skapar snapshot: $SNAP_DIR"

if ! $DRYRUN; then
  mkdir -p "$DATA_DIR"
else
  log "(dry-run) skulle skapa katalog: $DATA_DIR"
fi

# ----- Kopiera data -----
log "Kopierar $SOURCE_DIR → $DATA_DIR"

if $DRYRUN; then
  rsync -a --dry-run "$SOURCE_DIR/" "$DATA_DIR/"
else
  rsync -a "$SOURCE_DIR/" "$DATA_DIR/"
fi

log "Kopiering klar."

# ----- Verifiering (om inte dry-run) -----
if $DRYRUN; then
  log "Verifiering hoppad (dry-run)."
else
  log "Verifierar snapshot ..."
  src_files=$(find "$SOURCE_DIR" -type f | wc -l)
  snap_files=$(find "$DATA_DIR" -type f | wc -l)
  src_bytes=$(du -sb "$SOURCE_DIR" | cut -f1)
  snap_bytes=$(du -sb "$DATA_DIR" | cut -f1)

  log "Filer: källa=$src_files  snapshot=$snap_files"
  log "Bytes: källa=$src_bytes snapshot=$snap_bytes"

  if [[ "$src_files" == "$snap_files" && "$src_bytes" == "$snap_bytes" ]]; then
    log "Verifiering OK."
  else
    log "⚠️  Verifiering misslyckades (skillnad i filer/bytes)."
  fi
fi

# ----- Rotation: behåll endast senaste $KEEP snapshots -----
log "Roterar snapshots, behåller de $KEEP senaste."

mapfile -t SNAPS < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
  | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r || true)

if (( ${#SNAPS[@]} > KEEP )); then
  for (( i=KEEP; i<${#SNAPS[@]}; i++ )); do
    OLD_SNAP="$BASE_DIR/${SNAPS[$i]}"
    log "Tar bort gammal snapshot: $OLD_SNAP"
    if ! $DRYRUN; then
      rm -rf -- "$OLD_SNAP"
    else
      log "(dry-run) skulle ta bort: $OLD_SNAP"
    fi
  done
else
  log "Inget att ta bort (antal snapshots <= $KEEP)."
fi

log "Backup klar."
log "------------------------------------------------------------"
echo "✅ Backup färdig (snapshot: $SNAP_DIR)"

