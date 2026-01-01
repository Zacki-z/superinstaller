#!/bin/bash
set -euo pipefail

###############################################################################
# deb-downloader-install.sh
#
# 1) Läser .deb-URL:er från en textfil (standard: deb_list.txt)
# 2) Laddar ner .deb-filer till ett valt bibliotek
# 3) Installerar dem med apt-get install ./file.deb
#
###############################################################################

DRYRUN=false
VERBOSITY="normal"
TARGET_DIR="$HOME/deb_packages"
URL_FILE="deb_list.txt"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

log() {
    local level="$1"; shift
    local msg="$*"

    case "$VERBOSITY" in
        quiet)
            [[ "$level" == "ERROR" ]] || return 0
            ;;
        normal)
            [[ "$level" == "DEBUG" ]] && return 0
            ;;
        verbose)
            ;;
    esac

    case "$level" in
        INFO)  printf "${BLUE}[INFO]${NC}  %s\n" "$msg" ;;
        WARN)  printf "${YELLOW}[WARN]${NC}  %s\n" "$msg" ;;
        ERROR) printf "${RED}[ERROR]${NC} %s\n" "$msg" ;;
        DEBUG) printf "${GREEN}[DEBUG]${NC} %s\n" "$msg" ;;
    esac
}

run_cmd() {
    if $DRYRUN; then
        log DEBUG "DRY-RUN: $*"
    else
        log DEBUG "Kör: $*"
        "$@"
    fi
}

usage() {
    cat <<EOF
Användning: $0 [alternativ]

Alternativ:
  --dir PATH        Var .deb-filer ska sparas (default: $TARGET_DIR)
  --list FIL        Fil med .deb-URL:er (default: $URL_FILE)
  --dry-run         Visa åtgärder utan att göra något
  --quiet           Endast fel skrivs ut
  --verbose         Extra debug-utskrifter
  -h, --help        Visa denna hjälp

Format på URL-listan:
  En URL per rad
  Tomma rader och rader som börjar med # ignoreras

Exempel:
  $0 --list deb_list.txt --dir ~/mina_debs
EOF
}

# -------------------------------
# Argument-parsing
# -------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            TARGET_DIR="$2"; shift
            ;;
        --list)
            URL_FILE="$2"; shift
            ;;
        --dry-run)
            DRYRUN=true
            ;;
        --quiet)
            VERBOSITY="quiet"
            ;;
        --verbose)
            VERBOSITY="verbose"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log WARN "Okänt argument: $1 (ignoreras)"
            ;;
    esac
    shift
done

# -------------------------------
# Läs URL:er från textfil
# -------------------------------
read_url_file() {
    log INFO "Läser URL:er från fil: $URL_FILE"

    if [[ ! -f "$URL_FILE" ]]; then
        log ERROR "Fil saknas: $URL_FILE"
        exit 1
    fi

    mapfile -t DEB_URLS < <(
        grep -Ev '^\s*(#|$)' "$URL_FILE"
    )

    if [[ "${#DEB_URLS[@]}" -eq 0 ]]; then
        log WARN "Inga URL:er hittades i $URL_FILE"
    fi
}

# -------------------------------
# Förkrav
# -------------------------------
check_prereqs() {
    for bin in wget apt-get; do
        if ! command -v "$bin" >/dev/null; then
            log ERROR "Saknar program: $bin"
            exit 1
        fi
    done
}

# -------------------------------
# Skapa katalog
# -------------------------------
prepare_dir() {
    log INFO "Skapar katalog: $TARGET_DIR"
    run_cmd mkdir -p "$TARGET_DIR"
}

# -------------------------------
# Nedladdning
# -------------------------------
download_debs() {
    if [[ "${#DEB_URLS[@]}" -eq 0 ]]; then
        log WARN "Inga URL:er att ladda ner"
        return
    fi

    log INFO "Laddar ner .deb-filer …"

    for url in "${DEB_URLS[@]}"; do
        log INFO "Hämtar: $url"

        if $DRYRUN; then
            run_cmd wget -P "$TARGET_DIR" -N "$url"
        else
            wget -P "$TARGET_DIR" -N "$url"
        fi
    done
}

# -------------------------------
# Installation
# -------------------------------
install_debs() {
    log INFO "Installerar .deb-filer från: $TARGET_DIR"

    mapfile -t debs < <(find "$TARGET_DIR" -name "*.deb" -type f)

    if [[ "${#debs[@]}" -eq 0 ]]; then
        log WARN "Inga .deb-filer att installera."
        return
    fi

    log INFO "Installerar ${#debs[@]} st .deb-paket"
    run_cmd sudo apt-get install -y "${debs[@]}"
}

# -------------------------------
# Huvud
# -------------------------------
main() {
    read_url_file
    check_prereqs
    prepare_dir
    download_debs
    install_debs
    log INFO "Klart! 🎉"
}

main
#!/bin/bash
set -euo pipefail

###############################################################################
# deb-downloader-install.sh
#
# 1) Läser .deb-URL:er från en textfil (standard: deb_list.txt)
# 2) Laddar ner .deb-filer till ett valt bibliotek
# 3) Installerar dem med apt-get install ./file.deb
#
###############################################################################

DRYRUN=false
VERBOSITY="normal"
TARGET_DIR="$HOME/deb_packages"
URL_FILE="deb_list.txt"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

log() {
    local level="$1"; shift
    local msg="$*"

    case "$VERBOSITY" in
        quiet)
            [[ "$level" == "ERROR" ]] || return 0
            ;;
        normal)
            [[ "$level" == "DEBUG" ]] && return 0
            ;;
        verbose)
            ;;
    esac

    case "$level" in
        INFO)  printf "${BLUE}[INFO]${NC}  %s\n" "$msg" ;;
        WARN)  printf "${YELLOW}[WARN]${NC}  %s\n" "$msg" ;;
        ERROR) printf "${RED}[ERROR]${NC} %s\n" "$msg" ;;
        DEBUG) printf "${GREEN}[DEBUG]${NC} %s\n" "$msg" ;;
    esac
}

run_cmd() {
    if $DRYRUN; then
        log DEBUG "DRY-RUN: $*"
    else
        log DEBUG "Kör: $*"
        "$@"
    fi
}

usage() {
    cat <<EOF
Användning: $0 [alternativ]

Alternativ:
  --dir PATH        Var .deb-filer ska sparas (default: $TARGET_DIR)
  --list FIL        Fil med .deb-URL:er (default: $URL_FILE)
  --dry-run         Visa åtgärder utan att göra något
  --quiet           Endast fel skrivs ut
  --verbose         Extra debug-utskrifter
  -h, --help        Visa denna hjälp

Format på URL-listan:
  En URL per rad
  Tomma rader och rader som börjar med # ignoreras

Exempel:
  $0 --list deb_list.txt --dir ~/mina_debs
EOF
}

# -------------------------------
# Argument-parsing
# -------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            TARGET_DIR="$2"; shift
            ;;
        --list)
            URL_FILE="$2"; shift
            ;;
        --dry-run)
            DRYRUN=true
            ;;
        --quiet)
            VERBOSITY="quiet"
            ;;
        --verbose)
            VERBOSITY="verbose"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log WARN "Okänt argument: $1 (ignoreras)"
            ;;
    esac
    shift
done

# -------------------------------
# Läs URL:er från textfil
# -------------------------------
read_url_file() {
    log INFO "Läser URL:er från fil: $URL_FILE"

    if [[ ! -f "$URL_FILE" ]]; then
        log ERROR "Fil saknas: $URL_FILE"
        exit 1
    fi

    mapfile -t DEB_URLS < <(
        grep -Ev '^\s*(#|$)' "$URL_FILE"
    )

    if [[ "${#DEB_URLS[@]}" -eq 0 ]]; then
        log WARN "Inga URL:er hittades i $URL_FILE"
    fi
}

# -------------------------------
# Förkrav
# -------------------------------
check_prereqs() {
    for bin in wget apt-get; do
        if ! command -v "$bin" >/dev/null; then
            log ERROR "Saknar program: $bin"
            exit 1
        fi
    done
}

# -------------------------------
# Skapa katalog
# -------------------------------
prepare_dir() {
    log INFO "Skapar katalog: $TARGET_DIR"
    run_cmd mkdir -p "$TARGET_DIR"
}

# -------------------------------
# Nedladdning
# -------------------------------
download_debs() {
    if [[ "${#DEB_URLS[@]}" -eq 0 ]]; then
        log WARN "Inga URL:er att ladda ner"
        return
    fi

    log INFO "Laddar ner .deb-filer …"

    for url in "${DEB_URLS[@]}"; do
        log INFO "Hämtar: $url"

        if $DRYRUN; then
            run_cmd wget -P "$TARGET_DIR" -N "$url"
        else
            wget -P "$TARGET_DIR" -N "$url"
        fi
    done
}

# -------------------------------
# Installation
# -------------------------------
install_debs() {
    log INFO "Installerar .deb-filer från: $TARGET_DIR"

    mapfile -t debs < <(find "$TARGET_DIR" -name "*.deb" -type f)

    if [[ "${#debs[@]}" -eq 0 ]]; then
        log WARN "Inga .deb-filer att installera."
        return
    fi

    log INFO "Installerar ${#debs[@]} st .deb-paket"
    run_cmd sudo apt-get install -y "${debs[@]}"
}

# -------------------------------
# Huvud
# -------------------------------
main() {
    read_url_file
    check_prereqs
    prepare_dir
    download_debs
    install_debs
    log INFO "Klart! 🎉"
}

main

