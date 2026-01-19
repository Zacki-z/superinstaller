#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Tar backup från SOURCE_DIR till current/ med rotation och loggning.
# Behåller de 3 senaste versionerna i old/.
# Stöd för --dry-run och integritetskontroll efter rotation.

set -euo pipefail

# ----- KONFIGURATION -----
SOURCE_DIR="~/.config/darktable"                 # katalogen du vill ta backup av
BASE_DIR="~/bup_darktable"                    # basmapp där new/current/old ligger
LOG_FILE="~/bup_darktable/backup_rotate.log"  # loggfilens plats
KEEP=3                                        # antal gamla versioner att behålla

# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  echo "=== KÖR I DRY-RUN-LÄGE (INGA FÖRÄNDRINGAR GÖRS) ==="
fi

# ----- Hjälpfunktioner -----
expand_tilde() { case "$1" in "~"|"~/"*) printf "%s%s" "$HOME" "${1#\~}";; * ) printf "%s" "$1";; esac; }
abspath_or_die() { cd "$1" 2>/dev/null && pwd || { echo "Fel: katalog finns ej: $1" >&2; exit 1; }; }
log() { printf '[%s] %s\n' "$(date +%F' '%T)" "$*"; }

# ---- Preflight ----
LOG_FILE="$(expand_tilde "$LOG_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log "------------------------------------------------------------"
log "Backup-rotation startad"
$DRYRUN && log "DRY-RUN aktiverad – inga filer flyttas eller tas bort."

SOURCE_DIR="$(expand_tilde "$SOURCE_DIR")"
BASE_DIR="$(expand_tilde "$BASE_DIR")"

if [[ ! -d "$SOURCE_DIR" ]]; then
  log "Fel: SOURCE_DIR finns inte: $SOURCE_DIR"
  exit 1
fi
SOURCE_DIR="$(abspath_or_die "$SOURCE_DIR")"
mkdir -p "$BASE_DIR"
BASE_DIR="$(abspath_or_die "$BASE_DIR")"

NEW_DIR="$BASE_DIR/new"
CURRENT_DIR="$BASE_DIR/current"
OLD_BASE="$BASE_DIR/old"
LOCKFILE="$BASE_DIR/.backup_rotate.lock"

log "Källa:        $SOURCE_DIR"
log "Backupbas:    $BASE_DIR"
log "Loggfil:      $LOG_FILE"
log "Behåll (KEEP): $KEEP"

# ----- LÅS -----
exec 9>"$LOCKFILE"
cleanup() {
  log "Städar låsfil..."
  exec 9>&- || true
  rm -f "$LOCKFILE" || true
}
trap cleanup EXIT
flock -n 9 || { log "Ett annat jobb körs. Avbryter."; exit 1; }

# ----- SKAPA KATALOGER -----
for DIR in "$BASE_DIR" "$OLD_BASE" "$NEW_DIR"; do
  [[ -d "$DIR" ]] || { log "Skapar katalog: $DIR"; mkdir -p "$DIR"; }
done

# ----- SKAPA NY BACKUP -----
log "Skapar ny backup från $SOURCE_DIR till $NEW_DIR ..."
if $DRYRUN; then
  rsync -a --delete --dry-run "$SOURCE_DIR/" "$NEW_DIR/"
else
  rsync -a --delete "$SOURCE_DIR/" "$NEW_DIR/"
fi
log "Backup av källa klar."

# ----- ROTATION -----
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -d "$CURRENT_DIR" ]]; then
  DEST="$OLD_BASE/$TS"
  log "Flyttar current -> $DEST"
  $DRYRUN || mv "$CURRENT_DIR" "$DEST"
else
  log "Ingen current hittades – hoppar över backup av current."
fi

log "Flyttar new -> current"
$DRYRUN || mv "$NEW_DIR" "$CURRENT_DIR"

# ----- DITT ÖNSKADE TILLÄGG -----
echo linkss
ls -l /home/alain/snap/darktable/ >/home/alain/bup_darktable/current/linkss

# ----- RENSNING AV GAMLA VERSIONER -----
log "Rensar gamla versioner, behåller $KEEP senaste ..."
mapfile -t ALL < <(find "$OLD_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
  | grep -E '^[0-9]{8}-[0-9]{6}$' || true)
IFS=$'\n' ALL=($(printf "%s\n" "${ALL[@]}" | sort -r))

if (( ${#ALL[@]} > KEEP )); then
  for (( i=KEEP; i<${#ALL[@]}; i++ )); do
    TARGET="$OLD_BASE/${ALL[$i]}"
    log "Tar bort: $TARGET"
    $DRYRUN || rm -rf -- "$TARGET"
  done
else
  log "Inget att ta bort (<= $KEEP versioner)."
fi

# ----- VERIFIERING -----
if $DRYRUN; then
  log "Verifiering hoppades över (dry-run)."
else
  log "Påbörjar verifiering (källa vs current) ..."
  files_src=$(find "$SOURCE_DIR" -type f | wc -l | tr -d ' ')
  files_cur=$(find "$CURRENT_DIR" -type f | wc -l | tr -d ' ')
  bytes_src=$(du -sb "$SOURCE_DIR" | cut -f1)
  bytes_cur=$(du -sb "$CURRENT_DIR" | cut -f1)
  log "Filer: källa=$files_src, current=$files_cur"
  log "Bytes: källa=$bytes_src, current=$bytes_cur"

  verify_ok=true
  if [[ "$files_src" != "$files_cur" ]]; then
    log "VARNING: Antal filer skiljer (källa $files_src vs current $files_cur)."
    verify_ok=false
  fi
  if [[ "$bytes_src" != "$bytes_cur" ]]; then
    log "VARNING: Totala bytes skiljer (källa $bytes_src vs current $bytes_cur)."
    verify_ok=false
  fi
  if $verify_ok; then
    log "Verifiering OK."
  else
    log "Verifiering MISSLYCKADES."
  fi
fi

log "Rotation färdig."
log "------------------------------------------------------------"
ls -la "$BASE_DIR" || true
ls -la "$OLD_BASE" || true
echo " backup färdigt "
sleep 10

