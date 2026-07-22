#!/usr/bin/env bash
# ============================================================
# backup_darktable-5.0.sh
# ============================================================
# Robust backup av Darktables konfigurationskatalog.
#
# Funktioner:
#   - Hittar automatiskt Darktable-konfiguration för:
#       Snap, Flatpak och native/APT/AppImage.
#   - Kan använda en uttrycklig källa med --source=PATH.
#   - Skapar fristående snapshots:
#       ~/bup_darktable/YYYYMMDD-HHMMSS/darktable/
#   - Kopierar först till en dold temporär katalog.
#   - Publicerar snapshoten först efter godkänd verifiering.
#   - Behåller som standard de 3 senaste snapshotsen.
#   - Förhindrar två samtidiga normala körningar med flock.
#   - Har ett verkligt dry-run-läge som inte skapar filer,
#     kataloger, logg eller låsfil.
#
# Användning:
#   ./backup_darktable-5.0.sh
#   ./backup_darktable-5.0.sh --dry-run
#   ./backup_darktable-5.0.sh --source="$HOME/.config/darktable"
#   ./backup_darktable-5.0.sh --keep=5
#
# ============================================================

set -Eeuo pipefail

VERSION="5.0"
SCRIPT_NAME="$(basename "$0")"

# ---------------------------
# Standardinställningar
# ---------------------------
KEEP=3
BASE_DIR="~/bup_darktable"
SOURCE_OVERRIDE=""
DRYRUN=false

# Dessa sätts senare.
SOURCE_DIR=""
DT_MODE="okänd"
LOG_FILE=""
LOCK_FILE=""
PARTIAL_DIR=""

# ---------------------------
# Hjälpfunktioner
# ---------------------------
usage() {
  cat <<EOF_USAGE
Användning:
  $SCRIPT_NAME [flaggor]

Flaggor:
  --dry-run, -n
      Visa vad som skulle göras utan att skapa, ändra eller ta bort något.

  --source=PATH
      Använd exakt denna Darktable-konfigurationskatalog i stället för
      automatisk identifiering.

  --base-dir=PATH
      Katalog där snapshots och logg sparas.
      Standard: ~/bup_darktable

  --keep=ANTAL
      Antal snapshots som ska behållas.
      Standard: 3

  --help, -h
      Visa denna hjälptext.

Exempel:
  $SCRIPT_NAME
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --source="\$HOME/.config/darktable"
  $SCRIPT_NAME --base-dir="/media/\$USER/backup/darktable" --keep=5
EOF_USAGE
}

expand_tilde() {
  case "$1" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *)       printf '%s' "$1" ;;
  esac
}

absolute_existing_dir() {
  local dir="$1"
  (
    cd -- "$dir" 2>/dev/null || exit 1
    pwd -P
  )
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fatal() {
  log "❌ $*" >&2
  exit 1
}

check_dependencies() {
  local -a required=(rsync find grep sort date basename dirname mkdir mv rm)
  local -a missing=()
  local cmd

  if [[ "$DRYRUN" == false ]]; then
    required+=(flock tee)
  fi

  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if ((${#missing[@]} > 0)); then
    printf '❌ Följande nödvändiga kommandon saknas: %s\n' "${missing[*]}" >&2
    printf 'På Ubuntu/Debian kan relevanta paket installeras med exempelvis:\n' >&2
    printf '  sudo apt install rsync util-linux coreutils findutils grep\n' >&2
    exit 1
  fi
}

detect_darktable_config() {
  local rev=""

  # Snap – aktiv revision via current.
  if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
    printf '%s|%s\n' \
      "snap (current)" \
      "$HOME/snap/darktable/current/.config/darktable"
    return 0
  fi

  # Snap – senaste numeriska revision om current saknas.
  if [[ -d "$HOME/snap/darktable" ]]; then
    rev="$({
      find "$HOME/snap/darktable" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true
    } | grep -E '^[0-9]+$' | sort -n | tail -n 1 || true)"

    if [[ -n "$rev" && -d "$HOME/snap/darktable/$rev/.config/darktable" ]]; then
      printf '%s|%s\n' \
        "snap (revision $rev)" \
        "$HOME/snap/darktable/$rev/.config/darktable"
      return 0
    fi
  fi

  # Flatpak.
  if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
    printf '%s|%s\n' \
      "flatpak" \
      "$HOME/.var/app/org.darktable.Darktable/config/darktable"
    return 0
  fi

  # Native, APT eller AppImage.
  if [[ -d "$HOME/.config/darktable" ]]; then
    printf '%s|%s\n' \
      "native/APT/AppImage" \
      "$HOME/.config/darktable"
    return 0
  fi

  return 1
}

choose_snapshot_name() {
  local base_name
  local candidate
  local number=1

  base_name="$(date +%Y%m%d-%H%M%S)"
  candidate="$base_name"

  # Normalt behövs inget suffix. Det hanterar två körningar under samma sekund.
  while [[ -e "$BASE_DIR/$candidate" ]]; do
    candidate="${base_name}-$(printf '%02d' "$number")"
    ((number += 1))
  done

  printf '%s' "$candidate"
}

list_snapshots() {
  [[ -d "$BASE_DIR" ]] || return 0

  find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$' \
    | sort -r \
    || true
}

cleanup_partial() {
  local status=$?

  if [[ "$DRYRUN" == false && -n "$PARTIAL_DIR" && -d "$PARTIAL_DIR" ]]; then
    log "Städar ofullständig temporär snapshot: $PARTIAL_DIR"
    rm -rf -- "$PARTIAL_DIR" || true
  fi

  return "$status"
}

# ---------------------------
# Argument
# ---------------------------
while (($# > 0)); do
  case "$1" in
    --dry-run|-n)
      DRYRUN=true
      ;;
    --source=*)
      SOURCE_OVERRIDE="${1#*=}"
      ;;
    --base-dir=*)
      BASE_DIR="${1#*=}"
      ;;
    --keep=*)
      KEEP="${1#*=}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf '❌ Okänt argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
  printf '❌ --keep måste vara ett heltal större än noll. Angivet: %s\n' "$KEEP" >&2
  exit 1
fi

check_dependencies

BASE_DIR="$(expand_tilde "$BASE_DIR")"

# ---------------------------
# Hitta källkatalog
# ---------------------------
if [[ -n "$SOURCE_OVERRIDE" ]]; then
  SOURCE_DIR="$(expand_tilde "$SOURCE_OVERRIDE")"
  DT_MODE="manuellt angiven källa"
else
  if DETECT_OUT="$(detect_darktable_config)"; then
    DT_MODE="${DETECT_OUT%%|*}"
    SOURCE_DIR="${DETECT_OUT#*|}"
  else
    printf '❌ Hittar ingen Darktable-konfigurationskatalog.\n' >&2
    printf 'Ange den uttryckligen med --source=PATH.\n' >&2
    exit 1
  fi
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  printf '❌ Källkatalogen finns inte: %s\n' "$SOURCE_DIR" >&2
  exit 1
fi

if ! SOURCE_DIR="$(absolute_existing_dir "$SOURCE_DIR")"; then
  printf '❌ Kan inte öppna källkatalogen: %s\n' "$SOURCE_DIR" >&2
  exit 1
fi

# ---------------------------
# Logg och lås
# ---------------------------
if [[ "$DRYRUN" == true ]]; then
  printf '=== DRY-RUN: inga filer eller kataloger ändras ===\n'
else
  mkdir -p -- "$BASE_DIR"

  if ! BASE_DIR="$(absolute_existing_dir "$BASE_DIR")"; then
    printf '❌ Kan inte öppna backupkatalogen: %s\n' "$BASE_DIR" >&2
    exit 1
  fi

  LOG_FILE="$BASE_DIR/backup_darktable.log"
  LOCK_FILE="$BASE_DIR/.backup_darktable.lock"

  exec > >(tee -a "$LOG_FILE") 2>&1

  # Låsfilen får ligga kvar. flock låser filbeskrivaren, inte filnamnet.
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    fatal "En annan Darktable-backup körs redan."
  fi

  trap cleanup_partial EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

log "------------------------------------------------------------"
log "Startar $SCRIPT_NAME version $VERSION"
log "Installationstyp: $DT_MODE"
log "Källa:            $SOURCE_DIR"
log "Backupbas:        $BASE_DIR"
log "Behåll snapshots: $KEEP"
log "Dry-run:          $DRYRUN"

if command -v pgrep >/dev/null 2>&1 && pgrep -x darktable >/dev/null 2>&1; then
  log "⚠️  Darktable verkar vara igång. Stäng helst programmet före backup"
  log "    så att databasfilerna inte ändras under kopieringen."
fi

# ---------------------------
# Namn och målkataloger
# ---------------------------
SNAP_NAME="$(choose_snapshot_name)"
FINAL_DIR="$BASE_DIR/$SNAP_NAME"
FINAL_DATA_DIR="$FINAL_DIR/darktable"
PARTIAL_DIR="$BASE_DIR/.partial-${SNAP_NAME}-$$"
PARTIAL_DATA_DIR="$PARTIAL_DIR/darktable"

log "Planerad snapshot: $FINAL_DIR"

# ---------------------------
# Dry-run
# ---------------------------
if [[ "$DRYRUN" == true ]]; then
  log "Skulle skapa temporär katalog: $PARTIAL_DATA_DIR"
  log "Skulle kopiera och sedan verifiera:"

  rsync -a --delete --dry-run --itemize-changes \
    "$SOURCE_DIR/" "$PARTIAL_DATA_DIR/"

  log "Skulle byta namn efter godkänd verifiering:"
  log "  $PARTIAL_DIR → $FINAL_DIR"

  mapfile -t EXISTING_SNAPS < <(list_snapshots)
  TOTAL_AFTER=$(( ${#EXISTING_SNAPS[@]} + 1 ))

  if (( TOTAL_AFTER > KEEP )); then
    REMOVE_COUNT=$(( TOTAL_AFTER - KEEP ))
    log "Rotation skulle ta bort $REMOVE_COUNT gammal/gamla snapshot(s)."
  else
    log "Rotation skulle inte ta bort något."
  fi

  log "✅ DRY-RUN klar – ingenting ändrades."
  log "------------------------------------------------------------"
  exit 0
fi

# ---------------------------
# Skapa och kopiera
# ---------------------------
log "Skapar temporär snapshot: $PARTIAL_DIR"
mkdir -p -- "$PARTIAL_DATA_DIR"

log "Kopierar konfigurationen ..."
if ! rsync -a --delete "$SOURCE_DIR/" "$PARTIAL_DATA_DIR/"; then
  fatal "rsync misslyckades. Ingen giltig snapshot publicerades."
fi
log "Kopieringen är klar."

# ---------------------------
# Verifiera med checksummor
# ---------------------------
log "Verifierar filer, metadata och innehåll med rsync-checksummor ..."
VERIFY_OUTPUT=""

if ! VERIFY_OUTPUT="$(
  rsync -a --checksum --delete --dry-run --itemize-changes \
    "$SOURCE_DIR/" "$PARTIAL_DATA_DIR/" 2>&1
)"; then
  [[ -n "$VERIFY_OUTPUT" ]] && printf '%s\n' "$VERIFY_OUTPUT"
  fatal "Verifieringskommandot misslyckades."
fi

if [[ -n "$VERIFY_OUTPUT" ]]; then
  log "❌ Verifieringen hittade skillnader:"
  printf '%s\n' "$VERIFY_OUTPUT"
  fatal "Snapshoten godkändes inte."
fi

log "✅ Verifiering OK."

# ---------------------------
# Publicera snapshot atomiskt
# ---------------------------
if [[ -e "$FINAL_DIR" ]]; then
  fatal "Målkatalogen finns redan: $FINAL_DIR"
fi

mv -- "$PARTIAL_DIR" "$FINAL_DIR"
PARTIAL_DIR=""
log "Snapshot publicerad: $FINAL_DIR"

# ---------------------------
# Rotation
# ---------------------------
log "Roterar snapshots och behåller de $KEEP senaste."
mapfile -t SNAPSHOTS < <(list_snapshots)

if ((${#SNAPSHOTS[@]} > KEEP)); then
  for ((i=KEEP; i<${#SNAPSHOTS[@]}; i++)); do
    OLD_SNAPSHOT="$BASE_DIR/${SNAPSHOTS[$i]}"
    log "Tar bort gammal snapshot: $OLD_SNAPSHOT"
    rm -rf -- "$OLD_SNAPSHOT"
  done
else
  log "Inget behöver tas bort. Antal snapshots: ${#SNAPSHOTS[@]}."
fi

log "✅ Backup färdig: $FINAL_DIR"
log "------------------------------------------------------------"
