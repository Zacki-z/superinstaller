#!/bin/bash
set -euo pipefail

echo "🚀 Installerar AppImages + menyikoner ..."

# Mapp där AppImages lagras
TARGET="${HOME}/appimages_applications"
BIN="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"

# Se till att mapparna finns
mkdir -p "$TARGET" "$BIN" "$DESKTOP_DIR"
cd "$TARGET"

# Skapa .desktop-fil
make_desktop_entry() {
  local key="$1"         # t.ex. "darktable"
  local file="$2"        # full path till AppImage
  local exec_path="$BIN/$key"
  local desktop_file="${DESKTOP_DIR}/${key}.desktop"

  # Mänskligt namn till meny
  declare -A names=(
    ["darktable"]="Darktable"
    ["krita"]="Krita"
    ["obs"]="OBS Studio"
    ["rawtherapee"]="RawTherapee"
    ["arduino-ide"]="Arduino IDE"
    ["musescore"]="MuseScore Studio"
  )

  local display_name="${names[$key]:-$key}"

  # Välj någorlunda vettiga kategorier
  local category="Utility"
  case "$key" in
    darktable|rawtherapee|krita)
      category="Graphics"
      ;;
    obs|musescore)
      category="AudioVideo"
      ;;
    arduino-ide)
      category="Development"
      ;;
  esac

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
    
    # Gimp
    ["Gimp"]="https://download.gimp.org/gimp/v3.0/linux/GIMP-3.0.6-x86_64.AppImage"
  )

  for key in "${!urls[@]}"; do
    url="${urls[$key]}"
    file=$(basename "$url")

    echo
    echo "🔽 Laddar ner: $key"
    echo "   URL: $url"

    if wget -q --show-progress -O "$file" "$url"; then
      chmod +x "$file"
      echo "✅ Klart: $file"

      # Skapa symlänk i ~/.local/bin
      ln -sf "${TARGET}/${file}" "${BIN}/${key}"
      echo "🔗 Länk skapad: ${BIN}/${key} → ${file}"

      # Skapa .desktop-fil så den syns i menyn
      make_desktop_entry "$key" "${TARGET}/${file}"
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
echo "Desktop-filer skapade i: $DESKTOP_DIR"
echo
echo "🔍 Kontrollera att ~/.local/bin finns i din PATH:"
echo '  echo "$PATH" | tr ":" "\n" | grep -E "^'"$BIN"'$" || echo "⚠️ ~/.local/bin saknas i PATH"'
echo
echo "▶ Exempel: starta Darktable genom att skriva:"
echo "  darktable"
echo
echo "📂 Logga ut/in eller kör 'gio mime' / 'update-desktop-database' om menyerna inte uppdateras direkt."

