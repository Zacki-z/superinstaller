#!/bin/bash
set -euo pipefail

# ===========================
# DRY RUN?
# ===========================
DRY_RUN="false"
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN="true"
    echo "==================================================="
    echo "🟡 DRY-RUN LÄGE: Ingen fil kommer skrivas eller ändras."
    echo "    Endast simulering (rsync --dry-run)."
    echo "==================================================="
fi

# ===========================
# Inställningar
# ===========================
HOME_DIR="/home/alain"
USB_MOUNT="/media/alain/move_stuff"

LOG="/tmp/packupp-time"
ERROR_LOG="$(mktemp /tmp/packupp_errors_XXXXXX)"

# rsync-flaggor för RESTORE (ingen --delete)
RSYNC_OPTS=(-a --info=progress2)

if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

TAR_DIR="${USB_MOUNT}/tar_files"

# ===========================
# Hjälpfunktioner
# ===========================
log() {
    echo "$@" | tee -a "$LOG"
}

rsync_restore() {
    local src="$1"
    local dest="$2"

    log "  rsync: $src → $dest (opts: ${RSYNC_OPTS[*]})"
    rsync "${RSYNC_OPTS[@]}" "$src" "$dest"
    echo
}

# ===========================
# Start
# ===========================
: > "$LOG"
date >> "$LOG"
log "pack upp startar (DRY_RUN=$DRY_RUN)"
log "Felfil (tar): $ERROR_LOG"
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

mkdir -p \
    "${HOME_DIR}/.mixxx" \
    "${HOME_DIR}/.cache" \
    "${HOME_DIR}/snap/darktable" \
    "${HOME_DIR}/.config"

rsync_restore "${USB_MOUNT}/dot-mixxx/"    "${HOME_DIR}/.mixxx/"
rsync_restore "${USB_MOUNT}/dot-cache/"    "${HOME_DIR}/.cache/"
rsync_restore "${USB_MOUNT}/dot-darktable/" "${HOME_DIR}/snap/darktable/"
rsync_restore "${USB_MOUNT}/dot-config/"   "${HOME_DIR}/.config/"

# ===========================
# 2. Återställ my_bin och my_etc från USB
# ===========================
log "Återställer my_bin och my_etc från USB"

mkdir -p \
    "${HOME_DIR}/my_bin" \
    "${HOME_DIR}/my_etc"

rsync_restore "${USB_MOUNT}/my_bin/" "${HOME_DIR}/my_bin/"
rsync_restore "${USB_MOUNT}/my_etc/" "${HOME_DIR}/my_etc/"

# ===========================
# 3. Hitta senaste tar-arkiv
# ===========================
LATEST_TAR=""

if [[ -d "$TAR_DIR" ]]; then
    LATEST_TAR=$(ls -1t "${TAR_DIR}"/flytta*.tarz 2>/dev/null | head -n1 || true)
fi

if [[ -z "${LATEST_TAR}" ]]; then
    log "⚠️  Hittar inget tar-arkiv i: $TAR_DIR (hoppar över tar-uppackning)"
else
    log "Senaste tar-arkiv: $LATEST_TAR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "🟡 DRY-RUN: Skipper faktisk uppackning av tar."
        log "  (Skulle ha kört: tar xf \"$LATEST_TAR\")"
    else
        # ===========================
        # SÄKERHETSFRÅGA
        # ===========================
        echo
        echo "⚠️  VARNING: Detta kommer packa upp TAR-arkivet"
        echo "    och skriva över filer i ditt hemkatalogträd:"
        echo
        echo "      $LATEST_TAR"
        echo
        read -rp "Vill du fortsätta? Skriv exakt: yes → " confirm

        if [[ "$confirm" != "yes" ]]; then
            log "❌ Avbryter tar-uppackning (fel svar: $confirm)"
        else
            log "Packar upp tar-arkivet till systemet"
            sleep 1
            tar xf "$LATEST_TAR" 2> "$ERROR_LOG"
        fi
    fi
fi

log "klart"
date >> "$LOG"
log "Om tar gav fel, se: $ERROR_LOG"

