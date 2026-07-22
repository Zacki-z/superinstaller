#!/usr/bin/env bash
# ============================================
# backup_appconfig-3.11.sh
# ============================================
# Backup av applikationskonfigurationer baserat på en gemensam paths-fil.
#
#  - Utan app-argument: backa upp ALLA appar som finns i paths-filen.
#  - Med app-argument: backa upp bara den appen.
#
#  - Paths-fil (standard): $HOME/.config/backup_appconfig/app_paths.txt
#    Format (en rad per sökväg):
#       appnamn   /sök/väg/till/config
#
#  - För varje app:
#       - välj första katalog som existerar
#       - skapa arkiv:  <app>.<YYYYMMDD-HHMMSS>.tar.gz
#         under:        $HOME/bup_appl_config (standard)
#
#  - Ingen rotation, en fil per körning per app.
#
# ============================================

set -euo pipefail

DEFAULT_BACKUP_ROOT="${HOME}/bup_appl_config"
# Ändra denna rad om du vill använda /home/alain/my_bin/etc/app_paths.txt som default:
DEFAULT_PATH_FILE="${HOME}/.config/backup_appconfig/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"
DRYRUN=false
VERBOSE=false

# -------------------------
# Hjälpfunktioner
# -------------------------
msg() {
  printf '%s\n' "$*" >&2
}

die() {
  msg "❌ $*"
  exit 1
}

usage() {
  cat <<EOF
Användning: $(basename "\$0") [app-namn] [flaggor]

  Utan app-namn:
    Backar upp ALLA appar som finns i paths-filen:
      \$PATH_FILE  (eller BUP_APPCONFIG_PATH_FILE)

  Med app-namn:
    Backar upp endast den appen.

Flaggor:
  --backup-root=PATH   Var backup-filerna ska hamna (default: $DEFAULT_BACKUP_ROOT)
  --paths-file=PATH    Ange var app_paths.txt ligger
  --dry-run, -n        Visa vad som skulle göras utan att skapa arkiv
  --verbose, -v        Lite mer utskrifter
  --help, -h           Visa denna hjälptext

Format på paths-fil (app_paths.txt):
  # appnamn   path
  darktable   ~/.config/darktable
  darktable   ~/.var/app/org.darktable.Darktable/config/darktable
  darktable   ~/snap/darktable/current/.config/darktable

  kicad       ~/.config/kicad
  kicad       ~/.local/share/kicad

Exempel:
  $(basename "\$0")                  # backa upp alla appar i app_paths.txt
  $(basename "\$0") darktable        # backa upp bara darktable
  $(basename "\$0") kicad --dry-run
EOF
}

# -------------------------
# Läs in paths-fil / kandidater
# -------------------------

get_candidates_for_app() {
  local app="\$1"
  local pathfile="\$2"
  local -a candidates=()
  [[ -f "\$pathfile" ]] || return 1

  while read -r col1 col2; do
    # hoppa över tomma rader
    [[ -z "\${col1:-}" ]] && continue
    # hoppa över kommentarer
    [[ "\$col1" == \#* ]] && continue

    # bara rader för aktuell app
    [[ "\$col1" != "\$app" ]] && continue
    [[ -z "\${col2:-}" ]] && continue

    local expanded="\$col2"
    # expandera ~ till \$HOME
    expanded="\${expanded/#\~/\$HOME}"
    candidates+=("\$expanded")
  done < "\$pathfile"

  if (("\${#candidates[@]}" == 0)); then
    return 1
  fi

  printf '%s\0' "\${candidates[@]}"
}

get_all_apps() {
  local pathfile="\$1"
  local -A seen=()
  local -a apps=()

  [[ -f "\$pathfile" ]] || return 1

  while read -r col1 col2; do
    [[ -z "\${col1:-}" ]] && continue
    [[ "\$col1" == \#* ]] && continue
    [[ -z "\${col2:-}" ]] && continue

    if [[ -z "\${seen[\$col1]+x}" ]]; then
      seen["\$col1"]=1
      apps+=("\$col1")
    fi
  done < "\$pathfile"

  (("\${#apps[@]}" > 0)) || return 1

  printf '%s\0' "\${apps[@]}"
}

# -------------------------
# Utför backup för EN app
# -------------------------
backup_one_app() {
  local app="\$1"
  local run_ts="\$2"

  # hämta kandidater
  local -a cands=()
  if ! mapfile -d '' -t cands < <(get_candidates_for_app "\$app" "\$PATH_FILE"); then
    msg "⚠️  Hittar inga path-rader för app '\$app' i \$PATH_FILE – hoppar över."
    return 0
  fi

  local src=""
  local c
  for c in "\${cands[@]}"; do
    if [[ -d "\$c" ]]; then
      src="\$c"
      break
    fi
  done

  if [[ -z "\$src" ]]; then
    msg "⚠️  Ingen existerande katalog hittades för app '\$app' i kandidatlistan – hoppar över."
    return 0
  fi

  local dest_file="\${BACKUP_ROOT}/\${app}.\${run_ts}.tar.gz"

  msg "----------------------------------------"
  msg "App:            \$app"
  msg "Källa:          \$src"
  msg "Målfil:         \$dest_file"
  msg "Dry-run:        \$DRYRUN"
  msg "----------------------------------------"

  if [[ "\$DRYRUN" == true ]]; then
    msg "🟡 (dry-run) skulle köra:"
    msg "    mkdir -p \"\$BACKUP_ROOT\""
    msg "    tar -czf \"\$dest_file\" -C \"\$src\" ."
  else
    mkdir -p "\$BACKUP_ROOT"
    tar -czf "\$dest_file" -C "\$src" .
    msg "✅ Klar för app '\$app'. Skapad fil: \$dest_file"
  fi
}

# -------------------------
# Argumentparsning
# -------------------------
APP_NAME=""

if [[ \$# -gt 0 ]]; then
  case "\$1" in
    --backup-root=*|--paths-file=*|--dry-run|-n|--verbose|-v|--help|-h)
      # första argumentet är en flagga, ingen app
      :
      ;;
    *)
      APP_NAME="\$1"
      shift
      ;;
  esac
fi

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --backup-root=*)
      BACKUP_ROOT="\${1#*=}"
      shift
      ;;
    --paths-file=*)
      PATH_FILE="\${1#*=}"
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
      die "Okänt argument: \$1"
      ;;
  esac
done

# -------------------------
# Grundkoll
# -------------------------
if [[ ! -f "\$PATH_FILE" ]]; then
  die "Paths-fil saknas: \$PATH_FILE"
fi

RUN_TS="\$(date +%Y%m%d-%H%M%S)"

msg "BACKUP_ROOT: \$BACKUP_ROOT"
msg "PATH_FILE:   \$PATH_FILE"
msg "RUN_TS:      \$RUN_TS"
msg "APP_NAME:    \${APP_NAME:-<alla>}"
msg "DRYRUN:      \$DRYRUN"
msg

# -------------------------
# Kör backup
# -------------------------
if [[ -n "\$APP_NAME" ]]; then
  backup_one_app "\$APP_NAME" "\$RUN_TS"
else
  local_apps=()
  if ! mapfile -d '' -t local_apps < <(get_all_apps "\$PATH_FILE"); then
    die "Inga appar hittades i paths-filen: \$PATH_FILE"
  fi

  for app in "\${local_apps[@]}"; do
    backup_one_app "\$app" "\$RUN_TS"
  done
fi

msg
msg "🎉 Backup-körning klar."

