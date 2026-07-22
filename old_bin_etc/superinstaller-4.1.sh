#!/usr/bin/env bash
#
# Superinstaller 4.1
#
# Anpassad till filerna i ~/my_bin.
#
# Huvudmeny:
#   1) Flytta data
#   2) Installera program
#   3) Utilities
#   q) Avsluta
#
# Viktig ändring i 4.1:
#   Menyn "Flytta data" börjar med de säkerhetskopieringar som bör
#   göras innan packa_to_move körs:
#     - Darktable
#     - Mixxx
#     - RawTherapee
#     - övriga appkonfigurationer
#
# Standardsökväg:
#   ~/my_bin
#
# Alternativ sökväg:
#   MY_BIN_DIR="/annan/sökväg" ./superinstaller-4.1.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="4.1"
MAIN_TITLE="Superinstaller $VERSION"

BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"
APP_PATHS_FILE="$BIN_DIR/etc/app_paths.txt"

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
    local candidate

    for candidate in "$@"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

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
            14 74
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
    if ((status == 0)); then
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
            12 72
        return 0
    fi

    local choice
    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra programmet?" \
            17 74 7 \
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

run_with_dryrun_menu() {
    local title="$1"
    local script="$2"
    shift 2 || true
    local -a base_args=("$@")

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script" \
            12 72
        return 0
    fi

    local choice
    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra?" \
            16 74 6 \
            "1" "Normal körning" \
            "2" "Dry-run – ändra ingenting" \
            "b" "Tillbaka" \
            3>&1 1>&2 2>&3
    ) || return 0

    case "$choice" in
        1) run_script "$script" "$title" "${base_args[@]}" ;;
        2) run_script "$script" "$title – dry-run" "${base_args[@]}" --dry-run ;;
        b) return 0 ;;
    esac
}

app_in_paths_file() {
    local app="$1"

    [[ -f "$APP_PATHS_FILE" ]] || return 1

    awk -v wanted="$app" '
        $1 !~ /^#/ && $1 == wanted && NF >= 2 {
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$APP_PATHS_FILE"
}

run_appconfig_backup() {
    local app="$1"
    local display_name="$2"
    local fallback_path="$3"
    local mode=""

    if [[ ! -f "$BACKUP_APPCONFIG" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte backupverktyget:\n\n$BACKUP_APPCONFIG" \
            12 74
        return 0
    fi

    mode=$(
        whiptail \
            --title "Backup $display_name" \
            --menu "Välj körläge:" \
            17 78 7 \
            "1" "Normal backup" \
            "2" "Dry-run – visa utan att skapa backup" \
            "b" "Tillbaka" \
            3>&1 1>&2 2>&3
    ) || return 0

    [[ "$mode" != "b" ]] || return 0

    local -a args=("$app")

    if ! app_in_paths_file "$app"; then
        if [[ -d "$fallback_path" ]]; then
            args+=("--source=$fallback_path")
        else
            whiptail \
                --title "Konfigurationen hittades inte" \
                --msgbox "Ingen post för '$app' finns i:\n\n$APP_PATHS_FILE\n\noch reservsökvägen finns inte:\n\n$fallback_path\n\nLägg till appen i app_paths.txt eller kontrollera var programmet sparar sin konfiguration." \
                20 82
            return 0
        fi
    fi

    if [[ "$mode" == "2" ]]; then
        args+=("--dry-run")
    fi

    run_script "$BACKUP_APPCONFIG" "Backup $display_name" "${args[@]}"
}

show_move_order() {
    whiptail \
        --title "Rekommenderad ordning före flytt" \
        --msgbox "Kör normalt följande i ordning:\n\n1. Backup Darktable\n2. Backup Mixxx\n3. Backup RawTherapee\n4. Backup övriga programinställningar\n5. Packa data för flytt\n\nStäng gärna programmen innan deras konfiguration säkerhetskopieras.\n\nEfter installation på den nya datorn använder du Packa upp/återställ och därefter återställningsverktygen vid behov." \
        20 82
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

    if ((missing == 0)); then
        output+="Alla konfigurerade filer hittades."
    else
        output+="$missing konfigurerad(e) fil(er) saknas."
    fi

    whiptail \
        --title "Kontroll av scriptsökvägar" \
        --scrolltext \
        --msgbox "$output" \
        28 94
}

show_my_bin() {
    local output

    if [[ ! -d "$BIN_DIR" ]]; then
        whiptail \
            --title "Katalogen saknas" \
            --msgbox "Katalogen finns inte:\n\n$BIN_DIR" \
            11 70
        return 0
    fi

    output="$(find "$BIN_DIR" -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)"

    whiptail \
        --title "Innehåll i $BIN_DIR" \
        --scrolltext \
        --msgbox "${output:-Katalogen är tom.}" \
        28 88
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

# Backup och återställning
BACKUP_APPCONFIG="$BIN_DIR/backup_appconfig-4.0.sh"
RESTORE_APPCONFIG="$BIN_DIR/restore_appconfig-3.3.sh"
BACKUP_DARKTABLE="$BIN_DIR/backup_darktable-5.0.sh"
RESTORE_DARKTABLE="$BIN_DIR/restore_darktable-3.0.sh"

# Utilities
APPIMAGE_DESKTOPIFY="$BIN_DIR/appimage-desktopify5.0.sh"
APPIMAGE_UBUNTU26="$BIN_DIR/ubuntu-26-appimage-max-setup.sh"
APT_UNINSTALL="$BIN_DIR/apt_pkg_uninstall-5.1.sh"
MIGRATE_DARKTABLE="$BIN_DIR/migrate_darktable-6.0.sh"
DARKTABLE_OPENCL="$BIN_DIR/ensure_darktable_opencl-1.0.sh"
SURFACE_TABLET_MODE="$BIN_DIR/surface_tablet_mode-1.0.sh"
PASSWORD_GENERATOR="$BIN_DIR/passwd-gen.sh"
MONTERA_SAMBA="$BIN_DIR/montera samba"

FIX_TIMESTAMPS="$(
    resolve_script \
        "$BIN_DIR/fix_future_to_birthtime.sh" \
        "$BIN_DIR/fix_future_to_birthtime.sh:" \
        || true
)"

# ------------------------------------------------------------
# Kontrollista
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
Backup AppConfig|$BACKUP_APPCONFIG
Restore AppConfig|$RESTORE_APPCONFIG
Backup Darktable|$BACKUP_DARKTABLE
Restore Darktable|$RESTORE_DARKTABLE
AppImage-skrivbordsikoner|$APPIMAGE_DESKTOPIFY
Ubuntu 26 AppImage-förberedelse|$APPIMAGE_UBUNTU26
Avinstallera apt-paket|$APT_UNINSTALL
Migrera Darktable 6.0|$MIGRATE_DARKTABLE
Darktable OpenCL|$DARKTABLE_OPENCL
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
                --menu "Börja med säkerhetskopiorna och packa därefter data:" \
                28 94 18 \
                "0" "Visa rekommenderad ordning" \
                "1" "1. Backup Darktable" \
                "2" "2. Backup Mixxx" \
                "3" "3. Backup RawTherapee" \
                "4" "4. Backup alla programinställningar i app_paths.txt" \
                "5" "5. Packa data för flytt (packa_to_move-5.6.sh)" \
                "6" "Packa upp och återställ på ny dator (packa_upp_move-6.4.sh)" \
                "7" "Återställ programinställningar (restore_appconfig-3.3.sh)" \
                "8" "Återställ Darktable (restore_darktable-3.0.sh)" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            0)
                show_move_order
                ;;
            1)
                run_with_dryrun_menu \
                    "Backup Darktable" \
                    "$BACKUP_DARKTABLE"
                ;;
            2)
                run_appconfig_backup \
                    "mixxx" \
                    "Mixxx" \
                    "$HOME/.mixxx"
                ;;
            3)
                run_appconfig_backup \
                    "rawtherapee" \
                    "RawTherapee" \
                    "$HOME/.config/RawTherapee"
                ;;
            4)
                run_with_dryrun_menu \
                    "Backup alla programinställningar" \
                    "$BACKUP_APPCONFIG"
                ;;
            5)
                run_with_dryrun_menu \
                    "Packa data för flytt" \
                    "$PACKA_DATA"
                ;;
            6)
                run_with_dryrun_menu \
                    "Packa upp och återställ" \
                    "$PACKA_UPP"
                ;;
            7)
                run_script \
                    "$RESTORE_APPCONFIG" \
                    "Återställ programinställningar"
                ;;
            8)
                run_script \
                    "$RESTORE_DARKTABLE" \
                    "Återställ Darktable"
                ;;
            b)
                return 0
                ;;
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
                24 84 14 \
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
# Meny: Utilities
# ------------------------------------------------------------

utilities_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Utilities" \
                --menu "Välj ett verktyg:" \
                28 92 18 \
                "1"  "AppImage: skapa skrivbordsikoner" \
                "2"  "AppImage: förbered Ubuntu 26.04" \
                "3"  "Avinstallera apt-paket" \
                "4"  "Migrera Darktable 6.0" \
                "5"  "Kontrollera/fixa Darktable OpenCL" \
                "6"  "Surface tablet mode" \
                "7"  "Lösenordsgenerator" \
                "8"  "Montera Samba" \
                "9"  "Rätta framtida tidsstämplar" \
                "10" "Kontrollera alla scriptsökvägar" \
                "11" "Visa innehållet i my_bin" \
                "b"  "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                run_script \
                    "$APPIMAGE_DESKTOPIFY" \
                    "AppImage: skapa skrivbordsikoner"
                ;;
            2)
                run_script \
                    "$APPIMAGE_UBUNTU26" \
                    "AppImage: förbered Ubuntu 26.04"
                ;;
            3)
                run_with_mode_menu \
                    "Avinstallera apt-paket" \
                    "$APT_UNINSTALL"
                ;;
            4)
                run_with_dryrun_menu \
                    "Migrera Darktable 6.0" \
                    "$MIGRATE_DARKTABLE"
                ;;
            5)
                run_script \
                    "$DARKTABLE_OPENCL" \
                    "Kontrollera/fixa Darktable OpenCL"
                ;;
            6)
                run_script \
                    "$SURFACE_TABLET_MODE" \
                    "Surface tablet mode"
                ;;
            7)
                run_script \
                    "$PASSWORD_GENERATOR" \
                    "Lösenordsgenerator"
                ;;
            8)
                run_script \
                    "$MONTERA_SAMBA" \
                    "Montera Samba"
                ;;
            9)
                run_script \
                    "$FIX_TIMESTAMPS" \
                    "Rätta framtida tidsstämplar"
                ;;
            10)
                show_script_status
                ;;
            11)
                show_my_bin
                ;;
            b)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Huvudprogram
# ------------------------------------------------------------

require_whiptail

if [[ ! -d "$BIN_DIR" ]]; then
    if whiptail \
        --title "$MAIN_TITLE" \
        --yesno "Katalogen finns inte:\n\n$BIN_DIR\n\nVill du skapa den?" \
        13 74
    then
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
            20 80 10 \
            "1" "Flytta data" \
            "2" "Installera program" \
            "3" "Utilities" \
            "q" "Avsluta" \
            3>&1 1>&2 2>&3
    ) || exit 0

    case "$choice" in
        1) flytta_data_menu ;;
        2) installera_program_menu ;;
        3) utilities_menu ;;
        q) exit 0 ;;
    esac
done
