#!/bin/bash
# ================================================
# packupp_from_move.sh – Release 2.1 (2025-11-21)
#
# Förbättringar i 2.1:
#   • --dest= tolkas alltid relativt HOME → uppackning under $HOME
#   • pv-progressbar vid tar-uppackning (.tar.zst / .tar.gz / .tar)
#   • Version-header, VERSION/RELEASE_DATE och --help / -h
#
# Befintlig funktionalitet:
#   • DRY-RUN-läge (--dry-run / -n)
#   • Återställning via rsync av:
#       – dot-mixxx → ~/.mixxx
#       – dot-cache → ~/.cache
#       – dot-darktable → ~/snap/darktable
#       – dot-config → ~/.config
#       – my_bin → ~/my_bin
#       – my_etc → ~/my_etc
#   • Hämtar senaste arkiv från: /media/$USER/move_stuff/tar_files
#     med namn flytta-*.tar.{zst,gz} eller flytta*.tarz
# ================================================

set -euo pipefail

VERSION="2.1"
RELEASE_DATE="2025-11-21"
SCRIPT_NAME="$(basename "$0")"

# ===========================
# Hjälptext
# ===========================
show_help() {
    cat <<EOF
${SCRIPT_NAME} – återställning från move_stuff (version ${VERSION}, ${RELEASE_DATE})

Används för att:
  • rsync-återställa config och skript från USB:
      /media/\$USER/move_stuff/
  • packa upp senaste flytta-*.tar.zst/tar.gz/tarz
    till en katalog under \$HOME.

USAGE:
  ${SCRIPT_NAME} [OPTIONER]

OPTIONER:
  -h, --help          Visa denna hjälptext och avsluta.
  -n, --dry-run       Torrkörning:
                      • rsync körs med --dry-run
                      • ingen tar-uppackning görs (bara loggar vad som skulle hänt)
  --dest=KATALOG      Var tar-arkivet ska packas upp, RELATIVT \$HOME.
                      Exempel:
                        --dest=restore     →  \$HOME/restore
                        --dest=foo/bar     →  \$HOME/foo/bar
                      Om --dest inte anges → uppackning direkt i \$HOME.

DAVBETEENDE:
  • Läser arkiv från: /media/\$USER/move_stuff/tar_files/
  • Hittar senaste: flytta-*.tar.zst, flytta-*.tar.gz eller flytta*.tarz
  • Om pv finns används progress-bar vid uppackning.

EOF
}

# ===========================
# DRY RUN? + DESTINATION (alltid under $HOME)
# ===========================
DRY_RUN="false"
TAR_DEST_REL=""

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run|-n)
            DRY_RUN="true"
            ;;
        --dest=*)
            TAR_DEST_REL="${arg#*=}"
            ;;
        *)
            echo "Okänd flagga: $arg"
            echo "Använd --help för hjälp."
            exit 1
            ;;
    esac
done

# Normalisera destinationen: alltid under $HOME
if [[ -z "$TAR_DEST_REL" ]]; then
    TAR_DEST="$HOME"
else
    # Ta bort ev. inledande slash för att undvika absoluta paths
    TAR_DEST="$HOME/${TAR_DEST_REL#/}"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "==================================================="
    echo "🟡 DRY-RUN LÄGE: Ingen fil kommer skrivas eller ändras."
    echo "    Endast simulering (rsync --dry-run, ingen tar-uppackning)."
    echo "==================================================="
fi

# ===========================
# Inställningar
# ===========================
HOME_DIR="${HOME}"
USB_MOUNT="/media/${USER}/move_stuff"

LOG="/tmp/packupp-time"
ERROR_LOG="$(mktemp /tmp/packupp_errors_XXXXXX)"

# rsync-flaggor för RESTORE (ingen --delete)
RSYNC_OPTS=(-a -h --info=progress2)
if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

TAR_DIR="${USB_MOUNT}/tar_files"

# Transformregel för toppkatalog i arkivet (behålls för kompatibilitet)
TAR_OLD="home"
TAR_NEW="hem"

# ===========================
# Hjälpfunktioner
# ===========================
log() {
    echo "$@" | tee -a "$LOG"
}

ask_create_dir() {
    local dir="$1"

    if [[ -d "$dir" ]]; then
        log "📁 Katalog finns redan: $dir"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "🟡 DRY-RUN: Skulle skapa katalog: $dir"
        return 0
    fi

    echo
    echo "⚠️  Katalog saknas:"
    echo "    $dir"
    read -rp "Vill du skapa den? [y/N] " answer

    case "$answer" in
        y|Y|yes|YES)
            mkdir -p "$dir"
            log "📁 Skapade katalog: $dir"
            return 0
            ;;
        *)
            log "❌ Skapar inte katalog: $dir (kan påverka återställning)"
            return 1
            ;;
    esac
}

rsync_restore() {
    local src="$1"
    local dest="$2"

    if [[ ! -d "$src" && ! -e "$src" ]]; then
        log "⚠️  Källa saknas, hoppar över: $src"
        return 0
    fi

    if ! ask_create_dir "$dest"; then
        log "⏭️ Hoppar över rsync för: $src → $dest (katalog ej skapad)"
        echo
        return 0
    fi

    log "  rsync: $src → $dest (opts: ${RSYNC_OPTS[*]})"
    rsync "${RSYNC_OPTS[@]}" "$src" "$dest"
    echo
}

# ===========================
# Start
# ===========================
: > "$LOG"
date >> "$LOG"
log "packupp_from_move.sh – version ${VERSION} (${RELEASE_DATE})"
log "DRY_RUN=$DRY_RUN"
log "Felfil (tar): $ERROR_LOG"
log "Mål för tar-uppackning (under HOME): $TAR_DEST"
sleep 1

# Kolla USB
if [[ ! -d "$USB_MOUNT" ]]; then
    log "❌ USB-disk saknas: $USB_MOUNT"
    exit 1
fi

cd "$HOME_DIR"

# ===========================
# 1. Återställ config från USB
# ===========================
log "Återställer config från USB → HOME"

rsync_restore "${USB_MOUNT}/dot-mixxx/"     "${HOME_DIR}/.mixxx/"
rsync_restore "${USB_MOUNT}/dot-cache/"     "${HOME_DIR}/.cache/"
rsync_restore "${USB_MOUNT}/dot-darktable/" "${HOME_DIR}/snap/darktable/"
rsync_restore "${USB_MOUNT}/dot-config/"    "${HOME_DIR}/.config/"

# ===========================
# 2. Återställ my_bin och my_etc från USB
# ===========================
log "Återställer my_bin och my_etc från USB"

rsync_restore "${USB_MOUNT}/my_bin/" "${HOME_DIR}/my_bin/"
rsync_restore "${USB_MOUNT}/my_etc/" "${HOME_DIR}/my_etc/"

# ===========================
# 3. Hitta senaste tar-arkiv (.tar.zst / .tar.gz / .tarz)
# ===========================
LATEST_TAR=""

if [[ -d "$TAR_DIR" ]]; then
    LATEST_TAR=$(ls -1t \
        "${TAR_DIR}"/flytta*.tar.zst \
        "${TAR_DIR}"/flytta*.tar.gz \
        "${TAR_DIR}"/flytta*.tarz \
        2>/dev/null | head -n1 || true)
fi

if [[ -z "${LATEST_TAR}" ]]; then
    log "⚠️  Hittar inget tar-arkiv i: $TAR_DIR (hoppar över tar-uppackning)"
else
    log "Senaste tar-arkiv: $LATEST_TAR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "🟡 DRY-RUN: Skippar faktisk uppackning av tar."
        log "  (Skulle packa upp $(basename "$LATEST_TAR") till $TAR_DEST)"
    else
        echo
        echo "⚠️  VARNING: Detta kommer packa upp TAR-arkivet"
        echo "    och kan skriva över filer i din mål-katalog:"
        echo
        echo "      TAR-fil : $LATEST_TAR"
        echo "      DEST    : $TAR_DEST"
        echo
        read -rp "Vill du fortsätta? Skriv exakt: yes → " confirm

        if [[ "$confirm" != "yes" ]]; then
            log "❌ Avbryter tar-uppackning (svar: $confirm)"
        else
            log "Packar upp tar-arkivet till: $TAR_DEST"
            sleep 1

            # ===========================
            # TAR-UPPACKNING MED PV
            # ===========================
            if command -v pv >/dev/null 2>&1; then
                log "pv hittades – använder progress-bar vid uppackning"

                if [[ "$LATEST_TAR" == *.tar.zst ]]; then
                    pv "$LATEST_TAR" \
                    | zstd -d -q \
                    | tar xf - \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"

                elif [[ "$LATEST_TAR" == *.tar.gz ]]; then
                    pv "$LATEST_TAR" \
                    | gzip -dc \
                    | tar xf - \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"

                else
                    # .tar, .tarz eller okänt → behandla som ren tar
                    pv "$LATEST_TAR" \
                    | tar xf - \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"
                fi

            else
                log "pv saknas – uppackning utan progress-bar"

                if [[ "$LATEST_TAR" == *.tar.zst ]]; then
                    zstd -d -q -c "$LATEST_TAR" \
                    | tar xf - \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"

                elif [[ "$LATEST_TAR" == *.tar.gz ]]; then
                    gzip -dc "$LATEST_TAR" \
                    | tar xf - \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"

                else
                    tar xf "$LATEST_TAR" \
                        -C "$TAR_DEST" \
                        --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                        2> "$ERROR_LOG"
                fi
            fi
        fi
    fi
fi

log "klart"
date >> "$LOG"
log "Om tar gav fel, se: $ERROR_LOG"

if [[ "$DRY_RUN" == "true" ]]; then
    log "✅ DRY-RUN klar – inga filer ändrades."
fi

