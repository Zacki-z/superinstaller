#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Rotera versioner: current -> old/<timestamp>, new -> current
# Behåll endast de 3 senaste i old/
set -euo pipefail

# ----- Konfiguration -----
BASE_DIR="/path/to/your/project"   # <-- ändra
NEW_DIR="$BASE_DIR/new"
CURRENT_DIR="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"           # här lagras tidsstämplade backuper
KEEP=3                             # antal att behålla

# ----- Lås för att undvika parallella körningar -----
LOCKFILE="$BASE_DIR/.backup_rotate.lock"
exec 9>"$LOCKFILE"
flock -n 9 || { echo "Ett annat jobb körs. Avbryter."; exit 1; }

echo "=== Startar rotation $(date) ==="
echo "Bas: $BASE_DIR"

# Säkerställ kataloger
mkdir -p "$OLD_BASE"

# Kontrollera att NEW finns
if [[ ! -d "$NEW_DIR" ]]; then
  echo "Fel: $NEW_DIR finns inte."
  exit 1
fi

# Skapa tidsstämpel (lokal tid)
TS="$(date +%Y%m%d-%H%M%S)"

# Flytta current -> old/<TS> om current finns
if [[ -d "$CURRENT_DIR" ]]; then
  DEST="$OLD_BASE/$TS"
  echo "Flyttar current -> $DEST"
  mv "$CURRENT_DIR" "$DEST"
else
  echo "Ingen current hittades – hoppar över backup av current."
fi

# Flytta new -> current
echo "Flyttar new -> current"
mv "$NEW_DIR" "$CURRENT_DIR"

# Rensa äldre än de KEEP senaste
echo "Rensar gamla versioner, behåller $KEEP senaste ..."
# Hämta tidsstämplade mappar i old/ sorterade nyast först
mapfile -t ALL <<EOF
$(find "$OLD_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
  | grep -E '^[0-9]{8}-[0-9]{6}$' \
  | sort -r)
EOF

if (( ${#ALL[@]} > KEEP )); then
  # Ta allt från index KEEP och framåt = de äldsta
  for (( i=KEEP; i<${#ALL[@]}; i++ )); do
    TARGET="$OLD_BASE/${ALL[$i]}"
    echo "Tar bort: $TARGET"
    rm -rf -- "$TARGET"
  done
else
  echo "Inget att ta bort (<= $KEEP versioner)."
fi

echo "=== Klart ==="
echo "Innehåll i $BASE_DIR:"
ls -la "$BASE_DIR"
echo "Innehåll i $OLD_BASE:"
ls -la "$OLD_BASE"

