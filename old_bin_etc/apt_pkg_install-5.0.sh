#!/bin/bash
set -euo pipefail

###############################################################################
# aptp-install v5 — Full Stabilitetslager
# • Aldrig krascha av set -e
# • Smart PPA-validering
# • Full dry-run
# • PPA-formatkontroller
# • Tystlägen och debug
###############################################################################

# ===============================
#  Verbosity & Dry-run
# ===============================
VERBOSITY="normal"
DRYRUN=false

for arg in "$@"; do
    case "$arg" in
        --quiet) VERBOSITY="quiet" ;;
        --debug) VERBOSITY="debug" ;;
        --dry-run) DRYRUN=true ;;
        --normal) VERBOSITY="normal" ;;
        *)
            echo "Okänt argument: $arg"
            exit 1
            ;;
    esac
done

# ===============================
#  Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# ===============================
# Filvägar
# ===============================
REPO_FILE="$HOME/my_bin/etc/repos.txt"
PACKAGE_FILE="$HOME/my_bin/etc/packages.txt"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/aptp_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

# ===============================
# Loggning
# ===============================
if [[ "$VERBOSITY" == "debug" ]]; then
    exec 2>&1 | tee -a "$LOGFILE"
else
    exec > >(tee -a "$LOGFILE") 2>&1
fi

echo -e "${BLUE}========================================================="
echo -e "🚀 aptp-install v5 (Stable Edition)"
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
ADDED_REPOS=0
SKIPPED_REPOS=0
INSTALLED_PKGS=0
SKIPPED_PKGS=0
FAILED_PKGS=0

UBU_VERSION="$(. /etc/os-release; echo "$UBUNTU_CODENAME")"

# ===============================
# Stabilitetslager-funktioner
# ===============================

safe_run() {
    # Kör kommando men tillåt fel (p.g.a. set -e)
    # Logga felkod för debugging men krascha aldrig
    set +e
    "$@"
    local STATUS=$?
    set -e
    return $STATUS
}

# ===============================
# PPA-formatkontroll
# ===============================
is_valid_ppa_syntax() {
    [[ "$1" =~ ^ppa:[^/]+/[^/]+$ ]]
}

# ===============================
# Smart PPA-validering
# ===============================
validate_repo() {
    local repo="$1"

    # Ignorera ej-repo-format
    if [[ "$repo" =~ ^(universe|multiverse|restricted|main)$ ]]; then
        return 2  # 2 = ignorerad typ
    fi

    # Ogiltigt PPA-format
    if [[ "$repo" =~ ^ppa: ]] && ! is_valid_ppa_syntax "$repo"; then
        return 3  # 3 = felaktigt format
    fi

    # Testa källans Release via apt-get update --print-uris
    if [[ "$repo" =~ ^ppa: ]]; then
        local user="${repo#ppa:}"
        user="${user%%/*}"
        local ppa="${repo##*/}"

        local URI="http://ppa.launchpad.net/$user/$ppa/ubuntu/dists/$UBU_VERSION/Release"

        # Tyst kontroll
        safe_run curl -fsSL "$URI" >/dev/null 2>&1
        return $?  # 0 = ok, 1 = saknar release
    fi

    if [[ "$repo" =~ ^http ]]; then
        safe_run curl -fsSL "$repo/dists/$UBU_VERSION/Release" >/dev/null 2>&1
        return $?
    fi

    return 0
}

# ===============================
# Kontroll om repo redan finns
# ===============================
repo_exists() {
    grep -RslF "$1" /etc/apt/sources.list /etc/apt/sources.list.d/* \
        2>/dev/null | safe_run grep -q .
}

# ===============================
# Lägg till repo
# ===============================
add_repo() {
    local repo="$1"

    echo -e "➕ Lägger till repo: ${YELLOW}$repo${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: add-apt-repository $repo"
        return
    fi

    if [[ "$VERBOSITY" == "debug" ]]; then
        safe_run sudo add-apt-repository -y "$repo"
    else
        safe_run sudo add-apt-repository -y "$repo" >/dev/null 2>&1
    fi

    echo -e "✔ ${GREEN}Repo tillagt${NC}"
    ((ADDED_REPOS++))
}

# ===============================
# Paketinstallation
# ===============================
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

install_pkg() {
    local pkg="$1"

    echo -e "📦 Installerar: ${BLUE}$pkg${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: apt install $pkg"
        return
    fi

    if [[ "$VERBOSITY" == "quiet" ]]; then
        safe_run sudo apt-get install -y "$pkg" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        safe_run sudo apt-get install -y "$pkg"
    else
        safe_run sudo apt-get install -y "$pkg" -o=DPkg::Progress-Fancy=1 -o=quiet=2
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "✔ ${GREEN}Installerat:${NC} $pkg"
        ((INSTALLED_PKGS++))
    else
        echo -e "❌ ${RED}Installationsfel:${NC} $pkg"
        ((FAILED_PKGS++))
    fi
}

# ===============================
# 1. Hantera repos
# ===============================
echo -e "${BLUE}🔧 Bearbetar repositories...${NC}"

while IFS= read -r repo || [[ -n "$repo" ]]; do
    repo="$(echo "$repo" | xargs)"
    [[ -z "$repo" ]] && continue
    [[ "$repo" =~ ^# ]] && continue

    # Ignorera komponenter
    if [[ "$repo" =~ ^(universe|multiverse|restricted|main)$ ]]; then
        echo -e "⏭ Hoppar över komponent: $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    # Syntaxfel i PPA
    if [[ "$repo" =~ ^ppa: ]] && ! is_valid_ppa_syntax "$repo"; then
        echo -e "⏭ Ogiltigt PPA-format: $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    # Redan installerat?
    if repo_exists "$repo"; then
        echo -e "⏭ Repo finns redan: $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    echo -e "🔍 Testar repo: $repo"

    safe_run validate_repo "$repo"
    VALID_STATUS=$?

    case $VALID_STATUS in
        0)
            add_repo "$repo"
            ;;
        1)
            echo -e "⚠ ${YELLOW}Hoppar över (ingen Release för $UBU_VERSION):${NC} $repo"
            ((SKIPPED_REPOS++))
            ;;
        2)
            echo -e "⏭ Hoppar över komponent: $repo"
            ((SKIPPED_REPOS++))
            ;;
        3)
            echo -e "⏭ Ogiltigt PPA-format: $repo"
            ((SKIPPED_REPOS++))
            ;;
        *)
            echo -e "⚠ Okänt reporesultat: $repo"
            ((SKIPPED_REPOS++))
            ;;
    esac

done < "$REPO_FILE"

# ===============================
# apt update
# ===============================
echo -e "\n🔄 ${BLUE}apt update...${NC}"

if [[ "$DRYRUN" == true ]]; then
    echo -e "   🧪 (dry-run) Skulle köra: apt-get update"
else
    safe_run sudo apt-get update -qq
fi

# ===============================
# 2. Installera paket
# ===============================
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

# ===============================
# Summering
# ===============================
echo -e "${BLUE}---------------------------------------------------------
🎉 Klart! Sammanfattning
---------------------------------------------------------${NC}"

echo -e "▶ Dry-run: $DRYRUN"

echo -e "📚 Repositories:"
echo -e "   ➕ Nya:                ${GREEN}$ADDED_REPOS${NC}"
echo -e "   ⏭ Överhoppade:        ${YELLOW}$SKIPPED_REPOS${NC}"
echo
echo -e "📦 Paket:"
echo -e "   ✔ Installerade:       ${GREEN}$INSTALLED_PKGS${NC}"
echo-e "   ⏭ Redan installerade: ${YELLOW}$SKIPPED_PKGS${NC}"
echo -e "   ❌ Misslyckades:       ${RED}$FAILED_PKGS${NC}"
echo
echo -e "📄 Logg sparad i: $LOGFILE"
echo -e "${BLUE}---------------------------------------------------------${NC}"

