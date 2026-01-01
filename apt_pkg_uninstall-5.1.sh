#!/bin/bash
# Medvetet INTE -e, så att enstaka fel inte dödar hela skriptet
set -u

###############################################################################
# aptp-uninstall v5.1 — enkel & stabil
# Tar bort repos + paket som finns i samma listor som aptp-install v5.1
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
# Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# ===============================
# Filvägar
# ===============================
REPO_FILE="$HOME/my_bin/etc/repos.txt"
PACKAGE_FILE="$HOME/my_bin/etc/packages.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/aptp_uninstall_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

# ===============================
# Loggning
# ===============================
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BLUE}========================================================="
echo -e "🗑️ aptp-uninstall v5.1 (enkel & stabil)"
echo -e "▶ Verbosity:  $VERBOSITY"
echo -e "▶ Dry-run:    $DRYRUN"
echo -e "📄 Repo-fil:  $REPO_FILE"
echo -e "📄 Paket-fil: $PACKAGE_FILE"
echo -e "📄 Loggfil:   $LOGFILE"
echo -e "=========================================================${NC}"
echo

[[ ! -f "$REPO_FILE" ]] && { echo -e "❌ ${RED}Repo-fil saknas${NC}"; exit 1; }
[[ ! -f "$PACKAGE_FILE" ]] && { echo -e "❌ ${RED}Paket-fil saknas${NC}"; exit 1; }

# ===============================
# Statistik
# ===============================
REMOVED_REPOS=0
SKIPPED_REPOS=0
REMOVED_PACKAGES=0
SKIPPED_PACKAGES=0
FAILED_PACKAGES=0

# ===============================
# Hjälpfunktioner
# ===============================
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

remove_repo() {
    local repo="$1"

    echo -e "🗑️  Tar bort repo: ${YELLOW}$repo${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle försöka hitta och ta bort källor som matchar: $repo"
        return
    fi

    # Leta efter filer där repo-strängen förekommer
    local FILES
    FILES=$(grep -RslF "$repo" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true)

    if [[ -z "$FILES" ]]; then
        echo -e "⏭ Repo hittades inte i systemet: $repo"
        ((SKIPPED_REPOS++))
        return
    fi

    for f in $FILES; do
        echo -e "   🗑️  Tar bort fil: $f"
        sudo rm -f "$f" 2>/dev/null || {
            echo -e "   ❌ ${RED}Kunde inte ta bort:${NC} $f"
        }
    done

    ((REMOVED_REPOS++))
}

remove_pkg() {
    local pkg="$1"

    echo -e "🗑️  Tar bort paket: ${BLUE}$pkg${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: apt-get remove -y $pkg"
        return
    fi

    if ! is_installed "$pkg"; then
        echo -e "⏭ Paket ej installerat: $pkg"
        ((SKIPPED_PACKAGES++))
        return
    fi

    if [[ "$VERBOSITY" == "quiet" ]]; then
        sudo apt-get remove -y "$pkg" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        sudo apt-get remove -y "$pkg"
    else
        sudo apt-get remove -y "$pkg" -o=DPkg::Progress-Fancy=1 -o=quiet=2
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "✔ ${GREEN}Paket borttaget:${NC} $pkg"
        ((REMOVED_PACKAGES++))
    else
        echo -e "❌ ${RED}Kunde inte ta bort (kod $status):${NC} $pkg"
        ((FAILED_PACKAGES++))
    fi
}

# ===============================
# 1. Ta bort repos
# ===============================
echo -e "${BLUE}🗑️  Bearbetar repos...${NC}"

while IFS= read -r repo || [[ -n "$repo" ]]; do
    repo="$(echo "$repo" | xargs)"
    [[ -z "$repo" ]] && continue
    [[ "$repo" =~ ^# ]] && continue

    # hoppa över komponenter (samma logik som install)
    if [[ "$repo" =~ ^(universe|multiverse|restricted|main)$ ]]; then
        echo -e "⏭ Hoppar över komponent (ej repo): $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    remove_repo "$repo"

done < "$REPO_FILE"

# ===============================
# apt update efter borttagning
# ===============================
echo -e "\n🔄 ${BLUE}apt update efter repo-clean...${NC}"

if [[ "$DRYRUN" == true ]]; then
    echo -e "   🧪 (dry-run) Skulle köra: apt-get update -qq"
else
    if [[ "$VERBOSITY" == "debug" ]]; then
        sudo apt-get update || true
    else
        sudo apt-get update -qq || true
    fi
fi

# ===============================
# 2. Ta bort paket
# ===============================
echo -e "\n${BLUE}🗑️  Bearbetar paket...${NC}"

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    pkg="$(echo "$pkg" | xargs)"
    [[ -z "$pkg" ]] && continue
    [[ "$pkg" =~ ^# ]] && continue

    remove_pkg "$pkg"

done < "$PACKAGE_FILE"

# ===============================
# Summering
# ===============================
echo -e "${BLUE}---------------------------------------------------------
🎉 Uninstall klar! Sammanfattning
---------------------------------------------------------${NC}"

echo -e "▶ Dry-run: $DRYRUN"
echo
echo -e "📚 Repositories:"
echo -e "   🗑️  Borttagna:        ${GREEN}$REMOVED_REPOS${NC}"
echo -e "   ⏭ Överhoppade:        ${YELLOW}$SKIPPED_REPOS${NC}"
echo
echo -e "📦 Paket:"
echo -e "   🗑️  Borttagna:        ${GREEN}$REMOVED_PACKAGES${NC}"
echo -e "   ⏭ Ej installerade:    ${YELLOW}$SKIPPED_PACKAGES${NC}"
echo -e "   ❌ Misslyckades:       ${RED}$FAILED_PACKAGES${NC}"
echo
echo -e "📄 Logg sparad i: $LOGFILE"
echo -e "${BLUE}---------------------------------------------------------${NC}"

