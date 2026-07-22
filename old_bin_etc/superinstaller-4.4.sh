#!/usr/bin/env bash
#
# Superinstaller 4.4
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
#   MY_BIN_DIR="/annan/sökväg" ./superinstaller-4.4.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="4.4"
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
        --msgbox "REKOMMENDERAD ORDNING\n\nPÅ DEN GAMLA DATORN\n1. Stäng Darktable, Mixxx och RawTherapee\n2. Kör Kontroll före flytt\n3. Säkerhetskopiera Darktable, Mixxx och RawTherapee\n4. Säkerhetskopiera övriga programinställningar\n5. Kör Kontroll före packning igen\n6. Skapa flyttpaketet\n\nPÅ DEN NYA DATORN\n7. Installera Ubuntu och programmen\n8. Starta viktiga program en gång och stäng dem\n9. Packa upp flyttpaketet\n10. Återställ programinställningar och Darktable" \
        23 84
}

expand_config_path() {
    local path="$1"

    path="${path%\"}"
    path="${path#\"}"
    path="${path%\'}"
    path="${path#\'}"

    case "$path" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s/%s\n' "$HOME" "${path#\~/}"
            ;;
        '$HOME')
            printf '%s\n' "$HOME"
            ;;
        '$HOME/'*)
            printf '%s/%s\n' "$HOME" "${path#\$HOME/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

find_app_source() {
    local app="$1"
    shift
    local app_col
    local path_col
    local expanded
    local fallback

    if [[ -f "$APP_PATHS_FILE" ]]; then
        while read -r app_col path_col _; do
            [[ -n "${app_col:-}" ]] || continue
            [[ "$app_col" != \#* ]] || continue
            [[ "$app_col" == "$app" ]] || continue
            [[ -n "${path_col:-}" ]] || continue

            expanded="$(expand_config_path "$path_col")"
            if [[ -d "$expanded" ]]; then
                printf '%s\n' "$expanded"
                return 0
            fi
        done < "$APP_PATHS_FILE"
    fi

    for fallback in "$@"; do
        if [[ -d "$fallback" ]]; then
            printf '%s\n' "$fallback"
            return 0
        fi
    done

    return 1
}

find_darktable_source() {
    local candidates=(
        "$HOME/snap/darktable/current/.config/darktable"
        "$HOME/.var/app/org.darktable.Darktable/config/darktable"
        "$HOME/.config/darktable"
    )
    local candidate
    local revision

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if [[ -d "$HOME/snap/darktable" ]]; then
        revision="$(
            find "$HOME/snap/darktable" \
                -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null |
            awk '/^[0-9]+$/' |
            sort -n |
            tail -n 1
        )"

        if [[ -n "$revision" &&
              -d "$HOME/snap/darktable/$revision/.config/darktable" ]]; then
            printf '%s\n' \
                "$HOME/snap/darktable/$revision/.config/darktable"
            return 0
        fi
    fi

    return 1
}

latest_matching_item() {
    local root="$1"
    local pattern="$2"

    [[ -d "$root" ]] || return 1

    find "$root" -mindepth 1 -maxdepth 1 -name "$pattern" \
        -printf '%T@|%p\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d '|' -f 2-
}

file_age_text() {
    local path="$1"
    local modified
    local now
    local seconds
    local hours
    local days

    modified="$(stat -c '%Y' "$path" 2>/dev/null || printf '0')"
    now="$(date +%s)"
    seconds=$((now - modified))
    ((seconds >= 0)) || seconds=0

    hours=$((seconds / 3600))
    days=$((hours / 24))

    if ((days > 0)); then
        printf '%d dag(ar)' "$days"
    elif ((hours > 0)); then
        printf '%d timme/timmar' "$hours"
    else
        printf 'mindre än en timme'
    fi
}

preflight_before_move() {
    local report=""
    local errors=0
    local warnings=0
    local passed=0
    local log_file
    local pack_log
    local source
    local latest
    local available
    local available_human
    local process_output
    local status
    local -a mixxx_args=("mixxx")
    local -a rawtherapee_args=("rawtherapee")

    mkdir -p "$PREFLIGHT_LOG_DIR"
    log_file="$PREFLIGHT_LOG_DIR/preflight-$(date +%Y%m%d-%H%M%S).log"
    pack_log="$(mktemp)"

    pf_ok() {
        report+="OK      $*"$'\n'
        ((passed += 1))
    }

    pf_warn() {
        report+="VARNING $*"$'\n'
        ((warnings += 1))
    }

    pf_error() {
        report+="FEL     $*"$'\n'
        ((errors += 1))
    }

    check_script() {
        local label="$1"
        local script="$2"

        if [[ ! -f "$script" ]]; then
            pf_error "$label saknas: $script"
            return 1
        fi

        if bash -n "$script" >>"$log_file" 2>&1; then
            if [[ -x "$script" ]]; then
                pf_ok "$label finns och Bash-syntaxen är korrekt."
            else
                pf_warn "$label finns och syntaxen är korrekt, men filen saknar körbehörighet."
            fi
            return 0
        fi

        pf_error "$label har syntaxfel. Se loggen."
        return 1
    }

    run_dry_test() {
        local label="$1"
        local script="$2"
        shift 2
        local -a command=()

        [[ -f "$script" ]] || return 1

        if [[ -x "$script" ]]; then
            command=("$script")
        else
            command=(bash "$script")
        fi

        {
            echo
            echo "============================================================"
            echo "$label"
            printf 'Kommando:'
            printf ' %q' "${command[@]}" "$@"
            echo
            echo "============================================================"
        } >>"$log_file"

        set +e
        timeout 180s "${command[@]}" "$@" >>"$log_file" 2>&1
        status=$?
        set -e

        case "$status" in
            0)
                pf_ok "$label lyckades."
                return 0
                ;;
            124)
                pf_error "$label nådde tidsgränsen 180 sekunder."
                return 1
                ;;
            *)
                pf_error "$label misslyckades med felkod $status."
                return 1
                ;;
        esac
    }

    {
        echo "Superinstaller $VERSION – Kontroll före flytt"
        echo "Datum: $(date --iso-8601=seconds)"
        echo "Användare: $USER"
        echo "Dator: $(hostname)"
        echo "BIN_DIR: $BIN_DIR"
        echo
    } >"$log_file"

    report+="KONTROLL FÖRE FLYTT"$'\n'
    report+="Logg: $log_file"$'\n\n'

    report+="--- Nödvändiga skript ---"$'\n'
    check_script "Backup Darktable" "$BACKUP_DARKTABLE" || true
    check_script "Backup AppConfig" "$BACKUP_APPCONFIG" || true
    check_script "Packa data" "$PACKA_DATA" || true
    check_script "Packa upp data" "$PACKA_UPP" || true
    report+=$'\n'

    report+="--- Verktyg ---"$'\n'
    local command
    for command in bash tar gzip rsync flock timeout find stat df; do
        if command -v "$command" >/dev/null 2>&1; then
            pf_ok "Kommandot '$command' finns."
        else
            pf_error "Kommandot '$command' saknas."
        fi
    done

    if command -v pv >/dev/null 2>&1; then
        pf_ok "Kommandot 'pv' finns."
    else
        pf_warn "Kommandot 'pv' saknas. Packnings- eller uppackningsskriptet kan behöva installera det."
    fi
    report+=$'\n'

    report+="--- Program måste vara stängda ---"$'\n'
    process_output="$(
        ps -u "$(id -u)" -o pid=,comm=,args= 2>/dev/null |
        awk '
            BEGIN { IGNORECASE=1 }
            $2 ~ /^darktable/ { print; next }
            $2 ~ /^mixxx/ { print; next }
            $2 ~ /^rawtherapee/ { print; next }
            $0 ~ /darktable[^ ]*\.AppImage/ { print; next }
            $0 ~ /rawtherapee[^ ]*\.AppImage/ { print }
        '
    )"

    if [[ -n "$process_output" ]]; then
        pf_error "Darktable, Mixxx eller RawTherapee verkar vara igång."
        {
            echo
            echo "Pågående relevanta processer:"
            echo "$process_output"
        } >>"$log_file"
    else
        pf_ok "Darktable, Mixxx och RawTherapee verkar vara stängda."
    fi
    report+=$'\n'

    report+="--- Konfigurationskällor ---"$'\n'

    if source="$(find_darktable_source)"; then
        pf_ok "Darktable-konfiguration hittad:\n        $source"
    else
        pf_error "Ingen Darktable-konfiguration hittades."
    fi

    if source="$(find_app_source "mixxx" "$HOME/.mixxx")"; then
        pf_ok "Mixxx-konfiguration hittad:\n        $source"
        if ! app_in_paths_file "mixxx"; then
            mixxx_args+=("--source=$source")
            pf_warn "Mixxx saknas i app_paths.txt; reservsökvägen används."
        fi
    else
        pf_error "Ingen Mixxx-konfiguration hittades."
    fi

    if source="$(
        find_app_source \
            "rawtherapee" \
            "$HOME/.config/RawTherapee" \
            "$HOME/.config/RawTherapee-dev" \
            "$HOME/.var/app/com.rawtherapee.RawTherapee/config/RawTherapee"
    )"; then
        pf_ok "RawTherapee-konfiguration hittad:\n        $source"
        if ! app_in_paths_file "rawtherapee"; then
            rawtherapee_args+=("--source=$source")
            pf_warn "RawTherapee saknas i app_paths.txt; reservsökvägen används."
        fi
    else
        pf_error "Ingen RawTherapee-konfiguration hittades."
    fi

    if [[ -r "$APP_PATHS_FILE" ]]; then
        local app_count
        app_count="$(
            awk '
                $1 !~ /^#/ && NF >= 2 { seen[$1]=1 }
                END { for (app in seen) count++; print count+0 }
            ' "$APP_PATHS_FILE"
        )"
        pf_ok "app_paths.txt finns och innehåller $app_count appnamn."
    else
        pf_warn "app_paths.txt saknas eller är inte läsbar: $APP_PATHS_FILE"
    fi
    report+=$'\n'

    report+="--- Befintliga backupresultat ---"$'\n'

    latest="$(latest_matching_item "$DARKTABLE_BACKUP_DIR" '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]*' || true)"
    if [[ -n "$latest" ]]; then
        pf_ok "Senaste Darktable-backup ($(file_age_text "$latest") gammal):\n        $latest"
    else
        pf_warn "Ingen färdig Darktable-snapshot hittades i $DARKTABLE_BACKUP_DIR."
    fi

    latest="$(latest_matching_item "$APPCONFIG_BACKUP_DIR" 'mixxx.*.tar.gz' || true)"
    if [[ -n "$latest" ]]; then
        pf_ok "Senaste Mixxx-backup ($(file_age_text "$latest") gammal):\n        $latest"
    else
        pf_warn "Ingen Mixxx-backup hittades i $APPCONFIG_BACKUP_DIR."
    fi

    latest="$(latest_matching_item "$APPCONFIG_BACKUP_DIR" 'rawtherapee.*.tar.gz' || true)"
    if [[ -n "$latest" ]]; then
        pf_ok "Senaste RawTherapee-backup ($(file_age_text "$latest") gammal):\n        $latest"
    else
        pf_warn "Ingen RawTherapee-backup hittades i $APPCONFIG_BACKUP_DIR."
    fi

    if [[ -d "$BIN_DIR" ]]; then
        pf_ok "Scriptkatalogen finns: $BIN_DIR"
    else
        pf_error "Scriptkatalogen saknas: $BIN_DIR"
    fi
    report+=$'\n'

    report+="--- Ledigt utrymme ---"$'\n'
    available="$(df -PB1 "$HOME" | awk 'NR==2 {print $4}')"
    if command -v numfmt >/dev/null 2>&1; then
        available_human="$(numfmt --to=iec-i --suffix=B "$available")"
    else
        available_human="$available byte"
    fi
    pf_ok "Ledigt utrymme på hemfilsystemet: $available_human"
    if ((available < 2147483648)); then
        pf_warn "Mindre än 2 GiB är ledigt. Det kan vara för lite för backup och flyttpaket."
    fi
    report+=$'\n'

    report+="--- Dry-run av arbetskedjan ---"$'\n'

    run_dry_test \
        "Darktable-backup: dry-run" \
        "$BACKUP_DARKTABLE" \
        --dry-run || true

    if ((${#mixxx_args[@]} > 1)) || app_in_paths_file "mixxx"; then
        run_dry_test \
            "Mixxx-backup: dry-run" \
            "$BACKUP_APPCONFIG" \
            "${mixxx_args[@]}" \
            --dry-run || true
    fi

    if ((${#rawtherapee_args[@]} > 1)) || app_in_paths_file "rawtherapee"; then
        run_dry_test \
            "RawTherapee-backup: dry-run" \
            "$BACKUP_APPCONFIG" \
            "${rawtherapee_args[@]}" \
            --dry-run || true
    fi

    if [[ -r "$APP_PATHS_FILE" ]]; then
        run_dry_test \
            "Backup av alla appar: dry-run" \
            "$BACKUP_APPCONFIG" \
            --dry-run || true
    fi

    if [[ -f "$PACKA_DATA" ]]; then
        {
            echo
            echo "============================================================"
            echo "Packa data: dry-run"
            echo "============================================================"
        } >>"$log_file"

        set +e
        if [[ -x "$PACKA_DATA" ]]; then
            timeout 180s "$PACKA_DATA" --dry-run \
                >"$pack_log" 2>&1
        else
            timeout 180s bash "$PACKA_DATA" --dry-run \
                >"$pack_log" 2>&1
        fi
        status=$?
        set -e

        cat "$pack_log" >>"$log_file"

        case "$status" in
            0) pf_ok "Packa data: dry-run lyckades." ;;
            124) pf_error "Packa data: dry-run nådde tidsgränsen 180 sekunder." ;;
            *) pf_error "Packa data: dry-run misslyckades med felkod $status." ;;
        esac

        if grep -Fq "bup_darktable" "$PACKA_DATA" "$pack_log" 2>/dev/null; then
            pf_ok "Packningsunderlaget nämner bup_darktable."
        else
            pf_warn "Kunde inte bekräfta att bup_darktable tas med i flyttpaketet."
        fi

        if grep -Fq "bup_appl_config" "$PACKA_DATA" "$pack_log" 2>/dev/null; then
            pf_ok "Packningsunderlaget nämner bup_appl_config."
        else
            pf_warn "Kunde inte bekräfta att bup_appl_config tas med i flyttpaketet."
        fi

        if grep -Fq "my_bin" "$PACKA_DATA" "$pack_log" 2>/dev/null; then
            pf_ok "Packningsunderlaget nämner my_bin."
        else
            pf_warn "Kunde inte bekräfta att my_bin tas med i flyttpaketet."
        fi
    fi

    report+=$'\n'
    report+="RESULTAT"$'\n'
    report+="OK: $passed   Varningar: $warnings   Fel: $errors"$'\n\n'

    if ((errors > 0)); then
        report+="INTE REDO ATT PACKA. Rätta felen och kör kontrollen igen."
    elif ((warnings > 0)); then
        report+="KAN PACKAS MED VARNINGAR. Läs varningarna och kör gärna kontrollen igen efter att backuperna skapats."
    else
        report+="REDO ATT PACKA."
    fi

    {
        echo
        echo "============================================================"
        echo "SAMMANFATTNING"
        echo "============================================================"
        printf '%s\n' "$report"
    } >>"$log_file"

    local title="Kontroll före flytt"
    if ((errors > 0)); then
        title="Inte redo att packa"
    elif ((warnings > 0)); then
        title="Redo med varningar"
    else
        title="Redo att packa"
    fi

    local wrapped_report
    wrapped_report="$(mktemp)"

    # Whiptail kan annars horisontellt rulla långa rader, vilket gör att
    # de första bokstäverna ser ut att försvinna. Bryt därför rapporten
    # innan den visas.
    printf '%s\n' "$report" |
        fold -s -w 88 > "$wrapped_report"

    whiptail \
        --title "$title" \
        --scrolltext \
        --textbox "$wrapped_report" \
        34 96

    rm -f -- "$pack_log" "$wrapped_report"
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

backup_before_move_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Förbered flytt" \
                --menu "Säkerhetskopiera programdata innan du packar flyttpaketet." \
                24 86 14 \
                "1" "Kontrollera att allt är redo" \
                "2" "Säkerhetskopiera Darktable" \
                "3" "Säkerhetskopiera Mixxx" \
                "4" "Säkerhetskopiera RawTherapee" \
                "5" "Säkerhetskopiera alla programinställningar" \
                "i" "Visa rekommenderad arbetsordning" \
                "b" "Tillbaka" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                preflight_before_move
                ;;
            2)
                run_with_dryrun_menu \
                    "Säkerhetskopiera Darktable" \
                    "$BACKUP_DARKTABLE"
                ;;
            3)
                run_appconfig_backup \
                    "mixxx" \
                    "Mixxx" \
                    "$HOME/.mixxx"
                ;;
            4)
                run_appconfig_backup \
                    "rawtherapee" \
                    "RawTherapee" \
                    "$HOME/.config/RawTherapee"
                ;;
            5)
                run_with_dryrun_menu \
                    "Säkerhetskopiera alla programinställningar" \
                    "$BACKUP_APPCONFIG"
                ;;
            i)
                show_move_order
                ;;
            b)
                return 0
                ;;
        esac
    done
}

pack_move_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Skapa flyttpaket" \
                --menu "Kontrollera först att säkerhetskopiorna är färdiga." \
                19 82 9 \
                "1" "Kontroll före packning" \
                "2" "Skapa flyttpaket" \
                "i" "Visa rekommenderad arbetsordning" \
                "b" "Tillbaka" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                preflight_before_move
                ;;
            2)
                run_with_dryrun_menu \
                    "Skapa flyttpaket" \
                    "$PACKA_DATA"
                ;;
            i)
                show_move_order
                ;;
            b)
                return 0
                ;;
        esac
    done
}

restore_on_new_system_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Återställ ny dator" \
                --menu "Installera normalt programmen innan deras inställningar återställs." \
                22 88 12 \
                "1" "Packa upp flyttpaketet" \
                "2" "Återställ programinställningar" \
                "3" "Återställ Darktable" \
                "i" "Visa rekommenderad arbetsordning" \
                "b" "Tillbaka" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                run_with_dryrun_menu \
                    "Packa upp flyttpaketet" \
                    "$PACKA_UPP"
                ;;
            2)
                run_script \
                    "$RESTORE_APPCONFIG" \
                    "Återställ programinställningar"
                ;;
            3)
                run_script \
                    "$RESTORE_DARKTABLE" \
                    "Återställ Darktable"
                ;;
            i)
                show_move_order
                ;;
            b)
                return 0
                ;;
        esac
    done
}

flytta_data_menu() {
    while true; do
        local choice

        choice=$(
            whiptail \
                --title "$MAIN_TITLE – Flytta system" \
                --menu "Välj vilket steg du vill arbeta med:" \
                21 78 11 \
                "1" "Förbered flytten och skapa säkerhetskopior" \
                "2" "Skapa flyttpaketet" \
                "3" "Återställ på den nya datorn" \
                "i" "Visa hela arbetsordningen" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1)
                backup_before_move_menu
                ;;
            2)
                pack_move_menu
                ;;
            3)
                restore_on_new_system_menu
                ;;
            i)
                show_move_order
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
