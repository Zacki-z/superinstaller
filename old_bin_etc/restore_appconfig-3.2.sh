#!/usr/bin/env bash
# ============================================
# restore_appconfig-3.2.sh
# ============================================
# Återställ applikationskonfiguration från tar.gz-backupfiler
# skapade av backup_appconfig-3.x.sh.
#
#  - Backup-filer antas ligga i:
#        $HOME/bup_appl_config
#    och heta:
#        <app>.<YYYYMMDD-HHMMSS>.tar.gz
#
#  - Scriptet kan:
#      * Leta upp senaste backup för en app
#      * Eller använda en specifik fil via --file
#      * Välja mål-katalog via:
#          --target
#          app_paths.txt (gemensam fil)
#          fallback (~/.config/<app>, ~/.local/share/<app>)
#
#  - Befintlig mål-katalog flyttas först till:
#        <target>.bak-<timestamp>
#
#  - Stöd för --dry-run (ingen ändring görs)
#
# --------------------------------------------
# KONFIGURATION (kan ändras / överstyras)
# --------------------------------------------
DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
# Gemensam fil med app-namn och standard-sökvägar:
# Kan överstyras med env-variabeln BUP_APPCONFIG_PATH_FILE
DEFAULT_PATH_FILE="$HOME/.config/backup_appconfig/app_paths.txt"
# ============================================

set -euo pipefail

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"

APP_NAME=""
ARCHIVE_FILE=""
TARGET_DIR=""
DRYRUN=false

RUN_TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<EOF
Användning: $(basename "$0") <app-namn> [flaggor]

  <app-namn>
      Namn på applikationen vars config ska återställas, t.ex.:
        darktable
        kicad
        rawtherapee
        densiometer

Flaggor:
  --file=FIL
      Använd specifik backup-fil.
      Om FIL är relativt (saknar '/'), antas den ligga i:
        $BACKUP_ROOT/FIL

  --target=KATALOG
      Återställ till denna mål-katalog.
      Om inte angiven används:
        1) app_paths.txt (om rad för appen finns)
        2) fallback (~/.config/<app> eller ~/.local/share/<app>)

  --backup-root=PATH
      Var backup-filerna normalt ligger.
      Default: $DEFAULT_BACKUP_ROOT

  --paths-file=PATH
      Var app_paths.txt ligger.
      Default: $DEFAULT_PATH_FILE
      Kan också sättas via env-variabeln:
        BUP_APPCONFIG_PATH_FILE

  --dry-run, -n
      Visa vad som skulle göras utan att skapa, flytta eller skriva något.

  --help, -h
      Visa denna hjälp.

Exempel:
  $(basename "$0") darktable
  $(basename "$0") darktable --dry-run
  $(basename "$0") darktable --file=darktable.20251122-190000.tar.gz
  $(basename "$0") kicad --target="\$HOME/.config/kicad"
EOF
}

# --------------------------------------------
# Hitta mål-katalog via app_paths.txt
# Format på app_paths.txt:
#   appname   path
#   darktable ~/.config/darktable
#   kicad     ~/.config/kicad
# --------------------------------------------
find_target_from_pathsfile() {
  local app="$1"
  local pathfile="$2"
  local line_app
  local line_path

  if [[ ! -f "$pathfile" ]]; then
    return 1
  fi

  while read -r line_app line_path; do
    # hoppa över tomma rader
    if [[ -z "${line_app:-}" ]]; then
      continue
    fi
    # hoppa över kommentarer
    if [[ "$line_app" == \#* ]]; then
      continue
    fi
    # endast rader för aktuell app
    if [[ "$line_app" != "$app" ]]; then
      continue
    fi
    if [[ -z "${line_path:-}" ]]; then
      continue
    fi

    # expandera ~ till $HOME
    local expanded="$line_path"
    expanded="${expanded/#\~/$HOME}"

    TARGET_DIR="$expanded"
    return 0
  done < "$pathfile"

  return 1
}

# --------------------------------------------
# Fallback-mål om ingen paths-fil används
# --------------------------------------------
fallback_target_guess() {
  local app="$1"
  local c1="$HOME/.config/$app"
  local c2="$HOME/.local/share/$app"

  if [[ -d "$c1" ]]; then
    TARGET_DIR="$c1"
    return 0
  fi
  if [[ -d "$c2" ]]; then
    TARGET_DIR="$c2"
    return 0
  fi

  # Om ingen av dem finns, välj ~/.config/<app> som default
  TARGET_DIR="$c1"
  return 0
}

# --------------------------------------------
# Hitta backup-fil om --file inte angetts
# --------------------------------------------
find_latest_archive_for_app() {
  local app="$1"
  local root="$2"

  if [[ ! -d "$root" ]]; then
    return 1
  fi

  local pattern="$root/${app}."*.tar.gz
  # Glob utan träff ger pattern bokstavligen; hantera detta
  shopt -s nullglob
  local files=( $pattern )
  shopt -u nullglob

  if ((${#files[@]} == 0)); then
    return 1
  fi

  # sortera och ta sista (senaste)
  local latest
  IFS=$'\n' read -r -d '' latest < <(printf '%s\n' "${files[@]}" | sort | tail -n 1 && printf '\0')
  ARCHIVE_FILE="$latest"
  return 0
}

# --------------------------------------------
# Argumentparsning
# --------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

APP_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file=*)
      ARCHIVE_FILE="${1#*=}"
      shift
      ;;
    --target=*)
      TARGET_DIR="${1#*=}"
      shift
      ;;
    --backup-root=*)
      BACKUP_ROOT="${1#*=}"
      shift
      ;;
    --paths-file=*)
      PATH_FILE="${1#*=}"
      shift
      ;;
    --dry-run|-n)
      DRYRUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Okänt argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# --------------------------------------------
# Bestäm backup-fil (ARCHIVE_FILE)
# --------------------------------------------
if [[ -n "$ARCHIVE_FILE" ]]; then
  # Relativa namn tolkas relativt till BACKUP_ROOT
  if [[ "$ARCHIVE_FILE" != /* ]]; then
    ARCHIVE_FILE="$BACKUP_ROOT/$ARCHIVE_FILE"
  fi
else
  if ! find_latest_archive_for_app "$APP_NAME" "$BACKUP_ROOT"; then
    echo "❌ Hittar ingen backup-fil för app \"$APP_NAME\" under: $BACKUP_ROOT" >&2
    echo "   Förväntat namnformat: ${APP_NAME}.YYYYMMDD-HHMMSS.tar.gz" >&2
    echo "   Antingen:" >&2
    echo "     - skapa en backup först, eller" >&2
    echo "     - ange fil direkt: --file=/sök/väg/fil.tar.gz" >&2
    exit 1
  fi
fi

if [[ ! -f "$ARCHIVE_FILE" ]]; then
  echo "❌ Backup-filen finns inte: $ARCHIVE_FILE" >&2
  exit 1
fi

# --------------------------------------------
# Bestäm TARGET_DIR
# --------------------------------------------
if [[ -z "$TARGET_DIR" ]]; then
  # 1) Försök med paths-fil
  if ! find_target_from_pathsfile "$APP_NAME" "$PATH_FILE"; then
    # 2) Fallback
    fallback_target_guess "$APP_NAME"
  fi
fi

# expandera ev ~ i TARGET_DIR
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

if [[ -z "$TARGET_DIR" ]]; then
  echo "❌ Kunde inte avgöra mål-katalog (TARGET_DIR)." >&2
  exit 1
fi

# --------------------------------------------
# Visa sammanfattning
# --------------------------------------------
echo "========================================"
echo "Återställ applikationskonfiguration"
echo "----------------------------------------"
echo "App-namn:       $APP_NAME"
echo "Backup-fil:     $ARCHIVE_FILE"
echo "Backup-root:    $BACKUP_ROOT"
echo "Paths-fil:      $PATH_FILE"
echo "Mål-katalog:    $TARGET_DIR"
echo "Dry-run:        $DRYRUN"
echo "Tidstämpel:     $RUN_TS"
echo "========================================"

# --------------------------------------------
# Förbered mål: flytta ev. gammal config
# --------------------------------------------
SAFE_DIR=""

if [[ -d "$TARGET_DIR" ]]; then
  # Om katalogen finns och inte är tom, flytta undan
  if [[ -n "$(ls -A "$TARGET_DIR" 2>/dev/null || true)" ]]; then
    parent="$(dirname "$TARGET_DIR")"
    base="$(basename "$TARGET_DIR")"
    SAFE_DIR="${parent}/${base}.bak-${RUN_TS}"

    echo
    echo "Befintlig config upptäckt:"
    echo "  $TARGET_DIR"
    echo "Den kommer att flyttas till:"
    echo "  $SAFE_DIR"
  fi
fi

if [[ "$DRYRUN" == true ]]; then
  echo
  echo "🟡 DRY-RUN: Inga filer kommer att flyttas eller skrivas."
  if [[ -n "$SAFE_DIR" ]]; then
    echo "(dry-run) skulle köra: mv \"$TARGET_DIR\" \"$SAFE_DIR\""
  fi
  echo "(dry-run) skulle säkerställa att katalogen finns: mkdir -p \"$TARGET_DIR\""
  echo "(dry-run) skulle extrahera: tar -xzf \"$ARCHIVE_FILE\" -C \"$TARGET_DIR\""
  exit 0
fi

# Utför faktisk återställning
echo
echo "🚧 Påbörjar återställning..."

if [[ -n "$SAFE_DIR" ]]; then
  echo "Flyttar befintlig config:"
  echo "  mv \"$TARGET_DIR\" \"$SAFE_DIR\""
  mv "$TARGET_DIR" "$SAFE_DIR"
fi

echo "Skapar mål-katalog (om den inte finns):"
mkdir -p "$TARGET_DIR"

echo "Extraherar backup:"
tar -xzf "$ARCHIVE_FILE" -C "$TARGET_DIR"

echo
echo "✅ Återställning klar."
echo "   App:              $APP_NAME"
echo "   Från backup-fil:  $ARCHIVE_FILE"
echo "   Till katalog:     $TARGET_DIR"
if [[ -n "$SAFE_DIR" ]]; then
  echo "   Tidigare config flyttad till: $SAFE_DIR"
fi
echo

