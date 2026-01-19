#!/usr/bin/env bash
# ============================================
# restore_appconfig-3.0.sh
# ============================================
# Återställ applikationskonfiguration från arkiv skapade av:
#   backup_appconfig-2.0.sh (eller kompatibla skript).
#
# Förväntat backup-format:
#   BACKUP_ROOT/appname.YYYYMMDD-HHMMSS.tar.gz
#
# Grundidé:
#   1. Du anger ett app-namn (t.ex. darktable, kicad, ha, densiometer)
#   2. Scriptet hittar arkivet:
#        - via --file=...  (direkt)
#        - annars: senaste appname.*.tar.gz i BACKUP_ROOT
#   3. Scriptet bestämmer mål-katalog:
#        - via --target=PATH
#        - annars via app_paths.txt
#        - annars fallback: ~/.config/<app>, ~/.local/share/<app>
#   4. Om det redan finns config där:
#        - den flyttas till  <target>.pre-restore.<timestamp>
#
# ============================================

set -euo pipefail

DEFAULT_BACKUP_ROOT="$HOME/bup_appl_config"
DEFAULT_PATH_FILE="$HOME/my_bin/etc/app_paths.txt"

BACKUP_ROOT="$DEFAULT_BACKUP_ROOT"
PATH_FILE="${BUP_APPCONFIG_PATH_FILE:-$DEFAULT_PATH_FILE}"

APP_NAME=""
ARCHIVE_FILE=""
TARGET_DIR=""
DRYRUN=false
FORCE=false

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
  --file=FIL
      Ange vilket arkiv som ska återställas.
      Kan vara:
        - absolut/relativ sökväg: /path/till/app.20251122-120000.tar.gz
        - bara filnamn: app.20251122-120000.tar.gz
          (tolkas då relativt BACKUP_ROOT)

  --target=PATH
      Var konfigurationen ska återställas (mål-katalog).
      Om den inte finns skapas den.

  --backup-root=PATH
      Var arkiven ligger (default: $DEFAULT_BACKUP_ROOT)

  --paths-file=PATH
      Var app_paths.txt ligger.
      Default: $DEFAULT_PATH_FILE
      Kan också sättas via env:
        export BUP_APPCONFIG_PATH_FILE=/någon/annanstans/app_paths.txt

  --dry-run, -n
      Visa vad som skulle göras, utan att ändra något.

  --force, -f
      Fråga inte om bekräftelse före återställning.

  --help, -h
      Visa denna hjälp.

Exempel:
  $(basename "\$0") darktable
  $(basename "\$0") darktable --file=darktable.20251122-120000.tar.gz
  $(basename "\$0") kicad --target="\$HOME/.config/kicad"
  $(basename "\$0") rawtherapee --paths-file="\$HOME/my_paths/app_paths.txt"

Format på app_paths.txt:
  # appname   path
  darktable   ~/.config/darktable
  darktable   ~/.var/app/org.darktable.Darktable/config/darktable
  darktable   ~/snap/darktable/current/.config/darktable

  kicad       ~/.config/kicad
  kicad       ~/.local/share/kicad
EOF
}

# --------------------------------------------
# Hitta mål-katalog via app_paths.txt
# --------------------------------------------
find_target_from_pathsfile() {
  local app="\$1"
  local pathfile="\$2"
  local -a candidates=()

  [[ ! -f "\$pathfile" ]] && return 1

  while read -r col1 col2; do
    [[ -z "\${col1:-}" ]] && continue
    [[ "\$col1" == \#* ]] && continue
    [[ "\$col1" != "\$app" ]] && continue
    [[ -z "\${col2:-}" ]] && continue

    local expanded="\$col2"
    expanded="\${expanded/#\~/\$HOME}"
    candidates+=("\$expanded")
  done < "\$pathfile"

  if ((${#candidates[@]} == 0)); then
    return 1
  fi

  # välj första existerande katalog,
  # om ingen existerar: välj första som "preferred target"
  local d
  for d in "\${candidates[@]}"; do
    if [[ -d "\$d" ]]; then
      TARGET_DIR="\$d"
      return 0
    fi
  done

  TARGET_DIR="\${candidates[0]}"
  return 0
}

# --------------------------------------------
# Fallback-mål om paths-fil inte ger något
# --------------------------------------------
fallback_target_guess() {
  local app="\$1"
  local -a candidates=(
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

  TARGET_DIR="\${candidates[0]}"
  return 0
}

# --------------------------------------------
# Hitta arkivfil för app
# --------------------------------------------
find_archive_for_app() {
  local app="\$1"
  local root="\$2"

  shopt -s nullglob
  local files=( "\$root/\${app}."*.tar.gz )
  shopt -u nullglob

  if ((${#files[@]} == 0)); then
    return 1
  fi

  # Tidsstämpel i namnet gör att lexicografisk sortering räcker
  local latest
  latest=\$(printf '%s\n' "\${files[@]}" | sort | tail -n1)
  ARCHIVE_FILE="\$latest"
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
    --dry-run|-n)
      DRYRUN=true
      shift
      ;;
    --force|-f)
      FORCE=true
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
# Normalisera ARCHIVE_FILE om bara filnamn
# --------------------------------------------
if [[ -n "\$ARCHIVE_FILE" ]]; then
  if [[ "\$ARCHIVE_FILE" != /* ]]; then
    ARCHIVE_FILE="\$BACKUP_ROOT/\$ARCHIVE_FILE"
  fi
  if [[ ! -f "\$ARCHIVE_FILE" ]]; then
    echo "❌ Angiven arkivfil finns inte: \$ARCHIVE_FILE" >&2
    exit 1
  fi
else
  # Försök hitta senaste arkivet för appen
  if ! find_archive_for_app "\$APP_NAME" "\$BACKUP_ROOT"; then
    echo "❌ Hittar inget arkiv för app \"\$APP_NAME\" under: \$BACKUP_ROOT" >&2
    exit 1
  fi
fi

# --------------------------------------------
# Bestäm mål-katalog
# --------------------------------------------
if [[ -z "\$TARGET_DIR" ]]; then
  if ! find_target_from_pathsfile "\$APP_NAME" "\$PATH_FILE"; then
    if ! fallback_target_guess "\$APP_NAME"; then
      echo "❌ Kunde inte avgöra mål-katalog för \"\$APP_NAME\"." >&2
      exit 1
    fi
  fi
fi

# Expandera ~ i TARGET_DIR om användaren gav det direkt
TARGET_DIR="\${TARGET_DIR/#\~/\$HOME}"

SAFE_DIR=""
if [[ -d "\$TARGET_DIR" && -n "\$(ls -A "\$TARGET_DIR" 2>/dev/null || true)" ]]; then
  SAFE_DIR="\${TARGET_DIR%/}.pre-restore.\$RUN_TS"
fi

echo "========================================"
echo "Återställ applikationskonfiguration"
echo "----------------------------------------"
echo "App-namn:       \$APP_NAME"
echo "Arkivfil:       \$ARCHIVE_FILE"
echo "Mål-katalog:    \$TARGET_DIR"
echo "Paths-fil:      \$PATH_FILE"
echo "Backup-root:    \$BACKUP_ROOT"
echo "Dry-run:        \$DRYRUN"
if [[ -n "\$SAFE_DIR" ]]; then
  echo "Tidigare config kommer att flyttas till:"
  echo "  \$SAFE_DIR"
fi
echo "========================================"

if [[ "\$DRYRUN" == true ]]; then
  echo "🟡 DRY-RUN: Ingen faktisk återställning görs."
else
  if [[ "\$FORCE" == false ]]; then
    read -rp "⚠️  Är du säker på att du vill återställa? (ja/nej) " ans
    case "\$ans" in
      j|ja|J|JA|y|yes|Y|YES)
        ;;
      *)
        echo "Avbrutet."
        exit 0
        ;;
    esac
  fi
fi

# --------------------------------------------
# Utför återställning
# --------------------------------------------
if [[ "\$DRYRUN" == true ]]; then
  if [[ -n "\$SAFE_DIR" ]]; then
    echo "(dry-run) skulle flytta: \$TARGET_DIR → \$SAFE_DIR"
  fi
  echo "(dry-run) skulle skapa katalog: \$TARGET_DIR (om den inte finns)"
  echo "(dry-run) skulle extrahera:"
  echo "  tar -xzf \"\$ARCHIVE_FILE\" -C \"\$TARGET_DIR\""
  exit 0
fi

# Flytta gammal config om det fanns något
if [[ -n "\$SAFE_DIR" ]]; then
  echo "📦 Flyttar befintlig config till: \$SAFE_DIR"
  mkdir -p "\$(dirname "\$SAFE_DIR")"
  mv "\$TARGET_DIR" "\$SAFE_DIR"
fi

echo "📁 Skapar mål-katalog (om den inte finns): \$TARGET_DIR"
mkdir -p "\$TARGET_DIR"

echo "📂 Extraherar arkiv..."
tar -xzf "\$ARCHIVE_FILE" -C "\$TARGET_DIR"

echo
echo "✅ Återställning klar."
echo "   Arkiv:          \$ARCHIVE_FILE"
echo "   Mål:            \$TARGET_DIR"
if [[ -n "\$SAFE_DIR" ]]; then
  echo "   Tidigare config: \$SAFE_DIR"
fi

