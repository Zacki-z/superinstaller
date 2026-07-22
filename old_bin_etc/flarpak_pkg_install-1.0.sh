#!/bin/bash
set -euo pipefail

echo "-------------------------------------------------------"
echo "🚀 Startar Flatpak-installation"
echo "-------------------------------------------------------"
echo


# ---------------------------------------------------------
# 1. Installera Flatpak om det saknas
# ---------------------------------------------------------
if ! command -v flatpak &>/dev/null; then
    echo "📦 Installerar Flatpak..."
    sudo apt install -y flatpak
else
    echo "⏭  Flatpak redan installerat"
fi
echo


# ---------------------------------------------------------
# 2. Lägg till Flathub (om den inte redan finns)
# ---------------------------------------------------------
if flatpak remotes | grep -q flathub; then
    echo "⏭  Flathub finns redan"
else
    echo "➕ Lägger till Flathub…"
    flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo
fi
echo


# ---------------------------------------------------------
# 3. Installera Flatpak-appar (GnuCash, GIMP)
# ---------------------------------------------------------
install_flatpak_app() {
    local app="$1"
    echo "📦 Installerar Flatpak-app: $app"

    flatpak install -y flathub "$app"
    echo "✔ Installerad: $app"
    echo
}

install_flatpak_app "org.gnucash.GnuCash"
# install_flatpak_app "org.gimp.GIMP"


echo "-------------------------------------------------------"
echo "🎉 Klar! Flatpak och appar installerade."
echo "-------------------------------------------------------"

