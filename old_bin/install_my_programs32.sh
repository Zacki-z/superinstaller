#!/bin/bash
set -e  # stoppa vid fel

# Gör apt icke-interaktivt
export DEBIAN_FRONTEND=noninteractive

echo "Uppdaterar paketindex..."
sudo apt update -y

echo "Installerar nödvändiga paket..."
sudo apt install -y curl git python3-pip

echo "Rensar oanvända paket..."
sudo apt autoremove -y
sudo apt clean

echo "Installerar appimages ..."
cd ~/Applictions
appimg() {
    # Lista över AppImages du vill ladda ner
    urls=(
        "https://github.com/darktable-org/darktable/releases/download/release-5.2.0/darktable-5.2.0-x86_64.AppImage"
        "https://github.com/KDE/krita/releases/download/v5.2.0/krita-5.2.0-x86_64.appimage"
        "https://github.com/obsproject/obs-studio/releases/download/30.0.0/OBS-Studio-30.0.0-x86_64.AppImage"
        "https://rawtherapee.com/downloads/5.12/RawTherapee_5.12_release.AppImage"
        "https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage"
        "https://cdn.jsdelivr.net/musescore/v4.4.2/MuseScore-4.4.2.251821617-x86_64.AppImage"

    )

    for url in "${urls[@]}"; do
        file=$(basename "$url")
        echo "🔽 Laddar ner $file ..."
        wget -q --show-progress -O "$file" "$url" || {
            echo "❌ Misslyckades att ladda ner $url"
            continue
        }
        chmod +x "$file"
        echo "✅ Klart: $file"
    done

echo "Klart!"
