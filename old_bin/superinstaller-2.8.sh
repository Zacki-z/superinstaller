#!/bin/bash
# superinstaller 2.8
# Huvudmeny:
#   1) Flytta data
#   2) Installera program
#   3) Utilities
#   q) Avsluta

set -Eeuo pipefail

trap 'echo -e "\e[31mEtt fel inträffade (rad $LINENO). Avbryter.\e[0m" >&2' ERR

# ===========================
# Basdir & scriptkatalog
# ===========================
# Var scriptet ligger (om du vill använda det senare)
BASE_DIR="$(dirname "$(realpath "$0")")"

# Global scriptkatalog:
# - ändra genom att sätta MY_BIN_DIR i env
#   ex:  MY_BIN_DIR="$HOME/scripts" ./superinstaller-2.8.sh
BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"

# ===========================
# Konfig: sökvägar till script
# ===========================
PACKA_UPP="$BIN_DIR/packa_upp.sh"
PACKA_DATA="$BIN_DIR/packa_data.sh"
APPIMAGE_INSTALL="$BIN_DIR/appimage_install-5.2.sh"
APT_INSTALL="$BIN_DIR/apt_pkg_install-5.1.sh"
SNAP_INSTALL="$BIN_DIR/snap_pkg_install-5.1.sh"
PROTON_INSTALL="$BIN_DIR/deb-downloader-install-1.1.sh"
EXTRA_TOOL2_INSTALL="$BIN_DIR/extra_tool2_install.sh"

# ===========================
# Konfig: menyval & script
# ===========================

# Huvudmeny
MAIN_TITLE="Superinstaller 2.8"
MAIN_PROMPT="Välj:"
MAIN_1_LABEL="Flytta data"
MAIN_2_LABEL="Installera program"
MAIN_3_LABEL="Utilities"
MAIN_Q_LABEL="Avsluta"

# Meny: Flytta data
ENTRY_PACKA_DATA_LABEL="Packa data (backup)"
ENTRY_PACKA_DATA_CMD="$PACKA_DATA"

ENTRY_PACKA_UPP_LABEL="Packa upp data (restore)"
ENTRY_PACKA_UPP_CMD="$PACKA_UPP"

# Meny: Installera program
ENTRY_APPIMAGE_LABEL="Kör AppImage-install (appimage_install-5.2.sh)"
ENTRY_APPIMAGE_CMD="$APPIMAGE_INSTALL"

ENTRY_APT_LABEL="Kör Apt-install (apt_pkg_install-5.1.sh)"
ENTRY_APT_CMD="$APT_INSTALL"

ENTRY_SNAP_LABEL="Kör Snap-install (snap_pkg_install-5.1.sh)"
ENTRY_SNAP_CMD="$SNAP_INSTALL"

ENTRY_PROTON_LABEL="Kör deb-install (deb-downloader-install-1.1.sh)"
ENTRY_PROTON_CMD="$PROTON_INSTALL"

ENTRY_EXTRA_TOOL2_LABEL="Installera Extra-verktyg 2"
ENTRY_EXTRA_TOOL2_CMD="$EXTRA_TOOL2_INSTALL"

# Meny: Utilities – FYRA entries
ENTRY_UTIL_1_LABEL="Desktop iconer för appimage"
ENTRY_UTIL_1_CMD="$BIN_DIR/appimage-desktopify5.0.sh"

ENTRY_UTIL_2_LABEL="fixa felaktiga timestamps"
ENTRY_UTIL_2_CMD="$BIN_DIR/fix_future_to_birthtime.sh"

ENTRY_UTIL_3_LABEL="Backup darktable"
ENTRY_UTIL_3_CMD="$BIN_DIR/bup_darktable-8.0.sh"

ENTRY_UTIL_4_LABEL="Migrera darktable"
ENTRY_UTIL_4_CMD="$BIN_DIR/migrate_darktable-5.0.sh"

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

run_with_mode_menu() {
    local base_title="$1"
    local script="$2"

    if [[ ! -x "$script" ]]; then
        whiptail --title "Fel" --msgbox "Hittar inte script:\n$script" 10 60
        return 0
    fi

    local sub
    sub=$(whiptail --title "$base_title" --menu "Hur vill du köra?" 15 70 5 \
        "1" "Normal körning" \
        "2" "Dry-run (--dry-run)" \
        "3" "Debug (--debug)" \
        "b" "Tillbaka" \
        3>&1 1>&2 2>&3) || return 0

    case "$sub" in
        "1")
            run_script "$script" "$base_title (normal)"
            ;;
        "2")
            clear
            echo "▶ Kör: $base_title (dry-run)"
            echo
            "$script" --dry-run
            echo
            read -rp "Tryck ENTER för att återgå till föregående meny..." _
            ;;
        "3")
            clear
            echo "▶ Kör: $base_title (debug)"
            echo
            "$script" --debug
            echo
            read -rp "Tryck ENTER för att återgå till föregående meny..." _
            ;;
        "b")
            ;;
    esac
}

# ===========================
# Meny: Flytta data
# ===========================
flytta_data_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Superinstaller – Flytta data" --menu "Välj ett alternativ:" 20 70 10 \
            "1" "$ENTRY_PACKA_DATA_LABEL" \
            "2" "$ENTRY_PACKA_UPP_LABEL" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                run_script "$ENTRY_PACKA_DATA_CMD" "$ENTRY_PACKA_DATA_LABEL"
                ;;
            "2")
                run_script "$ENTRY_PACKA_UPP_CMD" "$ENTRY_PACKA_UPP_LABEL"
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
            "1" "$ENTRY_APPIMAGE_LABEL" \
            "2" "$ENTRY_APT_LABEL" \
            "3" "$ENTRY_SNAP_LABEL" \
            "4" "$ENTRY_PROTON_LABEL" \
            "5" "$ENTRY_EXTRA_TOOL2_LABEL" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                run_with_mode_menu "AppImage-install" "$ENTRY_APPIMAGE_CMD"
                ;;
            "2")
                run_with_mode_menu "Apt-install" "$ENTRY_APT_CMD"
                ;;
            "3")
                run_with_mode_menu "Snap-install" "$ENTRY_SNAP_CMD"
                ;;
            "4")
                run_with_mode_menu "Proton-install" "$ENTRY_PROTON_CMD"
                ;;
            "5")
                if [[ -x "$ENTRY_EXTRA_TOOL2_CMD" ]]; then
                    run_script "$ENTRY_EXTRA_TOOL2_CMD" "$ENTRY_EXTRA_TOOL2_LABEL"
                else
                    whiptail --title "Ej konfigurerad" --msgbox "Extra-verktyg 2 är inte konfigurerat ännu.
Förväntat script:
$ENTRY_EXTRA_TOOL2_CMD" 10 70
                fi
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
            "1" "$ENTRY_UTIL_1_LABEL" \
            "2" "$ENTRY_UTIL_2_LABEL" \
            "3" "$ENTRY_UTIL_3_LABEL" \
            "4" "$ENTRY_UTIL_4_LABEL" \
            "b" "Tillbaka till huvudmenyn" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            "1")
                run_script "$ENTRY_UTIL_1_CMD" "$ENTRY_UTIL_1_LABEL"
                ;;
            "2")
                run_script "$ENTRY_UTIL_2_CMD" "$ENTRY_UTIL_2_LABEL"
                ;;
            "3")
                run_script "$ENTRY_UTIL_3_CMD" "$ENTRY_UTIL_3_LABEL"
                ;;
            "4")
                run_script "$ENTRY_UTIL_4_CMD" "$ENTRY_UTIL_4_LABEL"
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
    choice=$(whiptail --title "$MAIN_TITLE" --menu "$MAIN_PROMPT" 20 70 10 \
        "1" "$MAIN_1_LABEL" \
        "2" "$MAIN_2_LABEL" \
        "3" "$MAIN_3_LABEL" \
        "q" "$MAIN_Q_LABEL" \
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

