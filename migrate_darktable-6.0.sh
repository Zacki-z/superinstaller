#!/usr/bin/env bash
#
# migrate_darktable-6.0.sh
#
# Säker migrering av darktable från Snap till:
#   - AppImage eller APT: ~/.config/darktable
#   - Flatpak:            ~/.var/app/org.darktable.Darktable/config/darktable
#
# Standardmål är AppImage.
#
# Exempel:
#   ./migrate_darktable-6.0.sh --dry-run
#   ./migrate_darktable-6.0.sh
#   ./migrate_darktable-6.0.sh --appimage ~/Applications/darktable.AppImage
#   ./migrate_darktable-6.0.sh --target flatpak
#
# Kör som vanlig användare och stäng darktable först.
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="6.0"
DRY_RUN=false
DEBUG=false
TARGET="appimage"
APPIMAGE_PATH=""
ENABLE_OPENCL=true
TEST_OPENCL=false
ASSUME_YES=false
FORCE_OLDER=false
SKIP_VERSION_CHECK=false

SNAP_BASE="$HOME/snap/darktable"
BACKUP_ROOT="$HOME/darktable_migration_backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

STAGE_DIR=""
OLD_DEST=""
DEST_CONFIG=""
COMMITTED=false

log() {
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*" >&2
}

ok() {
    log "OK: $*"
}

warn() {
    log "VARNING: $*"
}

die() {
    log "FEL: $*"
    exit 1
}

usage() {
    cat <<'EOF'
migrate_darktable-6.0.sh

Migrerar hela darktables konfigurationskatalog från Snap till AppImage/APT
eller Flatpak.

Användning:
  migrate_darktable-6.0.sh [alternativ]

Alternativ:
  --target appimage   Mål ~/.config/darktable (standard)
  --target apt        Mål ~/.config/darktable
  --target flatpak    Mål Flatpaks darktable-katalog
  --appimage FIL      AppImage som används för versions- och OpenCL-test
  --dry-run, -n       Visa vad som skulle göras utan att skriva något
  --no-opencl         Ändra inte nyckeln opencl i darktablerc
  --test-opencl       Kör OpenCL-test efter lyckad migrering
  --skip-version-check
                      Hoppa över jämförelse av darktable-versioner
  --force-older       Tillåt ett känt äldre målprogram
  --yes, -y           Bekräfta migreringen automatiskt
  --debug             Visa körda Bash-kommandon
  --help, -h          Visa hjälp

Viktigt:
  Darktable måste vara helt avstängt.
  Målversionen bör vara samma eller nyare än Snap-versionen.
EOF
}

while (($#)); do
    case "$1" in
        --target)
            (($# >= 2)) || die "--target kräver ett värde."
            TARGET="$2"
            shift 2
            ;;
        --appimage)
            (($# >= 2)) || die "--appimage kräver en sökväg."
            APPIMAGE_PATH="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --no-opencl)
            ENABLE_OPENCL=false
            shift
            ;;
        --test-opencl)
            TEST_OPENCL=true
            shift
            ;;
        --skip-version-check)
            SKIP_VERSION_CHECK=true
            shift
            ;;
        --force-older)
            FORCE_OLDER=true
            shift
            ;;
        --yes|-y)
            ASSUME_YES=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Okänt alternativ: $1"
            ;;
    esac
done

$DEBUG && set -x

case "$TARGET" in
    appimage|apt)
        DEST_CONFIG="$HOME/.config/darktable"
        ;;
    flatpak)
        DEST_CONFIG="$HOME/.var/app/org.darktable.Darktable/config/darktable"
        ;;
    *)
        die "Ogiltigt mål: $TARGET. Använd appimage, apt eller flatpak."
        ;;
esac

cleanup() {
    local rc=$?

    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR" || true
    fi

    if ((rc != 0)) && ! $COMMITTED &&
       [[ -n "$OLD_DEST" && -e "$OLD_DEST" && ! -e "$DEST_CONFIG" ]]; then
        warn "Återställer den tidigare målkatalogen."
        mv -- "$OLD_DEST" "$DEST_CONFIG" || true
    fi
}
trap cleanup EXIT INT TERM

human_size() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        printf '%s byte\n' "$bytes"
    fi
}

find_snap_source() {
    local current="$SNAP_BASE/current"
    local resolved=""
    local revisions=()

    if [[ -e "$current" ]]; then
        resolved="$(readlink -f -- "$current" 2>/dev/null || true)"
        if [[ -n "$resolved" && -d "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    [[ -d "$SNAP_BASE" ]] || return 1

    mapfile -t revisions < <(
        find "$SNAP_BASE" -mindepth 1 -maxdepth 1 -type d \
            -printf '%f\n' |
        awk '/^[0-9]+$/' |
        sort -n
    )

    ((${#revisions[@]} > 0)) || return 1
    printf '%s/%s\n' "$SNAP_BASE" "${revisions[-1]}"
}

find_appimage() {
    local candidates=()
    local newest=""
    local file

    if [[ -n "$APPIMAGE_PATH" ]]; then
        [[ -f "$APPIMAGE_PATH" ]] ||
            die "AppImage-filen finns inte: $APPIMAGE_PATH"
        readlink -f -- "$APPIMAGE_PATH"
        return 0
    fi

    shopt -s nullglob nocaseglob
    candidates=(
        "$HOME/Applications/"*darktable*.AppImage
        "$HOME/Applications/"*darktable*.appimage
    )
    shopt -u nullglob nocaseglob

    ((${#candidates[@]} > 0)) || return 1

    newest="${candidates[0]}"
    for file in "${candidates[@]:1}"; do
        [[ "$file" -nt "$newest" ]] && newest="$file"
    done

    readlink -f -- "$newest"
}

darktable_processes() {
    ps -u "$(id -u)" -o pid=,comm=,args= |
        awk '
            BEGIN { IGNORECASE=1 }
            /migrate_darktable-[0-9.]+\.sh/ { next }
            $2 ~ /^darktable/ { print; next }
            $2 == "AppRun" && $0 ~ /darktable/ { print; next }
            $0 ~ /darktable[^ ]*\.AppImage/ { print }
        '
}

check_not_running() {
    local running
    running="$(darktable_processes || true)"

    if [[ -n "$running" ]]; then
        printf '%s\n' "$running" >&2
        die "Darktable körs. Stäng programmet helt och försök igen."
    fi
}

check_lock_files() {
    local dir="$1"
    local locks=()

    [[ -d "$dir" ]] || return 0

    mapfile -t locks < <(
        find "$dir" -maxdepth 1 -type f \
            \( -name '*.db.lock' -o -name 'library.db.lock' -o -name 'data.db.lock' \) \
            -print
    )

    if ((${#locks[@]} > 0)); then
        printf '%s\n' "${locks[@]}" >&2
        die "Databasens låsfil finns kvar. Kontrollera att darktable är stängt. Ta inte bort låset utan att först kontrollera detta."
    fi
}

check_database() {
    local database="$1"
    local label="$2"
    local result=""

    if [[ ! -f "$database" ]]; then
        if [[ "$label" == "library.db" ]]; then
            die "$label saknas: $database"
        fi
        warn "$label saknas och kan därför inte kontrolleras: $database"
        return 0
    fi

    log "Kontrollerar SQLite-databasen $label ..."

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
        )" || die "Python kunde inte kontrollera SQLite-databasen: $database"
    else
        warn "Varken sqlite3 eller python3 finns. Databasen kan inte integritetskontrolleras."
        return 0
    fi

    if [[ "$result" != "ok" ]]; then
        printf '%s\n' "$result" >&2
        die "Integritetskontrollen rapporterade problem i $database."
    fi

    ok "$label är läsbar och rapporterar 'ok'."
}

extract_version() {
    grep -Eo '[0-9]+([.][0-9]+){1,3}' | head -n 1
}

get_source_version() {
    local output=""

    command -v snap >/dev/null 2>&1 || return 1
    snap list darktable >/dev/null 2>&1 || return 1

    output="$(timeout 20s snap run darktable --version 2>&1 || true)"
    printf '%s\n' "$output" | extract_version
}

get_target_version() {
    local appimage="$1"
    local output=""

    case "$TARGET" in
        appimage)
            [[ -n "$appimage" ]] || return 1
            chmod u+x "$appimage" 2>/dev/null || true
            output="$(timeout 20s "$appimage" --version 2>&1 || true)"
            if [[ -z "$(printf '%s\n' "$output" | extract_version)" ]]; then
                output="$(timeout 30s "$appimage" --appimage-extract-and-run --version 2>&1 || true)"
            fi
            ;;
        apt)
            command -v darktable >/dev/null 2>&1 || return 1
            output="$(timeout 20s darktable --version 2>&1 || true)"
            ;;
        flatpak)
            command -v flatpak >/dev/null 2>&1 || return 1
            flatpak info org.darktable.Darktable >/dev/null 2>&1 || return 1
            output="$(timeout 30s flatpak run org.darktable.Darktable --version 2>&1 || true)"
            ;;
    esac

    printf '%s\n' "$output" | extract_version
}

version_is_older() {
    local source_version="$1"
    local target_version="$2"
    local first

    [[ "$source_version" != "$target_version" ]] || return 1

    first="$(
        printf '%s\n%s\n' "$source_version" "$target_version" |
        sort -V |
        head -n 1
    )"

    [[ "$first" == "$target_version" ]]
}

ensure_kv() {
    local key="$1"
    local value="$2"
    local file="$3"
    local temp

    mkdir -p "$(dirname "$file")"
    touch "$file"

    temp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN { found=0 }
        index($0, key "=") == 1 {
            if (!found) {
                print key "=" value
                found=1
            }
            next
        }
        { print }
        END {
            if (!found) print key "=" value
        }
    ' "$file" > "$temp"

    cat "$temp" > "$file"
    rm -f "$temp"
}

write_manifest() {
    local source="$1"
    local appimage="$2"
    local source_version="$3"
    local target_version="$4"
    local manifest="$BACKUP_DIR/manifest.txt"

    {
        echo "darktable migration 6.0"
        echo "Datum: $(date --iso-8601=seconds)"
        echo "Användare: $USER"
        echo "Dator: $(hostname)"
        echo "Källa: $source"
        echo "Måltyp: $TARGET"
        echo "Målkatalog: $DEST_CONFIG"
        echo "AppImage: ${appimage:-inte angiven}"
        echo "Snap-version: ${source_version:-okänd}"
        echo "Målversion: ${target_version:-okänd}"
        echo "OpenCL satt till TRUE: $ENABLE_OPENCL"
        echo
        echo "Databasernas SHA256 före migreringen:"
        find "$source" -maxdepth 1 -type f \
            \( -name 'library.db' -o -name 'data.db' \) \
            -exec sha256sum {} \; 2>/dev/null || true
    } > "$manifest"
}

run_opencl_test() {
    local appimage="$1"
    local log_file="$BACKUP_DIR/opencl-test.log"
    local status=0

    log "Kör OpenCL-test. Resultatet sparas i $log_file"

    set +e
    case "$TARGET" in
        flatpak)
            flatpak run --command=darktable-cltest \
                org.darktable.Darktable 2>&1 |
                tee "$log_file"
            status=${PIPESTATUS[0]}
            ;;
        apt)
            if command -v darktable-cltest >/dev/null 2>&1; then
                darktable-cltest 2>&1 | tee "$log_file"
                status=${PIPESTATUS[0]}
            else
                timeout 25s darktable -d opencl 2>&1 | tee "$log_file"
                status=${PIPESTATUS[0]}
            fi
            ;;
        appimage)
            if [[ -z "$appimage" ]]; then
                warn "Ingen AppImage hittades. OpenCL-testet kan inte köras."
                return 0
            fi
            warn "AppImage-testet startar darktable i högst 25 sekunder."
            timeout 25s "$appimage" -d opencl 2>&1 | tee "$log_file"
            status=${PIPESTATUS[0]}
            ;;
    esac
    set -e

    if ((status == 0)); then
        ok "OpenCL-testet avslutades utan rapporterad felkod."
    elif ((status == 124)); then
        warn "Testet stoppades efter 25 sekunder. Läs OpenCL-loggen för resultat."
    else
        warn "OpenCL-testet avslutades med felkod $status. Läs $log_file"
    fi
}

log "darktable-migrering version $VERSION"
log "Källa: Snap"
log "Måltyp: $TARGET"
log "Målkatalog: $DEST_CONFIG"

check_not_running

SRC_DIR="$(find_snap_source || true)"
[[ -n "$SRC_DIR" && -d "$SRC_DIR" ]] ||
    die "Ingen Snap-konfiguration hittades under $SNAP_BASE."

[[ "$SRC_DIR" != "$DEST_CONFIG" ]] ||
    die "Källa och mål är samma katalog."

if [[ -L "$DEST_CONFIG" ]]; then
    die "Målkatalogen är en symbolisk länk. Av säkerhetsskäl avbryts migreringen: $DEST_CONFIG"
fi

log "Verklig Snap-källa: $SRC_DIR"

check_lock_files "$SRC_DIR"
check_lock_files "$DEST_CONFIG"

check_database "$SRC_DIR/library.db" "library.db"
check_database "$SRC_DIR/data.db" "data.db"

APPIMAGE_RESOLVED=""
if [[ "$TARGET" == "appimage" ]]; then
    APPIMAGE_RESOLVED="$(find_appimage || true)"
    if [[ -n "$APPIMAGE_RESOLVED" ]]; then
        log "AppImage för versions-/OpenCL-test: $APPIMAGE_RESOLVED"
    else
        warn "Ingen darktable-AppImage hittades i ~/Applications och ingen angavs med --appimage."
        warn "Migreringen kan ändå genomföras."
    fi
fi

SOURCE_VERSION=""
TARGET_VERSION=""

if ! $SKIP_VERSION_CHECK; then
    SOURCE_VERSION="$(get_source_version || true)"
    TARGET_VERSION="$(get_target_version "$APPIMAGE_RESOLVED" || true)"

    log "Snap-version: ${SOURCE_VERSION:-okänd}"
    log "Målversion: ${TARGET_VERSION:-okänd}"

    if [[ -n "$SOURCE_VERSION" && -n "$TARGET_VERSION" ]] &&
       version_is_older "$SOURCE_VERSION" "$TARGET_VERSION"; then
        if ! $FORCE_OLDER; then
            die "Målversionen $TARGET_VERSION är äldre än Snap-versionen $SOURCE_VERSION. Använd en lika ny eller nyare darktable-version, eller --force-older på egen risk."
        fi
        warn "Fortsätter trots att målversionen verkar äldre."
    fi
else
    warn "Versionskontrollen har hoppats över."
fi

SOURCE_BYTES="$(du -sb "$SRC_DIR" | awk '{print $1}')"
DEST_BYTES=0
[[ -d "$DEST_CONFIG" ]] &&
    DEST_BYTES="$(du -sb "$DEST_CONFIG" | awk '{print $1}')"

# Under arbetet behövs staging + backup av källa + eventuell backup av mål.
NEEDED_BYTES=$((SOURCE_BYTES * 2 + DEST_BYTES + 104857600))
DEST_PARENT="$(dirname "$DEST_CONFIG")"
SPACE_PATH="$HOME"
[[ -d "$DEST_PARENT" ]] && SPACE_PATH="$DEST_PARENT"
AVAILABLE_BYTES="$(df -PB1 "$SPACE_PATH" | awk 'NR==2 {print $4}')"

log "Snap-konfigurationens storlek: $(human_size "$SOURCE_BYTES")"
log "Befintligt mål: $(human_size "$DEST_BYTES")"
log "Uppskattat tillfälligt utrymmesbehov: $(human_size "$NEEDED_BYTES")"
log "Tillgängligt utrymme: $(human_size "$AVAILABLE_BYTES")"

if ((AVAILABLE_BYTES < NEEDED_BYTES)); then
    die "Det finns inte tillräckligt med ledigt diskutrymme för säker staging och backup."
fi

if $DRY_RUN; then
    cat <<EOF

============================================================
DRY-RUN – inga filer har skapats, kopierats eller ändrats
============================================================
Källa:
  $SRC_DIR

Mål:
  $DEST_CONFIG

Backup skulle skapas i:
  $BACKUP_DIR

Åtgärder:
  1. Säkerhetskopiera hela Snap-konfigurationen.
  2. Säkerhetskopiera befintlig målkatalog, om den finns.
  3. Kopiera hela Snap-konfigurationen till en staging-katalog.
  4. Kontrollera library.db och data.db i staging-kopian.
EOF

    if $ENABLE_OPENCL; then
        cat <<EOF
  5. Sätta endast opencl=TRUE i staging-kopians darktablerc.
  6. Ersätta målkatalogen atomiskt med den verifierade kopian.
EOF
    else
        cat <<EOF
  5. Inte ändra OpenCL-inställningen.
  6. Ersätta målkatalogen atomiskt med den verifierade kopian.
EOF
    fi

    echo
    exit 0
fi

if ! $ASSUME_YES; then
    echo
    printf 'Källa: %s\n' "$SRC_DIR"
    printf 'Mål:   %s\n' "$DEST_CONFIG"
    printf 'Backup:%s\n\n' "$BACKUP_DIR"
    read -r -p "Genomför migreringen? [j/N] " answer

    case "$answer" in
        j|J|ja|JA|Ja) ;;
        *)
            log "Avbrutet av användaren."
            exit 0
            ;;
    esac
fi

log "Skapar backupkatalog: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR/snap-config"

log "Säkerhetskopierar hela Snap-konfigurationen."
cp -a "$SRC_DIR"/. "$BACKUP_DIR/snap-config"/

if [[ -d "$DEST_CONFIG" ]]; then
    log "Säkerhetskopierar den befintliga målkatalogen."
    mkdir -p "$BACKUP_DIR/destination-before"
    cp -a "$DEST_CONFIG"/. "$BACKUP_DIR/destination-before"/
fi

write_manifest \
    "$SRC_DIR" \
    "$APPIMAGE_RESOLVED" \
    "$SOURCE_VERSION" \
    "$TARGET_VERSION"

mkdir -p "$DEST_PARENT"
STAGE_DIR="$(mktemp -d "$DEST_PARENT/.darktable-migrate-6.0.XXXXXX")"

log "Kopierar Snap-konfigurationen till staging: $STAGE_DIR"
cp -a "$SRC_DIR"/. "$STAGE_DIR"/
chmod --reference="$SRC_DIR" "$STAGE_DIR" 2>/dev/null || true

if $ENABLE_OPENCL; then
    log "Sätter opencl=TRUE i staging-kopians darktablerc."
    ensure_kv "opencl" "TRUE" "$STAGE_DIR/darktablerc"
else
    log "Lämnar OpenCL-inställningarna oförändrade."
fi

check_database "$STAGE_DIR/library.db" "library.db i staging"
check_database "$STAGE_DIR/data.db" "data.db i staging"

log "Staging-kopian är verifierad."

if [[ -e "$DEST_CONFIG" ]]; then
    OLD_DEST="${DEST_CONFIG}.pre-migrate-$STAMP"
    log "Flyttar befintligt mål till en tillfällig återställningsplats."
    mv -- "$DEST_CONFIG" "$OLD_DEST"
fi

log "Aktiverar den verifierade konfigurationen."
if ! mv -- "$STAGE_DIR" "$DEST_CONFIG"; then
    STAGE_DIR=""
    if [[ -n "$OLD_DEST" && -e "$OLD_DEST" ]]; then
        mv -- "$OLD_DEST" "$DEST_CONFIG" || true
    fi
    die "Kunde inte aktivera den nya konfigurationen."
fi

STAGE_DIR=""
COMMITTED=true
sync

if [[ -n "$OLD_DEST" && -e "$OLD_DEST" ]]; then
    log "Tar bort den tillfälliga gamla målkatalogen. Backupen finns kvar."
    rm -rf -- "$OLD_DEST"
    OLD_DEST=""
fi

check_database "$DEST_CONFIG/library.db" "installerad library.db"
check_database "$DEST_CONFIG/data.db" "installerad data.db"

ok "Migreringen är klar."
log "Målkatalog: $DEST_CONFIG"
log "Fullständig backup: $BACKUP_DIR"
log "Cachen kopierades inte separat; darktable bygger vid behov om sin cache."

if $TEST_OPENCL; then
    run_opencl_test "$APPIMAGE_RESOLVED"
elif [[ -t 0 ]]; then
    echo
    read -r -p "Vill du testa OpenCL nu? [j/N] " answer
    case "$answer" in
        j|J|ja|JA|Ja)
            run_opencl_test "$APPIMAGE_RESOLVED"
            ;;
        *)
            log "OpenCL-testet hoppades över."
            ;;
    esac
fi

cat <<EOF

Klart.

Mål:
  $DEST_CONFIG

Backup:
  $BACKUP_DIR

Starta nu den nya darktable-versionen. Första starten kan uppgradera
databaserna om målversionen är nyare. Backupen gör att du kan återgå.
EOF
