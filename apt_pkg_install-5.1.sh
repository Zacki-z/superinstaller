#!/bin/bash
# Medvetet INTE -e, för att skriptet inte ska dö på enstaka fel
set -u

###############################################################################
# aptp-install v5.1 — Enkel & stabil
# - Inga tysta krascher p.g.a. set -e
# - Dry-run
# - Verbosity: normal | quiet | debug
# - Skippar universe/multiverse/restricted/main
# - Hoppar över ogiltig PPA-syntax
###############################################################################

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

# Färger
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# Filvägar
REPO_FILE="$HOME/my_bin/etc/repos.txt"
PACKAGE_FILE="$HOME/my_bin/etc/packages.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/aptp_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

# Loggning
if [[ "$VERBOSITY" == "debug" ]]; then
    exec > >(tee -a "$LOGFILE") 2>&1
else
    exec > >(tee -a "$LOGFILE") 2>&1
fi

echo -e "${BLUE}========================================================="
echo -e "🚀 aptp-install v5.1 (enkel & stabil)"
echo -e "▶ Verbosity:  $VERBOSITY"
echo -e "▶ Dry-run:    $DRYRUN"
echo -e "📄 Repo-fil:  $REPO_FILE"
echo -e "📄 Paket-fil: $PACKAGE_FILE"
echo -e "📄 Loggfil:   $LOGFILE"
echo -e "=========================================================${NC}"
echo

[[ ! -f "$REPO_FILE" ]] && { echo -e "❌ ${RED}Repo-fil saknas${NC}"; exit 1; }
[[ ! -f "$PACKAGE_FILE" ]] && { echo -e "❌ ${RED}Paket-fil saknas${NC}"; exit 1; }

# Statistik
ADDED_REPOS=0
SKIPPED_REPOS=0
INSTALLED_PKGS=0
SKIPPED_PKGS=0
FAILED_PKGS=0

# Hjälpfunktioner
is_valid_ppa_syntax() {
    # Måste vara ppa:user/repo
    [[ "$1" =~ ^ppa:[^/]+/[^/]+$ ]]
}

repo_exists() {
    # Returnerar 0 om repot redan finns i någon apt-källa
    grep -RslF "$1" /etc/apt/sources.list /etc/apt/sources.list.d/* \
        2>/dev/null | grep -q . 2>/dev/null
}

add_repo() {
    local repo="$1"
    echo -e "➕ Lägger till repo: ${YELLOW}$repo${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: add-apt-repository -y \"$repo\""
        return
    fi

    if [[ "$VERBOSITY" == "debug" ]]; then
        sudo add-apt-repository -y "$repo"
    else
        sudo add-apt-repository -y "$repo" >/dev/null 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "✔ ${GREEN}Repo tillagt${NC}"
        ((ADDED_REPOS++))
    else
        echo -e "❌ ${RED}Misslyckades lägga till repo (kod $status):${NC} $repo"
        ((SKIPPED_REPOS++))
    fi
}

is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

install_pkg() {
    local pkg="$1"
    echo -e "📦 Installerar: ${BLUE}$pkg${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: apt-get install -y $pkg"
        return
    fi

    if [[ "$VERBOSITY" == "quiet" ]]; then
        sudo apt-get install -y "$pkg" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        sudo apt-get install -y "$pkg"
    else
        sudo apt-get install -y "$pkg" -o=DPkg::Progress-Fancy=1 -o=quiet=2
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -e "✔ ${GREEN}Installerat:${NC} $pkg"
        ((INSTALLED_PKGS++))
    else
        echo -e "❌ ${RED}Installationsfel (kod $status):${NC} $pkg"
        ((FAILED_PKGS++))
    fi
}

# 1. Hantera repos
echo -e "${BLUE}🔧 Bearbetar repositories...${NC}"

while IFS= read -r repo || [[ -n "$repo" ]]; do
    repo="$(echo "$repo" | xargs)"   # trim
    [[ -z "$repo" ]] && continue
    [[ "$repo" =~ ^# ]] && continue

    # Hoppa över universe/multiverse/restricted/main
    if [[ "$repo" =~ ^(universe|multiverse|restricted|main)$ ]]; then
        echo -e "⏭ Hoppar över APT-komponent (ej repo): $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    # Ogiltigt PPA-format
    if [[ "$repo" =~ ^ppa: ]] && ! is_valid_ppa_syntax "$repo"; then
        echo -e "⏭ Ogiltigt PPA-format, hoppar över: $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    if repo_exists "$repo"; then
        echo -e "⏭ Repo finns redan: $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    add_repo "$repo"

done < "$REPO_FILE"

echo -e "\n🔄 ${BLUE}apt update...${NC}"
if [[ "$DRYRUN" == true ]]; then
    echo -e "   🧪 (dry-run) Skulle köra: apt-get update -qq"
else
    if [[ "$VERBOSITY" == "debug" ]]; then
        sudo apt-get update
    else
        sudo apt-get update -qq || true   # fel här stoppar inte skriptet
    fi
fi

# 2. Installera paket
echo -e "\n${BLUE}🔧 Installerar paket...${NC}"

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    pkg="$(echo "$pkg" | xargs)"
    [[ -z "$pkg" ]] && continue
    [[ "$pkg" =~ ^# ]] && continue

    if is_installed "$pkg"; then
        echo -e "⏭ Redan installerad: $pkg"
        ((SKIPPED_PKGS++))
        continue
    fi

    install_pkg "$pkg"

done < "$PACKAGE_FILE"

# Summering
echo -e "${BLUE}---------------------------------------------------------
🎉 Klart! Sammanfattning
---------------------------------------------------------${NC}"

echo -e "▶ Dry-run: $DRYRUN"
echo
echo -e "📚 Repositories:"
echo -e "   ➕ Nya:                ${GREEN}$ADDED_REPOS${NC}"
echo -e "   ⏭ Överhoppade:        ${YELLOW}$SKIPPED_REPOS${NC}"
echo
echo -e "📦 Paket:"
echo -e "   ✔ Installerade:       ${GREEN}$INSTALLED_PKGS${NC}"
echo -e "   ⏭ Redan installerade: ${YELLOW}$SKIPPED_PKGS${NC}"
echo -e "   ❌ Misslyckades:       ${RED}$FAILED_PKGS${NC}"
echo
echo -e "📄 Logg sparad i: $LOGFILE"
echo -e "${BLUE}---------------------------------------------------------${NC}"

