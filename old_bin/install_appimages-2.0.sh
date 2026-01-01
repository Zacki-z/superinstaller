#!/bin/bash
set -euo pipefail

echo "🚀 Installerar AppImages ..."

# Mapp där AppImages lagras
TARGET="${HOME}/appimages_applications"
BIN="${HOME}/.local/bin"

# Se till att mapparna finns
mkdir -p "$TARGET" 
cd "$TARGET"

appimg() {
  # Lista över AppImages du vill ladda ner
  declare -A urls=(
    ["darktable"]="https://github.com/darktable-org/darktable/releases/download/release-5.2.0/darktable-5.2.0-x86_64.AppImage"
    ["krita"]="https://github.com/KDE/krita/releases/download/v5.2.0/krita-5.2.0-x86_64.appimage"
    ["obs"]="https://github.com/obsproject/obs-studio/releases/download/30.0.0/OBS-Studio-30.0.0-x86_64.AppImage"
    ["rawtherapee"]="https://rawtherapee.com/downloads/5.12/RawTherapee_5.12_release.AppImage"
    ["arduino-ide"]="https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage"
    ["musescore"]="https://cdn.jsdelivr.net/musescore/v4.4.2/MuseScore-4.4.2.251821617-x86_64.AppImage"
  )

  for name in "${!urls[@]}"; do
    url="${urls[$name]}"
    file=$(basename "$url")

    echo "🔽 Laddar ner $file ..."
    wget -q --show-progress -O "$file" "$url" || {
      echo "❌ Misslyckades att ladda ner $url"
      continue
    }

    chmod +x "$file"
    echo "✅ Klart: $file"

    # Skapa symlänk i ~/bin
    ln -sf "${TARGET}/${file}" "${BIN}/${name}"
    echo "🔗 Länk skapad: ${BIN}/${name} → ${file}"
  done
}

appimg

echo
echo "🎉 Klart!"
echo "Alla AppImages installerade i: $TARGET"
echo "Symlänkar skapade i: $BIN"
echo
echo "Kontrollera att ~/bin finns i din PATH med:"
echo "  echo \$PATH | grep ~/bin"
echo
echo "Exempel: starta Darktable genom att bara skriva:"
echo "  darktable"

