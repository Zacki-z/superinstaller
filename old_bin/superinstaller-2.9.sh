#!/usr/bin/env bash
# === bup_darktable-8.1.sh ===
# Backup & rotation för Darktable med autodetektering av config-katalog.
# Behåller de 3 senaste versionerna i old/.
# Stöd för --dry-run och integritetskontroll efter rotation.

set -euo pipefail

# ------------------------------------------------------------
# AUTO-DETECT: Hitta Darktable-katalog (APT / Snap / Flatpak / AppImage)
# ------------------------------------------------------------

CANDIDATES=(
    "$HOME/.config/darktable"                                         # APT/DEB + AppImage
    "$HOME/.var/app/org.darktable.Darktable/config/darktable"         # Flatpak
    "$HOME/snap/darktable/current"                                    # Snap (aktiv revision)
    "$HOME/snap/darktable"                                            # Snap (hela trädet)
)

DT_DIR=""
for d in "${CANDIDATES[@]}"; do
    if [ -d "$d" ]; then
        DT_DIR="$d"
        break
    fi
done

if [ -z "$DT_DIR" ]; then
    echo "❌ Hittade ingen Darktable-katalog. Har du startat programmet minst en gång?"
    exit 1
fi

echo "✔ Darktable-katalog hittad: $DT_DIR"

# ----- KONFIGURATION -----
SOURCE_DIR="$DT_DIR"                      # nu autodetekterad katalog
BASE_DIR="$HOME/bup_darktable"            # basmapp där new/current/old ligger
LOG_FILE="$HOME/bup_darktable/backup_rotate.log"
KEEP=3                                     # antal gamla versioner att spara

# Expandera ~ ifall det skulle ligga kvar i skriptet
SOURCE_DIR=$(eval echo "$SOURCE_DIR")
BASE_DIR=$(eval echo "$BASE_DIR")
LOG_FILE=$(eval echo "$LOG_FILE")

# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  echo "=== DRY RUN ==="
fi

# ----- FUNKTIONER -----
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

copy_cmd() {
  if $DRYRUN; then
    echo "DRYRUN: cp -a \"$1\" \"$2\""
  else
    cp -a "$1" "$2"
  fi
}

mv_cmd() {
  if $DRYRUN; then
    echo "DRYRUN: mv \"$1\" \"$2\""
  else
    mv "$1" "$2"
  fi
}

rm_cmd() {
  if $DRYRUN; then
    echo "DRYRUN: rm -rf \"$1\""
  else
    rm -rf "$1"
  fi
}

# ----- SKAPA STRUKTUR -----
NEW_BASE="$BASE_DIR/new"
CURRENT_BASE="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"

mkdir -p "$BASE_DIR" "$NEW_BASE" "$CURRENT_BASE" "$OLD_BASE"
touch "$LOG_FILE"

# ----- LOGG -----
log "------------------------------------------------------------"
log "Startar backup av $SOURCE_DIR"
log "DRYRUN = $DRYRUN"

# ----- STEG 1: Kopiera till new/ -----
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
DEST="$NEW_BASE/$TIMESTAMP"

log "Skapar ny backup: $DEST"
mkdir -p "$DEST"

copy_cmd "$SOURCE_DIR" "$DEST"

# ----- STEG 2: Rotation -----
log "Kör rotationssteg..."

# Flytta gammal current till old/
if [[ -d "$CURRENT_BASE" && "$(ls -A "$CURRENT_BASE" 2>/dev/null)" ]]; then
  CURRENT_DIR=$(ls -1 "$CURRENT_BASE")
  log "Flyttar current → old: $CURRENT_DIR"
  mv_cmd "$CURRENT_BASE/$CURRENT_DIR" "$OLD_BASE/"
else
  log "Ingen current/ att flytta."
fi

# Flytta new/TIMESTAMP → current/
log "Flyttar new/$TIMESTAMP → current/"
mv_cmd "$DEST" "$CURRENT_BASE/"

# Ta bort äldsta katalogerna i old/
COUNT=$(ls -1 "$OLD_BASE" | wc -l || true)
if (( COUNT > KEEP )); then
  REMOVE=$(( COUNT - KEEP ))
  log "Tar bort $REMOVE gamla versioner..."
  ls -1t "$OLD_BASE" | tail -n "$REMOVE" | while read -r dir; do
    rm_cmd "$OLD_BASE/$dir"
  done
else
  log "Inget att ta bort i old/. (count=$COUNT ≤ keep=$KEEP)"
fi

# ----- STEG 3: Verifiering -----
if ! $DRYRUN; then
  log "Verifierar att current/ matchar källa..."
  diff -r "$SOURCE_DIR" "$CURRENT_BASE/$TIMESTAMP" >/dev/null && verify_ok=true || verify_ok=false

  if $verify_ok; then
    log "Verifiering OK."
  else
    log "❌ Verifiering MISSLYCKADES."
  fi
fi

log "Rotation färdig."
log "------------------------------------------------------------"
ls -la "$BASE_DIR" || true
ls -la "$OLD_BASE" || true
echo " backup färdigt "
sleep 5

