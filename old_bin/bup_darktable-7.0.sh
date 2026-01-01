#!/usr/bin/env bash
# === backup_rotate_3.sh ===
# Tar backup från SOURCE_DIR till current/ med rotation och loggning.
# Behåller de 3 senaste versionerna i old/.
# Stöd för --dry-run och integritetskontroll efter rotation.

set -euo pipefail

# ----- KONFIGURATION (ändra dessa) -----
SOURCE_DIR="~/snap/darktable"                 # katalogen du vill ta backup av
BASE_DIR="~/bup_darktable"                       # basmapp där new/current/old ligger
LOG_FILE="~/bup_darktable/backup_rotate.log"         # loggfilens plats
KEEP=3                                      # antal gamla versioner att behålla
echo linkss
ls -l /home/alain/snap/darktable/ >/home/alain/bup_darktable/current/linkss
# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  echo "=== KÖR I DRY-RUN-LÄGE (INGA FÖRÄNDRINGAR GÖRS) ==="
fi

# ----- Hjälpfunktioner -----
expand_tilde() { case "$1" in "~"|"~/"*) printf "%s%s" "$HOME" "${1#\~}";; * ) printf "%s" "$1";; esac; }
abspath_or_die() {  # $1=path ; echo abs path or exit
  local p="$1"
  cd "$p" 2>/dev/null && pwd || { echo "Fel: katalog finns ej: $p" >&2; exit 1; }
}
log() { printf '[%s] %s\n' "$(date +%F' '%T)" "$*"; }

# ---- Preflight: expandera ~ och starta logg ----
LOG_FILE="$(expand_tilde "$LOG_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"
# shellcheck disable=SC2094
exec > >(tee -a "$LOG_FILE") 2>&1

log "------------------------------------------------------------"
log "Backup-rotation startad"
$DRYRUN && log "DRY-RUN aktiverad – inga filer flyttas eller tas bort."

# 2) Expandera övriga konfig-vägar
SOURCE_DIR="$(expand_tilde "$SOURCE_DIR")"
BASE_DIR="$(expand_tilde "$BASE_DIR")"

# 3) Verifiera källa och gör absoluta vägar
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

# ----- SKAPA NÖDVÄNDIGA KATALOGER -----
for DIR in "$BASE_DIR" "$OLD_BASE" "$NEW_DIR"; do
  if [[ -d "$DIR" ]]; then
    log "Katalog finns redan: $DIR"
  else
    log "Skapar katalog: $DIR"
    mkdir -p "$DIR"
  fi
done

# ----- SKAPA NY BACKUP (SOURCE → new) -----
log "Skapar ny backup från $SOURCE_DIR till $NEW_DIR ..."
if $DRYRUN; then
  rsync -a --delete --dry-run "$SOURCE_DIR/" "$NEW_DIR/"
else
  rsync -a --delete "$SOURCE_DIR/" "$NEW_DIR/"
fi
log "Backup av källa klar."
echo linkss
ls -l /home/alain/snap/darktable/ >/home/alain/bup_darktable/current/linkss

# ----- ROTATION -----
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -d "$CURRENT_DIR" ]]; then
  DEST="$OLD_BASE/$TS"
  log "Flyttar current -> $DEST"
  if ! $DRYRUN; then
    mv "$CURRENT_DIR" "$DEST"
  fi
else
  log "Ingen current hittades – hoppar över backup av current."
fi

log "Flyttar new -> current"
if ! $DRYRUN; then
  mv "$NEW_DIR" "$CURRENT_DIR"
fi

# ----- RENSNING AV GAMLA VERSIONER -----
log "Rensar gamla versioner, behåller $KEEP senaste ..."
mapfile -t ALL < <(find "$OLD_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" \
  | grep -E '^[0-9]{8}-[0-9]{6}$' || true)
IFS=$'\n' ALL=($(printf "%s\n" "${ALL[@]}" | sort -r))

if (( ${#ALL[@]} > KEEP )); then
  for (( i=KEEP; i<${#ALL[@]}; i++ )); do
    TARGET="$OLD_BASE/${ALL[$i]}"
    log "Tar bort: $TARGET"
    if ! $DRYRUN; then
      rm -rf -- "$TARGET"
    fi
  done
else
  log "Inget att ta bort (<= $KEEP versioner)."
fi

# ----- VERIFIERING EFTER ROTATION -----
if $DRYRUN; then
  log "Verifiering hoppades över (dry-run)."
else
  log "Påbörjar verifiering (källa vs current) ..."
  # Antal filer
  files_src=$(find "$SOURCE_DIR" -type f | wc -l | tr -d ' ')
  files_cur=$(find "$CURRENT_DIR" -type f | wc -l | tr -d ' ')
  # Total storlek i bytes (du -sb ger summan i bytes)
  bytes_src=$(du -sb "$SOURCE_DIR" | cut -f1)
  bytes_cur=$(du -sb "$CURRENT_DIR" | cut -f1)

  log "Filer: källa=$files_src, current=$files_cur"
  log "Bytes: källa=$bytes_src, current=$bytes_cur"

  verify_ok=true
  if [[ "$files_src" != "$files_cur" ]]; then
    log "VARNING: Antal filer skiljer (källa $files_src vs current $files_cur)."
    verify_ok=false
  fi
  # Tillåt liten differens i bytes för metadata/symlänkar? Vi kör strikt här:
  if [[ "$bytes_src" != "$bytes_cur" ]]; then
    log "VARNING: Totala bytes skiljer (källa $bytes_src vs current $bytes_cur)."
    verify_ok=false
  fi

  if $verify_ok; then
    log "Verifiering OK: current matchar källan (filer & storlek)."
  else
    log "Verifiering MISSLYCKADES: kontrollera loggen ovan."
    # Vill du hårdstoppa på mismatch? Avkommentera nästa rad:
    # exit 2
  fi
fi

log "Rotation färdig."
log "------------------------------------------------------------"
ls -la "$BASE_DIR" || true
ls -la "$OLD_BASE" || true

