#!/bin/bash
set -euo pipefail

# ============================
#  REQUIRE ENV VARIABLE
# ============================

if [[ -z "${SUPERINSTALLER_PATH:-}" ]]; then
    echo "❌ SUPERINSTALLER_PATH är inte satt."
    echo "Sätt den med:"
    echo "   export SUPERINSTALLER_PATH=/full/path/to/superinstaller"
    exit 1
fi

# ============================
#  PATHS
# ============================

APP_NAME="superinstaller"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_PATH="$HOME/.local/share/icons/${APP_NAME}.png"

mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

# ============================
#  CREATE SYMLINK
# ============================

ln -sf "$SUPERINSTALLER_PATH" "$BIN_DIR/$APP_NAME"
chmod +x "$BIN_DIR/$APP_NAME"

echo "🔗 Länk skapad: $BIN_DIR/$APP_NAME → $SUPERINSTALLER_PATH"

# ============================
#  CREATE DESKTOP FILE
# ============================

DESKTOP_FILE="$DESKTOP_DIR/${APP_NAME}.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Superinstaller
Comment=Run the Superinstaller utility
Exec=gnome-terminal -- $BIN_DIR/$APP_NAME
Icon=$ICON_PATH
Terminal=false
Categories=Utility;
EOF

echo "🖥️ Desktop-fil skapad: $DESKTOP_FILE"

# ============================
#  UPDATE DESKTOP DATABASE
# ============================

update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

echo "✔️ Klart! Superinstaller finns nu i Ubuntu-menyn."


