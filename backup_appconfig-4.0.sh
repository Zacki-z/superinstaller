#!/usr/bin/env bash
# ============================================================
# backup_appconfig-4.0.sh
# ============================================================
# Backup av applikationskonfigurationer baserat på en gemensam paths-fil.
#
#  - Utan app-argument: backar upp ALLA appar i paths-filen.
#  - Med app-argument: backar upp endast den angivna appen.
#  - Med --source=PATH: använder exakt angiven källkatalog
#    (endast tillsammans med ett app-namn).
#
#  - Paths-fil (standard): $HOME/my_bin/etc/app_paths.txt
#    Format, en rad per möjlig sökväg:
#       appnamn   /sök/väg/till/config
#
#  - För varje app väljs den första katalog som existerar.
#  - Arkiv skapas som:
#       <app>.<YYYYMMDD-HHMMSS>.tar.gz
#    under:
#       $HOME/bup_appl_config
#
#  - Ingen rotation eller automatisk radering av äldre backupfiler.
# ============================================================

set -Eeuo pipefail

DEFAULT_BACKUP_ROOT="${HOME}/bup_appl_config"
DEFAULT_PATH_FILE="${HOME}/my_bin/etc/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"
APP_NAME=""
SOURCE_OVERRIDE=""
DRYRUN=false
VERBOSE=false
RUN_TS="$(date +%Y%m%d-%H%M%S)"

msg() {
  printf '%s\n' "$*" >&2
}

verbose_msg() {
  if [[ "$VERBOSE" == true ]]; then
    msg "$*"
  fi
}

die() {
  msg "❌ $*"
  exit 1
}

usage() {
  cat <<EOF_USAGE
Användning:
  $(basename "$0") [app-namn] [flaggor]

Lägen:
  Alla appar i paths-filen:
    $(basename "$0")
    $(basename "$0") --dry-run

  En specifik app:
    $(basename "$0") darktable
    $(basename "$0") kicad --dry-run

  En app med en tillfällig källsökväg:
    $(basename "$0") rawtherapee --source="\$HOME/.config/RawTherapee"

Flaggor:
  --source=PATH
      Använd exakt angiven källkatalog.
      Kräver att ett app-namn har angetts.

  --backup-root=PATH
      Var backupfilerna ska hamna.
      Standard: $DEFAULT_BACKUP_ROOT

  --paths-file=PATH
      Sökväg till app_paths.txt.
      Standard: $DEFAULT_PATH_FILE

      Kan även anges med miljövariabeln:
        BUP_APPCONFIG_PATH_FILE=/annan/sökväg/app_paths.txt

  --dry-run, -n
      Visa vad som skulle göras utan att skapa kataloger eller arkiv.

  --verbose, -v
      Visa mer information om kandidatsökvägar och val.

  --help, -h
      Visa denna hjälptext.

Format på app_paths.txt:
  # appnamn   path
  darktable   ~/.config/darktable
  darktable   ~/.var/app/org.darktable.Darktable/config/darktable
  darktable   ~/snap/darktable/current/.config/darktable

  kicad       ~/.config/kicad
  kicad       ~/.local/share/kicad
EOF_USAGE
}

expand_home_path() {
  local path="$1"

  case "$path" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${path#\~/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

get_candidates_for_app() {
  local app="$1"
  local pathfile="$2"
  local app_col path_col expanded
  local found=false

  [[ -f "$pathfile" ]] || return 1

  while read -r app_col path_col; do
    [[ -z "${app_col:-}" ]] && continue
    [[ "$app_col" == \#* ]] && continue
    [[ "$app_col" != "$app" ]] && continue
    [[ -z "${path_col:-}" ]] && continue

    expanded="$(expand_home_path "$path_col")"
    printf '%s\0' "$expanded"
    found=true
  done < "$pathfile"

  [[ "$found" == true ]]
}

get_all_apps() {
  local pathfile="$1"
  local app_col path_col
  local -A seen=()
  local found=false

  [[ -f "$pathfile" ]] || return 1

  while read -r app_col path_col; do
    [[ -z "${app_col:-}" ]] && continue
    [[ "$app_col" == \#* ]] && continue
    [[ -z "${path_col:-}" ]] && continue

    if [[ -z "${seen[$app_col]+x}" ]]; then
      seen["$app_col"]=1
      printf '%s\0' "$app_col"
      found=true
    fi
  done < "$pathfile"

  [[ "$found" == true ]]
}

backup_one_app() {
  local app="$1"
  local source_dir=""
  local dest_file

  msg "--------------------------------------------------"
  msg "App: $app"

  if [[ -n "$SOURCE_OVERRIDE" ]]; then
    source_dir="$(expand_home_path "$SOURCE_OVERRIDE")"
    verbose_msg "Källan angavs med --source: $source_dir"

    if [[ ! -d "$source_dir" ]]; then
      msg "❌ Källkatalogen finns inte: $source_dir"
      return 1
    fi
  else
    local -a candidates=()

    if ! mapfile -d '' -t candidates < <(get_candidates_for_app "$app" "$PATH_FILE"); then
      msg "⚠️  Hittar inga sökvägar för '$app' i: $PATH_FILE"
      msg "    Hoppar över appen."
      return 0
    fi

    local candidate
    for candidate in "${candidates[@]}"; do
      verbose_msg "Prövar kandidat: $candidate"
      if [[ -d "$candidate" ]]; then
        source_dir="$candidate"
        break
      fi
    done

    if [[ -z "$source_dir" ]]; then
      msg "⚠️  Ingen existerande katalog hittades för '$app'."
      if [[ "$VERBOSE" == true ]]; then
        msg "    Kontrollerade sökvägar:"
        printf '      - %s\n' "${candidates[@]}" >&2
      fi
      msg "    Hoppar över appen."
      return 0
    fi
  fi

  dest_file="${BACKUP_ROOT}/${app}.${RUN_TS}.tar.gz"

  msg "Källa:          $source_dir"
  msg "Backup-katalog: $BACKUP_ROOT"
  msg "Målfil:         $dest_file"

  if [[ "$DRYRUN" == true ]]; then
    msg "🟡 DRY-RUN: inga filer ändras."
    msg "Skulle köra:"
    msg "  mkdir -p \"$BACKUP_ROOT\""
    msg "  tar -czf \"$dest_file\" -C \"$source_dir\" ."
    return 0
  fi

  mkdir -p "$BACKUP_ROOT"

  msg "📦 Skapar arkiv..."
  if tar -czf "$dest_file" -C "$source_dir" .; then
    msg "✅ Klar: $dest_file"
    return 0
  fi

  msg "❌ tar misslyckades för appen: $app"
  return 1
}

# Första argumentet kan vara app-namn eller flagga.
if [[ $# -gt 0 ]]; then
  case "$1" in
    --source=*|--backup-root=*|--paths-file=*|--dry-run|-n|--verbose|-v|--help|-h)
      ;;
    --*)
      die "Okänt argument: $1"
      ;;
    *)
      APP_NAME="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source=*)
      SOURCE_OVERRIDE="${1#*=}"
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
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Okänt argument: $1"
      ;;
  esac
done

BACKUP_ROOT="$(expand_home_path "$BACKUP_ROOT")"
PATH_FILE="$(expand_home_path "$PATH_FILE")"

if [[ -n "$SOURCE_OVERRIDE" && -z "$APP_NAME" ]]; then
  die "--source kräver att du också anger ett app-namn."
fi

if [[ -z "$SOURCE_OVERRIDE" && ! -f "$PATH_FILE" ]]; then
  die "Paths-filen saknas: $PATH_FILE"
fi

msg "=== backup_appconfig 4.0 ==="
msg "BACKUP_ROOT: $BACKUP_ROOT"
msg "PATH_FILE:   $PATH_FILE"
msg "RUN_TS:      $RUN_TS"
msg "APP_NAME:    ${APP_NAME:-<alla>}"
msg "DRYRUN:      $DRYRUN"
msg "VERBOSE:     $VERBOSE"
msg

overall_status=0

if [[ -n "$APP_NAME" ]]; then
  if ! backup_one_app "$APP_NAME"; then
    overall_status=1
  fi
else
  apps=()
  if ! mapfile -d '' -t apps < <(get_all_apps "$PATH_FILE"); then
    die "Inga appar hittades i paths-filen: $PATH_FILE"
  fi

  msg "Appar att säkerhetskopiera:"
  printf '  - %s\n' "${apps[@]}" >&2
  msg

  for app in "${apps[@]}"; do
    if ! backup_one_app "$app"; then
      overall_status=1
    fi
  done
fi

msg
if [[ "$overall_status" -eq 0 ]]; then
  if [[ "$DRYRUN" == true ]]; then
    msg "✅ Dry-run klar. Inga filer ändrades."
  else
    msg "🎉 Backup-körningen är klar."
  fi
else
  msg "⚠️  Backup-körningen avslutades med minst ett fel."
fi

exit "$overall_status"
