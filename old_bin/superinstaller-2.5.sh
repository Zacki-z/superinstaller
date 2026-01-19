#!/bin/bash
# superinstaller 2.5
# Huvudmeny:
#   1) Flytta data
#   2) Installera program
#   3) Utilities
#   q) Avsluta

set -Eeuo pipefail

trap 'echo -e "\e[31mEtt fel inträffade (rad $LINENO). Avbryter.\e[0m" >&2' ERR

# ===========================
# Konfig: sökvägar till script
# ===========================
PACKA_UPP="$HOME/my_bin/packa_upp.sh"          # ditt packa_upp.sh
PACKA_DATA="$HOME/my_bin/packa_data.sh"        # ev. framtida packa-data-script
APPIMAGE_INSTALL="$HOME/my_bin/appimage-install.sh"  # ditt appimage-install v5.x

# ===========================
# Hjälpfunktioner
# ===========================
require_whiptail() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "whiptail är inte installerat. Kör t.ex.:"
        echo "  sudo apt install whiptail"
        exit 1
    fi
}

run_script() {
    local script="$1"
    local title="$2"

    if [[ -x "$script" ]]; then
        clear
        echo "▶ Kör: $title"
        echo "   ($script)"
        echo
        "$script"
        echo
        read -rp "Tryck ENTER för att återgå till föregående meny..." _
    else
        whiptail --title "Fel" --msgbox "Hittar inte körbar fil:\n$script" 10 60
    fi
}

# ===========================
# Meny: Flytta data
# ===========================
flytta_data_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Superinstaller – Flytta data" --menu "Välj ett alternativ:" 20 70 10 \
            "1" "Packa data (backup)  [PACKA_DATA]" \
            "2" "Packa upp data       [packa_upp.sh]" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                if [[ -x "$PACKA_DATA" ]]; then
                    run_script "$PACKA_DATA" "Packa data (backup)"
                else
                    whiptail --title "Ej konfigurerad" --msgbox "PACKA_DATA-script saknas:\n$PACKA_DATA\n\nSkapa det eller uppdatera sökvägen i superinstaller 2.5." 12 70
                fi
                ;;
            "2")
                run_script "$PACKA_UPP" "Packa upp data (packa_upp.sh)"
                ;;
            "b")
                return 0
                ;;
        esac
    done
}

# ===========================
# Meny: Installera program
# ===========================
installera_program_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Superinstaller – Installera program" --menu "Välj:" 20 70 10 \
            "1" "Kör AppImage-install (appimage-install.sh)" \
            "2" "Kör Apt-install (apt_pkg_uninstall-5.1.sh)" \
            "3" "Kör Snap-install (snap_pkg_install-5.1.sh)" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                if [[ -x "$APPIMAGE_INSTALL" ]]; then
                    # Fråga om ev. dry-run
                    local sub
                    sub=$(whiptail --title "AppImage-install" --menu "Hur vill du köra?" 15 70 5 \
                        "1" "Normal körning" \
                        "2" "Dry-run (--dry-run)" \
                        "3" "Debug (--debug)" \
                        "b" "Tillbaka" \
                        3>&1 1>&2 2>&3) || continue

                    case "$sub" in
                        "1")
                            run_script "$APPIMAGE_INSTALL" "AppImage-install (normal)"
                            ;;
                        "2")
                            clear
                            echo "▶ Kör: AppImage-install (dry-run)"
                            echo
                            "$APPIMAGE_INSTALL" --dry-run
                            echo
                            read -rp "Tryck ENTER för att återgå till föregående meny..." _
                            ;;
                        "3")
                            clear
                            echo "▶ Kör: AppImage-install (debug)"
                            echo
                            "$APPIMAGE_INSTALL" --debug
                            echo
                            read -rp "Tryck ENTER för att återgå till föregående meny..." _
                            ;;
                        "b")
                            ;;
                    esac
                else
                    whiptail --title "Fel" --msgbox "Hittar inte appimage-install:\n$APPIMAGE_INSTALL" 10 60
                fi
                ;;
            "2")
                whiptail --title "Ej implementerad" --msgbox "Detta menyval är ännu inte implementerat." 10 60
                ;;
            "3")
                whiptail --title "Ej implementerad" --msgbox "Detta menyval är ännu inte implementerat." 10 60
                ;;
            "b")
                return 0
                ;;
        esac
    done
}

# ===========================
# Meny: Utilities
# ===========================
utilities_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Superinstaller – Utilities" --menu "Välj ett verktyg:" 20 70 10 \
            "1" "Packa upp tar-arkiv (packa_upp.sh)" \
            "2" "Utility 2 (framtida)" \
            "3" "Utility 3 (framtida)" \
            "4" "Utility 4 (framtida)" \
            "5" "Utility 5 (framtida)" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                run_script "$PACKA_UPP" "Packa upp data (packa_upp.sh)"
                ;;
            "2")
                whiptail --title "Utility 2" --msgbox "Utility 2 är ännu inte definierad." 10 60
                ;;
            "3")
                whiptail --title "Utility 3" --msgbox "Utility 3 är ännu inte definierad." 10 60
                ;;
            "4")
                whiptail --title "Utility 4" --msgbox "Utility 4 är ännu inte definierad." 10 60
                ;;
            "5")
                whiptail --title "Utility 5" --msgbox "Utility 5 är ännu inte definierad." 10 60
                ;;
            "b")
                return 0
                ;;
        esac
    done
}

# ===========================
# Main
# ===========================
require_whiptail

while true; do
    choice=$(whiptail --title "Superinstaller 2.5" --menu "Välj:" 20 70 10 \
        "1" "Flytta data" \
        "2" "Installera program" \
        "3" "Utilities" \
        "q" "Avsluta" \
        3>&1 1>&2 2>&3) || exit 0

    case "$choice" in
        "1")
            flytta_data_menu
            ;;
        "2")
            installera_program_menu
            ;;
        "3")
            utilities_menu
            ;;
        "q")
            exit 0
            ;;
    esac
done

