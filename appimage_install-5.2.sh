#!/bin/bash
# Ingen set -e → skriptet dör inte på enstaka fel
set -u

###############################################################################
# appimage-install v5.2 — laddar ner AppImages och skapar symlänkar
#  (skapande av .desktop-filer ligger nu i separat script)
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
echo -e "🚀 AppImage-install startar (v5.2)"
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
DESKTOP_DIR="$HOME/.local/share/applications"   # används inte längre här, men lämnas kvar för info

mkdir -p "$TARGET" "$BIN" "$DESKTOP_DIR"
cd "$TARGET"

# ===============================
# Statistik
# ===============================
SUCCESS=0
FAILED=0
SKIPPED=0

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
        echo "   🔗 Länk: ${BIN}/${key} → ${TARGET}/${file}"

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

