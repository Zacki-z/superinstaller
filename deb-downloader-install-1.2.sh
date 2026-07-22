#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

###############################################################################
# deb-downloader-install v1.2
#
# - Läser .deb-URL:er från ~/my_bin/etc/deb_list.txt som standard.
# - Laddar ned paketen till ~/deb_packages.
# - Installerar endast filer som laddades ned under den aktuella körningen.
# - Stöder både korta argument och Superinstallers långa argument:
#     -n / --dry-run
#     --normal / --quiet / --debug
#     -v / --verbosity normal|quiet|debug
###############################################################################

VERSION="1.2"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DRYRUN=false
VERBOSITY="normal"
TARGET_DIR="$HOME/deb_packages"
URL_FILE="$SCRIPT_DIR/etc/deb_list.txt"

LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/deb-downloader-$(date +%Y-%m-%d_%H-%M-%S).log"

DEB_URLS=()
PLANNED_FILES=()
DOWNLOADED_FILES=()
DOWNLOAD_FAILED=0
INSTALL_FAILED=0

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$msg" >> "$LOGFILE"

    case "$VERBOSITY" in
        quiet)
            [[ "$level" == "ERROR" ]] && \
                printf '[%s] [%s] %s\n' "$timestamp" "$level" "$msg"
            ;;
        *)
            printf '[%s] [%s] %s\n' "$timestamp" "$level" "$msg"
            ;;
    esac
}

usage() {
    local status="${1:-0}"

    cat <<EOF_USAGE
Användning: $0 [alternativ]

  -n, --dry-run              Visa vad som skulle göras
      --normal               Normal terminalutskrift
      --quiet                Visa endast fel i terminalen
      --debug                Utförlig terminalutskrift
  -v, --verbosity NIVÅ       normal | quiet | debug
  -d, --target-dir KATALOG   Katalog för hämtade .deb-filer
  -f, --url-file FIL         Textfil med .deb-URL:er
  -h, --help                 Visa denna hjälp

Standard URL-fil:
  $SCRIPT_DIR/etc/deb_list.txt
EOF_USAGE

    exit "$status"
}

need_value() {
    local option="$1"
    local value="${2:-}"

    if [[ -z "$value" ]]; then
        printf 'Alternativet %s kräver ett värde.\n' "$option" >&2
        usage 1
    fi
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -n|--dry-run)
                DRYRUN=true
                shift
                ;;
            --normal)
                VERBOSITY="normal"
                shift
                ;;
            --quiet)
                VERBOSITY="quiet"
                shift
                ;;
            --debug)
                VERBOSITY="debug"
                shift
                ;;
            -v|--verbosity)
                need_value "$1" "${2:-}"
                VERBOSITY="$2"
                shift 2
                ;;
            --verbosity=*)
                VERBOSITY="${1#*=}"
                shift
                ;;
            -d|--target-dir)
                need_value "$1" "${2:-}"
                TARGET_DIR="$2"
                shift 2
                ;;
            --target-dir=*)
                TARGET_DIR="${1#*=}"
                shift
                ;;
            -f|--url-file)
                need_value "$1" "${2:-}"
                URL_FILE="$2"
                shift 2
                ;;
            --url-file=*)
                URL_FILE="${1#*=}"
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            --)
                shift
                if (($# > 0)); then
                    printf 'Oväntade argument:' >&2
                    printf ' %q' "$@" >&2
                    printf '\n' >&2
                    usage 1
                fi
                ;;
            -* )
                printf 'Okänt alternativ: %s\n' "$1" >&2
                usage 1
                ;;
            *)
                printf 'Oväntat argument: %s\n' "$1" >&2
                usage 1
                ;;
        esac
    done

    case "$VERBOSITY" in
        normal|quiet|debug) ;;
        *)
            printf 'Ogiltig verbosity: %s\n' "$VERBOSITY" >&2
            printf 'Tillåtna värden är normal, quiet och debug.\n' >&2
            exit 1
            ;;
    esac
}

trim_line() {
    local value="$1"

    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

read_url_file() {
    local line

    if [[ ! -f "$URL_FILE" ]]; then
        log ERROR "URL-fil saknas: $URL_FILE"
        exit 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_line "$line")"
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue
        DEB_URLS+=("$line")
    done < "$URL_FILE"

    log INFO "Läste ${#DEB_URLS[@]} URL:er från $URL_FILE"

    if ((${#DEB_URLS[@]} == 0)); then
        log WARN "URL-filen innehåller inga aktiva .deb-URL:er."
    fi
}

check_prereqs() {
    if [[ "$DRYRUN" == false ]] && ! command -v wget >/dev/null 2>&1; then
        log ERROR "wget saknas. Installera med: sudo apt install wget"
        exit 1
    fi

    log INFO "Nödvändiga beroenden är tillgängliga."
}

prepare_dir() {
    if [[ "$DRYRUN" == true ]]; then
        log INFO "DRY-RUN: skulle använda katalogen $TARGET_DIR"
        return 0
    fi

    mkdir -p -- "$TARGET_DIR"
    log INFO "Katalog klar: $TARGET_DIR"
}

filename_from_url() {
    local url="$1"
    local without_query
    local filename

    without_query="${url%%\?*}"
    without_query="${without_query%%\#*}"
    filename="$(basename -- "$without_query")"

    if [[ -z "$filename" || "$filename" == "." || "$filename" == "/" ]]; then
        return 1
    fi

    printf '%s\n' "$filename"
}

download_debs() {
    local url
    local filename
    local destination

    log INFO "Bearbetar nedladdningslistan."

    for url in "${DEB_URLS[@]}"; do
        if ! filename="$(filename_from_url "$url")"; then
            log ERROR "Kunde inte bestämma filnamn från URL: $url"
            ((DOWNLOAD_FAILED += 1))
            continue
        fi

        destination="$TARGET_DIR/$filename"
        PLANNED_FILES+=("$destination")

        if [[ "$DRYRUN" == true ]]; then
            log INFO "DRY-RUN: skulle ladda ned $url"
            log INFO "DRY-RUN: målfil $destination"
            continue
        fi

        log INFO "Laddar ned: $url"

        if wget "$url" -O "$destination" >> "$LOGFILE" 2>&1; then
            DOWNLOADED_FILES+=("$destination")
            log INFO "Nedladdad: $destination"
        else
            rm -f -- "$destination"
            log ERROR "Nedladdningen misslyckades: $url"
            ((DOWNLOAD_FAILED += 1))
        fi
    done
}

install_debs() {
    local file

    if [[ "$DRYRUN" == true ]]; then
        for file in "${PLANNED_FILES[@]}"; do
            log INFO "DRY-RUN: skulle installera $file"
        done
        return 0
    fi

    if ((${#DOWNLOADED_FILES[@]} == 0)); then
        log WARN "Det finns inga nerladdade paket från denna körning att installera."
        return 0
    fi

    for file in "${DOWNLOADED_FILES[@]}"; do
        log INFO "Installerar: $file"

        if sudo apt-get install -y "$file" >> "$LOGFILE" 2>&1; then
            log INFO "Installerat: $file"
        else
            log ERROR "Installationen misslyckades: $file"
            ((INSTALL_FAILED += 1))
        fi
    done
}

show_summary() {
    log INFO "Sammanfattning: ${#DEB_URLS[@]} URL:er, ${#DOWNLOADED_FILES[@]} nerladdade, $DOWNLOAD_FAILED nedladdningsfel, $INSTALL_FAILED installationsfel."
    log INFO "Loggfil: $LOGFILE"
}

main() {
    parse_args "$@"

    if [[ "$VERBOSITY" == "debug" ]]; then
        log DEBUG "Version: $VERSION"
        log DEBUG "Dry-run: $DRYRUN"
        log DEBUG "URL-fil: $URL_FILE"
        log DEBUG "Målkatalog: $TARGET_DIR"
    fi

    read_url_file
    check_prereqs
    prepare_dir
    download_debs
    install_debs
    show_summary

    if ((DOWNLOAD_FAILED > 0 || INSTALL_FAILED > 0)); then
        log ERROR "Körningen avslutades med ett eller flera fel."
        exit 1
    fi

    log INFO "Klart."
}

main "$@"
