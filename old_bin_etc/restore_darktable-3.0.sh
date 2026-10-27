#!/usr/bin/env bash
# === restore_darktable-3.0.sh ===
# Återställ Darktable-konfiguration från snapshots direkt under:
#   ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/...
#
# Klarar både:
#  - Korrekta snapshots (med underkatalog 'darktable')
#  - Platta snapshots (filer direkt i snapshot-mappen → läggs i darktable/)
#
# Användning:
#   ./restore_darktable-3.0.sh
#       → välj snapshot (whiptail om finns, annars senaste)
#
#   ./restore_darktable-3.0.sh 20251122-213500
#       → återställ specifik snapshot
#
#   ./restore_darktable-3.0.sh --dry-run
#       → visa vad som skulle göras

set -euo pipefail
export PAGER=cat

# ----- ARGUMENT -----
DRYRUN=false
SNAPSHOT_ARG=""

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRYRUN=true ;;
    *) SNAPSHOT_ARG="$arg" ;;
  esac
done

die() { echo "❌ $1" >&2; exit 1; }

have_whiptail() { command -v whiptail >/dev/null 2>&1; }

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

# ----- Hitta TARGET_DIR -----
DT_MODE="fallback"
TARGET_DIR="$HOME/.config/darktable"

if DETECT_OUT=$(detect_darktable_config); then
  DT_MODE="${DETECT_OUT%%|*}"
  TARGET_DIR="${DETECT_OUT#*|}"
fi

BASE_DIR="$HOME/bup_darktable"
PRE_RESTORE_BASE="$BASE_DIR/pre_restore"

echo "=== restore_darktable-3.0.sh ==="
echo "Installations-typ: $DT_MODE"
echo "Mål (TARGET_DIR): $TARGET_DIR"
echo "Backupbas:        $BASE_DIR"
echo "DRYRUN:           $DRYRUN"
echo

[[ -d "$BASE_DIR" ]] || die "Ingen backupbas hittad: $BASE_DIR"

# ----- Snapshot-hjälp -----

find_snapshot_dir_basic() {
  local name="$1"

  if [[ -n "$name" ]]; then
    [[ -d "$BASE_DIR/$name" ]] && { echo "$BASE_DIR/$name"; return 0; }
    return 1
  fi

  # Hitta senaste snapshot
  local latest
  latest=$(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
            | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r | head -n1 || true)
  [[ -n "$latest" ]] || return 1
  echo "$BASE_DIR/$latest"
}

choose_snapshot_whiptail() {
  local snaps
  snaps=$(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
           | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r || true)

  [[ -n "$snaps" ]] || return 1

  local items=()
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    items+=("$s" "snapshot")
  done <<< "$snaps"

  whiptail \
    --title "Välj Darktable-snapshot" \
    --menu "Snapshot att återställa" 20 80 10 \
    "${items[@]}" \
    3>&1 1>&2 2>&3
}

# ----- Välj snapshot -----
SNAP_DIR=""
SNAP_NAME=""

if [[ -n "$SNAPSHOT_ARG" && "$SNAPSHOT_ARG" != "--dry-run" && "$SNAPSHOT_ARG" != "-n" ]]; then
  SNAP_DIR=$(find_snapshot_dir_basic "$SNAPSHOT_ARG") \
    || die "Snapshot '$SNAPSHOT_ARG' hittades inte i $BASE_DIR."
  SNAP_NAME="$SNAPSHOT_ARG"
else
  if have_whiptail; then
    SNAP_NAME=$(choose_snapshot_whiptail) || die "Inga snapshots att välja."
    SNAP_DIR="$BASE_DIR/$SNAP_NAME"
  else
    SNAP_DIR=$(find_snapshot_dir_basic "") || die "Inga snapshots hittades i $BASE_DIR."
    SNAP_NAME="$(basename "$SNAP_DIR")"
  fi
fi

echo "Snapshot:  $SNAP_NAME"
echo "Full path: $SNAP_DIR"
echo

[[ -d "$SNAP_DIR" ]] || die "Snapshotkatalogen saknas: $SNAP_DIR"

# ----- Hitta/bygg SNAP_DATA (darktable/) -----
SNAP_DATA="$SNAP_DIR/darktable"

if [[ -d "$SNAP_DATA" ]]; then
  echo "Använder befintlig underkatalog: $SNAP_DATA"
else
  echo "Platt snapshot upptäckt – skapar underkatalog: $SNAP_DATA"
  if ! $DRYRUN; then
    mkdir -p "$SNAP_DATA"
    shopt -s nullglob
    for f in "$SNAP_DIR"/*; do
      [[ "$f" == "$SNAP_DATA" ]] && continue
      [[ -f "$f" ]] && mv "$f" "$SNAP_DATA/"
    done
    shopt -u nullglob
  else
    echo "(dry-run) skulle skapa $SNAP_DATA och flytta filer dit."
  fi
fi

[[ -d "$SNAP_DATA" ]] || die "Kunde inte hitta eller skapa SNAP_DATA: $SNAP_DATA"

echo "Snapshot-data: $SNAP_DATA"
echo

# ----- Säkerhetskopiera nuvarande config -----
TS_NOW=$(date '+%Y%m%d-%H%M%S')
SAFE_DIR="$PRE_RESTORE_BASE/$TS_NOW"

if [[ -d "$TARGET_DIR" ]] && [[ -n "$(ls -A "$TARGET_DIR" 2>/dev/null || true)" ]]; then
  echo "Säkerhetskopierar nuvarande config → $SAFE_DIR"
  if ! $DRYRUN; then
    mkdir -p "$SAFE_DIR"
    cp -a "$TARGET_DIR" "$SAFE_DIR"/
  else
    echo "(dry-run) skulle kopiera $TARGET_DIR → $SAFE_DIR/"
  fi
else
  echo "Ingen befintlig config att spara."
fi

# ----- Bekräfta -----
echo
echo "⚠️ Detta kommer skriva över:"
echo "   $TARGET_DIR"
$DRYRUN && echo "   (DRY RUN – inga filer kommer att ändras.)"
echo

read -r -p "Vill du fortsätta? (ja/nej) " ans
case "$ans" in
  ja|Ja|JA|j|J) ;;
  *) echo "Avbryter."; exit 0 ;;
esac

# ----- Återställ -----
echo
echo "Rensar mål: $TARGET_DIR"
if ! $DRYRUN; then
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
else
  echo "(dry-run) skulle köra: rm -rf \"$TARGET_DIR\" && mkdir -p \"$TARGET_DIR\""
fi

echo "Kopierar snapshot → $TARGET_DIR"
if ! $DRYRUN; then
  cp -a "$SNAP_DATA"/. "$TARGET_DIR"/
else
  echo "(dry-run) skulle kopiera: $SNAP_DATA/. → $TARGET_DIR/"
fi

echo
echo "✅ Återställning klar."
echo "   Snapshot:        $SNAP_NAME"
echo "   Mål:             $TARGET_DIR"
echo "   Backup av tidigare config (om skapad): $SAFE_DIR"
echo

read -rp "Tryck ENTER för att återgå till Darktable Tools-menyn..."

