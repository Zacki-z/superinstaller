#!/usr/bin/env bash
#
# create-superinstaller-appmenu-1.0.sh
#
# Skapar en programstartare för Superinstaller i Ubuntus appmeny.
#

set -Eeuo pipefail
IFS=$'\n\t'

SUPERINSTALLER="$HOME/my_bin/superinstaller-5.0.sh"
ICON="$HOME/my_bin/etc/wrench2.png"
APPLICATIONS_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/superinstaller.desktop"

die() {
    printf 'FEL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$SUPERINSTALLER" ]] ||
    die "Hittar inte Superinstaller:\n$SUPERINSTALLER"

[[ -f "$ICON" ]] ||
    die "Hittar inte ikonfilen:\n$ICON"

chmod +x "$SUPERINSTALLER"
mkdir -p "$APPLICATIONS_DIR"

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Superinstaller
Comment=Installera program, flytta data och kör systemverktyg
Exec=$SUPERINSTALLER
Icon=$ICON
Terminal=true
Categories=Utility;System;
Keywords=superinstaller;installera;verktyg;backup;restore;
StartupNotify=true
EOF

chmod 0644 "$DESKTOP_FILE"

if command -v desktop-file-validate >/dev/null 2>&1; then
    if ! desktop-file-validate "$DESKTOP_FILE"; then
        die "Programstartaren klarade inte desktop-file-validate."
    fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

printf '\nKlart.\n\n'
printf 'Programstartare:\n  %s\n\n' "$DESKTOP_FILE"
printf 'Program:\n  %s\n\n' "$SUPERINSTALLER"
printf 'Ikon:\n  %s\n\n' "$ICON"
printf 'Sök efter ”Superinstaller” i Ubuntus appmeny.\n'
