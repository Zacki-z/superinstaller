#!/bin/bash
set -euo pipefail

echo "🚀 Proton-installationsscript startar..."

### -- Funktioner ------------------------------------------------------------

check_installed() {
    # Kollar om ett kommando finns
    if command -v "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

install_deb() {
    local debfile="$1"
    echo "📦 Installerar $debfile ..."
    sudo apt install -y "./$debfile"
}

### -- Arbetskatalog ----------------------------------------------------------

WORKDIR="${HOME}/Downloads/proton_install"

if [ -d "$WORKDIR" ]; then
    echo "📁 Arbetskatalog finns redan: $WORKDIR"
else
    echo "📁 Skapar arbetskatalog: $WORKDIR"
    mkdir -p "$WORKDIR"
fi

cd "$WORKDIR"

### -- ProtonMail Bridge ------------------------------------------------------

if check_installed "protonmail-bridge"; then
    echo "✅ ProtonMail Bridge är redan installerat."
else
    echo "📥 Hämtar ProtonMail Bridge ..."
    wget -q --show-progress \
      https://proton.me/download/bridge/protonmail-bridge_3.13.0-1_amd64.deb

    install_deb "protonmail-bridge_3.13.0-1_amd64.deb"
fi

### -- ProtonVPN repo + app ---------------------------------------------------

if check_installed "protonvpn-cli"; then
    echo "✅ ProtonVPN är redan installerat."
else
    echo "📥 Hämtar ProtonVPN repo-paket..."
    wget -q --show-progress \
      https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb

    echo "📦 Installerar ProtonVPN repo..."
    sudo dpkg -i protonvpn-stable-release_1.0.8_all.deb || true
    sudo apt update

    echo "🔐 Installerar ProtonVPN GUI..."
    sudo apt install -y proton-vpn-gnome-desktop
fi

### -- Skapa .desktop-fil för ProtonMail Bridge -------------------------------

DESKTOP_FILE="$HOME/.local/share/applications/protonmail-bridge.desktop"

if [ -f "$DESKTOP_FILE" ]; then
    echo "🖥️  .desktop-fil finns redan."
else
    echo "📝 Skapar protonmail-bridge.desktop ..."

    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=ProtonMail Bridge
Comment=Secure email bridge for ProtonMail
Exec=protonmail-bridge --no-window
Icon=protonmail-bridge
Terminal=false
Categories=Network;Email;
EOF

    echo "✔ .desktop-fil skapad: $DESKTOP_FILE"
fi

### -- Avslut ----------------------------------------------------------------

echo "✨ Klart!"
echo "→ Starta ProtonVPN via din meny"
echo "→ Starta ProtonMail Bridge via menyn eller terminalen: protonmail-bridge"

