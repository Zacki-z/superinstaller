#!/bin/bash
set -euo pipefail

# ===========================
# DRY RUN?
# ===========================
DRY_RUN="false"
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN="true"
    echo "==================================================="
    echo "🟡 DRY-RUN LÄGE: Ingen fil kommer kopieras, tas bort,"
    echo "    eller skrivas! Endast simulering."
    echo "==================================================="
fi

# ===========================
# Inställningar
# ===========================
HOME_DIR="/home/alain"
USB_MOUNT="/media/alain/move_stuff"
DOT_DIR="${HOME_DIR}/dot-files"
LOG="/tmp/flytta-time"

# Unik temporär fil för tar-fel
ERROR_LOG="$(mktemp /tmp/flytta_errors_XXXXXX)"

# Standard rsync-flaggor
RSYNC_OPTS=(-a --delete --info=progress2)

# Lägg till dry-run om aktiverat
if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

# ===========================
# Hjälpfunktioner
# ===========================
log() {
    echo "$@" | tee -a "$LOG"
}

rsync_mirror() {
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
log "sätt igång (DRY_RUN=$DRY_RUN)"
log "Felfil (tar): $ERROR_LOG"
sleep 1

cd "$HOME_DIR"

# Kontrollera USB-disk
if [[ ! -d "$USB_MOUNT" ]]; then
    log "❌ USB-disk saknas: $USB_MOUNT"
    exit 1
fi

# ===========================
# 1. Spegla lokala config → dot-files
# ===========================
log "Speglar lokala config till ${DOT_DIR}"
sleep 1

mkdir -p \
    "${DOT_DIR}/dot-mixxx" \
    "${DOT_DIR}/dot-cache" \
    "${DOT_DIR}/dot-darktable" \
    "${DOT_DIR}/dot-config"

rsync_mirror "${HOME_DIR}/.mixxx/"         "${DOT_DIR}/dot-mixxx/"
rsync_mirror "${HOME_DIR}/.cache/"         "${DOT_DIR}/dot-cache/"
rsync_mirror "${HOME_DIR}/snap/darktable/" "${DOT_DIR}/dot-darktable/"
rsync_mirror "${HOME_DIR}/.config/"        "${DOT_DIR}/dot-config/"

# ===========================
# 2. Spegla config → USB
# ===========================
log "Speglar configfiler till USB"
sleep 1

mkdir -p \
    "${USB_MOUNT}/dot-mixxx" \
    "${USB_MOUNT}/dot-cache" \
    "${USB_MOUNT}/dot-darktable" \
    "${USB_MOUNT}/dot-config" \
    "${USB_MOUNT}/tar_files" \
    "${USB_MOUNT}/my_bin" \
    "${USB_MOUNT}/my_etc"

rsync_mirror "${HOME_DIR}/.mixxx/"         "${USB_MOUNT}/dot-mixxx/"
rsync_mirror "${HOME_DIR}/.cache/"         "${USB_MOUNT}/dot-cache/"
rsync_mirror "${HOME_DIR}/snap/darktable/" "${USB_MOUNT}/dot-darktable/"
rsync_mirror "${HOME_DIR}/.config/"        "${USB_MOUNT}/dot-config/"

# ===========================
# 3. Packning med tar
# ===========================
TARFILE="${HOME_DIR}/flytta.tarz"

if [[ "$DRY_RUN" == "true" ]]; then
    log "🟡 DRY-RUN: Skipper tar-arkivering (ingen tar skapas)"
else
    log "start packa tar-arkiv"
    sleep 1

    tar cf "$TARFILE" \
        "${HOME_DIR}/Dokument" \
        "${HOME_DIR}/Documents" \
        "${HOME_DIR}/Bilder" \
        "${HOME_DIR}/Pictures" \
        "${HOME_DIR}/Musik" \
        "${HOME_DIR}/bup_darktable" \
        "${HOME_DIR}/Skrivbord" \
        "${HOME_DIR}/Desktop" \
        "${HOME_DIR}/my_bin" \
        "${HOME_DIR}/my_etc" \
        "${HOME_DIR}/Calibre Library" \
        "${DOT_DIR}" \
        "${HOME_DIR}/Arduino" \
        "${HOME_DIR}/kicad_stuff" \
        "${HOME_DIR}/Applications" \
        2> "$ERROR_LOG"

    log "flyttar tar-arkiv till USB"
    cp -v "$TARFILE" "${USB_MOUNT}/tar_files/"
fi

# ===========================
# 4. Spegla my_bin och my_etc
# ===========================
log "Speglar my_bin"
sleep 1
rsync_mirror "${HOME_DIR}/my_bin/" "${USB_MOUNT}/my_bin/"

log "Speglar my_etc"
sleep 1
rsync_mirror "${HOME_DIR}/my_etc/" "${USB_MOUNT}/my_etc/"

cd "$HOME_DIR"

# ===========================
# 5. Ta bort tar-avbild (inte i dry-run)
# ===========================
if [[ "$DRY_RUN" == "true" ]]; then
    log "🟡 DRY-RUN: tar-filen tas inte bort (ingen tar skapad)"
else
    rm -i "$TARFILE"
fi

log "klart"
date >> "$LOG"

log "Om tar gav fel, se: $ERROR_LOG"

