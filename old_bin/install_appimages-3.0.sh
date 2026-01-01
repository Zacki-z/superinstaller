#!/bin/bash
set -euo pipefail

echo "🚀 Installerar AppImages ..."

# Mapp där AppImages lagras
TARGET="${HOME}/appimages_applications"
BIN="${HOME}/.local/bin"

# Se till att mapparna finns
mkdir -p "$TARGET" "$BIN"
cd "$TARGET"

appimg() {
  # Lista över AppImages du vill ladda ner
  declare -A urls=(
    ["darktable"]="https://github.com/darktable-org/darktable/releases/download/release-5.2.0/darktable-5.2.0-x86_64.AppImage"
    ["krita"]="https://github.com/KDE/krita/releases/download/v5.2.0/krita-5.2.0-x86_64.appimage"
    ["obs"]="https://github.com/obsproject/obs-studio/releases/download/30.0.0/OBS-Studio-30.0.0-x86_64.AppImage"

    # RawTherapee – fungerande länk
    ["rawtherapee"]="https://rawtherapee.com/shared/builds/linux/RawTherapee_5.12_release.AppImage"

    ["arduino-ide"]="https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage"

    # MuseScore – AppImage från GitHub-releasen 4.6.3
    ["musescore"]="https://github.com/musescore/MuseScore/releases/download/v4.6.3/MuseScore-Studio-4.6.3.252940956-x86_64.AppImage"
  )

  for name in "${!urls[@]}"; do
    url="${urls[$name]}"
    file=$(basename "$url")

    echo
    echo "🔽 Laddar ner: $name"
    echo "   URL: $url"

    if wget -q --show-progress -O "$file" "$url"; then
      chmod +x "$file"
      echo "✅ Klart: $file"

      # Skapa symlänk
      ln -sf "${TARGET}/${file}" "${BIN}/${name}"
      echo "🔗 Länk skapad: ${BIN}/${name} → ${file}"
    else
      echo "❌ Misslyckades att ladda ner: $url"
    fi
  done
}

appimg

echo
echo "🎉 Klart!"
echo "AppImages installerade i: $TARGET"
echo "Symlänkar skapade i: $BIN"
echo
echo "🔍 Kontrollera att ~/.local/bin finns i din PATH:"
echo '  echo "$PATH" | tr ":" "\n" | grep -E "^'"$BIN"'$" || echo "⚠️ ~/.local/bin saknas i PATH"'
echo
echo "▶ Exempel: starta Darktable genom att skriva:"
echo "  darktable"
echo

