#!/usr/bin/env bash
#
# Superinstaller 4.0
#
# Anpassad till filerna i ~/my_bin.
#
# Huvudmeny:
#   1) Flytta data
#   2) Installera program
#   3) Utilities
#   q) Avsluta
#
# Standardsökväg:
#   ~/my_bin
#
# Alternativ sökväg:
#   MY_BIN_DIR="/annan/sökväg" ./superinstaller-4.0.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="4.0"
MAIN_TITLE="Superinstaller $VERSION"

# Standardsökvägen är användarens my_bin-katalog.
BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"

# Färger för terminalutskrifter.
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
RESET=$'\e[0m'

trap 'printf "%sEtt oväntat fel inträffade på rad %s.%s\n" "$RED" "$LINENO" "$RESET" >&2' ERR

# ------------------------------------------------------------
# Hjälpfunktioner
# ------------------------------------------------------------

require_whiptail() {
    if command -v whiptail >/dev/null 2>&1; then
        return 0
    fi

    printf '%swhiptail är inte installerat.%s\n' "$YELLOW" "$RESET"
    printf 'Installerar whiptail...\n'

    sudo apt update
    sudo apt install -y whiptail
}

pause_terminal() {
    echo
    read -r -p "Tryck ENTER för att återgå till menyn..." _
}

resolve_script() {
    # Skriver ut den första fil som finns av de angivna alternativen.
    # Detta används bland annat för filen som tidigare råkat få kolon sist.
    local candidate

    for candidate in "$@"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    # Returnera det första namnet även när inget hittades,
    # så att felmeddelandet visar den avsedda sökvägen.
    printf '%s\n' "$1"
    return 1
}

run_command_file() {
    local script="$1"
    shift || true

    if [[ -x "$script" ]]; then
        "$script" "$@"
    elif [[ -f "$script" ]]; then
        bash "$script" "$@"
    else
        return 127
    fi
}

run_script() {
    local script="$1"
    local title="$2"
    shift 2 || true

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script\n\nKontrollera innehållet i:\n$BIN_DIR" \
            14 72
        return 0
    fi

    clear
    printf '%s▶ Kör: %s%s\n' "$BLUE" "$title" "$RESET"
    printf '   %s\n\n' "$script"

    set +e
    run_command_file "$script" "$@"
    local status=$?
    set -e

    echo
    if (( status == 0 )); then
        printf '%sKlart utan rapporterat fel.%s\n' "$GREEN" "$RESET"
    else
        printf '%sProgrammet avslutades med felkod %d.%s\n' \
            "$RED" "$status" "$RESET"
    fi

    pause_terminal
}

run_with_mode_menu() {
    local title="$1"
    local script="$2"

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script" \
            12 70
        return 0
    fi

    local choice
    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra programmet?" \
            17 72 7 \
            "1" "Normal körning" \
            "2" "Dry-run (--dry-run)" \
            "3" "Debug (--debug)" \
            "b" "Tillbaka" \
            3>&1 1>&2 2>&3
    ) || return 0

    case "$choice" in
        1) run_script "$script" "$title" ;;
        2) run_script "$script" "$title – dry-run" --dry-run ;;
        3) run_script "$script" "$title – debug" --debug ;;
        b) return 0 ;;
    esac
}

show_script_status() {
    local output=""
    local missing=0
    local label
    local path

    while IFS='|' read -r label path; do
        [[ -n "$label" ]] || continue

        if [[ -f "$path" ]]; then
            output+="OK      $label"$'\n'
            output+="        $path"$'\n\n'
        else
            output+="SAKNAS  $label"$'\n'
            output+="        $path"$'\n\n'
            ((missing += 1))
        fi
    done < <(all_script_entries)

    if (( missing == 0 )); then
        output+="Alla konfigurerade filer hittades."
    else
        output+="$missing konfigurerad(e) fil(er) saknas."
    fi

    whiptail \
        --title "Kontroll av scriptsökvägar" \
        --scrolltext \
        --msgbox "$output" \
        28 92
}

show_my_bin() {
    local output

    if [[ ! -d "$BIN_DIR" ]]; then
        whiptail \
            --title "Katalogen saknas" \
            --msgbox "Katalogen finns inte:\n\n$BIN_DIR" \
            11 68
        return 0
    fi

    output="$(find "$BIN_DIR" -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)"

    whiptail \
        --title "Innehåll i $BIN_DIR" \
        --scrolltext \
        --msgbox "${output:-Katalogen är tom.}" \
        28 86
}

# ------------------------------------------------------------
# Faktiska sökvägar i ~/my_bin
# ------------------------------------------------------------

# Flytta data
PACKA_DATA="$BIN_DIR/packa_to_move-5.6.sh"
PACKA_UPP="$BIN_DIR/packa_upp_move-6.4.sh"

# Installera program
APPIMAGE_INSTALL="$BIN_DIR/appimage_install-5.2.sh"
FLATPAK_INSTALL="$BIN_DIR/flatpak_install-5.2.sh"
SNAP_INSTALL="$BIN_DIR/snap_pkg_install-5.1.sh"
DEB_INSTALL="$BIN_DIR/deb-downloader-install-1.1.sh"
PROTON_INSTALL="$BIN_DIR/proton_install-5.1.sh"
INSTALLERA_PROTON="$BIN_DIR/Installera-proton-1.0.sh"
MAIN_INSTALL="$BIN_DIR/main_install-1.0.sh"

# Utilities
APPIMAGE_DESKTOPIFY="$BIN_DIR/appimage-desktopify5.0.sh"
APPIMAGE_UBUNTU26="$BIN_DIR/ubuntu-26-appimage-max-setup.sh"
APT_UNINSTALL="$BIN_DIR/apt_pkg_uninstall-5.1.sh"
BACKUP_APPCONFIG="$BIN_DIR/backup_appconfig-4.0.sh"
RESTORE_APPCONFIG="$BIN_DIR/restore_appconfig-3.3.sh"
BACKUP_DARKTABLE="$BIN_DIR/backup_darktable-5.0.sh"
RESTORE_DARKTABLE="$BIN_DIR/restore_darktable-3.0.sh"
MIGRATE_DARKTABLE="$BIN_DIR/migrate_darktable-5.0.sh"
MIGRATE_DARKTABLE_OLD="$BIN_DIR/migrate_darktable.sh"
DARKTABLE_TOOLS="$BIN_DIR/darktable_tools-1.0.sh"
DARKTABLE_OPENCL="$BIN_DIR/ensure_darktable_opencl-1.0.sh"
DARKTABLE_START="$BIN_DIR/dt-start.sh"
PROTON_DARKTABLE="$BIN_DIR/proton_darktable-3.0.sh"
SURFACE_TABLET_MODE="$BIN_DIR/surface_tablet_mode-1.0.sh"
PASSWORD_GENERATOR="$BIN_DIR/passwd-gen.sh"
MONTERA_SAMBA="$BIN_DIR/montera samba"

# Filen har i listan ett felaktigt kolon sist. Version 4.0 accepterar båda namnen.
FIX_TIMESTAMPS="$(
    resolve_script \
        "$BIN_DIR/fix_future_to_birthtime.sh" \
        "$BIN_DIR/fix_future_to_birthtime.sh:" \
        || true
)"

# ------------------------------------------------------------
# Fullständig kontrollista
# Format: etikett|sökväg
# ------------------------------------------------------------

all_script_entries() {
    cat <<EOF
Packa data|$PACKA_DATA
Packa upp data|$PACKA_UPP
AppImage-installation|$APPIMAGE_INSTALL
Flatpak-installation|$FLATPAK_INSTALL
Snap-installation|$SNAP_INSTALL
Deb-nedladdning och installation|$DEB_INSTALL
Proton-installation 5.1|$PROTON_INSTALL
Installera Proton 1.0|$INSTALLERA_PROTON
Huvudinstallation|$MAIN_INSTALL
AppImage-skrivbordsikoner|$APPIMAGE_DESKTOPIFY
Ubuntu 26 AppImage-förberedelse|$APPIMAGE_UBUNTU26
Avinstallera apt-paket|$APT_UNINSTALL
Backup AppConfig|$BACKUP_APPCONFIG
Restore AppConfig|$RESTORE_APPCONFIG
Backup Darktable|$BACKUP_DARKTABLE
Restore Darktable|$RESTORE_DARKTABLE
Migrera Darktable 5.0|$MIGRATE_DARKTABLE
Migrera Darktable äldre version|$MIGRATE_DARKTABLE_OLD
Darktable Tools|$DARKTABLE_TOOLS
Darktable OpenCL|$DARKTABLE_OPENCL
Starta Darktable|$DARKTABLE_START
Proton Darktable|$PROTON_DARKTABLE
Surface tablet mode|$SURFACE_TABLET_MODE
Lösenordsgenerator|$PASSWORD_GENERATOR
Montera Samba|$MONTERA_SAMBA
Rätta framtida tidsstämplar|$FIX_TIMESTAMPS
EOF
}

# ------------------------------------------------------------
# Meny: Flytta data
# ------------------------------------------------------------

flytta_data_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Flytta data" \
                --menu "Välj ett alternativ:" \
                18 76 8 \
                "1" "Packa data för flytt/backup (packa_to_move-5.6.sh)" \
                "2" "Packa upp och återställ (packa_upp_move-6.4.sh)" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_script "$PACKA_DATA" "Packa data för flytt/backup" ;;
            2) run_script "$PACKA_UPP" "Packa upp och återställ" ;;
            b) return 0 ;;
        esac
    done
}

# ------------------------------------------------------------
# Meny: Installera program
# ------------------------------------------------------------

installera_program_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Installera program" \
                --menu "Välj installationsverktyg:" \
                24 82 14 \
                "1" "AppImage-installation (appimage_install-5.2.sh)" \
                "2" "Flatpak-installation (flatpak_install-5.2.sh)" \
                "3" "Snap-installation (snap_pkg_install-5.1.sh)" \
                "4" "Hämta och installera deb (deb-downloader-install-1.1.sh)" \
                "5" "Proton-installation (proton_install-5.1.sh)" \
                "6" "Installera Proton (Installera-proton-1.0.sh)" \
                "7" "Huvudinstallation (main_install-1.0.sh)" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_with_mode_menu "AppImage-installation" "$APPIMAGE_INSTALL" ;;
            2) run_with_mode_menu "Flatpak-installation" "$FLATPAK_INSTALL" ;;
            3) run_with_mode_menu "Snap-installation" "$SNAP_INSTALL" ;;
            4) run_with_mode_menu "Deb-nedladdning och installation" "$DEB_INSTALL" ;;
            5) run_with_mode_menu "Proton-installation 5.1" "$PROTON_INSTALL" ;;
            6) run_script "$INSTALLERA_PROTON" "Installera Proton 1.0" ;;
            7) run_script "$MAIN_INSTALL" "Huvudinstallation" ;;
            b) return 0 ;;
        esac
    done
}

# ------------------------------------------------------------
# Meny: Utilities, sida 1
# ------------------------------------------------------------

utilities_menu_page_1() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Utilities 1/2" \
                --menu "Välj ett verktyg:" \
                27 88 18 \
                "1"  "AppImage: skapa skrivbordsikoner" \
                "2"  "AppImage: förbered Ubuntu 26.04" \
                "3"  "Avinstallera apt-paket" \
                "4"  "Backup AppConfig" \
                "5"  "Restore AppConfig" \
                "6"  "Backup Darktable 5.0" \
                "7"  "Restore Darktable 3.0" \
                "8"  "Migrera Darktable 5.0" \
                "9"  "Migrera Darktable – äldre script" \
                "10" "Darktable Tools-meny" \
                "11" "Fix Darktable OpenCL" \
                "12" "Starta Darktable" \
                "n"  "Nästa sida" \
                "b"  "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)  run_script "$APPIMAGE_DESKTOPIFY" "AppImage: skapa skrivbordsikoner" ;;
            2)  run_script "$APPIMAGE_UBUNTU26" "AppImage: förbered Ubuntu 26.04" ;;
            3)  run_with_mode_menu "Avinstallera apt-paket" "$APT_UNINSTALL" ;;
            4)  run_script "$BACKUP_APPCONFIG" "Backup AppConfig" ;;
            5)  run_script "$RESTORE_APPCONFIG" "Restore AppConfig" ;;
            6)  run_script "$BACKUP_DARKTABLE" "Backup Darktable 5.0" ;;
            7)  run_script "$RESTORE_DARKTABLE" "Restore Darktable 3.0" ;;
            8)  run_script "$MIGRATE_DARKTABLE" "Migrera Darktable 5.0" ;;
            9)  run_script "$MIGRATE_DARKTABLE_OLD" "Migrera Darktable – äldre script" ;;
            10) run_script "$DARKTABLE_TOOLS" "Darktable Tools-meny" ;;
            11) run_script "$DARKTABLE_OPENCL" "Fix Darktable OpenCL" ;;
            12) run_script "$DARKTABLE_START" "Starta Darktable" ;;
            n)  utilities_menu_page_2 ;;
            b)  return 0 ;;
        esac
    done
}

# ------------------------------------------------------------
# Meny: Utilities, sida 2
# ------------------------------------------------------------

utilities_menu_page_2() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Utilities 2/2" \
                --menu "Välj ett verktyg:" \
                25 88 16 \
                "13" "Proton Darktable 3.0" \
                "14" "Surface tablet mode" \
                "15" "Lösenordsgenerator" \
                "16" "Montera Samba" \
                "17" "Rätta framtida tidsstämplar" \
                "18" "Kontrollera alla scriptsökvägar" \
                "19" "Visa innehållet i my_bin" \
                "p"  "Föregående sida" \
                "b"  "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            13) run_script "$PROTON_DARKTABLE" "Proton Darktable 3.0" ;;
            14) run_script "$SURFACE_TABLET_MODE" "Surface tablet mode" ;;
            15) run_script "$PASSWORD_GENERATOR" "Lösenordsgenerator" ;;
            16) run_script "$MONTERA_SAMBA" "Montera Samba" ;;
            17) run_script "$FIX_TIMESTAMPS" "Rätta framtida tidsstämplar" ;;
            18) show_script_status ;;
            19) show_my_bin ;;
            p)  return 0 ;;
            b)  return 0 ;;
        esac
    done
}

# ------------------------------------------------------------
# Huvudprogram
# ------------------------------------------------------------

require_whiptail

if [[ ! -d "$BIN_DIR" ]]; then
    whiptail \
        --title "$MAIN_TITLE" \
        --yesno "Katalogen finns inte:\n\n$BIN_DIR\n\nVill du skapa den?" \
        13 72

    if [[ $? -eq 0 ]]; then
        mkdir -p "$BIN_DIR"
    else
        exit 1
    fi
fi

while true; do
    choice=$(
        whiptail \
            --title "$MAIN_TITLE" \
            --menu "Scriptkatalog: $BIN_DIR\n\nVälj:" \
            20 78 10 \
            "1" "Flytta data" \
            "2" "Installera program" \
            "3" "Utilities" \
            "q" "Avsluta" \
            3>&1 1>&2 2>&3
    ) || exit 0

    case "$choice" in
        1) flytta_data_menu ;;
        2) installera_program_menu ;;
        3) utilities_menu_page_1 ;;
        q) exit 0 ;;
    esac
done
