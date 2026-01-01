#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------
# Filvägar
# ---------------------------------------------------------
REPO_FILE="$HOME/my_bin/etc/repos.txt"
PACKAGE_FILE="$HOME/my_bin/etc/packages.txt"

LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/aptp_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

exec > >(tee -a "$LOGFILE") 2>&1

echo "---------------------------------------------------------"
echo "🚀 Startar aptp-install"
echo "📄 Repo-fil:    $REPO_FILE"
echo "📄 Paket-fil:   $PACKAGE_FILE"
echo "📄 Loggfil:     $LOGFILE"
echo "---------------------------------------------------------"
echo


# ---------------------------------------------------------
# Kontroll av listfiler
# ---------------------------------------------------------
[[ ! -f "$REPO_FILE" ]] && { echo "❌ Repo-fil saknas"; exit 1; }
[[ ! -f "$PACKAGE_FILE" ]] && { echo "❌ Paket-fil saknas"; exit 1; }


# ---------------------------------------------------------
# Funktioner
# ---------------------------------------------------------
is_repo_added() {
    grep -Rq "$1" /etc/apt/ || return 1
    return 0
}

add_repo() {
    local repo="$1"
    echo "➕ Lägger till repo: $repo"

    sudo add-apt-repository -y "$repo"
}

is_installed() {
    dpkg -s "$1" &>/dev/null
}

install_pkg() {
    local pkg="$1"
    echo "📦 Installerar: $pkg"
    sudo apt-get install -y "$pkg" \
        -o=DPkg::Progress-Fancy=1 \
        -o=quiet=2
    echo "✔ Färdigt: $pkg"
    echo
}


# ---------------------------------------------------------
# 1. Lägg till repos
# ---------------------------------------------------------
echo "🔧 Bearbetar repositories ..."
while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    [[ "$repo" =~ ^# ]] && continue

    if is_repo_added "$repo"; then
        echo "⏭ Repo finns redan: $repo"
        continue
    fi

    add_repo "$repo"

done < "$REPO_FILE"

echo
echo "🔄 Kör apt update ..."
sudo apt-get update -qq
echo "✔ apt update klar"
echo


# ---------------------------------------------------------
# 2. Installera paket
# ---------------------------------------------------------
echo "🔧 Installerar paket ..."
while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    [[ "$pkg" =~ ^# ]] && continue

    if is_installed "$pkg"; then
        echo "⏭ Redan installerad: $pkg"
        continue
    fi

    install_pkg "$pkg"

done < "$PACKAGE_FILE"


echo "---------------------------------------------------------"
echo "🎉 Klart! Alla repos och paket hanterade"
echo "📄 Logg sparad i: $LOGFILE"
echo "---------------------------------------------------------"

