#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Tar backup från SOURCE_DIR till current/, med rotation och loggning
# Behåller de 3 senaste versionerna i old/
# Loggar till fil, städar låsfil, och stödjer --dry-run

set -euo pipefail

# ----- KONFIGURATION -----
SOURCE_DIR="/home/alain/kicad_stuff"             # <-- den katalog du vill ta backup på
BASE_DIR="/home/alain/bup_base"               # <-- var backuperna ska lagras
LOG_FILE="/home/alain/bup_basebackup_rotate.log"
KEEP=3                                   # antal gamla versioner att behålla

NEW_DIR="$BASE_DIR/new"
CURRENT_DIR="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"

# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  echo "=== KÖR I DRY-RUN-LÄGE (INGA FÖRÄNDRINGAR GÖRS) ==="
fi

# ----- LOGGNING -----
mkdir -p "$(dirname "$LOG_FILE")"
# shellcheck disable=SC2094
exec > >(tee -a "$LOG_FILE") 2>&1
log() { printf '[%s] %s\n' "$(date +%F' '%T)" "$*"; }

log "------------------------------------------------------------"
log "Backup-rotation startad ($(date))"
log "Källa: $SOURCE_DIR"
log "Backup-katalog: $BASE_DIR"
if $DRYRUN; then log "DRY-RUN aktiverad – inga filer flyttas eller tas bort."; fi

# ----- LÅS -----
LOCKFILE="$BASE_DIR/.backup_rotate.lock"
mkdir -p "$BASE_DIR"
exec 9>"$LOCKFILE"

cleanup() {
  log "Städar låsfil..."
  exec 9>&- || true
  rm -f "$LOCKFILE" || true
}
trap cleanup EXIT

flock -n 9 || { log "Ett annat jobb körs. Avbryter."; exit 1; }

# ----- SKAPA NY BACKUP (SOURCE → new) -----
log "Skapar ny backup från $SOURCE_DIR till $NEW_DIR ..."
mkdir -p "$NEW_DIR"

if $DRYRUN; then
  rsync -a --delete --dry-run "$SOURCE_DIR/" "$NEW_DIR/"
else
  rsync -a --delete "$SOURCE_DIR/" "$NEW_DIR/"
fi
log "Backup av källa klar."

# ----- ROTATION -----
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -d "$CURRENT_DIR" ]]; then
  DEST="$OLD_BASE/$TS"
  log "Flyttar current -> $DEST"
  $DRYRUN || mv "$CURRENT_DIR" "$DEST"
else
  log "Ingen current hittades – hoppar över backup av current."
fi

log "Flyttar new -> current"
$DRYRUN || mv "$NEW_DIR" "$CURRENT_DIR"

# ----- RENSNING -----
log "Rensar gamla versioner, behåller $KEEP senaste ..."
mapfile -t ALL < <(find "$OLD_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
  | grep -E '^[0-9]{8}-[0-9]{6}$' || true)
IFS=$'\n' ALL=($(printf "%s\n" "${ALL[@]}" | sort -r))

if (( ${#ALL[@]} > KEEP )); then
  for (( i=KEEP; i<${#ALL[@]}; i++ )); do
    TARGET="$OLD_BASE/${ALL[$i]}"
    log "Tar bort: $TARGET"
    $DRYRUN || rm -rf -- "$TARGET"
  done
else
  log "Inget att ta bort (<= $KEEP versioner)."
fi

log "Rotation färdig."
log "------------------------------------------------------------"
ls -la "$BASE_DIR" || true
ls -la "$OLD_BASE" || true

