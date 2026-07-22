#!/usr/bin/env bash
# ============================================
# restore_appconfig-3.1.sh
# ============================================
# Återställ applikationskonfiguration från backup-arkiv skapade av
# backup_appconfig-2.x/3.x:
#
#  - Backup-filerna antas ligga i:
#        $HOME/bup_appl_config
#    och vara namngivna:
#        <app>.<YYYYMMDD-HHMMSS>.tar.gz
#
#  - Scriptet:
#      * hittar rätt arkiv (via --file eller automatiskt)
#      * hittar rätt mål-katalog (samma logik som backup-skriptet)
#      * backup:ar ev. befintlig config innan återställning
#
# --------------------------------------------
# KONFIGURATION (kan ändras / överstyras)
# --------------------------------------------
DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
DEFAULT_PATH_FILE="$HOME/.config/backup_appconfig/app_paths.txt"

set -euo pipefail

APP_NAME=""
BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"
ARCHIVE_FILE=""
TARGET_DIR_OVERRIDE=""
DRYRUN=false

# Tidsstämpel för denna körning
RUN_TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<EOF
Användning: $(basename "\$0") <app-namn> [flaggor]

  <app-namn>
      Namn på applikationen, t.ex.:
        darktable
        kicad
        rawtherapee
        densiometer

Flaggor:
  --file=PATH
      Vilket backup-arkiv (.tar.gz) som ska återställas.
      Om inte angivet väljs automatiskt:
        - senaste matchande filen: <app>.*.tar.gz
        - om whiptail finns och det finns flera → meny.

  --target=PATH
      Målkatalog att återställa till.
      Om inte angivet används samma logik som backup-skriptet:
        1) paths-fil (app_paths.txt)
        2) fallback: ~/.config/<app>, ~/.local/share/<app>, samt darktable-specifika paths.

  --backup-root=PATH
      Var backup-filerna ligger (default: $DEFAULT_BACKUP_ROOT)

  --paths-file=PATH
      Var app_paths.txt ligger (default: $DEFAULT_PATH_FILE)
      Kan också styras via env:
        export BUP_APPCONFIG_PATH_FILE=/någon/annanstans/app_paths.txt

  --dry-run, -n
      Visa vad som skulle göras utan att ändra något.

  --help, -h
      Visa denna hjälp.

Exempel:
  $(basename "\$0") darktable
  $(basename "\$0") darktable --dry-run
  $(basename "\$0") darktable --file="\$HOME/bup_appl_config/darktable.20251122-213500.tar.gz"
  $(basename "\$0") kicad --target="\$HOME/.config/kicad"
EOF
}

die() {
  echo "❌ \$*" >&2
  exit 1
}

# --------------------------------------------
# Hitta kandidat-målkatalog för app via paths-fil
# (samma format som backup_appconfig)
# --------------------------------------------
find_target_from_pathsfile() {
  local app="\$1"
  local pathfile="\$2"
  local -a candidates=()

  [[ ! -f "\$pathfile" ]] && return 1

  while read -r col1 col2; do
    # hoppa över tomma rader
    [[ -z "\${col1:-}" ]] && continue
    # hoppa över kommentarer
    [[ "\$col1" == \#* ]] && continue

    # bara rader för aktuell app
    [[ "\$col1" != "\$app" ]] && continue
    [[ -z "\${col2:-}" ]] && continue

    # expandera ~ till \$HOME
    local expanded="\$col2"
    expanded="\${expanded/#\~/\$HOME}"

    candidates+=("\$expanded")
  done < "\$pathfile"

  if (("\${#candidates[@]}" == 0)); then
    return 1
  fi

  # välj första som katalog (eller första, och skapa den om den saknas)
  local d
  for d in "\${candidates[@]}"; do
    # om den finns, använd den direkt
    if [[ -d "\$d" ]]; then
      TARGET_DIR_OVERRIDE="\$d"
      return 0
    fi
  done

  # inget av de listade finns ännu, ta första som förslag
  TARGET_DIR_OVERRIDE="\${candidates[0]}"
  return 0
}

# --------------------------------------------
# Fallback-mål om pathsfilen inte ger träff
# --------------------------------------------
fallback_target_guess() {
  local app="\$1"
  local -a candidates=()

  if [[ "\$app" == "darktable" ]]; then
    candidates=(
      "\$HOME/.config/darktable"
      "\$HOME/.var/app/org.darktable.Darktable/config/darktable"
      "\$HOME/snap/darktable/current/.config/darktable"
    )
  else
    candidates=(
      "\$HOME/.config/\$app"
      "\$HOME/.local/share/\$app"
    )
  fi

  local d
  for d in "\${candidates[@]}"; do
    if [[ -d "\$d" ]]; then
      TARGET_DIR_OVERRIDE="\$d"
      return 0
    fi
  done

  # om inga finns alls, använd första som förslag
  if (("\${#candidates[@]}" > 0)); then
    TARGET_DIR_OVERRIDE="\${candidates[0]}"
    return 0
  fi

  return 1
}

# --------------------------------------------
# Välj arkivfil för appen
# --------------------------------------------
choose_archive_for_app() {
  local app="\$1"
  local root="\$2"

  # Om användaren redan angivit ARCHIVE_FILE, kontrollera den
  if [[ -n "\$ARCHIVE_FILE" ]]; then
    [[ -f "\$ARCHIVE_FILE" ]] || die "Angiven arkivfil finns inte: \$ARCHIVE_FILE"
    echo "\$ARCHIVE_FILE"
    return 0
  fi

  # Leta upp alla matchande arkiv
  local pattern="\$root/\${app}."*.tar*
  shopt -s nullglob
  local files=( \$pattern )
  shopt -u nullglob

  (("\${#files[@]}" > 0)) || die "Hittar inga backup-arkiv för app \"\$app\" i \$root"

  # Om det bara finns en, ta den
  if (("\${#files[@]}" == 1)); then
    echo "\${files[0]}"
    return 0
  fi

  # Om whiptail finns, visa meny
  if command -v whiptail >/dev/null 2>&1; then
    local menu_items=()
    local f
    for f in "\${files[@]}"; do
      local base
      base="\$(basename "\$f")"
      menu_items+=( "\$f" "\$base" )
    done

    local choice
    choice=\$(whiptail --title "Välj backup-arkiv för \$app" \
                      --menu "Välj vilket arkiv som ska återställas:" \
                      20 90 10 \
                      "\${menu_items[@]}" \
                      3>&1 1>&2 2>&3) || die "Avbruten av användaren."

    echo "\$choice"
    return 0
  fi

  # Annars: ta senaste (sorterat)
  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "\${files[@]}" | sort && printf '\0')
  echo "\${sorted[-1]}"
  return 0
}

# --------------------------------------------
# Argumentparsning
# --------------------------------------------
if [[ \$# -lt 1 ]]; then
  usage
  exit 1
fi

APP_NAME="\$1"
shift

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --file=*)
      ARCHIVE_FILE="\${1#*=}"
      shift
      ;;
    --target=*)
      TARGET_DIR_OVERRIDE="\${1#*=}"
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
# Validera backup-root
# --------------------------------------------
[[ -d "\$BACKUP_ROOT" ]] || die "Backup-root finns inte: \$BACKUP_ROOT"

# --------------------------------------------
# Bestäm mål-katalog
# --------------------------------------------
if [[ -z "\$TARGET_DIR_OVERRIDE" ]]; then
  if ! find_target_from_pathsfile "\$APP_NAME" "\$PATH_FILE"; then
    if ! fallback_target_guess "\$APP_NAME"; then
      die "Hittar inget förslag på mål-katalog för app \"\$APP_NAME\"."
    fi
  fi
fi

TARGET_DIR="\$TARGET_DIR_OVERRIDE"

[[ -n "\$TARGET_DIR" ]] || die "Ingen mål-katalog bestämd."

# --------------------------------------------
# Välj arkivfil
# --------------------------------------------
ARCHIVE_FILE="\$(choose_archive_for_app "\$APP_NAME" "\$BACKUP_ROOT")"

[[ -f "\$ARCHIVE_FILE" ]] || die "Arkivfilen finns inte: \$ARCHIVE_FILE"

# --------------------------------------------
# Summering
# --------------------------------------------
echo "========================================"
echo "Återställning av applikationskonfiguration"
echo "----------------------------------------"
echo "App-namn:       \$APP_NAME"
echo "Arkiv:          \$ARCHIVE_FILE"
echo "Målkatalog:     \$TARGET_DIR"
echo "Backup-root:    \$BACKUP_ROOT"
echo "Paths-fil:      \$PATH_FILE"
echo "Dry-run:        \$DRYRUN"
echo "========================================"
echo

# --------------------------------------------
# Säkerhetskopiera nuvarande config (om något finns)
# --------------------------------------------
PRE_RESTORE_BASE="\$BACKUP_ROOT/.pre_restore/\$APP_NAME"
SAFE_DIR="\$PRE_RESTORE_BASE/\$RUN_TS"

if [[ -d "\$TARGET_DIR" ]] && [[ -n "\$(ls -A "\$TARGET_DIR" 2>/dev/null || true)" ]]; then
  echo "Säkerhetskopierar nuvarande config → \$SAFE_DIR"
  if ! \$DRYRUN; then
    mkdir -p "\$SAFE_DIR"
    cp -a "\$TARGET_DIR"/. "\$SAFE_DIR"/
  else
    echo "(dry-run) skulle skapa katalog: \$SAFE_DIR"
    echo "(dry-run) skulle kopiera: \$TARGET_DIR/. → \$SAFE_DIR/"
  fi
else
  echo "Ingen befintlig config att säkerhetskopiera (tom eller saknas)."
fi

echo

# --------------------------------------------
# Skapa mål-katalog
# --------------------------------------------
if [[ ! -d "\$TARGET_DIR" ]]; then
  echo "Skapar mål-katalog: \$TARGET_DIR"
  if ! \$DRYRUN; then
    mkdir -p "\$TARGET_DIR"
  else
    echo "(dry-run) skulle skapa: \$TARGET_DIR"
  fi
fi

# --------------------------------------------
# Töm mål-katalogen innan återställning
# --------------------------------------------
if [[ -d "\$TARGET_DIR" ]] && [[ -n "\$(ls -A "\$TARGET_DIR" 2>/dev/null || true)" ]]; then
  echo "Tömmer mål-katalogen innan återställning: \$TARGET_DIR"
  if ! \$DRYRUN; then
    rm -rf "\$TARGET_DIR"/*
    rm -rf "\$TARGET_DIR"/.[!.]*
    rm -rf "\$TARGET_DIR"/..?*
  else
    echo "(dry-run) skulle tömma innehållet i: \$TARGET_DIR"
  fi
fi

# --------------------------------------------
# Återställ från arkivet
# --------------------------------------------
echo "Återställer från arkiv..."
if ! \$DRYRUN; then
  tar -xzf "\$ARCHIVE_FILE" -C "\$TARGET_DIR"
else
  echo "(dry-run) skulle köra: tar -xzf \"\$ARCHIVE_FILE\" -C \"\$TARGET_DIR\""
fi

echo
echo "✅ Återställning klar."
echo "   App:             \$APP_NAME"
echo "   Arkiv:           \$ARCHIVE_FILE"
echo "   Mål:             \$TARGET_DIR"
echo "   Backup av tidigare config (om skapad): \$SAFE_DIR"
echo

