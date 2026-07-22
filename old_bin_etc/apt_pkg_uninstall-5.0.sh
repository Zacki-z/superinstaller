#!/bin/bash
set -euo pipefail

###############################################################################
# aptp-uninstall v5 — Full Stabilitetslager
# Tar bort repos + paket som finns i samma listor som aptp-install v5
###############################################################################

# ===============================
# Verbosity & Dry-run
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
if [[ "$VERBOSITY" == "debug" ]]; then
    exec 2>&1 | tee -a "$LOGFILE"
else
    exec > >(tee -a "$LOGFILE") 2>&1
fi

echo -e "${BLUE}========================================================="
echo -e "🗑️ aptp-uninstall v5 (Stable Edition)"
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
# Stabilitetslager
# ===============================
safe_run() {
    set +e
    "$@"
    local STATUS=$?
    set -e
    return $STATUS
}

# ===============================
# Repo/Tilläggsdetektering
# ===============================
remove_repo() {
    local repo="$1"

    echo -e "🗑️  Tar bort repo: ${YELLOW}$repo${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle ta bort repo: $repo"
        return
    fi

    # Ta bort .list filer
    FILES=$(grep -RslF "$repo" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true)

    if [[ -z "$FILES" ]]; then
        echo -e "⏭ Repo hittades inte i systemet: $repo"
        ((SKIPPED_REPOS++))
        return
    fi

    for f in $FILES; do
        echo -e "   🗑️  Tar bort fil: $f"
        safe_run sudo rm -f "$f"
    done

    ((REMOVED_REPOS++))
}

is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

remove_pkg() {
    local pkg="$1"

    echo -e "🗑️  Tar bort paket: ${BLUE}$pkg${NC}"

    if [[ "$DRYRUN" == true ]]; then
        echo -e "   🧪 (dry-run) Skulle köra: apt remove $pkg"
        return
    fi

    if ! is_installed "$pkg"; then
        echo -e "⏭ Paket ej installerat: $pkg"
        ((SKIPPED_PACKAGES++))
        return
    fi

    if [[ "$VERBOSITY" == "quiet" ]]; then
        safe_run sudo apt-get remove -y "$pkg" >/dev/null 2>&1
    elif [[ "$VERBOSITY" == "debug" ]]; then
        safe_run sudo apt-get remove -y "$pkg"
    else
        safe_run sudo apt-get remove -y "$pkg" -o=DPkg::Progress-Fancy=1 -o=quiet=2
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "✔ ${GREEN}Paket borttaget:${NC} $pkg"
        ((REMOVED_PACKAGES++))
    else
        echo -e "❌ ${RED}Kunde inte ta bort:${NC} $pkg"
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

    # hoppa över komponenter
    if [[ "$repo" =~ ^(universe|multiverse|restricted|main)$ ]]; then
        echo -e "⏭ Hoppar över komponent: $repo"
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
    echo "   🧪 (dry-run) Skulle köra: apt-get update"
else
    safe_run sudo apt-get update -qq
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

