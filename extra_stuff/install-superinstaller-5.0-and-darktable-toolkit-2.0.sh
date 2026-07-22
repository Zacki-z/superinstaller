#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"
APP_DIR="$HOME/.local/share/applications"

TOOLKIT_SOURCE="$SOURCE_DIR/darktable-toolkit-2.0.sh"
TOOLKIT_DEST="$BIN_DIR/darktable-toolkit-2.0.sh"
SUPER_SOURCE="$BIN_DIR/superinstaller-4.19.sh"
SUPER_DEST="$BIN_DIR/superinstaller-5.0.sh"

die() {
    printf 'FEL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$TOOLKIT_SOURCE" ]] || die "Hittar inte $TOOLKIT_SOURCE"
[[ -f "$SUPER_SOURCE" ]] || die "Hittar inte $SUPER_SOURCE"

mkdir -p "$BIN_DIR" "$APP_DIR"
install -m 0755 "$TOOLKIT_SOURCE" "$TOOLKIT_DEST"

python3 - "$SUPER_SOURCE" "$SUPER_DEST" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

text = text.replace("# Superinstaller 4.19", "# Superinstaller 5.0", 1)
text = text.replace('VERSION="4.19"', 'VERSION="5.0"', 1)

old_vars = """MIGRATE_DARKTABLE="$BIN_DIR/migrate_darktable-6.2.sh"
DARKTABLE_OPENCL="$BIN_DIR/ensure_darktable_opencl-1.0.sh"
SURFACE_TABLET_MODE="$BIN_DIR/surface_tablet_mode-1.0.sh"
"""
new_vars = """MIGRATE_DARKTABLE="$BIN_DIR/migrate_darktable-6.2.sh"
DARKTABLE_OPENCL="$BIN_DIR/ensure_darktable_opencl-1.0.sh"
DARKTABLE_TOOLKIT="$BIN_DIR/darktable-toolkit-2.0.sh"
SURFACE_TABLET_MODE="$BIN_DIR/surface_tablet_mode-1.0.sh"
"""
if old_vars not in text:
    raise SystemExit("Kunde inte hitta Utilities-variablerna.")
text = text.replace(old_vars, new_vars, 1)

old_entries = """Migrera Darktable 6.2|$MIGRATE_DARKTABLE
Darktable OpenCL|$DARKTABLE_OPENCL
Surface tablet mode|$SURFACE_TABLET_MODE
"""
new_entries = """Migrera Darktable 6.2|$MIGRATE_DARKTABLE
Darktable OpenCL|$DARKTABLE_OPENCL
Darktable Toolkit 2.0|$DARKTABLE_TOOLKIT
Surface tablet mode|$SURFACE_TABLET_MODE
"""
if old_entries not in text:
    raise SystemExit("Kunde inte hitta skriptlistan.")
text = text.replace(old_entries, new_entries, 1)

start_marker = """# ------------------------------------------------------------
# Meny: Utilities
# ------------------------------------------------------------
"""
end_marker = """# ------------------------------------------------------------
# Huvudprogram
# ------------------------------------------------------------
"""

start = text.find(start_marker)
end = text.find(end_marker, start + len(start_marker))
if start < 0 or end < 0:
    raise SystemExit("Kunde inte avgränsa Utilities-menyn.")

new_utilities = """# ------------------------------------------------------------
# Meny: Utilities
# ------------------------------------------------------------

utilities_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \\
                --title "$MAIN_TITLE – Utilities" \\
                --menu "Välj ett verktyg (använd piltangenterna för att rulla):" \\
                22 92 13 \\
                "1"  "AppImage: skapa skrivbordsikoner" \\
                "2"  "AppImage: förbered Ubuntu 26.04" \\
                "3"  "Darktable Toolkit" \\
                "4"  "Programinställningar: säkerhetskopiera" \\
                "5"  "Programinställningar: återställ" \\
                "6"  "Avinstallera apt-paket" \\
                "7"  "Surface tablet mode" \\
                "8"  "Lösenordsgenerator" \\
                "9"  "Montera Samba" \\
                "10" "Rätta framtida tidsstämplar" \\
                "11" "Kontrollera alla scriptsökvägar" \\
                "12" "Visa innehållet i my_bin" \\
                "b"  "Tillbaka till huvudmenyn" \\
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                run_script "$APPIMAGE_DESKTOPIFY" "AppImage: skapa skrivbordsikoner"
                ;;
            2)
                run_script "$APPIMAGE_UBUNTU26" "AppImage: förbered Ubuntu 26.04"
                ;;
            3)
                run_script "$DARKTABLE_TOOLKIT" "Darktable Toolkit 2.0"
                ;;
            4)
                run_with_dryrun_menu \\
                    "Säkerhetskopiera programinställningar" \\
                    "$BACKUP_APPCONFIG"
                ;;
            5)
                run_script "$RESTORE_APPCONFIG" "Återställ programinställningar"
                ;;
            6)
                run_with_mode_menu "Avinstallera apt-paket" "$APT_UNINSTALL"
                ;;
            7)
                run_script "$SURFACE_TABLET_MODE" "Surface tablet mode"
                ;;
            8)
                run_script "$PASSWORD_GENERATOR" "Lösenordsgenerator"
                ;;
            9)
                run_script "$MONTERA_SAMBA" "Montera Samba"
                ;;
            10)
                run_script "$FIX_TIMESTAMPS" "Rätta framtida tidsstämplar"
                ;;
            11)
                show_script_status
                ;;
            12)
                show_my_bin
                ;;
            b)
                return 0
                ;;
        esac
    done
}

"""

text = text[:start] + new_utilities + text[end:]
dest.write_text(text, encoding="utf-8")
dest.chmod(0o755)
PY

bash -n "$TOOLKIT_DEST"
bash -n "$SUPER_DEST"

cat >"$APP_DIR/darktable-toolkit.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Darktable Toolkit
Comment=Backup, restore, migration och databasunderhåll för Darktable
Exec=$TOOLKIT_DEST
Icon=darktable
Terminal=true
Categories=Utility;Graphics;Photography;
Keywords=darktable;backup;restore;sqlite;photo;
StartupNotify=true
EOF

cat >"$APP_DIR/superinstaller.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Superinstaller
Comment=Installera program, flytta data och kör systemverktyg
Exec=$SUPER_DEST
Icon=utilities-terminal
Terminal=true
Categories=Utility;System;
Keywords=installera;backup;restore;darktable;appimage;
StartupNotify=true
EOF

chmod 0644 "$APP_DIR/darktable-toolkit.desktop" "$APP_DIR/superinstaller.desktop"

command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true

printf '\nKlart.\n\n'
printf 'Darktable Toolkit 2.0:\n  %s\n\n' "$TOOLKIT_DEST"
printf 'Superinstaller 5.0:\n  %s\n\n' "$SUPER_DEST"
printf 'Originalet 4.19 är orört:\n  %s\n\n' "$SUPER_SOURCE"
printf 'Starta med:\n  %s\n' "$SUPER_DEST"
