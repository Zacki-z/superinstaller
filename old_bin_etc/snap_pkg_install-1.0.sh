#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Sökväg till snap-listan
# ----------------------------------------------------------------------
SNAP_FILE="$HOME/my_bin/etc/snaps.txt"

# ----------------------------------------------------------------------
# Loggning
# ----------------------------------------------------------------------
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/snap_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

exec > >(tee -a "$LOGFILE") 2>&1

echo "----------------------------------------------------------"
echo "🚀 Snap-install-wrapper startar"
echo "📄 Snap-fil: $SNAP_FILE"
echo "📄 Loggfil:  $LOGFILE"
echo "----------------------------------------------------------"
echo


# ----------------------------------------------------------------------
# Kontroll av fil
# ----------------------------------------------------------------------
if [[ ! -f "$SNAP_FILE" ]]; then
    echo "❌ Fel: snap-fil saknas:"
    echo "   $SNAP_FILE"
    exit 1
fi


# ----------------------------------------------------------------------
# Funktioner
# ----------------------------------------------------------------------
is_snap_installed() {
    local name="$1"
    snap list "$name" &>/dev/null
}

install_snap() {
    local name="$1"
    shift
    local args=("$@")

    echo "📦 Installerar snap: $name ${args[*]:-}"
    sudo snap install "$name" "${args[@]}"
    echo "✔ Installerad: $name"
    echo
}


# ----------------------------------------------------------------------
# Loop genom snap-fil
# Format:
#   namn [extra flaggor]
# ----------------------------------------------------------------------
while IFS= read -r line; do
    # hoppa över tomma eller kommenterade rader
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
        echo "⏭  Hoppar över (redan installerad): $name"
        continue
    fi

    install_snap "$name" "${args[@]}"

done < "$SNAP_FILE"


# ----------------------------------------------------------------------
# Efteråt: uppdatera alla snaps
# ----------------------------------------------------------------------
echo "🔄 Kör snap refresh ..."
sudo snap refresh
echo "✔ Snap refresh klart."
echo


echo "----------------------------------------------------------"
echo "🎉 Alla snaps installerade och uppdaterade"
echo "📄 Logg sparad i: $LOGFILE"
echo "----------------------------------------------------------"

