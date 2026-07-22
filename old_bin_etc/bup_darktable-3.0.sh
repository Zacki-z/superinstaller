#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Rotera versioner: current -> old/<timestamp>, new -> current
# Behåll endast de 3 senaste i old/
# Loggar alla steg till en definierad loggfil och städar låsfil automatiskt

set -euo pipefail

# ----- KONFIGURATION -----
BASE_DIR="/home/alain/bub_base"      # <-- ändra till din katalog
LOG_FILE="/home/alain/bub_base/backup_rotate.log"  # <-- ange loggfil här
NEW_DIR="$BASE_DIR/new"
CURRENT_DIR="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"
KEEP=3

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

# ----- START -----
mkdir -p "$OLD_BASE"

if [[ ! -d "$NEW_DIR" ]]; then
  log "Fel: $NEW_DIR finns inte."
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"

# ----- current -> old/<TS> -----
if [[ -d "$CURRENT_DIR" ]]; then
  DEST="$OLD_BASE/$TS"
  log "Flyttar current -> $DEST"
  $DRYRUN || mv "$CURRENT_DIR" "$DEST"
else
  log "Ingen current hittades – hoppar över backup av current."
fi

# ----- new -> current -----
log "Flyttar new -> current"
$DRYRUN || mv "$NEW_DIR" "$CURRENT_DIR"

# ----- rensa gamla versioner -----
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

