#!/bin/bash
# Ingen set -e → scriptet dör inte på enstaka fel
set -u

###############################################################################
# Proton-install v5.1 — utan ProtonMail Bridge
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
LOGFILE="$LOGDIR/proton_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BLUE}----------------------------------------------------------"
echo -e "🚀 Proton-install startar (v5.1, utan Bridge)"
echo -e "▶ Verbosity: $VERBOSITY"
echo -e "▶ Dry-run:   $DRYRUN"
echo -e "📄 Loggfil:  $LOGFILE"
echo -e "----------------------------------------------------------${NC}"
echo

# ===============================
# Funktioner
# ===============================
check_installed() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local outfile="$2"

    echo "📥 Hämtar: $outfile"

    if [[ "$DRYRUN" == true ]]; then
        echo "   🧪 (dry-run) Skulle hämta: $url"
        return
    fi

    wget -q --show-progress "$url" -O "$outfile"
}

# ===============================
# Arbetskatalog
# ===============================
WORKDIR="$HOME/Downloads/proton_install"
mkdir -p "$WORKDIR"
echo "📁 Arbetskatalog: $WORKDIR"
cd "$WORKDIR"

# ===============================
# ProtonVPN (repo + GUI)
# ===============================
VPN_DEB="protonvpn-stable-release_1.0.8_all.deb"
VPN_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/$VPN_DEB"

echo -e "\n${BLUE}🛡 ProtonVPN${NC}"

if check_installed "protonvpn-cli"; then
    echo "✔ Redan installerad"
else
    download_file "$VPN_URL" "$VPN_DEB"

    echo "📦 Installerar ProtonVPN repository..."
    if [[ "$DRYRUN" == true ]]; then
        echo "   🧪 (dry-run) Skulle köra: sudo dpkg -i $VPN_DEB"
    else
        sudo dpkg -i "$VPN_DEB" >/dev/null 2>&1 || true
        sudo apt update -qq
    fi

    echo "🔐 Installerar ProtonVPN GUI..."
    if [[ "$DRYRUN" == true ]]; then
        echo "   🧪 (dry-run) Skulle köra: sudo apt install -y proton-vpn-gnome-desktop"
    else
        sudo apt install -y proton-vpn-gnome-desktop >/dev/null 2>&1
    fi
fi

# ===============================
# Summering
# ===============================
echo -e "${BLUE}----------------------------------------------------------"
echo -e "🎉 Klart! Installationen är färdig"
echo -e "----------------------------------------------------------${NC}"
echo "→ Starta ProtonVPN via menyn"
echo -e "📄 Logg sparad i: $LOGFILE"

