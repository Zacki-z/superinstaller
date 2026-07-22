#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Tar backup från SOURCE_DIR till current/, med rotation och loggning
# Behåller de 3 senaste versionerna i old/
# Loggar till fil, städar låsfil, och stödjer --dry-run

set -euo pipefail

# ----- KONFIGURATION -----
SOURCE_DIR="home/alain/kicad_stuff"             # <-- katalog du vill ta backup av
BASE_DIR="/home/alain/bup_base"               # <-- huvudkatalog för backuper
LOG_FILE="/home/alain/bup_base/backup_rotate.log"
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
log "Backupkatalog: $BASE_DIR"
if $DRYRUN; then log "DRY-RUN aktiverad – inga filer flyttas eller tas bort."; fi

# ----- LÅS -----
LOCKFILE="$BASE_DIR/.backup_rotate.lock"
mkdir -p "$BASE_DIR"
exec 9>"$LOCKFILE"

cleanup

