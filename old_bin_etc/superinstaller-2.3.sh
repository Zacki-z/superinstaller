#!/bin/bash
set -u

###############################################################################
# SUPERINSTALLER 2.3
# Whiptail + Run-Mode Prompt + Checkbox + Progress-bar (gauge)
###############################################################################

# ===============================
# Sökvägar till delskripten
# ===============================
APT="$HOME/my_bin/apt_pkg_install-5.1.sh"
SNAP="$HOME/my_bin/snap_install-5.1.sh"
FLATPAK="$HOME/my_bin/flatpak_install-5.2.sh"
APPIMG="$HOME/my_bin/appimage_install-5.1.sh"
PROTON="$HOME/my_bin/proton_install-5.1-no-bridge.sh"

LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"

# ===============================
# Kontrollera whiptail
# ===============================
if ! command -v whiptail &>/dev/null; then
    echo "❌ whiptail saknas. Installera med:"
    echo "sudo apt install whiptail"
    exit 1
fi

# ===============================
# Fråga om körläge (normal / dry-run)
# ===============================
ask_run_mode() {
    MODE=$(whiptail --title "Körläge" \
        --menu "Välj körläge:" \
        15 50 4 \
        "normal" "Kör riktig installation" \
        "dry-run" "Simulera (ingen installation)" \
        3>&1 1>&2 2>&3)

    echo "$MODE"
}

# ===============================
# Kör ett enskilt skript (utan gauge)
# ===============================
run_script() {
    local script="$1"
    local mode="$2"

    if [[ ! -x "$script" ]]; then
        whiptail --title "Fel" --msgbox "Skript ej körbart:\n$script" 10 60
        return
    fi

    local LOG="$LOGDIR/superinstaller_$(date +%Y%m%d_%H%M%S).log"

    (
        echo "▶ Kör: $script $mode"
        echo "📄 Logg: $LOG"
        echo "-------------------------------------------"
        "$script" "$mode"
    ) | tee "$LOG"

    whiptail --title "Klar" --msgbox "Färdigt!\nLogg sparad i:\n$LOG" 12 60
}

# ===============================
# Kör ALLT med progress-bar (gauge)
# ===============================
run_all_with_gauge() {
    local mode="$1"
    local LOG="$LOGDIR/superinstaller_all_$(date +%Y%m%d_%H%M%S).log"

    {
        echo "0"
        echo "# Startar installationer (läge: $mode)..."
        sleep 1

        echo "5"
        echo "# Kör APT ($mode)..."
        "$APT" "--$mode" >>"$LOG" 2>&1
        echo "25"
        echo "# APT klar"

        echo "30"
        echo "# Kör SNAP ($mode)..."
        "$SNAP" "--$mode" >>"$LOG" 2>&1
        echo "50"
        echo "# SNAP klar"

        echo "55"
        echo "# Kör FLATPAK ($mode)..."
        "$FLATPAK" "--$mode" >>"$LOG" 2>&1
        echo "75"
        echo "# FLATPAK klar"

        echo "80"
        echo "# Kör APPIMAGE ($mode)..."
        "$APPIMG" "--$mode" >>"$LOG" 2>&1
        echo "90"
        echo "# APPIMAGE klar"

        echo "95"
        echo "# Kör PROTON ($mode)..."
        "$PROTON" "--$mode" >>"$LOG" 2>&1
        echo "100"
        echo "# Alla installationer klara!"
        sleep 1
    } | whiptail --title "Installera ALLT ($mode)" \
                 --gauge "Förbereder..." 20 70 0

    whiptail --title "ALLT klart" \
             --msgbox "Alla installationer körda.\nLäge: $mode\nLogg:\n$LOG" 12 70
}

# ===============================
# Checkbox-menyn — flera installationer
# ===============================
run_checkbox_menu() {

    CHOICES=$(whiptail --title "Installera flera" \
        --checklist "Markera vad du vill installera:" \
        22 70 14 \
        "apt"      "APT-installation" OFF \
        "snap"     "Snap-installation" OFF \
        "flatpak"  "Flatpak-installation" OFF \
        "appimage" "AppImage-installation" OFF \
        "proton"   "Proton VPN-installation" OFF \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return

    RUNMODE=$(ask_run_mode)

    for choice in $CHOICES; do
        case "$choice" in
            "\"apt\"")      run_script "$APT" "--$RUNMODE" ;;
            "\"snap\"")     run_script "$SNAP" "--$RUNMODE" ;;
            "\"flatpak\"")  run_script "$FLATPAK" "--$RUNMODE" ;;
            "\"appimage\"") run_script "$APPIMG" "--$RUNMODE" ;;
            "\"proton\"")   run_script "$PROTON" "--$RUNMODE" ;;
        esac
    done
}

# ===============================
# Huvudmeny (radiomeny)
# ===============================
while true; do

    CHOICE=$(whiptail --title "SUPERINSTALLER 2.3" \
        --menu "Välj funktion:" 22 70 12 \
        "1" "Installera ALLT (med progress-bar)" \
        "2" "Installera flera samtidigt (checkbox)" \
        "3" "APT-install" \
        "4" "Snap-install" \
        "5" "Flatpak-install" \
        "6" "AppImage-install" \
        "7" "Proton-install" \
        "8" "Dry-run ALLT (med progress-bar)" \
        "0" "Avsluta" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && clear && exit 0

    case "$CHOICE" in

        "1")
            MODE=$(ask_run_mode)
            run_all_with_gauge "$MODE"
            ;;

        "2")
            run_checkbox_menu
            ;;

        "3")
            MODE=$(ask_run_mode)
            run_script "$APT" "--$MODE"
            ;;

        "4")
            MODE=$(ask_run_mode)
            run_script "$SNAP" "--$MODE"
            ;;

        "5")
            MODE=$(ask_run_mode)
            run_script "$FLATPAK" "--$MODE"
            ;;

        "6")
            MODE=$(ask_run_mode)
            run_script "$APPIMG" "--$MODE"
            ;;

        "7")
            MODE=$(ask_run_mode)
            run_script "$PROTON" "--$MODE"
            ;;

        "8")
            run_all_with_gauge "dry-run"
            ;;

        "0")
            clear
            exit 0
            ;;
    esac
done

