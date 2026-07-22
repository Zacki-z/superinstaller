#!/usr/bin/env bash
# === restore_darktable-1.1.sh ===
# Återställ Darktable-konfiguration från bup_darktable-backuper.
#
# Struktur (skapad av bup_darktable-8.x):
#   ~/bup_darktable/
#       current/<TIMESTAMP>/darktable/...
#       old/<TIMESTAMP>/darktable/...
#
# Användning:
#   ./restore_darktable-1.1.sh
#       → välj snapshot via whiptail, återställ
#
#   ./restore_darktable-1.1.sh 20251120-123456
#       → återställ specifik snapshot
#
#   ./restore_darktable-1.1.sh --dry-run
#       → visa vad som skulle göras, utan att skriva något
#
#   ./restore_darktable-1.1.sh --dry-run 20251120-123456
#       → torrkör en specifik snapshot

set -euo pipefail

# ------------------------------------------------------------
# PARSA ARGUMENT
# ------------------------------------------------------------

DRYRUN=false
SNAPSHOT_ARG=""

for arg in "${@:-}"; do
    case "$arg" in
        --dry-run)
            DRYRUN=true
            ;;
        *)
            SNAPSHOT_ARG="$arg"
            ;;
    esac
done

# ------------------------------------------------------------
# AUTO-DETECT: Hitta nuvarande Darktable-katalog (mål för restore)
# ------------------------------------------------------------

CANDIDATES=(
    "$HOME/.config/darktable"                                         # APT/DEB + AppImage
    "$HOME/.var/app/org.darktable.Darktable/config/darktable"         # Flatpak
    "$HOME/snap/darktable/current"                                    # Snap (aktiv revision)
    "$HOME/snap/darktable"                                            # Snap (hela trädet)
)

TARGET_DIR=""
for d in "${CANDIDATES[@]}"; do
    if [ -d "$d" ]; then
        TARGET_DIR="$d"
        break
    fi
done

# Om inget hittas: anta klassiskt läge (~/.config/darktable)
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/.config/darktable"
    echo "⚠️  Ingen befintlig Darktable-katalog hittad."
    echo "   Antar mål: $TARGET_DIR"
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
# HJÄLPPROCEDURER
# ------------------------------------------------------------

die() {
    echo "❌ $1" >&2
    exit 1
}

have_whiptail() {
    command -v whiptail >/dev/null 2>&1
}

mkd_cmd() {
    if $DRYRUN; then
        echo "DRYRUN: mkdir -p \"$1\""
    else
        mkdir -p "$1"
    fi
}

cp_cmd() {
    if $DRYRUN; then
        echo "DRYRUN: cp -a \"$1\" \"$2\""
    else
        cp -a "$1" "$2"
    fi
}

rm_cmd() {
    if $DRYRUN; then
        echo "DRYRUN: rm -rf \"$1\""
    else
        rm -rf "$1"
    fi
}

# Hämta snapshot-katalog (utan interaktiv meny)
find_snapshot_dir_basic() {
    local snap_name="$1"

    # 1) Om ett specifikt namn angivits: leta i current/ och old/
    if [ -n "$snap_name" ]; then
        if [ -d "$CURRENT_BASE/$snap_name" ]; then
            echo "$CURRENT_BASE/$snap_name"
            return 0
        fi
        if [ -d "$OLD_BASE/$snap_name" ]; then
            echo "$OLD_BASE/$snap_name"
            return 0
        fi
        return 1
    fi

    # 2) Ingen snapshot angiven:
    # Först försök med current/ (normalt bara en dir)
    if [ -d "$CURRENT_BASE" ] && [ -n "$(ls -1 "$CURRENT_BASE" 2>/dev/null || true)" ]; then
        local cur
        cur=$(ls -1 "$CURRENT_BASE" | head -n1)
        echo "$CURRENT_BASE/$cur"
        return 0
    fi

    # 3) Annars: ta senaste från old/
    if [ -d "$OLD_BASE" ] && [ -n "$(ls -1 "$OLD_BASE" 2>/dev/null || true)" ]; then
        local latest
        latest=$(ls -1t "$OLD_BASE" | head -n1)
        echo "$OLD_BASE/$latest"
        return 0
    fi

    return 1
}

# Interaktivt val av snapshot via whiptail
choose_snapshot_whiptail() {
    local items=()

    if [ -d "$CURRENT_BASE" ]; then
        while IFS= read -r s; do
            [ -z "$s" ] && continue
            items+=("$s" "current")
        done < <(ls -1 "$CURRENT_BASE" 2>/dev/null || true)
    fi

    if [ -d "$OLD_BASE" ]; then
        while IFS= read -r s; do
            [ -z "$s" ] && continue
            items+=("$s" "old")
        done < <(ls -1 "$OLD_BASE" 2>/dev/null || true)
    fi

    if [ "${#items[@]}" -eq 0 ]; then
        return 1
    fi

    local choice
    choice=$(whiptail \
        --title "Välj Darktable-snapshot" \
        --menu "Välj snapshot att återställa" 20 78 10 \
        "${items[@]}" \
        3>&1 1>&2 2>&3) || return 1

    echo "$choice"
    return 0
}

# ------------------------------------------------------------
# HUVUDFLÖDE
# ------------------------------------------------------------

echo "=== restore_darktable-1.1.sh ==="
echo "Mål (Darktable-config): $TARGET_DIR"
echo "Backup-bas:              $BASE_DIR"
echo "DRYRUN:                  $DRYRUN"
echo

[ -d "$BASE_DIR" ] || die "Hittar inte $BASE_DIR. Har du kört bup_darktable-8.1.sh tidigare?"

SNAP_DIR=""
SNAP_NAME=""

if [ -n "$SNAPSHOT_ARG" ]; then
    # Specifikt snapshot-namn angivet
    if ! SNAP_DIR=$(find_snapshot_dir_basic "$SNAPSHOT_ARG"); then
        die "Kunde inte hitta snapshot '$SNAPSHOT_ARG' varken i current/ eller old/."
    fi
    SNAP_NAME=$(basename "$SNAP_DIR")
else
    # Ingen snapshot angiven: försök whiptail först, annars basic
    if have_whiptail; then
        SNAP_NAME=$(choose_snapshot_whiptail) || die "Inga snapshots att välja eller avbrutet."
        if ! SNAP_DIR=$(find_snapshot_dir_basic "$SNAP_NAME"); then
            die "Internt fel: kunde inte hitta snapshot '$SNAP_NAME' efter val."
        fi
    else
        echo "ℹ️  whiptail hittades inte, använder enkla regler för att välja snapshot."
        if ! SNAP_DIR=$(find_snapshot_dir_basic ""); then
            die "Inga snapshots hittades i current/ eller old/."
        fi
        SNAP_NAME=$(basename "$SNAP_DIR")
    fi
fi

echo "🔄 Kommer att återställa snapshot: $SNAP_NAME"
echo "   Full path: $SNAP_DIR"
echo

[ -d "$SNAP_DIR" ] || die "Snapshotkatalogen '$SNAP_DIR' finns inte eller är inte en katalog."

INNER_NAME=$(ls -1 "$SNAP_DIR" | head -n1 || true)
[ -n "$INNER_NAME" ] || die "Snapshot '$SNAP_NAME' verkar vara tom (inga underkataloger)."

SNAP_DATA="$SNAP_DIR/$INNER_NAME"
[ -d "$SNAP_DATA" ] || die "Förväntade en katalog i '$SNAP_DATA', men hittade ingen."

echo "📁 Data i snapshot: $SNAP_DATA"
echo

# ------------------------------------------------------------
# SÄKERHETSKOPIA AV NUVARANDE KONFIG
# ------------------------------------------------------------

TS_NOW=$(date '+%Y%m%d-%H%M%S')
SAFE_DIR="$PRE_RESTORE_BASE/$TS_NOW"

if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null || true)" ]; then
    echo "🛟 Tar säkerhetskopia av nuvarande $TARGET_DIR → $SAFE_DIR"
    mkd_cmd "$PRE_RESTORE_BASE"
    mkd_cmd "$SAFE_DIR"
    cp_cmd "$TARGET_DIR" "$SAFE_DIR"/
else
    echo "ℹ️  Ingen befintlig data i $TARGET_DIR att säkerhetskopiera."
fi

# ------------------------------------------------------------
# BEKRÄFTELSE
# ------------------------------------------------------------

echo
echo "⚠️  Detta kommer att skriva över innehållet i:"
echo "    $TARGET_DIR"
echo
if $DRYRUN; then
    echo "   OBS: DRY RUN – inga filer kommer verkligen att ändras."
    echo
fi

read -r -p "Vill du fortsätta? (ja/nej) " answer
case "$answer" in
    ja|JA|Ja|j|J) ;;
    *) echo "Avbryter."; exit 0 ;;
esac

# ------------------------------------------------------------
# ÅTERSTÄLLNING
# ------------------------------------------------------------

echo
echo "🧹 Rensar mål: $TARGET_DIR"
rm_cmd "$TARGET_DIR"
mkd_cmd "$TARGET_DIR"

echo "📥 Kopierar snapshot-data → $TARGET_DIR"
cp_cmd "$SNAP_DATA"/. "$TARGET_DIR"/

echo
echo "✅ Återställning klar."
echo "   Återställd snapshot: $SNAP_NAME"
echo "   Mål:                 $TARGET_DIR"
echo "   Säkerhetskopia av tidigare config (om någon): $SAFE_DIR"
echo
echo "Tips: Starta om Darktable och kontrollera att allt ser rätt ut."

