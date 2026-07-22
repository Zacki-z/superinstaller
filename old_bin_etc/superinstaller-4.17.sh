#!/usr/bin/env bash
#
# Superinstaller 4.17
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
#   MY_BIN_DIR="/annan/sökväg" ./superinstaller-4.17.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="4.17"
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

show_scroll_message() {
    local title="$1"
    local content="$2"
    local terminal_rows
    local terminal_cols
    local dialog_rows
    local dialog_cols
    local wrap_width
    local wrapped_content

    terminal_rows="$(tput lines 2>/dev/null || printf '30')"
    terminal_cols="$(tput cols 2>/dev/null || printf '100')"

    # Lämna alltid en marginal runt dialogen så att vänsterkanten och
    # knappen blir synliga även i ett mindre terminalfönster.
    dialog_rows=$((terminal_rows - 4))
    dialog_cols=$((terminal_cols - 4))

    ((dialog_rows > 34)) && dialog_rows=34
    ((dialog_cols > 100)) && dialog_cols=100

    # För mycket små terminalfönster använder vi nästan hela ytan.
    ((dialog_rows < 12)) && dialog_rows=$((terminal_rows - 2))
    ((dialog_cols < 40)) && dialog_cols=$((terminal_cols - 2))

    # Skydda mot orimliga eller saknade terminalvärden.
    ((dialog_rows < 8)) && dialog_rows=8
    ((dialog_cols < 30)) && dialog_cols=30

    wrap_width=$((dialog_cols - 10))
    ((wrap_width < 20)) && wrap_width=20

    wrapped_content="$(
        printf '%s\n' "$content" |
            fold -s -w "$wrap_width"
    )"

    # --msgbox ger en tydlig knapp. "|| true" gör att även Esc tar
    # användaren tillbaka till menyn i stället för att avsluta skriptet.
    whiptail \
        --title "$title" \
        --scrolltext \
        --ok-button "Tillbaka" \
        --msgbox "$wrapped_content" \
        "$dialog_rows" "$dialog_cols" || true
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

    # Körningen ligger i ett if-villkor så att ett normalt fel från ett
    # underskript inte utlöser Superinstallers globala ERR-trap. Felkoden
    # visas fortfarande tydligt nedan.
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

detect_dryrun_arg() {
    local script="$1"

    [[ -f "$script" ]] || return 1

    # Föredra långformen när skriptet tydligt nämner den.
    if grep -Eq -- '(^|[[:space:](|])--dry-run([[:space:])|]|$)' "$script"; then
        printf '%s\n' "--dry-run"
        return 0
    fi

    # Äldre skript använder ofta getopts och kortformen -n.
    if grep -Eq -- 'getopts[[:space:]]+["'\''][^"'\'']*n|(^|[^[:alnum:]_])-n([^[:alnum:]_]|$)' "$script"; then
        printf '%s\n' "-n"
        return 0
    fi

    return 1
}

run_pack_with_dryrun_menu() {
    local title="$1"
    local script="$2"
    local choice
    local dryrun_arg=""

    if [[ ! -f "$script" ]]; then
        whiptail \
            --title "Filen saknas" \
            --msgbox "Hittar inte filen:\n\n$script" \
            12 72
        return 0
    fi

    choice=$(
        whiptail \
            --title "$title" \
            --menu "Hur vill du köra?" \
            16 76 6 \
            "1" "Normal körning" \
            "2" "Dry-run – ändra ingenting" \
            "b" "Tillbaka" \
            3>&1 1>&2 2>&3
    ) || return 0

    case "$choice" in
        1)
            run_script "$script" "$title"
            ;;
        2)
            dryrun_arg="$(detect_dryrun_arg "$script" || true)"
            if [[ -z "$dryrun_arg" ]]; then
                whiptail \
                    --title "Dry-run kunde inte identifieras" \
                    --msgbox "Superinstaller hittade varken --dry-run eller -n i:\n\n$script\n\nAv säkerhetsskäl körs inte skriptet." \
                    15 78
                return 0
            fi
            run_script \
                "$script" \
                "$title – dry-run ($dryrun_arg)" \
                "$dryrun_arg"
            ;;
        b)
            return 0
            ;;
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
        while IFS=$' \t' read -r app_col path_col _; do
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

        # Kommandot ligger i ett if-villkor. Då utlöses inte den
        # globala ERR-fällan för en felkod som kontrollen själv ska hantera.
        if timeout 180s "${command[@]}" "$@" >>"$log_file" 2>&1; then
            status=0
        else
            status=$?
        fi

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
        local dryrun_arg=""
        local -a pack_command=()
        local -a pack_list_files=()
        local candidate=""
        local required_entry=""
        local found_in=""

        {
            echo
            echo "============================================================"
            echo "Packa data: säker dry-run-kontroll"
            echo "============================================================"
        } >>"$log_file"

        dryrun_arg="$(detect_dryrun_arg "$PACKA_DATA" || true)"

        if [[ -n "$dryrun_arg" ]]; then
            if [[ -x "$PACKA_DATA" ]]; then
                pack_command=("$PACKA_DATA")
            else
                pack_command=(bash "$PACKA_DATA")
            fi

            {
                printf 'Identifierad dry-run-flagga: %s\n' "$dryrun_arg"
                printf 'Kommando:'
                printf ' %q' "${pack_command[@]}" "$dryrun_arg"
                printf '\n'
            } >>"$log_file"

            # En misslyckad dry-run är ett testresultat, inte ett
            # oväntat fel i Superinstaller. if-villkoret hindrar därför
            # den globala ERR-fällan från att skriva falska felrader.
            if timeout 180s "${pack_command[@]}" "$dryrun_arg" \
                >"$pack_log" 2>&1
            then
                status=0
            else
                status=$?
            fi

            cat "$pack_log" >>"$log_file"

            case "$status" in
                0)
                    pf_ok "Packa data: dry-run lyckades med $dryrun_arg."
                    ;;
                124)
                    pf_error "Packa data: dry-run nådde tidsgränsen 180 sekunder."
                    ;;
                *)
                    if grep -Eqi \
                        'illegal option|invalid option|unknown option|okänt (argument|alternativ)|usage:|användning:' \
                        "$pack_log"
                    then
                        pf_warn "Packa data: den identifierade flaggan $dryrun_arg accepterades inte. Skriptet räknas inte som felaktigt, men dry-run kunde inte verifieras automatiskt."
                    else
                        pf_error "Packa data: dry-run med $dryrun_arg misslyckades med felkod $status. Se loggen."
                    fi
                    ;;
            esac
        else
            : >"$pack_log"
            pf_warn "Packa data: inget säkert dry-run-alternativ kunde identifieras. Skriptets Bash-syntax är kontrollerad, men det kördes inte."
            printf 'Ingen dry-run-flagga identifierades. Packningsskriptet kördes inte.\n' \
                >>"$log_file"
        fi

        # Leta efter den faktiska packlistan i stället för att bara söka
        # efter katalognamn inne i packningsskriptet.
        while IFS= read -r -d '' candidate; do
            pack_list_files+=("$candidate")
        done < <(
            find "$BIN_DIR" -maxdepth 3 -type f \
                \( -name 'tar_dirs.txt' \
                   -o -name 'tar_dirs_*.txt' \
                   -o -name '*tar*dirs*.txt' \) \
                -print0 2>/dev/null
        )

        if ((${#pack_list_files[@]} > 0)); then
            {
                echo
                echo "Packlistor som kontrolleras:"
                printf '  %s\n' "${pack_list_files[@]}"
            } >>"$log_file"
        else
            pf_warn "Ingen tar_dirs-lista hittades under $BIN_DIR."
        fi

        for required_entry in bup_darktable bup_appl_config my_bin; do
            found_in=""

            for candidate in "${pack_list_files[@]}"; do
                if awk -v wanted="$required_entry" '
                    {
                        sub(/\r$/, "", $0)
                        line=$0
                        sub(/^[[:space:]]+/, "", line)
                        sub(/[[:space:]]+$/, "", line)
                    }
                    line == "" || line ~ /^#/ { next }
                    {
                        sub(/^~\//, "", line)
                        sub(/^\$HOME\//, "", line)
                        home=ENVIRON["HOME"] "/"
                        if (index(line, home) == 1) {
                            line=substr(line, length(home) + 1)
                        }
                    }
                    line == wanted { found=1 }
                    END { exit(found ? 0 : 1) }
                ' "$candidate"
                then
                    found_in="$candidate"
                    break
                fi
            done

            # Reservkontroll för skript som bygger listan internt.
            if [[ -z "$found_in" ]] &&
               grep -Fq "$required_entry" "$PACKA_DATA" "$pack_log" 2>/dev/null
            then
                found_in="$PACKA_DATA eller dry-run-utskriften"
            fi

            if [[ -n "$found_in" ]]; then
                pf_ok "Packningsunderlaget innehåller $required_entry:\n        $found_in"
            else
                pf_warn "Kunde inte bekräfta att $required_entry finns i packlistan."
            fi
        done
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

    show_scroll_message "$title" "$report"

    rm -f -- "$pack_log"
    return 0
}

show_script_status() {
    local report_file
    local total=0
    local ok=0
    local missing=0
    local syntax_errors=0
    local not_executable=0
    local label
    local path
    local terminal_rows
    local terminal_cols
    local dialog_rows
    local dialog_cols

    report_file="$(mktemp)" || {
        whiptail \
            --title "Kontrollfel" \
            --msgbox "Kunde inte skapa en temporär rapportfil." \
            10 70
        return 0
    }

    {
        printf 'KONTROLL AV ALLA SCRIPTSÖKVÄGAR\n'
        printf 'Scriptkatalog: %s\n' "$BIN_DIR"
        printf 'Datum: %s\n\n' "$(date '+%F %T')"
    } >"$report_file"

    while IFS='|' read -r label path; do
        [[ -n "$label" ]] || continue
        ((total += 1))

        if [[ ! -f "$path" ]]; then
            printf 'SAKNAS      %s\n' "$label" >>"$report_file"
            printf '            %s\n\n' "$path" >>"$report_file"
            ((missing += 1))
            continue
        fi

        if ! bash -n "$path" >/dev/null 2>&1; then
            printf 'SYNTAXFEL   %s\n' "$label" >>"$report_file"
            printf '            %s\n\n' "$path" >>"$report_file"
            ((syntax_errors += 1))
            continue
        fi

        if [[ ! -x "$path" ]]; then
            printf 'EJ KÖRBAR   %s\n' "$label" >>"$report_file"
            printf '            %s\n' "$path" >>"$report_file"
            printf '            Kör: chmod +x "%s"\n\n' "$path" >>"$report_file"
            ((not_executable += 1))
            continue
        fi

        printf 'OK          %s\n' "$label" >>"$report_file"
        printf '            %s\n\n' "$path" >>"$report_file"
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

    terminal_rows="$(tput lines 2>/dev/null || printf '30')"
    terminal_cols="$(tput cols 2>/dev/null || printf '100')"
    dialog_rows=$((terminal_rows - 4))
    dialog_cols=$((terminal_cols - 4))

    ((dialog_rows > 34)) && dialog_rows=34
    ((dialog_cols > 110)) && dialog_cols=110
    ((dialog_rows < 12)) && dialog_rows=12
    ((dialog_cols < 50)) && dialog_cols=50

    whiptail \
        --title "Kontroll av scriptsökvägar" \
        --scrolltext \
        --textbox "$report_file" \
        "$dialog_rows" "$dialog_cols" || true

    rm -f -- "$report_file"
    return 0
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

    show_scroll_message \
        "Innehåll i $BIN_DIR" \
        "${output:-Katalogen är tom.}"
}

# ------------------------------------------------------------
# Faktiska sökvägar i ~/my_bin
# ------------------------------------------------------------

# Flytta data
PACKA_DATA="$BIN_DIR/packa_to_move-5.9.sh"
PACKA_UPP="$BIN_DIR/packa_upp_move-6.6.sh"

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
BACKUP_APPCONFIG="$BIN_DIR/backup_appconfig-4.1.sh"
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
APT-installation|$APT_INSTALL
AppImage-installation|$APPIMAGE_INSTALL
Flatpak-installation|$FLATPAK_INSTALL
Snap-installation|$SNAP_INSTALL
Deb-nedladdning och installation|$DEB_INSTALL
Proton-installation 5.1|$PROTON_INSTALL
Installera Proton 1.0|$INSTALLERA_PROTON
Huvudinstallation|$MAIN_INSTALL
Backup AppConfig|$BACKUP_APPCONFIG
Restore AppConfig|$RESTORE_APPCONFIG
Backup Darktable 5.0|$BACKUP_DARKTABLE
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
                run_pack_with_dryrun_menu \
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
                25 88 15 \
                "1" "APT-installation (apt_pkg_install-5.1.sh)" \
                "2" "AppImage-installation (appimage_install-5.2.sh)" \
                "3" "Flatpak-installation (flatpak_install-5.2.sh)" \
                "4" "Snap-installation (snap_pkg_install-5.1.sh)" \
                "5" "Hämta och installera deb (deb-downloader-install-1.2.sh)" \
                "6" "Proton-installation (proton_install-5.1.sh)" \
                "7" "Installera Proton (Installera-proton-1.0.sh)" \
                "8" "Huvudinstallation (main_install-1.0.sh)" \
                "b" "Tillbaka till huvudmenyn" \
                3>&1 1>&2 2>&3
        ) || return 0

        case "$choice" in
            1) run_with_mode_menu "APT-installation" "$APT_INSTALL" ;;
            2) run_with_mode_menu "AppImage-installation" "$APPIMAGE_INSTALL" ;;
            3) run_with_mode_menu "Flatpak-installation" "$FLATPAK_INSTALL" ;;
            4) run_with_mode_menu "Snap-installation" "$SNAP_INSTALL" ;;
            5) run_with_mode_menu "Deb-nedladdning och installation" "$DEB_INSTALL" ;;
            6) run_with_mode_menu "Proton-installation 5.1" "$PROTON_INSTALL" ;;
            7) run_script "$INSTALLERA_PROTON" "Installera Proton 1.0" ;;
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
                22 86 13 \
                "1"  "AppImage: skapa skrivbordsikoner" \
                "2"  "AppImage: förbered Ubuntu 26.04" \
                "3"  "Darktable: säkerhetskopiera konfiguration (5.0)" \
                "4"  "Darktable: återställ konfiguration (3.0)" \
                "5"  "Programinställningar: säkerhetskopiera (4.1)" \
                "6"  "Programinställningar: återställ (3.3)" \
                "7"  "Avinstallera apt-paket" \
                "8"  "Migrera Darktable 6.0" \
                "9"  "Kontrollera/fixa Darktable OpenCL" \
                "10" "Surface tablet mode" \
                "11" "Lösenordsgenerator" \
                "12" "Montera Samba" \
                "13" "Rätta framtida tidsstämplar" \
                "14" "Kontrollera alla scriptsökvägar" \
                "15" "Visa innehållet i my_bin" \
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
                run_with_dryrun_menu \
                    "Säkerhetskopiera Darktable 5.0" \
                    "$BACKUP_DARKTABLE"
                ;;
            4)
                run_script \
                    "$RESTORE_DARKTABLE" \
                    "Återställ Darktable 3.0"
                ;;
            5)
                run_with_dryrun_menu \
                    "Säkerhetskopiera programinställningar 4.1" \
                    "$BACKUP_APPCONFIG"
                ;;
            6)
                run_script \
                    "$RESTORE_APPCONFIG" \
                    "Återställ programinställningar 3.3"
                ;;
            7)
                run_with_mode_menu \
                    "Avinstallera apt-paket" \
                    "$APT_UNINSTALL"
                ;;
            8)
                run_with_dryrun_menu \
                    "Migrera Darktable 6.0" \
                    "$MIGRATE_DARKTABLE"
                ;;
            9)
                run_script \
                    "$DARKTABLE_OPENCL" \
                    "Kontrollera/fixa Darktable OpenCL"
                ;;
            10)
                run_script \
                    "$SURFACE_TABLET_MODE" \
                    "Surface tablet mode"
                ;;
            11)
                run_script \
                    "$PASSWORD_GENERATOR" \
                    "Lösenordsgenerator"
                ;;
            12)
                run_script \
                    "$MONTERA_SAMBA" \
                    "Montera Samba"
                ;;
            13)
                run_script \
                    "$FIX_TIMESTAMPS" \
                    "Rätta framtida tidsstämplar"
                ;;
            14)
                show_script_status
                ;;
            15)
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
