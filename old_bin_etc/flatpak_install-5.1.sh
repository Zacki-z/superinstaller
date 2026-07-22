#!/bin/bash
# Medvetet INTE -e, så att skriptet inte dör på enstaka fel
set -u

###############################################################################
# flatpak-install v5.1 — enkel & stabil
# Läser Flatpaks från ~/my_bin/etc/flatpaks.txt
# Format per rad:
#   remote/appname   (t.ex. flathub org.gimp.GIMP)
###############################################################################

# ===============================
# Verbosity & Dry-run
# ===============================
VERBOSITY="normal"
DRYRUN=false

for arg in "$@"; do
    case "$arg" in
        --quiet)  VERBOSITY="quiet" ;;
        --debug)  VERBOSITY="debug" ;;
        --normal) VERBOSITY="normal" ;;
        --dry-run) DRYRUN=true ;;
        *)
            echo "Okänt argument: $arg"
            exit 1
            ;;
    esac
done

# ===============================
# Sökvägar
# ===============================
FLATPAK_FILE="$HOME/my_bin/etc/flatpaks.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/flatpak_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

# ===============================
# Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# ===============================
# Loggning
# ===============================
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BLUE}----------------------------------------------------------"
echo -e "🚀 flatpak-install startar (v5.1 enkel & stabil)"
echo -e "▶ Verbosity: $VERBOSITY"
echo -e "▶ Dry-run:   $DRYRUN"
echo -e "📄 Flatpak-fil: $FLATPAK_FILE"
echo -e "📄 Loggfil:     $LOGFILE"
echo -e "----------------------------------------------------------${NC}"
echo

# ===============================
# Kontroll av fil
# ===============================
if [[ ! -f "$FLATPAK_FILE" ]]; then
    echo -e "❌ ${RED}Fel: flatpak-fil saknas:${NC}"
    echo "$FLATPAK_FILE"
    exit 1
fi

# ===============================
# Statistik
# ===============================
INSTALLED=0
SKIPPED=0
FAILED=0

# ===============================
# Funktioner
# ===============================
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

# ===============================
# Loop genom flatpak-listan
# Format:
#   remote appname
# ===============================
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

# ===============================
# Summering
# ===============================
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

