#!/bin/bash
# Ingen set -e → skriptet dör inte på enstaka fel
set -u

###############################################################################
# appimage-install v5.1 — stabil, med dry-run och verbosity
###############################################################################

# ===============================
# Verbosity + Dry-run
# ===============================
VERBOSITY="normal"
DRYRUN=false

for arg in "$@"; do
    case "$arg" in
        --quiet) VERBOSITY="quiet" ;;
        --debug) VERBOSITY="debug" ;;
        --normal) VERBOSITY="normal" ;;
        --dry-run) DRYRUN=true ;;
        *)
            echo "Okänt argument: $arg"
            exit 1 ;;
    esac
done

# ===============================
# Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# ===============================
# Loggning
# ===============================
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/appimage_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BLUE}----------------------------------------------------------"
echo -e "🚀 AppImage-install startar (v5.1)"
echo -e "▶ Verbosity: $VERBOSITY"
echo -e "▶ Dry-run:   $DRYRUN"
echo -e "📄 Loggfil:  $LOGFILE"
echo -e "----------------------------------------------------------${NC}"
echo

# ===============================
# Sökvägar
# ===============================
TARGET="$HOME/appimages_applications"
BIN="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$TARGET" "$BIN" "$DESKTOP_DIR"
cd "$TARGET"

# ===============================
# Statistik
# ===============================
SUCCESS=0
FAILED=0
SKIPPED=0

# ===============================
# Funktion: Skapa .desktop
# ===============================
make_desktop_entry() {
  local key="$1"
  local file="$2"
  local exec_path="$BIN/$key"
  local desktop_file="${DESKTOP_DIR}/${key}.desktop"

  declare -A names=(
    ["darktable"]="Darktable"
    ["rawtherapee"]="RawTherapee"
    ["arduino-ide"]="Arduino IDE"
    ["musescore"]="MuseScore Studio"
    ["gimp"]="GIMP"
  )

  local display_name="${names[$key]:-$key}"

  local category="Utility"
  case "$key" in
    darktable|rawtherapee|krita) category="Graphics" ;;
    obs|musescore) category="AudioVideo" ;;
    arduino-ide) category="Development" ;;
  esac

  if [[ "$DRYRUN" == true ]]; then
      echo "   🧪 (dry-run) Skulle skapa .desktop: $desktop_file"
      return
  fi

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=${display_name}
Exec=${exec_path}
Icon=${file}
Terminal=false
Categories=${category};
Comment=AppImage (${display_name})
EOF

  chmod +x "$desktop_file"
  echo "📝 .desktop skapad: $desktop_file"
}

# ===============================
# URL-lista
# ===============================
declare -A urls=(
  ["darktable"]="https://github.com/darktable-org/darktable/releases/download/release-5.2.0/darktable-5.2.0-x86_64.AppImage"
  ["rawtherapee"]="https://rawtherapee.com/shared/builds/linux/RawTherapee_5.12_release.AppImage"
  ["arduino-ide"]="https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage"
  ["musescore"]="https://github.com/musescore/MuseScore/releases/download/v4.6.3/MuseScore-Studio-4.6.3.252940956-x86_64.AppImage"
  ["gimp"]="https://download.gimp.org/gimp/v3.0/linux/GIMP-3.0.6-x86_64.AppImage"
)

# ===============================
# Installationsloopen
# ===============================
for key in "${!urls[@]}"; do
    url="${urls[$key]}"
    file=$(basename "$url")

    echo -e "${BLUE}🔽 $key${NC}"
    echo "   URL: $url"

    if [[ "$DRYRUN" == true ]]; then
        echo "   🧪 (dry-run) Skulle köra: wget -O $file $url"
        ((SKIPPED++))
        continue
    fi

    if wget -q --show-progress -O "$file" "$url"; then
        chmod +x "$file"
        echo "   ✔ Hämtad: $file"

        ln -sf "${TARGET}/${file}" "${BIN}/${key}"
        echo "   🔗 Länk: ${BIN}/${key}"

        make_desktop_entry "$key" "${TARGET}/${file}"

        ((SUCCESS++))
    else
        echo "   ❌ Misslyckades: $url"
        ((FAILED++))
    fi
done

# ===============================
# Summering
# ===============================
echo -e "\n${BLUE}----------------------------------------------------------"
echo -e "🎉 AppImage-install klar! Sammanfattning"
echo -e "----------------------------------------------------------${NC}"

echo -e "✔ Lyckade:        ${GREEN}$SUCCESS${NC}"
echo -e "⏭ Skippade (dry): ${YELLOW}$SKIPPED${NC}"
echo -e "❌ Misslyckade:    ${RED}$FAILED${NC}"
echo
echo -e "📄 Logg: $LOGFILE"
echo -e "${BLUE}----------------------------------------------------------${NC}"

