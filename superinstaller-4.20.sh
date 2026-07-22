#!/usr/bin/env bash
#
# Superinstaller 4.20
#
# Uppdateringar:
#   - Darktable-backup:  backup_darktable-5.1.sh
#   - Darktable-restore: restore_darktable-1.0.sh
#   - Darktable-migrering: migrate_darktable-6.2.sh
#   - Restore och migrering kan köras normalt eller som dry-run
#     direkt från Utilities.
#
# Standardsökväg:
#   ~/my_bin
#
# Alternativ sökväg:
#   MY_BIN_DIR="/annan/sökväg" ./superinstaller-4.19.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="4.20"
MAIN_TITLE="Superinstaller $VERSION"

BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"
APP_PATHS_FILE="$BIN_DIR/etc/app_paths.txt"
APPCONFIG_BACKUP_DIR="$HOME/bup_appl_config"
DARKTABLE_BACKUP_DIR="$HOME/bup_darktable"
PREFLIGHT_LOG_DIR="$HOME/.local/state/superinstaller"

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

    # Returnera förstahandsnamnet även om filen saknas.
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
            --msgbox "Hittar inte filen:\n\n$script\n\nKontrollera att filen ligger i:\n$BIN_DIR" \
            15 78
        return 0
    fi

    clear
    printf '%s▶ Kör: %s%s\n' "$BLUE" "$title" "$RESET"
    printf '   Script: %s\n' "$script"

    if (($# > 0)); then
        printf '   Argument:'
        printf ' %q' "$@"
        printf '\n'
    fi
    echo

    local status
    if run_command_file "$script" "$@"; then
        status=0
    else
        status=$?
    fi

    echo
    if ((status == 0)); then
        printf '%sKlart utan rapporterat fel.%s\n' "$GREEN" "$RESET"
    else
        printf '%sProgrammet avslutades med felkod %d.%s\n' \
            "$RED" "$status" "$RESET"
    fi

    pause_terminal
}

run_with_dryrun_menu() {
    local title="$1"
    local script="$2"
    shift 2 || true
    local -a base_args=("$@")
    local choice

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script" \
            12 74
        return 0
    fi

    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra?" \
            16 78 6 \
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

run_with_mode_menu() {
    local title="$1"
    local script="$2"
    local choice

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script" \
            12 74
        return 0
    fi

    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra?" \
            17 78 7 \
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

show_scroll_message() {
    local title="$1"
    local content="$2"
    local rows cols

    rows="$(tput lines 2>/dev/null || printf '30')"
    cols="$(tput cols 2>/dev/null || printf '100')"

    ((rows > 34)) && rows=34
    ((cols > 105)) && cols=105
    ((rows < 12)) && rows=12
    ((cols < 50)) && cols=50

    whiptail \
        --title "$title" \
        --scrolltext \
        --ok-button "Tillbaka" \
        --msgbox "$content" \
        "$rows" "$cols" || true
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
    local mode
    local -a args=("$app")

    if [[ ! -f "$BACKUP_APPCONFIG" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte backupverktyget:\n\n$BACKUP_APPCONFIG" \
            12 76
        return 0
    fi

    mode=$(
        whiptail \
            --title "Backup $display_name" \
            --menu "Välj körläge:" \
            17 80 7 \
            "1" "Normal backup" \
            "2" "Dry-run – visa utan att skapa backup" \
            "b" "Tillbaka" \
            3>&1 1>&2 2>&3
    ) || return 0

    [[ "$mode" != "b" ]] || return 0

    if ! app_in_paths_file "$app"; then
        if [[ -d "$fallback_path" ]]; then
            args+=("--source=$fallback_path")
        else
            whiptail \
                --title "Konfigurationen hittades inte" \
                --msgbox "Ingen post för '$app' finns i:\n\n$APP_PATHS_FILE\n\noch reservsökvägen finns inte:\n\n$fallback_path" \
                18 82
            return 0
        fi
    fi

    [[ "$mode" != "2" ]] || args+=("--dry-run")
    run_script "$BACKUP_APPCONFIG" "Backup $display_name" "${args[@]}"
}

valid_darktable_config() {
    local dir="$1"

    [[ -d "$dir" &&
       -f "$dir/darktablerc" &&
       -f "$dir/library.db" &&
       -f "$dir/data.db" ]]
}

find_darktable_source() {
    local revision=""

    # Snap: Darktables huvudfiler ligger direkt i current/revisionskatalogen.
    if valid_darktable_config "$HOME/snap/darktable/current"; then
        printf '%s\n' "$HOME/snap/darktable/current"
        return 0
    fi

    if [[ -d "$HOME/snap/darktable" ]]; then
        revision="$(
            find "$HOME/snap/darktable" \
                -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null |
            awk '/^[0-9]+$/' |
            sort -n |
            tail -n 1
        )"

        if [[ -n "$revision" ]] &&
           valid_darktable_config "$HOME/snap/darktable/$revision"; then
            printf '%s\n' "$HOME/snap/darktable/$revision"
            return 0
        fi
    fi

    if valid_darktable_config \
        "$HOME/.var/app/org.darktable.Darktable/config/darktable"; then
        printf '%s\n' \
            "$HOME/.var/app/org.darktable.Darktable/config/darktable"
        return 0
    fi

    if valid_darktable_config "$HOME/.config/darktable"; then
        printf '%s\n' "$HOME/.config/darktable"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Faktiska sökvägar i ~/my_bin
# ------------------------------------------------------------

# Flytta data – använd senaste kända version och äldre reservnamn.
PACKA_DATA="$(
    resolve_script \
        "$BIN_DIR/packa_to_move-5.9.sh" \
        "$BIN_DIR/packa_to_move-5.6.sh" \
        || true
)"
PACKA_UPP="$(
    resolve_script \
        "$BIN_DIR/packa_upp_move-6.6.sh" \
        "$BIN_DIR/packa_upp_move-6.4.sh" \
        || true
)"

# Installera program
APT_INSTALL="$BIN_DIR/apt_pkg_install-5.1.sh"
APPIMAGE_INSTALL="$BIN_DIR/appimage_install-5.2.sh"
FLATPAK_INSTALL="$BIN_DIR/flatpak_install-5.2.sh"
SNAP_INSTALL="$BIN_DIR/snap_pkg_install-5.1.sh"
DEB_INSTALL="$BIN_DIR/deb-downloader-install-1.2.sh"
PROTON_INSTALL="$BIN_DIR/proton_install-5.1.sh"
INSTALLERA_PROTON="$BIN_DIR/Installera-proton-1.0.sh"
MAIN_INSTALL="$BIN_DIR/main_install-1.0.sh"

# Backup och återställning
BACKUP_APPCONFIG="$(
    resolve_script \
        "$BIN_DIR/backup_appconfig-4.1.sh" \
        "$BIN_DIR/backup_appconfig-4.0.sh" \
        || true
)"
RESTORE_APPCONFIG="$(
    resolve_script \
        "$BIN_DIR/restore_appconfig-3.4.sh" \
        "$BIN_DIR/restore_appconfig-3.3.sh" \
        || true
)"
BACKUP_DARKTABLE="$BIN_DIR/backup_darktable-5.1.sh"
RESTORE_DARKTABLE="$BIN_DIR/restore_darktable-1.0.sh"

# Utilities
APPIMAGE_DESKTOPIFY="$BIN_DIR/appimage-desktopify5.0.sh"
APPIMAGE_UBUNTU26="$BIN_DIR/ubuntu-26-appimage-max-setup.sh"
APT_UNINSTALL="$BIN_DIR/apt_pkg_uninstall-5.1.sh"
MIGRATE_DARKTABLE="$BIN_DIR/migrate_darktable-6.2.sh"
DARKTABLE_TOOLKIT="$BIN_DIR/darktable-toolkit-1.0.sh"
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

all_script_entries() {
    cat <<EOF
Packa data|$PACKA_DATA
Packa upp data|$PACKA_UPP
APT-installation|$APT_INSTALL
AppImage-installation|$APPIMAGE_INSTALL
Flatpak-installation|$FLATPAK_INSTALL
Snap-installation|$SNAP_INSTALL
Deb-nedladdning och installation|$DEB_INSTALL
Proton-installation|$PROTON_INSTALL
Installera Proton|$INSTALLERA_PROTON
Huvudinstallation|$MAIN_INSTALL
Backup AppConfig|$BACKUP_APPCONFIG
Restore AppConfig|$RESTORE_APPCONFIG
Backup Darktable 5.1|$BACKUP_DARKTABLE
Restore Darktable 1.0|$RESTORE_DARKTABLE
AppImage-skrivbordsikoner|$APPIMAGE_DESKTOPIFY
Ubuntu 26 AppImage-förberedelse|$APPIMAGE_UBUNTU26
Avinstallera apt-paket|$APT_UNINSTALL
Migrera Darktable 6.2|$MIGRATE_DARKTABLE
Darktable Toolkit|$DARKTABLE_TOOLKIT
Darktable OpenCL|$DARKTABLE_OPENCL
Surface tablet mode|$SURFACE_TABLET_MODE
Lösenordsgenerator|$PASSWORD_GENERATOR
Montera Samba|$MONTERA_SAMBA
Rätta framtida tidsstämplar|$FIX_TIMESTAMPS
EOF
}

# ------------------------------------------------------------
# Kontroller
# ------------------------------------------------------------

show_script_status() {
    local report_file
    local total=0 ok=0 missing=0 syntax_errors=0 not_executable=0
    local label path

    report_file="$(mktemp)" || return 0

    {
        printf 'KONTROLL AV ALLA SCRIPTSÖKVÄGAR\n'
        printf 'Scriptkatalog: %s\n' "$BIN_DIR"
        printf 'Datum: %s\n\n' "$(date '+%F %T')"
    } >"$report_file"

    while IFS='|' read -r label path; do
        [[ -n "$label" ]] || continue
        ((total += 1))

        if [[ ! -f "$path" ]]; then
            printf 'SAKNAS      %s\n            %s\n\n' \
                "$label" "$path" >>"$report_file"
            ((missing += 1))
            continue
        fi

        if ! bash -n "$path" >/dev/null 2>&1; then
            printf 'SYNTAXFEL   %s\n            %s\n\n' \
                "$label" "$path" >>"$report_file"
            ((syntax_errors += 1))
            continue
        fi

        if [[ ! -x "$path" ]]; then
            printf 'EJ KÖRBAR   %s\n            %s\n' \
                "$label" "$path" >>"$report_file"
            printf '            Kör: chmod +x "%s"\n\n' \
                "$path" >>"$report_file"
            ((not_executable += 1))
            continue
        fi

        printf 'OK          %s\n            %s\n\n' \
            "$label" "$path" >>"$report_file"
        ((ok += 1))
    done < <(all_script_entries)

    {
        printf '%s\n' '------------------------------------------------------------'
        printf 'Totalt:       %d\n' "$total"
        printf 'OK:           %d\n' "$ok"
        printf 'Saknas:       %d\n' "$missing"
        printf 'Syntaxfel:    %d\n' "$syntax_errors"
        printf 'Ej körbara:   %d\n' "$not_executable"
    } >>"$report_file"

    whiptail \
        --title "Kontroll av scriptsökvägar" \
        --scrolltext \
        --textbox "$report_file" \
        30 105 || true

    rm -f -- "$report_file"
}

preflight_before_move() {
    local report=""
    local errors=0
    local warnings=0
    local source=""

    check_required() {
        local label="$1"
        local path="$2"

        if [[ ! -f "$path" ]]; then
            report+="FEL     $label saknas: $path"$'\n'
            ((errors += 1))
        elif ! bash -n "$path" >/dev/null 2>&1; then
            report+="FEL     $label har syntaxfel: $path"$'\n'
            ((errors += 1))
        elif [[ ! -x "$path" ]]; then
            report+="VARNING $label är inte körbar: $path"$'\n'
            ((warnings += 1))
        else
            report+="OK      $label"$'\n'
        fi
    }

    report+="KONTROLL FÖRE FLYTT"$'\n\n'

    check_required "Backup Darktable 5.1" "$BACKUP_DARKTABLE"
    check_required "Backup AppConfig" "$BACKUP_APPCONFIG"
    check_required "Packa data" "$PACKA_DATA"
    check_required "Packa upp data" "$PACKA_UPP"

    report+=$'\n'

    if source="$(find_darktable_source)"; then
        report+="OK      Darktable-konfiguration: $source"$'\n'
    else
        report+="FEL     Ingen giltig Darktable-konfiguration hittades."$'\n'
        ((errors += 1))
    fi

    if [[ -d "$HOME/.mixxx" ]] || app_in_paths_file "mixxx"; then
        report+="OK      Mixxx-konfiguration kan identifieras."$'\n'
    else
        report+="VARNING Mixxx-konfiguration hittades inte."$'\n'
        ((warnings += 1))
    fi

    if app_in_paths_file "rawtherapee" ||
       [[ -d "$HOME/.config/RawTherapee-AppImage" ||
          -d "$HOME/.config/RawTherapee" ]]; then
        report+="OK      RawTherapee-konfiguration kan identifieras."$'\n'
    else
        report+="VARNING RawTherapee-konfiguration hittades inte."$'\n'
        ((warnings += 1))
    fi

    if pgrep -x darktable >/dev/null 2>&1; then
        report+="FEL     Darktable verkar vara igång."$'\n'
        ((errors += 1))
    else
        report+="OK      Darktable verkar vara stängt."$'\n'
    fi

    report+=$'\n'
    report+="RESULTAT: $errors fel, $warnings varningar."$'\n'

    if ((errors > 0)); then
        report+=$'\n'"INTE REDO. Rätta felen innan du skapar flyttpaketet."
    elif ((warnings > 0)); then
        report+=$'\n'"REDO MED VARNINGAR. Läs varningarna innan du fortsätter."
    else
        report+=$'\n'"REDO ATT PACKA."
    fi

    mkdir -p "$PREFLIGHT_LOG_DIR"
    printf '%s\n' "$report" \
        >"$PREFLIGHT_LOG_DIR/preflight-$(date +%Y%m%d-%H%M%S).log"

    show_scroll_message "Kontroll före flytt" "$report"
}

show_my_bin() {
    local output

    if [[ ! -d "$BIN_DIR" ]]; then
        whiptail \
            --title "Katalogen saknas" \
            --msgbox "Katalogen finns inte:\n\n$BIN_DIR" \
            11 72
        return 0
    fi

    output="$(find "$BIN_DIR" -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)"
    show_scroll_message "Innehåll i $BIN_DIR" "${output:-Katalogen är tom.}"
}

show_move_order() {
    whiptail \
        --title "Rekommenderad arbetsordning" \
        --msgbox "PÅ DEN GAMLA DATORN\n\n1. Stäng Darktable, Mixxx och RawTherapee.\n2. Kör kontroll före flytt.\n3. Skapa Darktable-backup.\n4. Skapa övriga programbackuper.\n5. Skapa flyttpaketet.\n\nPÅ DEN NYA DATORN\n\n6. Installera programmen.\n7. Packa upp flyttpaketet.\n8. Återställ programinställningar.\n9. Återställ eller migrera Darktable.\n10. Starta programmen och kontrollera resultatet." \
        25 86
}

# ------------------------------------------------------------
# Meny: Flytta data
# ------------------------------------------------------------

backup_before_move_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Förbered flytt" \
                --menu "Säkerhetskopiera programdata innan flyttpaketet skapas." \
                24 88 14 \
                "1" "Kontrollera att allt är redo" \
                "2" "Säkerhetskopiera Darktable 5.1" \
                "3" "Säkerhetskopiera Mixxx" \
                "4" "Säkerhetskopiera RawTherapee" \
                "5" "Säkerhetskopiera alla programinställningar" \
                "i" "Visa rekommenderad arbetsordning" \
                "b" "Tillbaka" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) preflight_before_move ;;
            2) run_with_dryrun_menu \
                   "Säkerhetskopiera Darktable 5.1" \
                   "$BACKUP_DARKTABLE" ;;
            3) run_appconfig_backup \
                   "mixxx" "Mixxx" "$HOME/.mixxx" ;;
            4)
                local rt_path="$HOME/.config/RawTherapee-AppImage"
                [[ -d "$rt_path" ]] || rt_path="$HOME/.config/RawTherapee"
                run_appconfig_backup \
                    "rawtherapee" "RawTherapee" "$rt_path"
                ;;
            5) run_with_dryrun_menu \
                   "Säkerhetskopiera alla programinställningar" \
                   "$BACKUP_APPCONFIG" ;;
            i) show_move_order ;;
            b) return 0 ;;
        esac
    done
}

restore_on_new_computer_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Återställ på ny dator" \
                --menu "Välj återställningssteg:" \
                21 88 11 \
                "1" "Packa upp flyttpaketet" \
                "2" "Återställ programinställningar" \
                "3" "Återställ Darktable från snapshot (1.0)" \
                "4" "Migrera Darktable från backup/Snap (6.2)" \
                "b" "Tillbaka" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_script "$PACKA_UPP" "Packa upp flyttpaketet" ;;
            2) run_script \
                   "$RESTORE_APPCONFIG" \
                   "Återställ programinställningar" ;;
            3) run_with_dryrun_menu \
                   "Återställ Darktable 1.0" \
                   "$RESTORE_DARKTABLE" ;;
            4) run_with_dryrun_menu \
                   "Migrera Darktable 6.2" \
                   "$MIGRATE_DARKTABLE" ;;
            b) return 0 ;;
        esac
    done
}

flytta_data_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Flytta data" \
                --menu "Välj arbetssteg:" \
                21 88 11 \
                "1" "Förbered flytten och skapa säkerhetskopior" \
                "2" "Skapa flyttpaketet" \
                "3" "Återställ på den nya datorn" \
                "i" "Visa hela arbetsordningen" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) backup_before_move_menu ;;
            2) run_with_dryrun_menu \
                   "Skapa flyttpaket" "$PACKA_DATA" ;;
            3) restore_on_new_computer_menu ;;
            i) show_move_order ;;
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
                23 88 13 \
                "1" "APT-installation" \
                "2" "AppImage-installation" \
                "3" "Flatpak-installation" \
                "4" "Snap-installation" \
                "5" "DEB-nedladdning och installation" \
                "6" "Proton-installation" \
                "7" "Installera Proton" \
                "8" "Huvudinstallation" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_with_mode_menu "APT-installation" "$APT_INSTALL" ;;
            2) run_with_mode_menu "AppImage-installation" "$APPIMAGE_INSTALL" ;;
            3) run_with_mode_menu "Flatpak-installation" "$FLATPAK_INSTALL" ;;
            4) run_with_mode_menu "Snap-installation" "$SNAP_INSTALL" ;;
            5) run_with_mode_menu \
                   "DEB-nedladdning och installation" "$DEB_INSTALL" ;;
            6) run_with_mode_menu "Proton-installation" "$PROTON_INSTALL" ;;
            7) run_script "$INSTALLERA_PROTON" "Installera Proton" ;;
            8) run_script "$MAIN_INSTALL" "Huvudinstallation" ;;
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
                --menu "Välj ett verktyg (använd piltangenterna för att rulla):" \
                22 90 13 \
                "1"  "AppImage: skapa skrivbordsikoner" \
                "2"  "AppImage: förbered Ubuntu 26.04" \                "5"  "Programinställningar: säkerhetskopiera" \
                "6"  "Programinställningar: återställ" \
                "7"  "Avinstallera apt-paket" \                "10" "Surface tablet mode" \
                "11" "Lösenordsgenerator" \
                "12" "Montera Samba" \
                "13" "Rätta framtida tidsstämplar" \
                "14" "Kontrollera alla scriptsökvägar" \
                "15" "Visa innehållet i my_bin" \
                "b"  "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_script \
                   "$APPIMAGE_DESKTOPIFY" \
                   "AppImage: skapa skrivbordsikoner" ;;
            2) run_script \
                   "$APPIMAGE_UBUNTU26" \
                   "AppImage: förbered Ubuntu 26.04" ;;
            3) run_script \
                   "$DARKTABLE_TOOLKIT" \
                   "Darktable Toolkit" ;;

            5) run_with_dryrun_menu \
                   "Säkerhetskopiera programinställningar" \
                   "$BACKUP_APPCONFIG" ;;
            6) run_script \
                   "$RESTORE_APPCONFIG" \
                   "Återställ programinställningar" ;;
            7) run_with_mode_menu \
                   "Avinstallera apt-paket" \
                   "$APT_UNINSTALL" ;;
            10) run_script \
                    "$SURFACE_TABLET_MODE" \
                    "Surface tablet mode" ;;
            11) run_script \
                    "$PASSWORD_GENERATOR" \
                    "Lösenordsgenerator" ;;
            12) run_script "$MONTERA_SAMBA" "Montera Samba" ;;
            13) run_script \
                    "$FIX_TIMESTAMPS" \
                    "Rätta framtida tidsstämplar" ;;
            14) show_script_status ;;
            15) show_my_bin ;;
            b) return 0 ;;
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
        13 76
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
            20 82 10 \
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
