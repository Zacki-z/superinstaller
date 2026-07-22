#!/usr/bin/env bash
# ============================================================
# restore_darktable-1.0.sh
# ============================================================
# Enkel och säker återställning av en Darktable-snapshot skapad
# av backup_darktable-5.1.sh.
#
# Snapshotstruktur:
#   ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/
#
# Standardmål för AppImage/APT:
#   ~/.config/darktable
#
# Funktioner:
#   - Visar de tre senaste giltiga snapshotsen.
#   - Låter användaren välja snapshot i en meny.
#   - Kontrollerar library.db och data.db.
#   - Har dry-run-läge.
#   - Skapar en säkerhetskopia av befintligt mål före återställning.
#   - Återställer via staging så att målet inte lämnas halvkopierat.
#
# Användning:
#   restore_darktable-1.0.sh
#   restore_darktable-1.0.sh --dry-run
#   restore_darktable-1.0.sh --base-dir="$HOME/bup_darktable"
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0"
SCRIPT_NAME="$(basename "$0")"

BASE_DIR="$HOME/bup_darktable"
DEST_DIR="$HOME/.config/darktable"
DRY_RUN=false

STAGE_DIR=""
OLD_DEST=""
COMMITTED=false

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "FEL: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
$SCRIPT_NAME version $VERSION

Återställer en Darktable-snapshot till:
  $DEST_DIR

Användning:
  $SCRIPT_NAME [alternativ]

Alternativ:
  --dry-run, -n
      Visa vad som skulle återställas utan att ändra något.

  --base-dir=PATH
      Katalogen som innehåller snapshots.
      Standard: $BASE_DIR

  --dest=PATH
      Målkatalog för Darktable.
      Standard för AppImage/APT: $DEST_DIR

  --help, -h
      Visa denna hjälp.
EOF
}

expand_tilde() {
    case "$1" in
        "~")   printf '%s' "$HOME" ;;
        "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
        *)     printf '%s' "$1" ;;
    esac
}

cleanup() {
    local rc=$?

    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR" || true
    fi

    if ((rc != 0)) && ! $COMMITTED &&
       [[ -n "$OLD_DEST" && -e "$OLD_DEST" && ! -e "$DEST_DIR" ]]; then
        log "Återställer den tidigare Darktable-katalogen."
        mv -- "$OLD_DEST" "$DEST_DIR" || true
    fi

    return "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while (($# > 0)); do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=true
            ;;
        --base-dir=*)
            BASE_DIR="${1#*=}"
            ;;
        --dest=*)
            DEST_DIR="${1#*=}"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Okänt argument: $1"
            ;;
    esac
    shift
done

BASE_DIR="$(expand_tilde "$BASE_DIR")"
DEST_DIR="$(expand_tilde "$DEST_DIR")"

for cmd in rsync find sort grep head du awk date mkdir mktemp mv rm ps; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Nödvändigt kommando saknas: $cmd"
done

[[ -d "$BASE_DIR" ]] ||
    die "Backupkatalogen finns inte: $BASE_DIR"

darktable_running() {
    ps -u "$(id -u)" -o pid=,comm=,args= |
        awk '
            BEGIN { IGNORECASE=1 }
            $2 == "darktable" { print; found=1; next }
            $2 == "AppRun" && $0 ~ /darktable/ { print; found=1; next }
            $0 ~ /darktable[^ ]*\.AppImage/ { print; found=1 }
            END { exit(found ? 0 : 1) }
        '
}

check_database() {
    local database="$1"
    local label="$2"
    local result=""

    [[ -f "$database" ]] ||
        die "$label saknas: $database"

    log "Kontrollerar $label ..."

    if command -v sqlite3 >/dev/null 2>&1; then
        result="$(sqlite3 -readonly "$database" 'PRAGMA quick_check;' 2>&1)" ||
            die "SQLite-kontrollen misslyckades för $database: $result"
    elif command -v python3 >/dev/null 2>&1; then
        result="$(
            python3 - "$database" <<'PY'
import sqlite3
import sys
from pathlib import Path
from urllib.parse import quote

path = str(Path(sys.argv[1]).resolve())
uri = "file:" + quote(path) + "?mode=ro"

connection = sqlite3.connect(uri, uri=True)
try:
    rows = connection.execute("PRAGMA quick_check;").fetchall()
finally:
    connection.close()

print("\n".join(str(row[0]) for row in rows))
PY
        )" || die "Python kunde inte kontrollera databasen: $database"
    else
        log "VARNING: Varken sqlite3 eller python3 finns. Databasen kontrolleras inte."
        return 0
    fi

    [[ "$result" == "ok" ]] ||
        die "$label rapporterade problem: $result"

    log "OK: $label rapporterar 'ok'."
}

mapfile -t CANDIDATES < <(
    find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null |
        grep -E '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$' |
        sort -r |
        head -n 3
)

SNAPSHOTS=()
for name in "${CANDIDATES[@]}"; do
    dir="$BASE_DIR/$name/darktable"
    if [[ -f "$dir/darktablerc" &&
          -f "$dir/library.db" &&
          -f "$dir/data.db" ]]; then
        SNAPSHOTS+=("$dir")
    fi
done

((${#SNAPSHOTS[@]} > 0)) ||
    die "Hittar ingen giltig snapshot under $BASE_DIR."

echo
echo "Tillgängliga Darktable-snapshots:"
echo

for i in "${!SNAPSHOTS[@]}"; do
    snapshot="${SNAPSHOTS[$i]}"
    name="$(basename "$(dirname "$snapshot")")"
    size="$(du -sh "$snapshot" | awk '{print $1}')"
    printf '  %d) %s  (%s)\n' "$((i + 1))" "$name" "$size"
done

echo "  q) Avbryt"
echo

while true; do
    read -r -p "Välj snapshot [1-${#SNAPSHOTS[@]} eller q]: " choice

    case "$choice" in
        q|Q)
            log "Avbrutet."
            exit 0
            ;;
        ''|*[!0-9]*)
            echo "Ogiltigt val."
            ;;
        *)
            if ((choice >= 1 && choice <= ${#SNAPSHOTS[@]})); then
                SOURCE_DIR="${SNAPSHOTS[$((choice - 1))]}"
                break
            fi
            echo "Ogiltigt val."
            ;;
    esac
done

echo
log "Vald snapshot: $SOURCE_DIR"
log "Mål:          $DEST_DIR"

if running="$(darktable_running 2>/dev/null)"; then
    printf '%s\n' "$running" >&2
    die "Darktable körs. Stäng programmet helt före återställning."
fi

check_database "$SOURCE_DIR/library.db" "library.db"
check_database "$SOURCE_DIR/data.db" "data.db"

if $DRY_RUN; then
    echo
    echo "============================================================"
    echo "DRY-RUN – inga filer eller kataloger ändras"
    echo "============================================================"
    echo "Källa:"
    echo "  $SOURCE_DIR"
    echo
    echo "Mål:"
    echo "  $DEST_DIR"
    echo
    echo "Följande skillnader skulle återställas:"
    echo

    rsync -a --delete --dry-run --itemize-changes \
        "$SOURCE_DIR/" "$DEST_DIR/"

    echo
    log "DRY-RUN klar. Ingenting ändrades."
    exit 0
fi

echo
read -r -p "Återställ vald snapshot och ersätt nuvarande konfiguration? [j/N] " answer
case "$answer" in
    j|J|ja|JA|Ja) ;;
    *)
        log "Avbrutet."
        exit 0
        ;;
esac

STAMP="$(date +%Y%m%d-%H%M%S)"
SAFETY_ROOT="$BASE_DIR/restore-safety/$STAMP"
DEST_PARENT="$(dirname "$DEST_DIR")"

mkdir -p -- "$DEST_PARENT"

if [[ -d "$DEST_DIR" ]]; then
    log "Skapar säkerhetskopia av nuvarande mål:"
    log "  $SAFETY_ROOT/darktable"
    mkdir -p -- "$SAFETY_ROOT/darktable"
    rsync -a "$DEST_DIR/" "$SAFETY_ROOT/darktable/"
fi

STAGE_DIR="$(mktemp -d "$DEST_PARENT/.darktable-restore.XXXXXX")"

log "Kopierar snapshoten till staging."
rsync -a --delete "$SOURCE_DIR/" "$STAGE_DIR/"

check_database "$STAGE_DIR/library.db" "library.db i staging"
check_database "$STAGE_DIR/data.db" "data.db i staging"

if [[ -e "$DEST_DIR" ]]; then
    OLD_DEST="${DEST_DIR}.pre-restore-$STAMP"
    log "Flyttar nuvarande mål till en tillfällig plats."
    mv -- "$DEST_DIR" "$OLD_DEST"
fi

log "Aktiverar den återställda konfigurationen."
mv -- "$STAGE_DIR" "$DEST_DIR"
STAGE_DIR=""
COMMITTED=true
sync

if [[ -n "$OLD_DEST" && -e "$OLD_DEST" ]]; then
    rm -rf -- "$OLD_DEST"
    OLD_DEST=""
fi

check_database "$DEST_DIR/library.db" "installerad library.db"
check_database "$DEST_DIR/data.db" "installerad data.db"

echo
log "Återställningen är klar."
log "Aktiv konfiguration: $DEST_DIR"

if [[ -d "$SAFETY_ROOT/darktable" ]]; then
    log "Föregående konfiguration finns sparad i:"
    log "  $SAFETY_ROOT/darktable"
fi
