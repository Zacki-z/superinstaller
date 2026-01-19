#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# backup_appconfig-3.0.sh
# ==========================================================
# Funktioner:
#  - backup av EN app, t.ex:  ./script.sh darktable
#  - backup av ALLA appar i .txt: ./script.sh
#
# Format på .txt-filen:
#   # appname   path
#   darktable   ~/.config/darktable
#   darktable   ~/snap/darktable/current/.config/darktable
#   kicad       ~/.config/kicad
#   rawtherapee ~/.config/RawTherapee
#
# ==========================================================

DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
DEFAULT_PATH_FILE="$HOME/my_bin/etc/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="$DEFAULT_PATH_FILE"

APP_NAME="${1:-}"           # tom → kör ALLA
ALL_APPS=false
SOURCE_OVERRIDE=""
DRYRUN=false
RUN_TS="$(date +%Y%m%d-%H%M%S)"

# ------------------------------
# Hjälpfunktion
# ------------------------------
usage() {
cat <<EOF
Användning:
  backup_appconfig-3.0.sh <app>
  backup_appconfig-3.0.sh           # kör ALLA appar i app_paths.txt

Flaggor:
  --dry-run
  --source=PATH
  --paths-file=PATH
  --backup-root=PATH

EOF
}

# ------------------------------
# Läs argument
# ------------------------------
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRYRUN=true
            ;;
        --source=*)
            SOURCE_OVERRIDE="${1#*=}"
            ;;
        --paths-file=*)
            PATH_FILE="${1#*=}"
            ;;
        --backup-root=*)
            BACKUP_ROOT="${1#*=}"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Okänt argument: $1"
            exit 1
            ;;
    esac
    shift
done

# Om inget app-namn → alla
if [[ -z "$APP_NAME" ]]; then
    ALL_APPS=true
fi

# ------------------------------
# Funktion: expandera ~
# ------------------------------
expand_path() {
    local p="$1"
    echo "${p/#\~/$HOME}"
}

# ------------------------------
# Funktion: hitta sökvägar för en app
# ------------------------------
find_paths_for_app() {
    local app="$1"
    local -n out="$2"
    out=()

    if [[ ! -f "$PATH_FILE" ]]; then
        echo "❌ Paths-fil saknas: $PATH_FILE"
        exit 1
    fi

    while read -r col1 col2; do
        [[ -z "${col1:-}" ]] && continue
        [[ "$col1" == \#* ]] && continue
        [[ "$col1" != "$app" ]] && continue
        local expanded
        expanded=$(expand_path "$col2")
        out+=("$expanded")
    done < "$PATH_FILE"

    return 0
}

# ------------------------------
# Funktion: backup EN app
# ------------------------------
backup_app() {
    local app="$1"
    declare -a CANDIDATES=()

    echo "-------------------------------------------"
    echo "🔍 App: $app"

    # 1) Källkatalog via --source
    if [[ -n "$SOURCE_OVERRIDE" ]]; then
        SOURCE_DIR="$SOURCE_OVERRIDE"
        echo "➡ Använder override: $SOURCE_DIR"
    else
        # 2) Läs från txt-fil
        find_paths_for_app "$app" CANDIDATES

        if ((${#CANDIDATES[@]} == 0)); then
            echo "⚠ Inga sökvägar hittades i $PATH_FILE"
            return 0
        fi

        # välj första som existerar
        SOURCE_DIR=""
        for c in "${CANDIDATES[@]}"; do
            if [[ -d "$c" ]]; then
                SOURCE_DIR="$c"
                break
            fi
        done

        if [[ -z "$SOURCE_DIR" ]]; then
            echo "❌ Hittade inga existerande sökvägar för $app:"

