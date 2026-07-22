#!/usr/bin/env bash
# ============================================
# restore_appconfig-3.3.sh
# ============================================
# Återställ applikationskonfigurationer från tar.gz-backuper.
#
# - Backup-filer förväntas ligga i BACKUP_ROOT, t.ex.:
#       $HOME/bup_appl_config/<app>.YYYYMMDD-HHMMSS.tar.gz
#
# - Källinfo för var konfigurationen ska läggas kan hämtas från:
#       app_paths.txt  (samma format som för backup-skriptet)
#   eller så används fallback: ~/.config/<app> eller ~/.local/share/<app>
#
# - Felhantering:
#   * Körs scriptet utan argument -> visa hjälp och lista appar med backup.
#   * Finns ingen backup för angiven app -> tydligt fel + exit 1.
#   * Angiven --file finns inte -> tydligt fel + exit 1.
#
# ============================================

set -euo pipefail

DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
DEFAULT_PATH_FILE="$HOME/my_bin/etc/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"
APP_NAME=""
BACKUP_FILE=""
TARGET_DIR=""
DRYRUN=false
LIST_ONLY=false

usage() {
  cat <<EOF
Användning: $(basename "\$0") <app-namn> [flaggor]

Om du kör utan <app-namn> visas denna hjälp och en lista över applikationer
som det finns backup-filer för.

Argument:
  <app-namn>          Namn på applikationen (t.ex. darktable, kicad)

Flaggor:
  --file=PATH         Återställ från specifik tar.gz-fil
  --target=DIR        Målkatalog (default: bestäms via app_paths.txt eller fallback)
  --backup-root=DIR   Var backup-filerna ligger (default: $DEFAULT_BACKUP_ROOT)
  --paths-file=PATH   Var app_paths.txt ligger (default: $DEFAULT_PATH_FILE)
  --list-only         Lista hittade backup-filer för appen, gör ingen restore
  --dry-run, -n       Visa vad som skulle göras utan att skriva något
  --help, -h          Visa denna hjälp
EOF
}

list_apps_with_backups() {
  local root="\$1"
  [[ ! -d "\$root" ]] && return 0
  find "\$root" -maxdepth 1 -type f -name "*.tar.gz" -printf '%f\n' \
    | sed 's/\.[0-9]\{8\}-[0-9]\{6\}\.tar\.gz$//' \
    | sort -u
}

find_source_from_pathsfile() {
  local app="\$1"
  local pathfile="\$2"
  local appname path

  [[ ! -f "\$pathfile" ]] && return 1

  while read -r appname path; do
    # hoppa över tomma rader
    [[ -z "\${appname:-}" ]] && continue
    # hoppa över kommentarer
    [[ "\$appname" == \#* ]] && continue
    # bara rader för aktuell app
    [[ "\$appname" != "\$app" ]] && continue
    [[ -z "\${path:-}" ]] && continue

    # expandera ~ till \$HOME
    path="\${path/#\~/$HOME}"
    TARGET_DIR="\$path"
    return 0
  done < "\$pathfile"

  return 1
}

fallback_target_guess() {
  local app="\$1"
  local candidates=(
    "\$HOME/.config/\$app"
    "\$HOME/.local/share/\$app"
  )
  local d
  for d in "\${candidates[@]}"; do
    if [[ -d "\$d" ]]; then
      TARGET_DIR="\$d"
      return 0
    fi
  done
  # om ingen finns: välj första som default (skapas senare)
  TARGET_DIR="\${candidates[0]}"
  return 0
}

find_latest_backup_for_app() {
  local app="\$1"
  local root="\$2"
  local pattern
  pattern="\$root/\$app."*"*.tar.gz"

  shopt -s nullglob
  local files=( \$pattern )
  shopt -u nullglob

  if (("\${#files[@]}" == 0)); then
    return 1
  fi

  # sortera och ta sist (senaste)
  IFS=\$'\n' read -r -d '' -a files_sorted < <(printf '%s\n' "\${files[@]}" | sort && printf '\0')
  unset IFS

  BACKUP_FILE="\${files_sorted[-1]}"
  return 0
}

# --------------------------------------------
# Argumentparsning
# --------------------------------------------
if [[ \$# -eq 0 ]]; then
  usage
  echo
  echo "Tillgängliga applikationer med backup-filer i \$BACKUP_ROOT:"
  list_apps_with_backups "\$BACKUP_ROOT"
  exit 1
fi

APP_NAME="\$1"
shift

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --file=*)
      BACKUP_FILE="\${1#*=}"
      shift
      ;;
    --target=*)
      TARGET_DIR="\${1#*=}"
      shift
      ;;
    --backup-root=*)
      BACKUP_ROOT="\${1#*=}"
      shift
      ;;
    --paths-file=*)
      PATH_FILE="\${1#*=}"
      shift
      ;;
    --list-only)
      LIST_ONLY=true
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
      echo "Okänt argument: \$1" >&2
      usage
      exit 1
      ;;
  esac
done

# --------------------------------------------
# Hitta backupfil om inte specificerad
# --------------------------------------------
if [[ -z "\$BACKUP_FILE" ]]; then
  if ! find_latest_backup_for_app "\$APP_NAME" "\$BACKUP_ROOT"; then
    echo "❌ Hittar ingen backup-fil för app \"\$APP_NAME\" i \$BACKUP_ROOT." >&2
    echo "   Förväntat mönster: \$BACKUP_ROOT/\${APP_NAME}.YYYYMMDD-HHMMSS.tar.gz" >&2
    echo "   Tips: kör först backup_appconfig-skriptet för denna app." >&2
    exit 1
  fi
else
  if [[ ! -f "\$BACKUP_FILE" ]]; then
    echo "❌ Angiven backup-fil finns inte: \$BACKUP_FILE" >&2
    exit 1
  fi
fi

# --------------------------------------------
# Hitta mål om inte specificerat
# --------------------------------------------
if [[ -z "\$TARGET_DIR" ]]; then
  if ! find_source_from_pathsfile "\$APP_NAME" "\$PATH_FILE"; then
    fallback_target_guess "\$APP_NAME"
  fi
fi

echo "========================================"
echo "Restore av applikationskonfiguration"
echo "----------------------------------------"
echo "App-namn:       \$APP_NAME"
echo "Backup-fil:     \$BACKUP_FILE"
echo "Målkatalog:     \$TARGET_DIR"
echo "Backup-root:    \$BACKUP_ROOT"
echo "Paths-fil:      \$PATH_FILE"
echo "Dry-run:        \$DRYRUN"
echo "List-only:      \$LIST_ONLY"
echo "========================================"

if [[ "\$LIST_ONLY" == true ]]; then
  echo "Backup-filer för \$APP_NAME i \$BACKUP_ROOT:"
  find "\$BACKUP_ROOT" -maxdepth 1 -type f -name "\${APP_NAME}.*.tar.gz" -printf '%f\n' | sort
  exit 0
fi

if [[ "\$DRYRUN" == true ]]; then
  echo "🟡 DRY-RUN: Skulle köra:"
  echo "  mkdir -p \"\$TARGET_DIR\""
  echo "  tar -xzf \"\$BACKUP_FILE\" -C \"\$TARGET_DIR\""
  exit 0
fi

mkdir -p "\$TARGET_DIR"
tar -xzf "\$BACKUP_FILE" -C "\$TARGET_DIR"
echo "✅ Restore klar."

