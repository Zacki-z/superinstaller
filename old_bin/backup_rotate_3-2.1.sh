#!/usr/bin/env bash
# === backup_rotate_3-2.1.sh ===
# Tar backup av Darktables config till current/ med rotation och loggning.
# Behåller de 3 senaste versionerna i old/.
# Stöd för --dry-run och integritetskontroll efter rotation.
#
# Autodetekterar Darktables config-katalog:
#  - Snap:     $HOME/snap/darktable/current/.config/darktable (eller senaste rev)
#  - Flatpak:  $HOME/.var/app/org.darktable.Darktable/config/darktable
#  - Native:   $HOME/.config/darktable  (apt/AppImage/vanlig)

set -euo pipefail

# ----- KONFIGURATION -----
# SOURCE_DIR lämnas tom -> autodetektera Darktable
SOURCE_DIR=""                                    # låt scriptet hitta katalogen
BASE_DIR="~/bup_darktable"                      # basmapp där new/current/old ligger
LOG_FILE="~/bup_darktable/backup_rotate.log"    # loggfilens plats
KEEP=3                                           # antal gamla versioner att behålla

# ----- ARGUMENT -----
DRYRUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  echo "=== KÖR I DRY-RUN-LÄGE (INGA FÖRÄNDRINGAR GÖRS) ==="
fi

# ----- Hjälpfunktioner -----
expand_tilde() {
  case "$1" in
    "~"|"~/"*) printf "%s%s" "$HOME" "${1#\~}" ;;
    * )        printf "%s" "$1" ;;
  esac
}

abspath_or_die() {
  cd "$1" 2>/dev/null && pwd || { echo "Fel: katalog finns ej: $1" >&2; exit 1; }
}

log() {
  printf '[%s] %s\n' "$(date +%F' '%T)" "$*"
}

detect_darktable_config() {
  # Förklarande variabel för logg
  DT_MODE="okänd"

  # 1) Snap: ~/snap/darktable/current/.config/darktable
  if [[ -d "$HOME/snap/darktable" ]]; then
    if [[ -d "$HOME/snap/darktable/current/.config/darktable" ]]; then
      SOURCE_DIR="$HOME/snap/darktable/current/.config/darktable"
      DT_MODE="snap (current)"
      echo "$DT_MODE|$SOURCE_DIR"
      return 0
    fi

    # Om "current" inte finns, ta senaste numrerade revision
    local last_rev
    last_rev=$(ls -1 "$HOME/snap/darktable" 2>/dev/null \
               | grep -E '^[0-9]+$' \
               | sort -n | tail -n1 || true)
    if [[ -n "${last_rev:-}" && -d "$HOME/snap/darktable/$last_rev/.config/darktable" ]]; then
      SOURCE_DIR="$HOME/snap/darktable/$last_rev/.config/darktable"
      DT_MODE="snap (rev $last_rev)"
      echo "$DT_MODE|$SOURCE_DIR"
      return 0
    fi
  fi

  # 2) Flatpak: ~/.var/app/org.darktable.Darktable/config/darktable
  if [[ -d "$HOME/.var/app/org.darktable.Darktable/config/darktable" ]]; then
    SOURCE_DIR="$HOME/.var/app/org.darktable.Darktable/config/darktable"
    DT_MODE="flatpak"
    echo "$DT_MODE|$SOURCE_DIR"
    return 0
  fi

  # 3) Native/AppImage/apt: ~/.config/darktable
  if [[ -d "$HOME/.config/darktable" ]]; then
    SOURCE_DIR="$HOME/.config/darktable"
    DT_MODE="native/appimage/apt (~/.config/darktable)"
    echo "$DT_MODE|$SOURCE_DIR"
    return 0
  fi

  return 1
}

# ---- Preflight: logg och basdir ----
LOG_FILE="$(expand_tilde "$LOG_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log "------------------------------------------------------------"
log "Backup-rotation startad"
$DRYRUN && log "DRY-RUN aktiverad – inga filer flyttas eller tas bort."

# Autodetektera Darktable-katalog om SOURCE_DIR inte är satt manuellt
DT_MODE="okänd"
if [[ -z "$SOURCE_DIR" ]]; then
  if DETECT_OUT=$(detect_darktable_config); then
    DT_MODE="${DETECT_OUT%%|*}"
    SOURCE_DIR="${DETECT_OUT#*|}"
  else
    log "Fel: Kunde inte hitta någon Darktable-konfigurationskatalog."
    log "Försökte:"
    log "  - $HOME/snap/darktable/*/.config/darktable"
    log "  - $HOME/.var/app/org.darktable.Darktable/config/darktable"
    log "  - $HOME/.config/darktable"
    exit 1
  fi
fi

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

log "Identifierad Darktable-installation: $DT_MODE"
log "Källa (SOURCE_DIR): $SOURCE_DIR"
log "Backupbas:          $BASE_DIR"
log "Loggfil:            $LOG_FILE"
log "Behåll (KEEP):      $KEEP"

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

# ----- EXTRA: linkss (snap-info om den finns) -----
LINK_SRC="$HOME/snap/darktable"
LINK_DST="$CURRENT_DIR/linkss"

if [[ -d "$LINK_SRC" ]]; then
  log "Sparar kataloglistning från $LINK_SRC till $LINK_DST"
  if $DRYRUN; then
    log "(dry-run) skulle köra: ls -l \"$LINK_SRC\" > \"$LINK_DST\""
  else
    ls -l "$LINK_SRC" >"$LINK_DST" 2>&1 || log "VARNING: kunde inte skriva $LINK_DST"
  fi
else
  log "Ingen snap-katalog hittades under $LINK_SRC – hoppar över linkss-dump."
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
log "Backup färdig."
sleep 10

