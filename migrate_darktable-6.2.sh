#!/usr/bin/env bash
# ============================================================
# migrate_darktable-6.2.sh
# ============================================================
# Säker återställning/migrering av darktable-konfiguration till:
#   - AppImage eller APT: ~/.config/darktable
#   - Flatpak:            ~/.var/app/org.darktable.Darktable/config/darktable
#
# Standardkälla, i denna ordning:
#   1. Senaste giltiga snapshot skapad av backup_darktable-5.1.sh:
#        ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/
#   2. Äldre backupformat: ~/bup_darktable/current/
#   3. Aktiv Snap-konfiguration: ~/snap/darktable/current/
#
# En särskild källa kan alltid anges med --source=PATH.
# Standardmål är AppImage.
#
# Exempel:
#   ./migrate_darktable-6.2.sh --dry-run
#   ./migrate_darktable-6.2.sh
#   ./migrate_darktable-6.2.sh --source="$HOME/bup_darktable/20260721-165914/darktable" --dry-run
#   ./migrate_darktable-6.2.sh --appimage="$HOME/Applications/darktable.AppImage"
#   ./migrate_darktable-6.2.sh --target flatpak
#
# Kör som vanlig användare och stäng darktable först.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="6.2"
SCRIPT_NAME="$(basename "$0")"

DRY_RUN=false
DEBUG=false
TARGET="appimage"
APPIMAGE_PATH=""
SOURCE_OVERRIDE=""
ENABLE_OPENCL=true
TEST_OPENCL=false
ASSUME_YES=false
FORCE_OLDER=false
SKIP_VERSION_CHECK=false

BACKUP_BASE="$HOME/bup_darktable"
SNAP_BASE="$HOME/snap/darktable"
MIGRATION_BACKUP_ROOT="$HOME/darktable_migration_backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
MIGRATION_BACKUP_DIR="$MIGRATION_BACKUP_ROOT/$STAMP"

STAGE_DIR=""
OLD_DEST=""
DEST_CONFIG=""
SRC_DIR=""
SOURCE_KIND=""
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
    cat <<EOF_USAGE
$SCRIPT_NAME

Återställer eller migrerar darktables konfiguration till AppImage/APT
eller Flatpak.

Utan --source väljs automatiskt den senaste giltiga snapshoten från:
  ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/

Om ingen sådan finns provas äldre ~/bup_darktable/current och därefter Snap.

Användning:
  $SCRIPT_NAME [alternativ]

Alternativ:
  --target appimage   Mål ~/.config/darktable (standard)
  --target apt        Mål ~/.config/darktable
  --target flatpak    Mål Flatpaks darktable-katalog

  --source=KATALOG    Använd exakt denna källa. Både snapshotkatalogen och
                      dess darktable-underkatalog accepteras.
  --backup-base=PATH  Bas för snapshots från backup_darktable.
                      Standard: ~/bup_darktable
  --appimage=FIL      AppImage för versions- och OpenCL-test.

  --dry-run, -n       Kontrollera och visa planen utan att skriva något.
  --no-opencl         Ändra inte nyckeln opencl i darktablerc.
  --test-opencl       Kör OpenCL-test efter lyckad migrering.
  --skip-version-check
                      Hoppa över jämförelse av darktable-versioner.
  --force-older       Tillåt ett känt äldre målprogram.
  --yes, -y           Bekräfta migreringen automatiskt.
  --debug             Visa körda Bash-kommandon.
  --help, -h          Visa hjälp.

Viktigt:
  Darktable måste vara helt avstängt.
  Målversionen bör vara samma eller nyare än den version som skapade databaserna.
EOF_USAGE
}

expand_path() {
    case "$1" in
        "~")   printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

valid_config_dir() {
    local dir="$1"

    [[ -d "$dir" \
       && -f "$dir/darktablerc" \
       && -f "$dir/library.db" \
       && -f "$dir/data.db" ]]
}

resolve_valid_source() {
    local requested="$1"
    local expanded=""
    local resolved=""

    expanded="$(expand_path "$requested")"
    resolved="$(readlink -f -- "$expanded" 2>/dev/null || true)"

    if [[ -n "$resolved" ]] && valid_config_dir "$resolved"; then
        printf '%s\n' "$resolved"
        return 0
    fi

    if [[ -n "$resolved" ]] && valid_config_dir "$resolved/darktable"; then
        printf '%s\n' "$resolved/darktable"
        return 0
    fi

    return 1
}

find_latest_snapshot() {
    local name=""
    local candidate=""

    [[ -d "$BACKUP_BASE" ]] || return 1

    while IFS= read -r name; do
        candidate="$BACKUP_BASE/$name/darktable"
        if valid_config_dir "$candidate"; then
            readlink -f -- "$candidate"
            return 0
        fi
    done < <(
        find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
            | grep -E '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$' \
            | sort -r \
            || true
    )

    return 1
}

find_legacy_backup() {
    local candidate="$BACKUP_BASE/current"

    if valid_config_dir "$candidate"; then
        readlink -f -- "$candidate"
        return 0
    fi

    if valid_config_dir "$candidate/darktable"; then
        readlink -f -- "$candidate/darktable"
        return 0
    fi

    return 1
}

find_snap_source() {
    local current="$SNAP_BASE/current"
    local resolved=""
    local rev=""

    if [[ -e "$current" ]]; then
        resolved="$(readlink -f -- "$current" 2>/dev/null || true)"
        if [[ -n "$resolved" ]] && valid_config_dir "$resolved"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    [[ -d "$SNAP_BASE" ]] || return 1

    rev="$(
        find "$SNAP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
            | grep -E '^[0-9]+$' \
            | sort -n \
            | tail -n 1 \
            || true
    )"

    if [[ -n "$rev" ]] && valid_config_dir "$SNAP_BASE/$rev"; then
        readlink -f -- "$SNAP_BASE/$rev"
        return 0
    fi

    return 1
}

detect_source() {
    local found=""

    if [[ -n "$SOURCE_OVERRIDE" ]]; then
        found="$(resolve_valid_source "$SOURCE_OVERRIDE" || true)"
        [[ -n "$found" ]] || return 1
        printf '%s|%s\n' "manuellt angiven källa" "$found"
        return 0
    fi

    found="$(find_latest_snapshot || true)"
    if [[ -n "$found" ]]; then
        printf '%s|%s\n' "senaste backup-snapshot" "$found"
        return 0
    fi

    found="$(find_legacy_backup || true)"
    if [[ -n "$found" ]]; then
        printf '%s|%s\n' "äldre backupformat (current)" "$found"
        return 0
    fi

    found="$(find_snap_source || true)"
    if [[ -n "$found" ]]; then
        printf '%s|%s\n' "Snap-konfiguration" "$found"
        return 0
    fi

    return 1
}

cleanup() {
    local rc=$?

    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf -- "$STAGE_DIR" || true
    fi

    if ((rc != 0)) && ! $COMMITTED \
       && [[ -n "$OLD_DEST" && -e "$OLD_DEST" && ! -e "$DEST_CONFIG" ]]; then
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

find_appimage() {
    local candidates=()
    local newest=""
    local file=""
    local explicit=""

    if [[ -n "$APPIMAGE_PATH" ]]; then
        explicit="$(expand_path "$APPIMAGE_PATH")"
        [[ -f "$explicit" ]] || die "AppImage-filen finns inte: $explicit"
        readlink -f -- "$explicit"
        return 0
    fi

    shopt -s nullglob nocaseglob
    candidates=(
        "$HOME/Applications/"*darktable*.AppImage
        "$HOME/Applications/"*darktable*.appimage
        "$HOME/Downloads/"*darktable*.AppImage
        "$HOME/Downloads/"*darktable*.appimage
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
    ps -u "$(id -u)" -o pid=,comm=,args= \
        | awk '
            BEGIN { IGNORECASE=1 }
            /migrate_darktable-[0-9.]+\.sh/ { next }
            $2 ~ /^darktable/ { print; next }
            $2 == "AppRun" && $0 ~ /darktable/ { print; next }
            $0 ~ /darktable[^ ]*\.AppImage/ { print }
        '
}

check_not_running() {
    local running=""
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
        die "Databasens låsfil finns kvar. Kontrollera att darktable är stängt."
    fi
}

check_database() {
    local database="$1"
    local label="$2"
    local required="${3:-true}"
    local result=""

    if [[ ! -f "$database" ]]; then
        if [[ "$required" == true ]]; then
            die "$label saknas: $database"
        fi
        warn "$label saknas och kan därför inte kontrolleras: $database"
        return 0
    fi

    log "Kontrollerar SQLite-databasen $label ..."

    if command -v sqlite3 >/dev/null 2>&1; then
        result="$(sqlite3 -readonly "$database" 'PRAGMA quick_check;' 2>&1)" \
            || die "SQLite-kontrollen misslyckades för $database: $result"
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

    [[ "$SOURCE_KIND" == "Snap-konfiguration" ]] || return 1
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
            [[ -n "$appimage" && -x "$appimage" ]] || return 1
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
    local first=""

    [[ "$source_version" != "$target_version" ]] || return 1

    first="$(
        printf '%s\n%s\n' "$source_version" "$target_version" \
            | sort -V \
            | head -n 1
    )"

    [[ "$first" == "$target_version" ]]
}

ensure_kv() {
    local key="$1"
    local value="$2"
    local file="$3"
    local temp=""

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
    local source_version="$1"
    local target_version="$2"
    local appimage="$3"
    local manifest="$MIGRATION_BACKUP_DIR/manifest.txt"

    {
        echo "darktable migration $VERSION"
        echo "Datum: $(date --iso-8601=seconds)"
        echo "Användare: $USER"
        echo "Dator: $(hostname)"
        echo "Källtyp: $SOURCE_KIND"
        echo "Källa: $SRC_DIR"
        echo "Måltyp: $TARGET"
        echo "Målkatalog: $DEST_CONFIG"
        echo "AppImage: ${appimage:-inte angiven}"
        echo "Källversion: ${source_version:-okänd}"
        echo "Målversion: ${target_version:-okänd}"
        echo "OpenCL satt till TRUE: $ENABLE_OPENCL"
        echo
        echo "Databasernas SHA256 före migreringen:"
        find "$SRC_DIR" -maxdepth 1 -type f \
            \( -name 'library.db' -o -name 'data.db' \) \
            -exec sha256sum {} \; 2>/dev/null || true
    } > "$manifest"
}

run_opencl_test() {
    local appimage="$1"
    local log_file="$MIGRATION_BACKUP_DIR/opencl-test.log"
    local status=0

    log "Kör OpenCL-test. Resultatet sparas i $log_file"

    set +e
    case "$TARGET" in
        flatpak)
            flatpak run --command=darktable-cltest \
                org.darktable.Darktable 2>&1 | tee "$log_file"
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
            if [[ -z "$appimage" || ! -x "$appimage" ]]; then
                warn "Ingen körbar AppImage hittades. OpenCL-testet kan inte köras."
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

while (($#)); do
    case "$1" in
        --target)
            (($# >= 2)) || die "--target kräver ett värde."
            TARGET="$2"
            shift 2
            ;;
        --target=*)
            TARGET="${1#*=}"
            shift
            ;;
        --appimage)
            (($# >= 2)) || die "--appimage kräver en sökväg."
            APPIMAGE_PATH="$2"
            shift 2
            ;;
        --appimage=*)
            APPIMAGE_PATH="${1#*=}"
            shift
            ;;
        --source)
            (($# >= 2)) || die "--source kräver en katalog."
            SOURCE_OVERRIDE="$2"
            shift 2
            ;;
        --source=*)
            SOURCE_OVERRIDE="${1#*=}"
            shift
            ;;
        --backup-base)
            (($# >= 2)) || die "--backup-base kräver en katalog."
            BACKUP_BASE="$(expand_path "$2")"
            shift 2
            ;;
        --backup-base=*)
            BACKUP_BASE="$(expand_path "${1#*=}")"
            shift
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

check_not_running

DETECT_OUT="$(detect_source || true)"
if [[ -z "$DETECT_OUT" ]]; then
    die "Ingen giltig Darktable-källa hittades. Förväntade senaste snapshot under $BACKUP_BASE, äldre current-backup eller Snap. Använd --source=PATH vid behov."
fi
SOURCE_KIND="${DETECT_OUT%%|*}"
SRC_DIR="${DETECT_OUT#*|}"

[[ "$SRC_DIR" != "$DEST_CONFIG" ]] \
    || die "Källa och mål är samma katalog."

if [[ -L "$DEST_CONFIG" ]]; then
    die "Målkatalogen är en symbolisk länk. Av säkerhetsskäl avbryts migreringen: $DEST_CONFIG"
fi

log "darktable-migrering version $VERSION"
log "Källtyp: $SOURCE_KIND"
log "Källa: $SRC_DIR"
log "Måltyp: $TARGET"
log "Målkatalog: $DEST_CONFIG"

check_lock_files "$SRC_DIR"
check_lock_files "$DEST_CONFIG"
check_database "$SRC_DIR/library.db" "library.db" true
check_database "$SRC_DIR/data.db" "data.db" true

APPIMAGE_RESOLVED=""
if [[ "$TARGET" == "appimage" ]]; then
    APPIMAGE_RESOLVED="$(find_appimage || true)"
    if [[ -n "$APPIMAGE_RESOLVED" ]]; then
        log "AppImage för versions-/OpenCL-test: $APPIMAGE_RESOLVED"
        if [[ ! -x "$APPIMAGE_RESOLVED" ]]; then
            warn "AppImage-filen är inte körbar. Versions- och OpenCL-test hoppas över."
        fi
    else
        warn "Ingen darktable-AppImage hittades i ~/Applications eller ~/Downloads och ingen angavs med --appimage."
        warn "Migreringen kan ändå genomföras."
    fi
fi

SOURCE_VERSION=""
TARGET_VERSION=""

if ! $SKIP_VERSION_CHECK; then
    SOURCE_VERSION="$(get_source_version || true)"
    TARGET_VERSION="$(get_target_version "$APPIMAGE_RESOLVED" || true)"

    log "Källversion: ${SOURCE_VERSION:-okänd}"
    log "Målversion: ${TARGET_VERSION:-okänd}"

    if [[ -n "$SOURCE_VERSION" && -n "$TARGET_VERSION" ]] \
       && version_is_older "$SOURCE_VERSION" "$TARGET_VERSION"; then
        if ! $FORCE_OLDER; then
            die "Målversionen $TARGET_VERSION är äldre än källversionen $SOURCE_VERSION. Använd en lika ny eller nyare darktable-version, eller --force-older på egen risk."
        fi
        warn "Fortsätter trots att målversionen verkar äldre."
    fi
else
    warn "Versionskontrollen har hoppats över."
fi

SOURCE_BYTES="$(du -sb "$SRC_DIR" | awk '{print $1}')"
DEST_BYTES=0
[[ -d "$DEST_CONFIG" ]] \
    && DEST_BYTES="$(du -sb "$DEST_CONFIG" | awk '{print $1}')"

# Under arbetet behövs staging + separat migreringsbackup av källa
# samt eventuell backup av befintligt mål.
NEEDED_BYTES=$((SOURCE_BYTES * 2 + DEST_BYTES + 104857600))
DEST_PARENT="$(dirname "$DEST_CONFIG")"
SPACE_PATH="$HOME"
[[ -d "$DEST_PARENT" ]] && SPACE_PATH="$DEST_PARENT"
AVAILABLE_BYTES="$(df -PB1 "$SPACE_PATH" | awk 'NR==2 {print $4}')"

log "Källkonfigurationens storlek: $(human_size "$SOURCE_BYTES")"
log "Befintligt mål: $(human_size "$DEST_BYTES")"
log "Uppskattat tillfälligt utrymmesbehov: $(human_size "$NEEDED_BYTES")"
log "Tillgängligt utrymme: $(human_size "$AVAILABLE_BYTES")"

if ((AVAILABLE_BYTES < NEEDED_BYTES)); then
    die "Det finns inte tillräckligt med ledigt diskutrymme för säker staging och backup."
fi

if $DRY_RUN; then
    cat <<EOF_DRY

============================================================
DRY-RUN – inga filer har skapats, kopierats eller ändrats
============================================================
Källtyp:
  $SOURCE_KIND

Källa:
  $SRC_DIR

Mål:
  $DEST_CONFIG

Separat migreringsbackup skulle skapas i:
  $MIGRATION_BACKUP_DIR

Åtgärder:
  1. Säkerhetskopiera hela källkonfigurationen.
  2. Säkerhetskopiera befintlig målkatalog, om den finns.
  3. Kopiera hela källkonfigurationen till en staging-katalog.
  4. Kontrollera library.db och data.db i staging-kopian.
EOF_DRY

    if $ENABLE_OPENCL; then
        cat <<EOF_OPENCL
  5. Sätta endast opencl=TRUE i staging-kopians darktablerc.
  6. Ersätta målkatalogen atomiskt med den verifierade kopian.
EOF_OPENCL
    else
        cat <<EOF_NOOPENCL
  5. Lämna OpenCL-inställningen oförändrad.
  6. Ersätta målkatalogen atomiskt med den verifierade kopian.
EOF_NOOPENCL
    fi

    echo
    exit 0
fi

if ! $ASSUME_YES; then
    echo
    printf 'Källtyp: %s\n' "$SOURCE_KIND"
    printf 'Källa:    %s\n' "$SRC_DIR"
    printf 'Mål:      %s\n' "$DEST_CONFIG"
    printf 'Backup:   %s\n\n' "$MIGRATION_BACKUP_DIR"
    read -r -p "Genomför migreringen? [j/N] " answer

    case "$answer" in
        j|J|ja|JA|Ja) ;;
        *)
            log "Avbrutet av användaren."
            exit 0
            ;;
    esac
fi

log "Skapar migreringsbackup: $MIGRATION_BACKUP_DIR"
mkdir -p "$MIGRATION_BACKUP_DIR/source-config"

log "Säkerhetskopierar hela källkonfigurationen."
cp -a "$SRC_DIR"/. "$MIGRATION_BACKUP_DIR/source-config"/

if [[ -d "$DEST_CONFIG" ]]; then
    log "Säkerhetskopierar den befintliga målkatalogen."
    mkdir -p "$MIGRATION_BACKUP_DIR/destination-before"
    cp -a "$DEST_CONFIG"/. "$MIGRATION_BACKUP_DIR/destination-before"/
fi

write_manifest "$SOURCE_VERSION" "$TARGET_VERSION" "$APPIMAGE_RESOLVED"

mkdir -p "$DEST_PARENT"
STAGE_DIR="$(mktemp -d "$DEST_PARENT/.darktable-migrate-6.2.XXXXXX")"

log "Kopierar källkonfigurationen till staging: $STAGE_DIR"
cp -a "$SRC_DIR"/. "$STAGE_DIR"/
chmod --reference="$SRC_DIR" "$STAGE_DIR" 2>/dev/null || true

if $ENABLE_OPENCL; then
    log "Sätter opencl=TRUE i staging-kopians darktablerc."
    ensure_kv "opencl" "TRUE" "$STAGE_DIR/darktablerc"
else
    log "Lämnar OpenCL-inställningen oförändrad."
fi

check_database "$STAGE_DIR/library.db" "library.db i staging" true
check_database "$STAGE_DIR/data.db" "data.db i staging" true
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
    log "Tar bort den tillfälliga gamla målkatalogen. Migreringsbackupen finns kvar."
    rm -rf -- "$OLD_DEST"
    OLD_DEST=""
fi

check_database "$DEST_CONFIG/library.db" "installerad library.db" true
check_database "$DEST_CONFIG/data.db" "installerad data.db" true

ok "Migreringen är klar."
log "Målkatalog: $DEST_CONFIG"
log "Fullständig migreringsbackup: $MIGRATION_BACKUP_DIR"
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

cat <<EOF_DONE

Klart.

Källa:
  $SRC_DIR

Mål:
  $DEST_CONFIG

Migreringsbackup:
  $MIGRATION_BACKUP_DIR

Starta nu den nya darktable-versionen. Första starten kan uppgradera
databaserna om målversionen är nyare. Migreringsbackupen gör att du kan återgå.
EOF_DONE
