#!/bin/bash
set -euo pipefail

echo "============================================="
echo "  Surface Tablet Mode 1.0 – Ubuntu + Surface"
echo "============================================="
echo
echo "Detta kommer att:"
echo "  • Lägga till linux-surface repository"
echo "  • Installera linux-surface-kärnan + drivrutiner"
echo "  • Installera Onboard (skärmtangentbord)"
echo "  • Aktivera Onboard vid login + på skrivbordet"
echo "  • Installera sensordemon (rotation m.m.)"
echo

if [[ $EUID -ne 0 ]]; then
    echo "❌ Kör mig med sudo:"
    echo "   sudo $0"
    exit 1
fi

# ==========================
# Hitta 'riktig' användare
# ==========================
TARGET_USER="${SUDO_USER:-$USER}"

if [[ "$TARGET_USER" == "root" ]]; then
    echo "⚠ Hittade ingen icke-root-användare (SUDO_USER saknas)."
    echo "  Jag försöker använda miljövariabler för HOME."
    TARGET_HOME="${HOME}"
else
    TARGET_HOME="$(eval echo "~${TARGET_USER}")"
fi

echo "Använder användare: $TARGET_USER"
echo "Använder hemkatalog: $TARGET_HOME"
echo

# ==========================
# Grundpaket
# ==========================
echo "➡ Installerar grundpaket (git, wget, curl, Onboard, sensorer)..."
apt update
apt install -y git wget curl gpg onboard iio-sensor-proxy touchegg

echo
echo "✅ Grundpaket installerade."
echo

# ==========================
# linux-surface repository
# (ny officiell metod)
# ==========================
echo "➡ Lägger till linux-surface nyckel + repository..."

# Importera GPG-nyckel för linux-surface
wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
    | gpg --dearmor | dd of=/etc/apt/trusted.gpg.d/linux-surface.gpg 2>/dev/null

# Lägg till apt-repo
echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" \
    > /etc/apt/sources.list.d/linux-surface.list

echo "➡ Uppdaterar apt-cache..."
apt update

echo
echo "➡ Installerar linux-surface-kärnan + drivrutiner..."
apt install -y linux-image-surface linux-headers-surface libwacom-surface iptsd

# Aktivera IP-based touch stack (för touch/penna)
systemctl enable iptsd || true

echo
echo "✅ linux-surface installerad."
echo "   Efter reboot ska 'uname -a' visa en kernel med ordet 'surface'."
echo

# ==========================
# (Valfritt) Secure Boot-stöd
# ==========================
echo "Vill du installera Secure Boot-stöd för linux-surface?"
echo "Det gör att kernel-signaturen funkar med aktiv Secure Boot."
read -r -p "Installera linux-surface-secureboot-mok? [y/N]: " SECUREBOOT_CHOICE

if [[ "${SECUREBOOT_CHOICE,,}" == "y" ]]; then
    echo "➡ Installerar linux-surface-secureboot-mok..."
    apt install -y linux-surface-secureboot-mok
    echo
    echo "ℹ Vid nästa boot kan du få en blå MOK-skärm."
    echo "   Standardlösenord för nyckeln brukar vara: surface"
    echo "   Följ instruktionerna och godkänn nyckeln."
    echo
else
    echo "⏭ Skippar Secure Boot-stöd."
    echo
fi

# ==========================
# Autostart: Onboard i session
# ==========================
echo "➡ Ställer in Onboard att starta automatiskt för användaren..."

AUTOSTART_DIR="${TARGET_HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"

if [[ -f /usr/share/applications/onboard.desktop ]]; then
    cp /usr/share/applications/onboard.desktop "${AUTOSTART_DIR}/onboard.desktop"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${AUTOSTART_DIR}"
    echo "✅ Onboard läggs till i autostart för ${TARGET_USER}."
else
    echo "⚠ Hittar inte /usr/share/applications/onboard.desktop – är Onboard rätt installerat?"
fi

# ==========================
# Autostart: Onboard i GDM (login-skärm)
# ==========================
echo
echo "➡ Aktiverar Onboard även på inloggningsskärmen (GDM)..."

mkdir -p /etc/xdg/autostart
if [[ -f /usr/share/applications/onboard.desktop ]]; then
    cp /usr/share/applications/onboard.desktop /etc/xdg/autostart/onboard.desktop
    echo "✅ Onboard startar även på GDM-login."
else
    echo "⚠ Kunde inte kopiera onboard.desktop till /etc/xdg/autostart."
fi

# ==========================
# Försök slå på GNOME:s skärmtangentbord
# ==========================
echo
echo "➡ Försöker aktivera GNOME:s eget skärmtangentbord (kan misslyckas tyst)..."

sudo -u "${TARGET_USER}" bash -c '
  gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true 2>/dev/null || exit 0
' || true

echo "   (Om detta inte tog, kan du slå på det manuellt:"
echo "    Inställningar → Tillgänglighet → Skärmtangentbord.)"
echo

# ==========================
# Touch-gester: touchegg (valfritt)
# ==========================
echo "➡ Försöker aktivera touchegg för touch-gester (användarsession)..."

sudo -u "${TARGET_USER}" bash -c '
  systemctl --user enable touchegg 2>/dev/null || exit 0
' || true

echo "   Du kan senare starta om sessionen och justera gester via touchegg."
echo

# ==========================
# Sammanfattning
# ==========================
echo "============================================="
echo "  KLART: Surface Tablet Mode 1.0"
echo "============================================="
echo
echo "Gör nu detta:"
echo "  1. Starta om datorn."
echo "  2. I GRUB välj den nya 'surface'-kärnan om det finns flera."
echo "  3. Testa:"
echo "       • Touch + penna"
echo "       • Auto-rotation (vänd plattan)"
echo "       • Onboard vid login och i skrivbordet"
echo
echo "Tips:"
echo "  – Kör 'uname -a' och kontrollera att kernel-namnet innehåller 'surface'."
echo "  – Om något strular: 'journalctl -b' direkt efter reboot."
echo
echo "Klart! Nu ska din Surface Pro fungera betydligt bättre som ren platta. 🧡"

