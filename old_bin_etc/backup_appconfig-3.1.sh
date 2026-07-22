#!/usr/bin/env bash
# ============================================================
# backup_appconfig-3.1.sh
# ============================================================
# Backup av applikationskonfigurationer.
#
#  - Sparar till:  $HOME/bup_appl_config
#  - Filnamn:      <app>.<YYYYMMDD-HHMMSS>.tar.gz
#
#  - Läser sökvägar ur EN gemensam fil:
#        $HOME/my_bin/etc/app_paths.txt   (default)
#    Format:
#        appname   /sök/väg/till/config
#
#  - Körlägen:
#      1) En app:
#           backup_appconfig-3.1.sh darktable
#           backup_appconfig-3.1.sh kicad --dry-run
#
#      2) Alla appar i app_paths.txt:
#           backup_appconfig-3.1.sh
#           backup_appconfig-3.1.sh --dry-run
#
#    Om du anger --source=PATH i en-app-läge används exakt den sökvägen.
#
# ============================================================

set -euo pipefail

# Standardkatalog för backup-filer
DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
# Standardplats för app_paths.txt (du kan ändra)
DEFAULT_PATH_FILE="$HOME/my_bin/etc/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"

APP_NAME=""          # tom = kör alla appar i filen
ALL_APPS=false
SOURCE_OVERRIDE=""   # --source=...
DRYRUN=false

# Global timestamp så alla filer från samma körning får samma tid
RUN_TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<EOF
Användning:
  $(basename "$0") [app-namn] [flaggor]

Lägen:
  1) En specifik app:
       $(basename "$0") darktable
       $(basename "$0") kicad --dry-run
       $(basename "$0") rawtherapee --source="\$HOME/.config/RawTherapee"

  2) Alla appar i app_paths.txt:
       $(basename "$0")
       $(basename "$0") --dry-run

Flaggor:
  --source=PATH
      Ange källkatalog direkt (endast vettigt i en-app-läge).

  --backup-root=PATH
      Var backup-filerna ska hamna.
      Default: $DEFAULT_BACKUP_ROOT

  --paths-file=PATH
      Var filen med app-sökvägar ligger.
      Default: $DEFAULT_PATH_FILE
      Kan också sättas via env:
        export BUP_APPCONFIG_PATH_FILE=/någon/annanstans/app_paths.txt

  --dry-run, -n
      Visa vad som skulle göras utan att skapa några arkiv.

  --help, -h
      Visa denna hjälp.

Format på app_paths.txt (EN gemensam fil):
  # appname   path
  darktable   ~/.config/darktable
  darktable   ~/.var/app/org.darktable.Darktable/config/darktable
  darktable   ~/snap/darktable/current/.config/darktable

  kicad       ~/.config/kicad
  kicad       ~/.local/share/kicad

  rawtherapee ~/.config/RawTherapee

EOF
}

# ------------------------------------------------------------
# Hämta alla unika app-namn ur app_paths.txt
# ------------------------------------------------------------
get_all_apps_from_pathsfile() {
  local pathfile="$1"
  local -A app_seen=()
  local app path

  [[ ! -f "$pathfile" ]] && return 1

  while read -r app path; do
    [[ -z "${app:-}" ]] && continue
    [[ "$app" == \#* ]] && continue
    app_seen["$app"]=1
  done < "$pathfile"

  if ((${#app_seen[@]} == 0)); then
    return 1
  fi

  # Skriv ut alla app-namn (en per rad)
  for app in "${!app_seen[@]}"; do
    echo "$app"
  done

  return 0
}

# ------------------------------------------------------------
# Hitta source_dir för en app via app_paths.txt + fallback
# ------------------------------------------------------------
resolve_source_for_app() {
  local app="$1"
  local pathfile="$2"
  local -a candidates=()
  local app_col path_col

  # 1) Försök via paths-fil (om den finns)
  if [[ -f "$pathfile" ]]; then
    while read -r app_col path_col; do
      [[ -z "${app_col:-}" ]] && continue
      [[ "$app_col" == \#* ]] && continue
      [[ "$app_col" != "$app" ]] && continue
      [[ -z "${path_col:-}" ]] && continue

      local expanded="$path_col"
      expanded="${expanded/#\~/$HOME}"
      candidates+=("$expanded")
    done < "$pathfile"
  fi

  # 2) Om inga kandidater därifrån: fallback
  if ((${#candidates[@]} == 0)); then
    if [[ "$app" == "darktable" ]]; then
      candidates=(
        "$HOME/.config/darktable"
        "$HOME/.var/app/org.darktable.Darktable/config/darktable"
        "$HOME/snap/darktable/current/.config/darktable"
      )
    else
      candidates=(
        "$HOME/.config/$app"
        "$HOME/.local/share/$app"
      )
    fi
  fi

  # 3) Välj första existerande katalog
  local d
  for d in "${candidates[@]}"; do
    if [[ -d "$d" ]]; then
      echo "$d"
      return 0
    fi
  done

  return 1
}

# ------------------------------------------------------------
# Backup av EN app
# ------------------------------------------------------------
backup_one_app() {
  local app="$1"
  local source_dir=""

  echo "--------------------------------------------------"
  echo "🔹 App: $app"

  # 1) Om --source användes (endast vettigt i en-app-läge)
  if [[ -n "$SOURCE_OVERRIDE" ]]; then
    local override="$SOURCE_OVERRIDE"
    override="${override/#\~/$HOME}"

    if [[ ! -d "$override" ]]; then
      echo "  ❌ Källkatalog finns inte (override): $override"
      return 1
    fi

    source_dir="$override"
  else
    # 2) Normal resolution via app_paths.txt + fallback
    if ! source_dir="$(resolve_source_for_app "$app" "$PATH_FILE")"; then
      echo "  ❌ Hittar ingen källkatalog för app: $app"
      echo "     (varken i $PATH_FILE eller i standardställen)"
      return 1
    fi
  fi

  echo "  Källa:          $source_dir"
  echo "  Backup-katalog: $BACKUP_ROOT"

  mkdir -p "$BACKUP_ROOT"

  local dest_file="$BACKUP_ROOT/${app}.${RUN_TS}.tar.gz"
  echo "  Målfil:         $dest_file"

  if [[ "$DRYRUN" == true ]]; then
    echo "  🟡 DRY-RUN: skulle köra:"
    echo "      tar -czf \"$dest_file\" -C \"$source_dir\" ."
    return 0
  fi

  echo "  📦 Skapar arkiv..."
  if tar -czf "$dest_file" -C "$source_dir" .; then
    echo "  ✅ Klar. Skapad fil:"
    echo "     $dest_file"
    return 0
  else
    echo "  ❌ tar misslyckades för app: $app"
    return 1
  fi
}

# ------------------------------------------------------------
# Argumentparsning
# ------------------------------------------------------------

# Första icke-flaggan (utan "--" i början) tolkas som APP_NAME
if [[ $# -gt 0 && "${1#--}" == "$1" ]]; then
  APP_NAME="$1"
  shift
fi

# Resten är flaggor
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

# Bestäm om vi kör en app eller alla
if [[ -z "$APP_NAME" ]]; then
  ALL_APPS=true
fi

# ------------------------------------------------------------
# Körläge: ALLA appar
# ------------------------------------------------------------
if [[ "$ALL_APPS" == true ]]; then
  echo "=== Körläge: ALLA appar i $PATH_FILE ==="

  if [[ ! -f "$PATH_FILE" ]]; then
    echo "❌ Hittar inte paths-fil: $PATH_FILE" >&2
    exit 1
  fi

  mapfile -t APPS < <(get_all_apps_from_pathsfile "$PATH_FILE" || true)

  if ((${#APPS[@]} == 0)); then
    echo "❌ Inga app-namn hittades i: $PATH_FILE" >&2
    exit 1
  fi

  echo "Appar att backup:a:"
  printf '  - %s\n' "${APPS[@]}"
  echo

  overall_status=0

  for app in "${APPS[@]}"; do
    if ! backup_one_app "$app"; then
      overall_status=1
    fi
  done

  exit "$overall_status"
fi

# ------------------------------------------------------------
# Körläge: EN app
# ------------------------------------------------------------
# Om du anger --source men inget app-namn → det är ologiskt, varna:
if [[ -n "$SOURCE_OVERRIDE" && "$ALL_APPS" == true ]]; then
  echo "⚠️  --source används men inget app-namn angavs; --source ignoreras i ALL_APPS-läge." >&2
fi

echo "=== Körläge: EN app ==="
backup_one_app "$APP_NAME"

