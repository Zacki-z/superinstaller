#!/bin/bash
set -u

###############################################################################
# SUPERINSTALLER 1.1 – Med AppImage
###############################################################################

# ===============================
# Färger
# ===============================
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# ===============================
# Paths till delskript
# ===============================
APT="$HOME/my_bin/apt_pkg_install-5.1.sh"
SNAP="$HOME/my_bin/snap_install-5.1.sh"
FLATPAK="$HOME/my_bin/flatpak_install-5.2.sh"
APPIMG="$HOME/my_bin/appimage_install-5.1.sh"
PROTON="$HOME/my_bin/proton_install-5.1.sh"

LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"

# ===============================
# Funktioner
# ===============================
run_script() {
    local script="$1"
    local args="$2"

    echo -e "${BLUE}----------------------------------------------------------"
    echo -e "▶ Kör: $script $args"
    echo -e "----------------------------------------------------------${NC}"

    if [[ ! -x "$script" ]]; then
        echo -e "❌ ${RED}Skript saknas eller är ej körbart:${NC} $script"
        return
    fi

    bash "$script" $args
}

pause() {
    echo
    read -rp "Tryck Enter för att fortsätta..."
}

# ===============================
# Meny-loop
# ===============================
while true; do
    clear
    echo -e "${BLUE}=========================================================="
    echo -e "                SUPERINSTALLER 1.1"
    echo -e "==========================================================${NC}"
    echo
    echo " 1) Installera ALLT"
    echo " 2) Kör apt-install"
    echo " 3) Kör snap-install"
    echo " 4) Kör flatpak-install"
    echo " 5) Kör AppImage-install"
    echo " 6) Kör Proton-install"
    echo " 7) Kör ALLT i dry-run"
    echo " 8) Visa senaste loggar"
    echo " 0) Avsluta"
    echo
    read -rp "Val: " choice

    case "$choice" in

        1)
            run_script "$APT"      "--normal"
            run_script "$SNAP"     "--normal"
            run_script "$FLATPAK"  "--normal"
            run_script "$APPIMG"   "--normal"
            run_script "$PROTON"   "--normal"
            pause
            ;;

        2)
            run_script "$APT" "--normal"
            pause
            ;;

        3)
            run_script "$SNAP" "--normal"
            pause
            ;;

        4)
            run_script "$FLATPAK" "--normal"
            pause
            ;;

        5)
            run_script "$APPIMG" "--normal"
            pause
            ;;

        6)
            run_script "$PROTON" "--normal"
            pause
            ;;

        7)
            run_script "$APT"      "--dry-run"
            run_script "$SNAP"     "--dry-run"
            run_script "$FLATPAK"  "--dry-run"
            run_script "$APPIMG"   "--dry-run"
            run_script "$PROTON"   "--dry-run"
            pause
            ;;

        8)
            echo -e "${BLUE}Senaste loggar:${NC}"
            ls -1t "$LOGDIR" | head -20
            echo
            pause
            ;;

        0)
            echo -e "${GREEN}Avslutar superinstaller.${NC}"
            exit 0
            ;;

        *)
            echo -e "${YELLOW}Ogiltigt val${NC}"
            sleep 1
            ;;
    esac
done

