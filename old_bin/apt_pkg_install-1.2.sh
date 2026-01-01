#!/bin/bash
set -euo pipefail

###############################################################################
# aptp-install v4 — repo-verifiering + verbosity: quiet | normal | debug
###############################################################################

# ===============================
#  VERBOSITY-lägen
# ===============================
# normal = snygg output (default)
# quiet  = minimal output, allt tyst så långt möjligt
# debug  = visar exakt vad som händer, inga redirect
# ===============================

VERBOSITY="normal"

# Flagga via kommandorad
if [[ $# -gt 0 ]]; then
    case "$1" in
        --quiet) VERBOSITY="quiet" ;;
        --debug) VERBOSITY="debug" ;;
        --normal) VERBOSITY="normal" ;;
        *) echo "Okänt argument: $1"; exit 1 ;;
    esac
fi


# ===============================
#  Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"


# ===============================
#  Filvägar
# ===============================
REPO_FILE="$HOME/my_bin/etc/repos.txt"
PACKAGE_FILE="$HOME/my_bin/etc/packages.txt"

LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/aptp_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"


# ===============================
#  Logg
# ===============================
if [[ "$VERBOSITY" == "debug" ]]; then
    # Debug: skriv ALLT
    exec 2>&1 | tee -a "$LOGFILE"
else
    # Normal/quiet: normal loggning
    exec > >(tee -a "$LOGFILE") 2>&1
fi


echo -e "${BLUE}========================================================="
echo -e "🚀 aptp-install v4  (verbosity: $VERBOSITY)"
echo -e "📄 Repo-fil:    $REPO_FILE"
echo -e "📄 Paket-fil:   $PACKAGE_FILE"
echo -e "📄 Loggfil:     $LOGFILE"
echo -e "=========================================================${NC}\n"

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
#  Funktioner
# ===============================

# Expandera ppa: till URL
expand_ppa_url() {
    local ppa="$1"
    local ppa_clean="${ppa#ppa:}"
    local user="${ppa_clean%%/*}"
    local repo="${ppa_clean##*/}"

    echo "https://ppa.launchpadcontent.net/$user/$repo/ubuntu/dists/$UBU_VERSION/Release"
}

# Kontrollera om PPA/Repo har Release-fil
validate_repo() {
    local repo="$1"

    if [[ "$repo" =~ ^ppa: ]]; then
        local url
        url=$(expand_ppa_url "$repo")
        [[ "$VERBOSITY" == "debug" ]] && echo "TESTAR PPA Release: $url"
        curl -fsSL "$url" >/dev/null 2>&1 && return 0 || return 1
    fi

    if [[ "$repo" =~ ^http ]]; then
        local url="$repo/dists/$UBU_VERSION/Release"
        [[ "$VERBOSITY" == "debug" ]] && echo "TESTAR APT Release: $url"
        curl -fsSL "$url" >/dev/null 2>&1 && return 0 || return 1
    fi

    return 0
}

is_repo_added() {
    grep -RslF "$1" /etc/apt/sources.list /etc/apt/sources.list.d/* \
        2>/dev/null | grep -q .
}

add_repo() {
    local repo="$1"

    echo -e "➕ Lägger till repo: ${YELLOW}$repo${NC}"

    if [[ "$VERBOSITY" == "quiet" ]]; then
        sudo add-apt-repository -y "$repo" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        sudo add-apt-repository -y "$repo"
    else
        sudo add-apt-repository -y "$repo" >/dev/null 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "✔ ${GREEN}Repo tillagt${NC}"
        ((ADDED_REPOS++))
    else
        echo -e "❌ ${RED}Misslyckades lägga till repo${NC}"
    fi
}

is_installed() {
    dpkg -s "$1" &>/dev/null
}

install_pkg() {
    local pkg="$1"
    echo -e "📦 Installerar: ${BLUE}$pkg${NC}"

    if [[ "$VERBOSITY" == "quiet" ]]; then
        sudo apt-get install -y "$pkg" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        sudo apt-get install -y "$pkg"
    else
        sudo apt-get install -y "$pkg" -o=DPkg::Progress-Fancy=1 -o=quiet=2
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
# 1. Bearbeta repos
# ===============================
echo -e "${BLUE}🔧 Bearbetar repositories...${NC}"

while IFS= read -r repo || [[ -n "$repo" ]]; do
    repo="$(echo "$repo" | xargs)"
    [[ -z "$repo" ]] && continue
    [[ "$repo" =~ ^# ]] && continue

    if is_repo_added "$repo"; then
        [[ "$VERBOSITY" != "quiet" ]] &&
            echo -e "⏭ ${GREEN}Repo finns redan:${NC} $repo"
        ((SKIPPED_REPOS++))
        continue
    fi

    echo -e "🔍 Testar repo: $repo"

    if validate_repo "$repo"; then
        add_repo "$repo"
    else
        echo -e "⚠ ${YELLOW}Hoppar över (ingen Release för $UBU_VERSION):${NC} $repo"
        ((SKIPPED_REPOS++))
    fi

done < "$REPO_FILE"


echo -e "\n🔄 ${BLUE}Kör apt update...${NC}"

if [[ "$VERBOSITY" == "quiet" ]]; then
    sudo apt-get update -qq >/dev/null 2>&1 || true
elif [[ "$VERBOSITY" == "debug" ]]; then
    sudo apt-get update
else
    sudo apt-get update -qq || true
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
        [[ "$VERBOSITY" != "quiet" ]] &&
            echo -e "⏭ ${GREEN}Redan installerad:${NC} $pkg"
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

