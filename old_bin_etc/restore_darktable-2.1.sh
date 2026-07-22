#!/usr/bin/env bash
# === restore_darktable-2.1.sh ===
# Återställ Darktable-konfiguration från bup_darktable-backuper.
#
# Förbättrad version:
#  - Autodetekterar Darktable-installation (snap/flatpak/native/appimage)
#  - Samma detection-mekanik som backup_rotate_3-2.1.sh
#  - DRY_RUN fungerar överallt
#  - Behåller whiptail-menyn

set -euo pipefail

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
# FUNKTION: hitta Darktable-installation (snap, flatpak, native)
# ------------------------------------------------------------

detect_darktable_config() {
    local DT_MODE="okänd"

    # 1) Snap explicitly: current
    if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
        echo "snap (current)|$HOME/snap/darktable/current/.config/darktable"
        return 0
    fi

    # Snap: senaste revision
    if [[ -d "$HOME/snap/darktable" ]]; then
        local rev
        rev=$(ls -1 "$HOME/snap/darktable" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)
        if [[ -n "$rev" ]] && [[ -d "$HOME/snap/darktable/$rev/.config/darktable" ]]; then
            echo "snap (rev $rev)|$HOME/snap/darktable/$rev/.config/darktable"
            return 0
        fi
    fi

    # 2) Flatpak
    if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
        echo "flatpak|$HOME/.var/app/org.darktable.Darktable/config/darktable"
        return 0
    fi

    # 3) Native/AppImage
    if [[ -d "$HOME/.config/darktable" ]]; then
        echo "native (~/.config/darktable)|$HOME/.config/darktable"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Välj TARGET_DIR med samma logik som backup-scriptet
# ------------------------------------------------------------

DT_MODE="okänd"
TARGET_DIR=""

if DETECT_OUT=$(detect_darktable_config); then
    DT_MODE="${DETECT_OUT%%|*}"
    TARGET_DIR="${DETECT_OUT#*|}"
else
    echo "⚠️  Ingen Darktable-katalog hittad. Antar ~/.config/darktable"
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

die() {
    echo "❌ $1" >&2
    exit 1
}

have_whiptail() { command -v whiptail >/dev/null 2>&1; }

mkd_cmd() {
    if $DRYRUN; then echo "DRYRUN: mkdir -p \"$1\""; else mkdir -p "$1"; fi
}

cp_cmd() {
    if $DRYRUN; then echo "DRYRUN: cp -a \"$1\" \"$2\""; else cp -a "$1" "$2"; fi
}

rm_cmd() {
    if $DRYRUN; then echo "DRYRUN: rm -rf \"$1\""; else rm -rf "$1"; fi
}

# ------------------------------------------------------------
# Sök snapshot
# ------------------------------------------------------------

find_snapshot_dir_basic() {
    local name="$1"

    # Specifik snapshot given
    if [[ -n "$name" ]]; then
        [[ -d "$CURRENT_BASE/$name" ]] && { echo "$CURRENT_BASE/$name"; return 0; }
        [[ -d "$OLD_BASE/$name" ]] &&     { echo "$OLD_BASE/$name"; return 0; }
        return 1
    fi

    # Ingen snapshot given: välj current (om finns)
    if [[ -d "$CURRENT_BASE" ]] && [[ -n "$(ls -1 "$CURRENT_BASE" 2>/dev/null || true)" ]]; then
        echo "$CURRENT_BASE/$(ls -1 "$CURRENT_BASE" | head -n1)"
        return 0
    fi

    # Annars senaste old
    if [[ -d "$OLD_BASE" ]] && [[ -n "$(ls -1 "$OLD_BASE" 2>/dev/null || true)" ]]; then
        echo "$OLD_BASE/$(ls -1t "$OLD_BASE" | head -n1)"
        return 0
    fi

    return 1
}

choose_snapshot_whiptail() {
    local items=()

    if [[ -d "$CURRENT_BASE" ]]; then
        while IFS= read -r s; do
            items+=("$s" "current")
        done < <(ls -1 "$CURRENT_BASE" 2>/dev/null || true)
    fi
    if [[ -d "$OLD_BASE" ]]; then
        while IFS= read -r s; do
            items+=("$s" "old")
        done < <(ls -1 "$OLD_BASE" 2>/dev/null || true)
    fi

    [[ ${#items[@]} -eq 0 ]] && return 1

    local choice
    choice=$(whiptail \
        --title "Välj Darktable-snapshot" \
        --menu "Välj snapshot att återställa:" 20 80 10 \
        "${items[@]}" \
        3>&1 1>&2 2>&3) || return 1

    echo "$choice"
}

# ------------------------------------------------------------
# INFO
# ------------------------------------------------------------

echo "=== restore_darktable-2.1.sh ==="
echo "Identifierad Darktable-installation: $DT_MODE"
echo "Mål (TARGET_DIR):                  $TARGET_DIR"
echo "Backup-bas:                        $BASE_DIR"
echo "DRYRUN:                            $DRYRUN"
echo

[[ -d "$BASE_DIR" ]] || die "Finns ingen katalog $BASE_DIR. Har du kört backup först?"

# ------------------------------------------------------------
# VÄLJ SNAPSHOT
# ------------------------------------------------------------

SNAP_DIR=""
SNAP_NAME=""

if [[ -n "$SNAPSHOT_ARG" ]]; then
    if ! SNAP_DIR=$(find_snapshot_dir_basic "$SNAPSHOT_ARG"); then
        die "Hittade inte snapshot '$SNAPSHOT_ARG'."
    fi
    SNAP_NAME="$SNAPSHOT_ARG"
else
    if have_whiptail; then
        SNAP_NAME=$(choose_snapshot_whiptail) || die "Inga snapshots att välja."
        SNAP_DIR=$(find_snapshot_dir_basic "$SNAP_NAME") || die "Intern fel efter val."
    else
        SNAP_DIR=$(find_snapshot_dir_basic "") || die "Inga snapshots funna."
        SNAP_NAME=$(basename "$SNAP_DIR")
    fi
fi

echo "🔄 Snapshot att återställa: $SNAP_NAME"
echo "📁 Full path: $SNAP_DIR"
echo

INNER_NAME=$(ls -1 "$SNAP_DIR" | head -n1 || true)
[[ -n "$INNER_NAME" ]] || die "Snapshot $SNAP_NAME är tom."
SNAP_DATA="$SNAP_DIR/$INNER_NAME"
[[ -d "$SNAP_DATA" ]] || die "Kunde inte hitta data i $SNAP_DATA."

# ------------------------------------------------------------
# BACKUP AV NUV. KONFIG
# ------------------------------------------------------------

TS_NOW=$(date '+%Y%m%d-%H%M%S')
SAFE_DIR="$PRE_RESTORE_BASE/$TS_NOW"

if [[ -d "$TARGET_DIR" ]] && [[ -n "$(ls -A "$TARGET_DIR" || true)" ]]; then
    echo "🛟 Tar säkerhetskopia av nuvarande config → $SAFE_DIR"
    mkd_cmd "$PRE_RESTORE_BASE"
    mkd_cmd "$SAFE_DIR"
    cp_cmd "$TARGET_DIR" "$SAFE_DIR"/
else
    echo "ℹ️  Ingen befintlig config att spara."
fi

# ------------------------------------------------------------
# BEKRÄFTA
# ------------------------------------------------------------

echo
echo "⚠️  Detta kommer skriva över:"
echo "    $TARGET_DIR"
$DRYRUN && echo "   Obs: DRY RUN – inga filer skrivs."
echo
read -r -p "Vill du fortsätta? (ja/nej) " ans
case "$ans" in
    ja|JA|Ja|j|J) ;;
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
echo "✅ Återställning klar:"
echo "   Snapshot: $SNAP_NAME"
echo "   Mål:      $TARGET_DIR"
echo "   Backup av tidigare config: $SAFE_DIR"
echo
echo "Starta om Darktable för att validera resultatet."

