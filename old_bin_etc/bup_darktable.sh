#!/bin/bash
# === backup_and_deploy.sh ===
# Enkel backuprotation: flytta current → old och new → current

# ---- Konfiguration ----
BASE_DIR="/path/to/your/project"   # <-- ändra till din katalog
NEW_DIR="$BASE_DIR/new"            # ny version
CURRENT_DIR="$BASE_DIR/current"    # aktiv version
OLD_DIR="$BASE_DIR/old"            # föregående version

echo "=== Startar backup och uppdatering ==="

# Kontrollera att nya filer finns
if [ ! -d "$NEW_DIR" ]; then
    echo "Fel: $NEW_DIR finns inte!"
    exit 1
fi

# Ta bort tidigare backup om den finns
if [ -d "$OLD_DIR" ]; then
    echo "Tar bort gammal backup..."
    rm -rf "$OLD_DIR"
fi

# Flytta nuvarande till old (om den finns)
if [ -d "$CURRENT_DIR" ]; then
    echo "Flyttar current → old..."
    mv "$CURRENT_DIR" "$OLD_DIR"
fi

# Flytta new → current
echo "Flyttar new → current..."
mv "$NEW_DIR" "$CURRENT_DIR"

echo "=== Klart! ==="
ls -l "$BASE_DIR"

