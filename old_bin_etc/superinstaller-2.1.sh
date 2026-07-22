#!/bin/bash
set -u

###############################################################################
# SUPERINSTALLER 2.1
# Radiomeny + Checkbox-meny för multipla installationer
###############################################################################

# ===============================
# Sökvägar
# ===============================
APT="$HOME/my_bin/apt_pkg_install-5.1.sh"
SNAP="$HOME/my_bin/snap_install-5.1.sh"
FLATPAK="$HOME/my_bin/flatpak_install-5.1.sh"
APPIMG="$HOME/my_bin/appimage_install-5.1.sh"
PROTON="$HOME/my_bin/proton_install-5.1-no-bridge.sh"

LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"

# ===============================
# Kontrollera whiptail
# ===============================
if ! command -v whiptail >/dev/null; then
    echo "❌ whiptail saknas (installera: sudo apt install whiptail)"
    exit 1
fi

# ===============================
# Funktion: kör ett skript
# ===============================
run_script() {
    local script="$1"
    local mode="$2"

    LOG="$LOGDIR/superinstaller_$(date +%Y%m%d_%H%M%S).log"

    (
        echo "▶ Kör: $script $mode"
        echo "📄 Logg: $LOG"
        echo "--------------------------------------"
        "$script" "$mode"
    ) | tee "$LOG"

    whiptail --title "Klart" --msgbox "Färdigt!\nLogg sparad i:\n$LOG" 12 60
}

# ===============================
# Checkbox-menyn
# ===============================
run_checkbox_menu() {
    CHOICES=$(whiptail --title "Installera flera samtidigt" \
        --checklist "Markera vad du vill installera:" \
        20 70 12 \
        "apt" "APT-installation" OFF \
        "snap" "Snap-installation" OFF \
        "flatpak" "Flatpak-installation" OFF \
        "appimage" "AppImage-installation" OFF \
        "proton" "Proton VPN" OFF \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
        return
    fi

    # CHOICES innehåller t.ex. '"apt" "flatpak"'
    for choice in $CHOICES; do
        case $choice in
            "\"apt\"")
                run_script "$APT" "--normal"
                ;;
            "\"snap\"")
                run_script "$SNAP" "--normal"
                ;;
            "\"flatpak\"")
                run_script "$FLATPAK" "--normal"
                ;;
            "\"appimage\"")
                run_script "$APPIMG" "--normal"
                ;;
            "\"proton\"")
                run_script "$PROTON" "--normal"
                ;;
        esac
    done
}

# ===============================
# Huvudmeny (radiomeny)
# ===============================
while true; do

    MENU_CHOICE=$(whiptail --title "SUPERINSTALLER 2.1" \
        --menu "Välj funktion:" \
        22 70 12 \
        "1" "Installera ALLT (apt + snap + flatpak + appimage + proton)" \
        "2" "Installera flera samtidigt (checkbox-meny)" \
        "3" "Apt-install" \
        "4" "Snap-install" \
        "5" "Flatpak-install" \
        "6" "AppImage-install" \
        "7" "Proton-install" \
        "8" "Dry-run ALLT" \
        "0" "Avsluta" \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
        clear
        exit 0
    fi

    case "$MENU_CHOICE" in

        "1")
            run_script "$APT" "--normal"
            run_script "$SNAP" "--normal"
            run_script "$FLATPAK" "--normal"
            run_script "$APPIMG" "--normal"
            run_script "$PROTON" "--normal"
            ;;

        "2")
            run_checkbox_menu
            ;;

        "3")
            run_script "$APT" "--normal"
            ;;

        "4")
            run_script "$SNAP" "--normal"
            ;;

        "5")
            run_script "$FLATPAK" "--normal"
            ;;

        "6")
            run_script "$APPIMG" "--normal"
            ;;

        "7")
            run_script "$PROTON" "--normal"
            ;;

        "8")
            run_script "$APT" "--dry-run"
            run_script "$SNAP" "--dry-run"
            run_script "$FLATPAK" "--dry-run"
            run_script "$APPIMG" "--dry-run"
            run_script "$PROTON" "--dry-run"
            ;;

        "0")
            clear
            exit 0
            ;;
    esac

done

