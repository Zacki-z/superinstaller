# ================================================
# packa_to_move.sh – Release 5.8 (2025-11-21)
#
# Förbättringar i 5.8:
#   • --help / -h visar hjälptext och avslutar
#   • Tydlig version/namn i hjälp och logg
#
# Innehåll från tidigare releaser:
#   • Version-variabler (VERSION, RELEASE_DATE)
#   • Zstandard-komprimering (zstd) som standard
#   • Fallback till gzip om zstd saknas
#   • pv-progressbar vid packning och kopiering
#   • Datumstämplade arkivfiler (YYYY-MM-DD_HHMM)
#   • DRY-RUN-läge (--dry-run / -n)
#   • Robust felhantering
# ================================================

#!/bin/bash
set -euo pipefail

VERSION="5.8"
RELEASE_DATE="2025-11-21"

SCRIPT_NAME="$(basename "$0")"

# ===========================
# Hjälptext
# ===========================
show_help() {
    cat <<EOF
${SCRIPT_NAME} – backup/packscript (version ${VERSION}, ${RELEASE_DATE})

Använder tar + zstd (eller gzip) för att packa utvalda kataloger
(enligt filen tar_dirs.txt) samt speglar config och my_bin/my_etc
till en USB-disk.

USAGE:
  ${SCRIPT_NAME} [OPTION]

OPTIONS:
  -h, --help       Visa denna hjälptext och avsluta.
  -n, --dry-run    Kör i torrkörningsläge:
                   • rsync körs med --dry-run
                   • ingen tar-fil skapas
                   • ingen kopiering till USB
                   • ingen tar-fil tas bort

DAVBETEENDE:
  • Läser lista över kataloger från:
      \$HOME/my_bin/etc/tar_dirs.txt
    (en katalog per rad, # = kommentar)

  • Skapar arkiv:
      \$HOME/flytta-YYYY-MM-DD_HHMM.tar.zst   (om zstd finns)
      eller
      \$HOME/flytta-YYYY-MM-DD_HHMM.tar.gz    (fallback)

  • Lägger arkivet på USB under:
      /media/alain/move_stuff/tar_files/

  • Speglar dessutom:
      ~/.mixxx, ~/.cache, ~/.config,
      \$HOME/my_bin, \$HOME/my_etc

EOF
}

# ===========================
# Standard-flaggor
# ===========================
DRY_RUN="false"

# ===========================
# Tolka första argumentet
# ===========================
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -n|--dry-run)
        DRY_RUN="true"
        echo "==================================================="
        echo "🟡 DRY-RUN LÄGE: Ingen fil kommer kopieras, tas bort,"
        echo "    eller skrivas! Endast simulering."
        echo "==================================================="
        ;;
    "" )
        # Inga argument – kör normalt
        ;;
    *)
        echo "Okänd flagga: $1"
        echo "Använd --help för hjälp."
        exit 1
        ;;
esac

# ===========================
# Inställningar
# ===========================
HOME_DIR="${HOME:-/home/alain}"
USB_MOUNT="/media/alain/move_stuff"
DOT_DIR="${HOME_DIR}/dot-files"
LOG="/tmp/flytta-time"

# Fil med lista över kataloger som ska in i tar (relativa till $HOME_DIR)
TAR_LIST_FILE="${HOME_DIR}/my_bin/etc/tar_dirs.txt"

# Unik temporär fil för tar-fel
ERROR_LOG="$(mktemp /tmp/flytta_errors_XXXXXX)"

# Standard rsync-flaggor
RSYNC_OPTS=(-a --delete --info=progress2)

# Lägg till dry-run om aktiverat
if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

# ===========================
# Hjälpfunktioner (logg + rsync)
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
log "packa_to_move.sh – version ${VERSION} (${RELEASE_DATE})"
log "sätt igång (DRY_RUN=$DRY_RUN)"
log "Felfil (tar): $ERROR_LOG"
sleep 1

cd "$HOME_DIR"

# Kontrollera USB-disk
if [[ ! -d "$USB_MOUNT" ]]; then
    log "❌ USB-disk saknas: $USB_MOUNT"
    exit 1
fi

# Kontrollera tar-listfil
if [[ ! -f "$TAR_LIST_FILE" ]]; then
    log "❌ tar-listfil saknas: $TAR_LIST_FILE"
    exit 1
fi

# ===========================
# Läs in kataloger till BACKUP_DIRS (relativa till $HOME_DIR)
# ===========================
BACKUP_DIRS=()
log "Läser kataloglista från: $TAR_LIST_FILE"
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue
    BACKUP_DIRS+=("$line")
done < "$TAR_LIST_FILE"

log "Följande kataloger (relativa till $HOME_DIR) kommer packas i tar:"
for d in "${BACKUP_DIRS[@]}"; do
    log "  - $d"
done
echo

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

if [[ -d "${HOME_DIR}/snap/darktable" ]]; then
    rsync_mirror "${HOME_DIR}/snap/darktable/" "${DOT_DIR}/dot-darktable/"
else
    log "⛔ hoppar darktable → dot-files, katalog saknas: ${HOME_DIR}/snap/darktable/"
fi

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

if [[ -d "${HOME_DIR}/snap/darktable" ]]; then
    rsync_mirror "${HOME_DIR}/snap/darktable/" "${USB_MOUNT}/dot-darktable/"
else
    log "⛔ hoppar darktable → USB, katalog saknas: ${HOME_DIR}/snap/darktable/"
fi

rsync_mirror "${HOME_DIR}/.config/"        "${USB_MOUNT}/dot-config/"

# ===========================
# 3. Packning med tar + zstd/gzip + pv + DATUMSTÄMPLING
# ===========================

TIMESTAMP="$(date +'%Y-%m-%d_%H%M')"

# Standard: försök använda zstd, annars gzip
if command -v zstd >/dev/null 2>&1; then
    COMPRESSOR="zstd"
    EXT="tar.zst"
else
    COMPRESSOR="gzip"
    EXT="tar.gz"
fi

TARFILE="${HOME_DIR}/flytta-${TIMESTAMP}.${EXT}"
log "Komprimeringsmetod: ${COMPRESSOR} (fil: $(basename "$TARFILE"))"

if [[ "$DRY_RUN" == "true" ]]; then
    log "🟡 DRY-RUN: Skipper tar-arkivering och kopiering (ingen tar skapas)"
else
    log "Startar packning: $TARFILE"
    sleep 1

    # Beräkna total storlek (i bytes) för alla kataloger
    cd "$HOME_DIR"
    TOTAL_SIZE="$(du -cb "${BACKUP_DIRS[@]}" 2>/dev/null | tail -1 | cut -f1)"
    cd "$HOME_DIR"

    TAR_LIST="$(mktemp /tmp/flytta_tarlist_XXXXXX)"
    printf "%s\n" "${BACKUP_DIRS[@]}" > "$TAR_LIST"

    if command -v pv >/dev/null 2>&1; then
        log "pv hittades – använder progress-bar vid packning"

        if [[ "$COMPRESSOR" == "zstd" ]]; then
            (
                cd "$HOME_DIR"
                tar cf - -T "$TAR_LIST" 2> "$ERROR_LOG"
            ) | pv -s "$TOTAL_SIZE" | zstd -T0 -q -c > "$TARFILE"
        else
            (
                cd "$HOME_DIR"
                tar cf - -T "$TAR_LIST" 2> "$ERROR_LOG"
            ) | pv -s "$TOTAL_SIZE" | gzip -c > "$TARFILE"
        fi
    else
        log "pv saknas – packar utan progress-bar"

        if [[ "$COMPRESSOR" == "zstd" ]]; then
            (
                cd "$HOME_DIR"
                tar cf - -T "$TAR_LIST" 2> "$ERROR_LOG"
            ) | zstd -T0 -q -c > "$TARFILE"
        else
            (
                cd "$HOME_DIR"
                tar cf - -T "$TAR_LIST" 2> "$ERROR_LOG"
            ) | gzip -c > "$TARFILE"
        fi
    fi

    rm -f "$TAR_LIST"

    # Kopiera arkivet till USB (också med pv om möjligt)
    log "Kopierar arkiv till USB"
    DEST_TAR="${USB_MOUNT}/tar_files/$(basename "$TARFILE")"

    if command -v pv >/dev/null 2>&1; then
        log "pv hittades – kopierar med progress-bar"
        pv "$TARFILE" > "$DEST_TAR"
    else
        log "pv saknas – använder cp -v"
        cp -v "$TARFILE" "$DEST_TAR"
    fi
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
# 5. Ta bort lokal tar-avbild (inte i dry-run)
# ===========================
if [[ "$DRY_RUN" == "true" ]]; then
    log "🟡 DRY-RUN: tar-filen tas inte bort (ingen tar skapad eller berörs)"
else
    rm -i "$TARFILE"
fi

log "klart"
date >> "$LOG"
log "Om tar gav fel, se: $ERROR_LOG"

