#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"
TOOLKIT_SOURCE="$SOURCE_DIR/darktable-toolkit-1.0.sh"
TOOLKIT_DEST="$BIN_DIR/darktable-toolkit-1.0.sh"
APPLICATIONS_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/darktable-toolkit.desktop"

die() { printf 'FEL: %s\n' "$*" >&2; exit 1; }

[[ -f "$TOOLKIT_SOURCE" ]] || die "Hittar inte $TOOLKIT_SOURCE"

mkdir -p "$BIN_DIR" "$APPLICATIONS_DIR"
install -m 0755 "$TOOLKIT_SOURCE" "$TOOLKIT_DEST"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Darktable Toolkit
Comment=Backup, restore, migrering och databasunderhåll för Darktable
Exec=gnome-terminal -- bash -lc '$TOOLKIT_DEST; exec bash'
Icon=darktable
Terminal=false
Categories=Utility;Graphics;Photography;
Keywords=darktable;backup;restore;sqlite;photo;
StartupNotify=true
EOF
chmod 0644 "$DESKTOP_FILE"

OLD="$BIN_DIR/superinstaller-4.19.sh"
NEW="$BIN_DIR/superinstaller-4.20.sh"

if [[ -f "$OLD" ]]; then
    python3 - "$OLD" "$NEW" <<'PY'
from pathlib import Path
import re, sys

old, new = map(Path, sys.argv[1:])
text = old.read_text(encoding="utf-8")
text = text.replace("Superinstaller 4.19", "Superinstaller 4.20")
text = text.replace('VERSION="4.19"', 'VERSION="4.20"')

if 'DARKTABLE_TOOLKIT=' not in text:
    pat = r'(MIGRATE_DARKTABLE="\$BIN_DIR/migrate_darktable-6\.2\.sh"\n)'
    text, n = re.subn(
        pat,
        r'\1DARKTABLE_TOOLKIT="$BIN_DIR/darktable-toolkit-1.0.sh"\n',
        text,
        count=1
    )
    if n == 0:
        raise SystemExit("Kunde inte hitta MIGRATE_DARKTABLE-raden.")

start = text.find("utilities_menu()")
end = text.find("# ------------------------------------------------------------", start + 20)
if start < 0 or end < 0:
    raise SystemExit("Kunde inte avgränsa Utilities-menyn.")

block = text[start:end]

for label in [
    r'\s*"3"\s+"Darktable: säkerhetskopiera konfiguration \(5\.1\)" \\\n',
    r'\s*"4"\s+"Darktable: återställ en snapshot \(1\.0\)" \\\n',
    r'\s*"8"\s+"Migrera Darktable \(6\.2\)" \\\n',
    r'\s*"9"\s+"Kontrollera/fixa Darktable OpenCL" \\\n',
]:
    block = re.sub(label, "", block, count=1)

anchor = '"2"  "AppImage: förbered Ubuntu 26.04" \\\n'
if '"3"  "Darktable Toolkit"' not in block:
    block = block.replace(
        anchor,
        anchor + '                "3"  "Darktable Toolkit" \\\n',
        1
    )

for num in ("3", "4", "8", "9"):
    block = re.sub(
        rf'\n\s*{num}\).*?(?=\n\s*(?:[0-9]+|b)\))',
        '',
        block,
        count=1,
        flags=re.S
    )

branch = (
    '\n            3) run_script \\\n'
    '                   "$DARKTABLE_TOOLKIT" \\\n'
    '                   "Darktable Toolkit" ;;\n'
)
marker = re.search(r'(\n\s*2\).*?;;)', block, flags=re.S)
if not marker:
    raise SystemExit("Kunde inte hitta case-gren 2 i Utilities.")
block = block[:marker.end()] + branch + block[marker.end():]
text = text[:start] + block + text[end:]

if "Darktable Toolkit|$DARKTABLE_TOOLKIT" not in text:
    text = text.replace(
        "Migrera Darktable 6.2|$MIGRATE_DARKTABLE\n",
        "Migrera Darktable 6.2|$MIGRATE_DARKTABLE\n"
        "Darktable Toolkit|$DARKTABLE_TOOLKIT\n",
        1
    )

new.write_text(text, encoding="utf-8")
new.chmod(0o755)
PY
    echo "Skapade: $NEW"
else
    echo "OBS: $OLD hittades inte."
    echo "Toolkit installerades ändå och finns i Ubuntu-programmen."
fi

bash -n "$TOOLKIT_DEST"
[[ ! -f "$NEW" ]] || bash -n "$NEW"

command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true

echo
echo "Klart."
echo "Toolkit:        $TOOLKIT_DEST"
echo "Ubuntu-app:     $DESKTOP_FILE"
[[ ! -f "$NEW" ]] || echo "Superinstaller: $NEW"
echo
echo "Starta direkt med:"
echo "  $TOOLKIT_DEST"
