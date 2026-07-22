#!/usr/bin/env bash
# === restore_darktable-2.3.sh ===
# Fixar både "platta" snapshots (filer direkt i snapshot-mappen)
# och korrekta snapshots (som har en underkatalog).
# Återställer Darktable-konfiguration.

set -euo pipefail
export PAGER=cat

DRYRUN=false
SNAPSHOT_ARG=""

for arg in "${@:-}"; do
    case "$arg" in
        --dry-run) DRYRUN=true;;
        *) SNAPSHOT_ARG="$arg";;
    esac
done

die() {
    echo "❌ $1" >&2
    exit 1
}

# -------- AUTO-DETEKTERA DARKTABLE-PROFIL --------

detect_darktable_config() {
    if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
        echo "snap|$HOME/snap/darktable/current/.config/darktable"
        return 0
    fi

    if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
        echo "flatpak|$HOME/.var/app/org.darktable.Darktable/config/darktable"
        return 0
    fi

    if [[ -d "$HOME/.config/darktable" ]]; then
        echo "native|$HOME/.config/darktable"
        return 0
    fi

    return 1
}

DT_MODE="fallback"
TARGET_DIR="$HOME/.config/darktable"

if DETECT_OUT=$(detect_darktable_config); then
    DT_MODE="${DETECT_OUT%%|*}"
    TARGET_DIR="${DETECT_OUT#*|}"
fi

# -------- BASMAPPA --------

BASE_DIR="$HOME/bup_darktable"
CURRENT_BASE="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"
PRE_RESTORE_BASE="$BASE_DIR/pre_restore"

echo "=== restore_darktable-2.3.sh ==="
echo "Installations-typ: $DT_MODE"
echo "Mål (TARGET_DIR): $TARGET_DIR"
echo "Backupbas:        $BASE_DIR"
echo "DRYRUN:           $DRYRUN"
echo

[[ -d "$BASE_DIR" ]] || die "Ingen backupbas hittad: $BASE_DIR"

have_whiptail() { command -v whiptail >/dev/null 2>&1; }

# -------- SNAPSHOT-SÖKNING --------

find_snapshot_dir_basic() {
    local name="$1"

    if [[ -n "$name" ]]; then
        [[ -d "$CURRENT_BASE/$name" ]] && { echo "$CURRENT_BASE/$name"; return 0; }
        [[ -d "$OLD_BASE/$name" ]] &&     { echo "$OLD_BASE/$name"; return 0; }
        return 1
    fi

    if [[ -d "$CURRENT_BASE" ]] && [[ -n "$(ls -1 "$CURRENT_BASE" 2>/dev/null)" ]]; then
        echo "$CURRENT_BASE/$(ls -1 "$CURRENT_BASE" | head -n1)"
        return 0
    fi

    if [[ -d "$OLD_BASE" ]] && [[ -n "$(ls -1 "$OLD_BASE" 2>/dev/null)" ]]; then
        echo "$OLD_BASE/$(ls -1t "$OLD_BASE" | head -n1)"
        return 0
    fi

    return 1
}

choose_snapshot_whiptail() {
    local items=()

    if [[ -d "$CURRENT_BASE" ]]; then
        while IFS= read -r s; do items+=("$s" "current"); done < <(ls -1 "$CURRENT_BASE")
    fi

    if [[ -d "$OLD_BASE" ]]; then
        while IFS= read -r s; do items+=("$s" "old"); done < <(ls -1 "$OLD_BASE")
    fi

    [[ ${#items[@]} -eq 0 ]] && return 1

    whiptail \
        --title "Välj snapshot" \
        --menu "Välj snapshot att återställa" 20 80 10 \
        "${items[@]}" \
        3>&1 1>&2 2>&3
}

# -------- VÄLJ SNAPSHOT --------

SNAP_DIR=""
SNAP_NAME=""

if [[ -n "$SNAPSHOT_ARG" ]]; then
    SNAP_DIR=$(find_snapshot_dir_basic "$SNAPSHOT_ARG") \
        || die "Snapshot '$SNAPSHOT_ARG' hittades inte."
    SNAP_NAME="$SNAPSHOT_ARG"
else
    if have_whiptail; then
        SNAP_NAME=$(choose_snapshot_whiptail) || die "Inga snapshots att välja."
        SNAP_DIR=$(find_snapshot_dir_basic "$SNAP_NAME") || die "Intern snapshot-fel."
    else
        SNAP_DIR=$(find_snapshot_dir_basic "") || die "Inga snapshots funna."
        SNAP_NAME=$(basename "$SNAP_DIR")
    fi
fi

echo "Snapshot:  $SNAP_NAME"
echo "Full path: $SNAP_DIR"
echo

[[ -d "$SNAP_DIR" ]] || die "Snapshotkatalogen saknas: $SNAP_DIR"

# -------- ORDINARIE / PLATT SNAPSHOT-HANTERING --------

# Fall 1: snapshot innehåller redan en enda underkatalog
INNER_DIR=$(find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)

if [[ -n "$INNER_DIR" ]]; then
    # Normalt korrekt snapshot
    SNAP_DATA="$INNER_DIR"
else
    # Fall 2: PLATT SNAPSHOT → skapa 'darktable'
    echo "Platt snapshot upptäckt — skapar darktable/ underkatalog …"

    SNAP_DATA="$SNAP_DIR/darktable"

    if [[ ! -d "$SNAP_DATA" ]]; then
        mkdir -p "$SNAP_DATA"
    fi

    # Flytta in filer
    for f in "$SNAP_DIR"/*; do
        [[ -f "$f" ]] || continue
        mv "$f" "$SNAP_DATA/"
    done

    echo "Snapshot omstrukturerad → $SNAP_DATA"
fi

[[ -d "$SNAP_DATA" ]] || die "Kunde inte hitta data i snapshotet."

echo "Snapshot-data: $SNAP_DATA"
echo

# -------- BACKUP AV NUVARANDE CONFIG --------

TS_NOW=$(date '+%Y%m%d-%H%M%S')
SAFE_DIR="$PRE_RESTORE_BASE/$TS_NOW"

if [[ -d "$TARGET_DIR" ]] && [[ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]]; then
    echo "Säkerhetskopierar nuvarande config → $SAFE_DIR"
    mkdir -p "$SAFE_DIR"
    cp -a "$TARGET_DIR" "$SAFE_DIR"/
else
    echo "Ingen befintlig config att spara."
fi

# -------- BEKRÄFTA --------

echo "⚠️ Detta kommer skriva över $TARGET_DIR"
$DRYRUN && echo "DRY RUN – inga filer ändras."

read -r -p "Vill du fortsätta? (ja/nej) " ans
case "$ans" in
    ja|Ja|JA|j|J) ;;
    *) echo "Avbryter."; exit 0 ;;
esac

# -------- ÅTERSTÄLLNING --------

echo "Rensar mål: $TARGET_DIR"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "Kopierar snapshot → $TARGET_DIR"
cp -a "$SNAP_DATA"/. "$TARGET_DIR"/

echo
echo "🌟 Restore färdigt!"
echo "Snapshot:        $SNAP_NAME"
echo "Restore-mål:     $TARGET_DIR"
echo "Backup sparad:   $SAFE_DIR"
echo

read -rp "Tryck ENTER för att återgå till Darktable Tools-menyn..."

