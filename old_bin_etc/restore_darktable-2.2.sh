#!/usr/bin/env bash
# === restore_darktable-2.2.sh ===
# Återställ Darktable-konfiguration från bup_darktable-backuper.
# Förbättrad med:
#   - PAGER=cat (ingen more/less/vim)
#   - Paus i slutet för Darktable Tools
#   - Autodetektering av Darktable-installation (snap / flatpak / native)

set -euo pipefail

# Stoppa less/more från att ta över terminalen
export PAGER=cat

# ------------------------------------------------------------
# ARGUMENT
# ------------------------------------------------------------

DRYRUN=false
SNAPSHOT_ARG=""

for arg in "${@:-}"; do
    case "$arg" in
        --dry-run) DRYRUN=true ;;
        *) SNAPSHOT_ARG="$arg" ;;
    esac
done

# ------------------------------------------------------------
# AUTO-DETEKTERA DARKTABLE-KONFIG
# ------------------------------------------------------------

detect_darktable_config() {
    # Snap aktuellt
    if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
        echo "snap (current)|$HOME/snap/darktable/current/.config/darktable"
        return 0
    fi

    # Snap tidigare revision
    if [[ -d "$HOME/snap/darktable" ]]; then
        local rev
        rev=$(ls -1 "$HOME/snap/darktable" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)
        if [[ -n "$rev" ]] && [[ -d "$HOME/snap/darktable/$rev/.config/darktable" ]]; then
            echo "snap (rev $rev)|$HOME/snap/darktable/$rev/.config/darktable"
            return 0
        fi
    fi

    # Flatpak
    if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
        echo "flatpak|$HOME/.var/app/org.darktable.Darktable/config/darktable"
        return 0
    fi

    # Native / AppImage / APT
    if [[ -d "$HOME/.config/darktable" ]]; then
        echo "native (~/.config/darktable)|$HOME/.config/darktable"
        return 0
    fi

    return 1
}

DT_MODE="okänd"
TARGET_DIR=""

if DETECT_OUT=$(detect_darktable_config); then
    DT_MODE="${DETECT_OUT%%|*}"
    TARGET_DIR="${DETECT_OUT#*|}"
else
    echo "⚠️  Ingen Darktable-profil hittad. Använder ~/.config/darktable"
    DT_MODE="fallback"
    TARGET_DIR="$HOME/.config/darktable"
fi

TARGET_DIR=$(eval echo "$TARGET_DIR")

# ------------------------------------------------------------
# VARIABLER
# ------------------------------------------------------------

BASE_DIR="$HOME/bup_darktable"
CURRENT_BASE="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"
PRE_RESTORE_BASE="$BASE_DIR/pre_restore"

# ------------------------------------------------------------
# HJÄLPFUNKTIONER
# ------------------------------------------------------------

die() { echo "❌ $1" >&2; exit 1; }
have_whiptail() { command -v whiptail >/dev/null 2>&1; }

mkd_cmd() { $DRYRUN && echo "DRYRUN: mkdir -p \"$1\"" || mkdir -p "$1"; }
cp_cmd() { $DRYRUN && echo "DRYRUN: cp -a \"$1\" \"$2\"" || cp -a "$1" "$2"; }
rm_cmd() { $DRYRUN && echo "DRYRUN: rm -rf \"$1\"" || rm -rf "$1"; }

find_snapshot_dir_basic() {
    local name="$1"

    # 1. Specifikt namn
    [[ -n "$name" && -d "$CURRENT_BASE/$name" ]] && { echo "$CURRENT_BASE/$name"; return 0; }
    [[ -n "$name" && -d "$OLD_BASE/$name" ]]     && { echo "$OLD_BASE/$name"; return 0; }

    # 2. current först
    if [[ -d "$CURRENT_BASE" ]] && [[ -n "$(ls -1 "$CURRENT_BASE" 2>/dev/null || true)" ]]; then
        echo "$CURRENT_BASE/$(ls -1 "$CURRENT_BASE" | head -n1)"
        return 0
    fi

    # 3. senaste old
    if [[ -d "$OLD_BASE" ]] && [[ -n "$(ls -1 "$OLD_BASE" 2>/dev/null || true)" ]]; then
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
        --title "Välj Darktable-snapshot" \
        --menu "Snapshot att återställa:" 20 80 10 \
        "${items[@]}" \
        3>&1 1>&2 2>&3
}

# ------------------------------------------------------------
# INFO
# ------------------------------------------------------------

echo "=== restore_darktable-2.2.sh ==="
echo "Identifierad installation: $DT_MODE"
echo "Mål (TARGET_DIR):          $TARGET_DIR"
echo "Backup-bas:                $BASE_DIR"
echo "DRYRUN:                    $DRYRUN"
echo

[[ -d "$BASE_DIR" ]] || die "Hittar inte $BASE_DIR. Ingen backup att återställa."

# ------------------------------------------------------------
# SNAPSHOTVAL
# ------------------------------------------------------------

SNAP_DIR=""
SNAP_NAME=""

if [[ -n "$SNAPSHOT_ARG" ]]; then
    SNAP_DIR=$(find_snapshot_dir_basic "$SNAPSHOT_ARG") || die "Snapshot '$SNAPSHOT_ARG' hittades inte."
    SNAP_NAME="$SNAPSHOT_ARG"
else
    if have_whiptail; then
        SNAP_NAME=$(choose_snapshot_whiptail) || die "Inga snapshots tillgängliga."
        SNAP_DIR=$(find_snapshot_dir_basic "$SNAP_NAME") || die "Internt fel vid snapshot-val."
    else
        SNAP_DIR=$(find_snapshot_dir_basic "") || die "Inga snapshots i current/ eller old/."
        SNAP_NAME=$(basename "$SNAP_DIR")
    fi
fi

echo "🔄 Snapshot:   $SNAP_NAME"
echo "📂 Full path:  $SNAP_DIR"
echo

INNER_NAME=$(ls -1 "$SNAP_DIR" | head -n1 || true)
[[ -n "$INNER_NAME" ]] || die "Snapshot $SNAP_NAME är tom."

SNAP_DATA="$SNAP_DIR/$INNER_NAME"
[[ -d "$SNAP_DATA" ]] || die "Saknar data i $SNAP_DATA."

# ------------------------------------------------------------
# BACKUP AV NUVARANDE KONFIG
# ------------------------------------------------------------

TS_NOW=$(date '+%Y%m%d-%H%M%S')
SAFE_DIR="$PRE_RESTORE_BASE/$TS_NOW"

if [[ -d "$TARGET_DIR" ]] && [[ -n "$(ls -A "$TARGET_DIR" 2>/dev/null || true)" ]]; then
    echo "🛟 Tar backup av nuvarande config → $SAFE_DIR"
    mkd_cmd "$PRE_RESTORE_BASE"
    mkd_cmd "$SAFE_DIR"
    cp_cmd "$TARGET_DIR" "$SAFE_DIR"/
else
    echo "ℹ️  Ingen tidigare config att bevara."
fi

# ------------------------------------------------------------
# BEKRÄFTA
# ------------------------------------------------------------

echo
echo "⚠️  Detta kommer skriva över:"
echo "    $TARGET_DIR"
$DRYRUN && echo "   (DRY RUN – inga filer ändras)"
echo
read -r -p "Vill du fortsätta? (ja/nej) " ans
case "$ans" in
    ja|Ja|JA|j|J) ;;
    *) echo "Avbryter."; exit 0 ;;
esac

# ------------------------------------------------------------
# RESTORE
# ------------------------------------------------------------

echo "🧹 Tömmer mål: $TARGET_DIR"
rm_cmd "$TARGET_DIR"
mkd_cmd "$TARGET_DIR"

echo "📥 Kopierar snapshot-data → $TARGET_DIR"
cp_cmd "$SNAP_DATA"/. "$TARGET_DIR"/

echo
echo "✅ Återställning färdig:"
echo "   Snapshot:        $SNAP_NAME"
echo "   Mål:             $TARGET_DIR"
echo "   Backup sparad i: $SAFE_DIR"
echo

# ------------------------------------------------------------
# PAUS FÖR DARKTABLE TOOLS
# ------------------------------------------------------------

read -rp "Tryck ENTER för att återgå till Darktable Tools-menyn..."

