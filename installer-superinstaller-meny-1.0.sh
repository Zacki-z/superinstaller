#!/usr/bin/env bash
# installer-superinstaller-meny-1.0.sh
#
# Lägger till Superinstaller i Ubuntus programmeny.
#
# Standard:
#   Script: ~/my_bin/superinstaller-4.19.sh
#   Menypost: ~/.local/share/applications/superinstaller.desktop
#
# Användning:
#   ./installer-superinstaller-meny-1.0.sh
#   ./installer-superinstaller-meny-1.0.sh --remove

set -Eeuo pipefail

SUPERINSTALLER="$HOME/my_bin/superinstaller-4.19.sh"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/superinstaller.desktop"

remove_entry() {
    if [[ -f "$DESKTOP_FILE" ]]; then
        rm -f -- "$DESKTOP_FILE"
        command -v update-desktop-database >/dev/null 2>&1 &&
            update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
        echo "Menyposten har tagits bort:"
        echo "  $DESKTOP_FILE"
    else
        echo "Ingen menypost finns att ta bort."
    fi
}

case "${1:-}" in
    --remove)
        remove_entry
        exit 0
        ;;
    --help|-h)
        cat <<EOF
Användning:
  $(basename "$0")
      Lägg till Superinstaller i Ubuntus programmeny.

  $(basename "$0") --remove
      Ta bort menyposten.
EOF
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Okänt argument: $1" >&2
        exit 1
        ;;
esac

if [[ ! -f "$SUPERINSTALLER" ]]; then
    echo "FEL: Hittar inte Superinstaller:" >&2
    echo "  $SUPERINSTALLER" >&2
    exit 1
fi

chmod +x "$SUPERINSTALLER"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Superinstaller
Comment=Installera program, flytta data och kör systemverktyg
Exec=$SUPERINSTALLER
Icon=utilities-terminal
Terminal=true
Categories=Utility;System;
Keywords=installera;backup;restore;darktable;appimage;
StartupNotify=true
EOF

chmod 644 "$DESKTOP_FILE"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP_FILE" || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "Klart. Superinstaller har lagts till i Ubuntus programmeny."
echo
echo "Menypost:"
echo "  $DESKTOP_FILE"
echo
echo "Program:"
echo "  $SUPERINSTALLER"
echo
echo "Sök efter 'Superinstaller' i programöversikten."
