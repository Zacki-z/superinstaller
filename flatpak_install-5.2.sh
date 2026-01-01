#!/bin/bash
# Ingen set -e → skriptet dör inte vid fel
set -u

###############################################################################
# flatpak-install v5.2 — enkel, stabil, med auto-Flathub
###############################################################################

VERBOSITY="normal"
DRYRUN=false

# --------------------------------------------------------
# Argument
# --------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --quiet)  VERBOSITY="quiet" ;;
        --debug)  VERBOSITY="debug" ;;
        --normal) VERBOSITY="normal" ;;
        --dry-run) DRYRUN=true ;;
        *)
            echo "Okänt argument: $arg"
            exit 1 ;;
    esac
done

# --------------------------------------------------------
# Färger
# --------------------------------------------------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# --------------------------------------------------------
# Sökvägar
# --------------------------------------------------------
FLATPAK_FILE="$HOME/my_bin/etc/flatpaks.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/flatpak_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

# --------------------------------------------------------
# Loggning
# --------------------------------------------------------
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BLUE}----------------------------------------------------------"
echo -e "🚀 flatpak-install startar (v5.2 auto-Flathub)"
echo -e "▶ Verbosity: $VERBOSITY"
echo -e "▶ Dry-run:   $DRYRUN"
echo -e "📄 Flatpak-fil: $FLATPAK_FILE"
echo -e "📄 Loggfil:     $LOGFILE"
echo -e "----------------------------------------------------------${NC}"
echo

[[ ! -f "$FLATPAK_FILE" ]] && {
    echo -e "❌ ${RED}Flatpak-fil saknas:${NC} $FLATPAK_FILE"
    exit 1
}

# --------------------------------------------------------
# Statistik
# --------------------------------------------------------
INSTALLED=0
SKIPPED=0
FAILED=0

# --------------------------------------------------------
# Funktioner
# --------------------------------------------------------
is_flatpak_installed() {
    local app="$1"
    flatpak list --app | grep -q " $app " 2>/dev/null
}

install_flatpak() {
    local remote="$1"
    local app="$2"

    echo -e "📦 Installerar flatpak: ${BLUE}$remote $app${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: flatpak install -y $remote $app"
        return
    fi

    if [[ "$VERBOSITY" == "debug" ]]; then
        flatpak install -y "$remote" "$app"
    elif [[ "$VERBOSITY" == "quiet" ]]; then
        flatpak install -y "$remote" "$app" >/dev/null 2>&1
    else
        flatpak install -y "$remote" "$app" >/dev/null 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "✔ ${GREEN}Installerat:${NC} $app"
        ((INSTALLED++))
    else
        echo -e "❌ ${RED}Misslyckades (kod $status):${NC} $app"
        ((FAILED++))
    fi
}

# --------------------------------------------------------
# 1. Kontroll: Flatpak installerad?
# --------------------------------------------------------
echo -e "${BLUE}🔍 Kontrollerar flatpak...${NC}"

if ! command -v flatpak >/dev/null 2>&1; then
    echo -e "⚠ ${YELLOW}Flatpak saknas.${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: sudo apt install -y flatpak"
    else
        echo -e "   ➕ Installerar flatpak..."
        sudo apt install -y flatpak
    fi
else
    echo -e "✔ Flatpak installerad"
fi
echo

# --------------------------------------------------------
# 2. Kontroll: Flathub remote finns?
# --------------------------------------------------------
echo -e "${BLUE}🔍 Kontrollerar Flathub-remote...${NC}"

if flatpak remotes | grep -q "^flathub"; then
    echo -e "✔ Flathub redan tillagd"
else
    echo -e "➕ Flathub saknas – lägger till..."

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    else
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
fi
echo

# --------------------------------------------------------
# 3. Installera flatpaks
# --------------------------------------------------------
echo -e "${BLUE}🔧 Bearbetar flatpaks...${NC}"

while IFS= read -r line || [[ -n "$line" ]]; do

    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue

    read -r remote app <<< "$line"

    if [[ -z "$remote" || -z "$app" ]]; then
        echo -e "⏭ ${YELLOW}Hoppar över felaktig rad:${NC} $line"
        ((SKIPPED++))
        continue
    fi

    if is_flatpak_installed "$app"; then
        echo -e "⏭ ${YELLOW}Redan installerad:${NC} $app"
        ((SKIPPED++))
        continue
    fi

    install_flatpak "$remote" "$app"

done < "$FLATPAK_FILE"

# --------------------------------------------------------
# 4. Summering
# --------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------"
echo -e "🎉 Flatpak-install klar! Sammanfattning"
echo -e "----------------------------------------------------------${NC}"

echo -e "▶ Dry-run: $DRYRUN"
echo
echo -e "📦 Flatpaks:"
echo -e "   ✔ Installerade:       ${GREEN}$INSTALLED${NC}"
echo -e "   ⏭ Redan installerade: ${YELLOW}$SKIPPED${NC}"
echo -e "   ❌ Misslyckades:       ${RED}$FAILED${NC}"
echo
echo -e "📄 Logg sparad i: $LOGFILE"
echo -e "${BLUE}----------------------------------------------------------${NC}"

