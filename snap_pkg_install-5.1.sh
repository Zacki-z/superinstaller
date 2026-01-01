#!/bin/bash
# Medvetet INTE -e, så att enstaka fel inte dödar hela skriptet
set -u

###############################################################################
# snap-install v5.1 — enkel & stabil
# Läser snaps från ~/my_bin/etc/snaps.txt
# Format per rad: namn [extra flaggor]  (t.ex. "code --classic")
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
SNAP_FILE="$HOME/my_bin/etc/snaps.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/snap_install_$(date +%Y%m%d_%H%M%S).log"
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
echo -e "🚀 Snap-install-wrapper startar (v5.1 enkel & stabil)"
echo -e "▶ Verbosity: $VERBOSITY"
echo -e "▶ Dry-run:   $DRYRUN"
echo -e "📄 Snap-fil: $SNAP_FILE"
echo -e "📄 Loggfil:  $LOGFILE"
echo -e "----------------------------------------------------------${NC}"
echo

# ===============================
# Kontroll av fil
# ===============================
if [[ ! -f "$SNAP_FILE" ]]; then
    echo -e "❌ ${RED}Fel: snap-fil saknas:${NC}"
    echo "   $SNAP_FILE"
    exit 1
fi

# ===============================
# Statistik
# ===============================
INSTALLED_SNAPS=0
SKIPPED_SNAPS=0
FAILED_SNAPS=0

# ===============================
# Funktioner
# ===============================
is_snap_installed() {
    local name="$1"
    snap list "$name" &>/dev/null
}

install_snap() {
    local name="$1"
    shift
    local args=("$@")

    echo -e "📦 Installerar snap: ${BLUE}$name${NC} ${args[*]:-}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: sudo snap install $name ${args[*]:-}"
        return
    fi

    if [[ "$VERBOSITY" == "debug" ]]; then
        sudo snap install "$name" "${args[@]}"
    elif [[ "$VERBOSITY" == "quiet" ]]; then
        sudo snap install "$name" "${args[@]}" >/dev/null 2>&1
    else
        sudo snap install "$name" "${args[@]}" >/dev/null 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "✔ ${GREEN}Installerad:${NC} $name"
        ((INSTALLED_SNAPS++))
    else
        echo -e "❌ ${RED}Misslyckades installera (kod $status):${NC} $name"
        ((FAILED_SNAPS++))
    fi

    echo
}

# ===============================
# Loop genom snap-fil
# Format:
#   namn [extra flaggor]
# ===============================
echo -e "${BLUE}🔧 Bearbetar snaps...${NC}"

while IFS= read -r line || [[ -n "$line" ]]; do
    # hoppa över tomma eller kommenterade rader
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue

    # Splitta till array
    read -r -a parts <<< "$line"
    name="${parts[0]}"

    if (( ${#parts[@]} > 1 )); then
        args=("${parts[@]:1}")
    else
        args=()
    fi

    # Kolla om redan installerad
    if is_snap_installed "$name"; then
        echo -e "⏭  ${YELLOW}Hoppar över (redan installerad):${NC} $name"
        ((SKIPPED_SNAPS++))
        continue
    fi

    install_snap "$name" "${args[@]}"

done < "$SNAP_FILE"

# ===============================
# Efteråt: snap refresh
# ===============================
echo -e "${BLUE}🔄 Kör snap refresh...${NC}"

if [[ "$DRYRUN" == true ]]; then
    echo -e "   🧪 (dry-run) Skulle köra: sudo snap refresh"
else
    if [[ "$VERBOSITY" == "debug" ]]; then
        sudo snap refresh || true
    else
        sudo snap refresh >/dev/null 2>&1 || true
    fi
    echo -e "✔ ${GREEN}Snap refresh klart.${NC}"
fi

echo

# ===============================
# Summering
# ===============================
echo -e "${BLUE}----------------------------------------------------------"
echo -e "🎉 Snap-install klart! Sammanfattning"
echo -e "----------------------------------------------------------${NC}"
echo -e "▶ Dry-run: $DRYRUN"
echo
echo -e "📦 Snaps:"
echo -e "   ✔ Installerade:       ${GREEN}$INSTALLED_SNAPS${NC}"
echo -e "   ⏭ Redan installerade: ${YELLOW}$SKIPPED_SNAPS${NC}"
echo -e "   ❌ Misslyckades:       ${RED}$FAILED_SNAPS${NC}"
echo
echo -e "📄 Logg sparad i: $LOGFILE"
echo -e "${BLUE}----------------------------------------------------------${NC}"

