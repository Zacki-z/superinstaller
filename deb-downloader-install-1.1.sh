#!/bin/bash
set -euo pipefail

###############################################################################
# deb-downloader-install.sh (v1.1 med loggning)
#
# 1) Läser .deb-URL:er från en textfil (standard: deb_list.txt)
# 2) Laddar ner .deb-filer till ett valt bibliotek
# 3) Installerar dem med apt-get install ./file.deb
#
###############################################################################

DRYRUN=false
VERBOSITY="normal"
TARGET_DIR="$HOME/deb_packages"
URL_FILE="etc/deb_list.txt"

###############################################################################
#                           LOGGNING
###############################################################################

LOGDIR="$HOME/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/deb-downloader-$(date +%Y-%m-%d_%H-%M-%S).log"

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Alltid till loggfil:
    echo "[$timestamp] [$level] $msg" >> "$LOGFILE"

    # Terminalutskrift beror på verbosity
    if [[ "$VERBOSITY" == "quiet" ]]; then
        [[ "$level" == "ERROR" ]] && echo "[$timestamp] [$level] $msg"
    else
        echo "[$timestamp] [$level] $msg"
    fi
}

###############################################################################
#                           FUNKTIONER
###############################################################################

usage() {
    echo "Usage: $0 [-n] [-v verbosity] [-d target_dir] [-f url_file]"
    echo ""
    echo "  -n                Dry-run (ladda inte ner / installera)"
    echo "  -v <verbosity>    quiet | normal"
    echo "  -d <dir>          Katalog att spara .deb i"
    echo "  -f <file>         Textfil med .deb-URL:er"
    exit 1
}

parse_args() {
    while getopts "nv:d:f:" opt; do
        case "$opt" in
            n) DRYRUN=true ;;
            v) VERBOSITY="$OPTARG" ;;
            d) TARGET_DIR="$OPTARG" ;;
            f) URL_FILE="$OPTARG" ;;
            *) usage ;;
        esac
    done
}

read_url_file() {
    if [[ ! -f "$URL_FILE" ]]; then
        log ERROR "URL-fil saknas: $URL_FILE"
        exit 1
    fi

    mapfile -t DEB_URLS < "$URL_FILE"
    log INFO "Läste ${#DEB_URLS[@]} URL:er från $URL_FILE"
}

check_prereqs() {
    if ! command -v wget >/dev/null 2>&1; then
        log ERROR "wget saknas. Installera med: sudo apt install wget"
        exit 1
    fi
    log INFO "Alla beroenden uppfyllda."
}

prepare_dir() {
    mkdir -p "$TARGET_DIR"
    log INFO "Katalog OK: $TARGET_DIR"
}

download_debs() {
    log INFO "Startar nedladdning…"

    for url in "${DEB_URLS[@]}"; do
        [[ -z "$url" ]] && continue
        filename="$TARGET_DIR/$(basename "$url")"

        log INFO "Laddar ner: $url"

        if $DRYRUN; then
            log INFO "DRYRUN: skulle ha laddat ner → $filename"
            continue
        fi

        wget -q "$url" -O "$filename" 2>&1 | tee -a "$LOGFILE"
        log INFO "Nedladdat → $filename"
    done
}

install_debs() {
    log INFO "Installerar .deb-filer…"

    for file in "$TARGET_DIR"/*.deb; do
        [[ ! -e "$file" ]] && { log WARN "Inga .deb-filer hittades."; return; }

        log INFO "Installerar: $file"

        if $DRYRUN; then
            log INFO "DRYRUN: skulle ha installerat → $file"
            continue
        fi

        sudo apt -y install "$file" 2>&1 | tee -a "$LOGFILE"
    done
}

###############################################################################
#                           HUVUDPROGRAM
###############################################################################

main() {
    parse_args "$@"
    read_url_file
    check_prereqs
    prepare_dir
    download_debs
    install_debs
    log INFO "KLART! 🎉 Logg finns här: $LOGFILE"
}

main "$@"

