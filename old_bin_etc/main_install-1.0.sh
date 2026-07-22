#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------
# Inställningar
# ---------------------------------------------------------

LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/installer_$(date +%Y%m%d_%H%M%S).log"

SCRIPT_DIR="$HOME/scripts"
SCRIPT1="$SCRIPT_DIR/setup.sh"
SCRIPT2="$SCRIPT_DIR/install.sh"
SCRIPT3="$SCRIPT_DIR/cleanup.sh"

# ---------------------------------------------------------
# Initiera loggning
# ---------------------------------------------------------

mkdir -p "$LOGDIR"

# Skickar både stdout + stderr till logg och terminal
exec > >(tee -a "$LOGFILE") 2>&1

echo "----------------------------------------------------"
echo "🚀 Startar huvudscript ($(date))"
echo "Loggfil: $LOGFILE"
echo "----------------------------------------------------"

# ---------------------------------------------------------
# Funktion för att köra script med loggutskrift
# ---------------------------------------------------------

run_script() {
    local script="$1"
    echo "▶ Kör: $script"
    bash "$script"
    echo "✔ Klart: $script"
    echo
}

# ---------------------------------------------------------
# Kör scripts
# ---------------------------------------------------------

run_script "$SCRIPT1"
run_script "$SCRIPT2"
run_script "$SCRIPT3"

echo "🎉 Alla script körda utan fel | $(date)"
echo "Logg finns på: $LOGFILE"

