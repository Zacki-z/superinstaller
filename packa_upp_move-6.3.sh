#!/bin/bash
set -euo pipefail

# ===========================
# DRY RUN? + DESTINATION
# ===========================
DRY_RUN="false"
TAR_DEST="/"

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)
            DRY_RUN="true"
            ;;
        --dest=*)
            TAR_DEST="${arg#*=}"
            ;;
    esac
done

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
# -a : arkivläge
# -h : human-readable (storlekar)
# --info=progress2 : totalprogress
RSYNC_OPTS=(-a -h --info=progress2)
if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

TAR_DIR="${USB_MOUNT}/tar_files"

# Byt namn på katalog i tar-arkivet vid uppackning:
# t.ex. "home" -> "hem"
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

    # Källkatalog måste finnas (på USB)
    if [[ ! -d "$src" && ! -e "$src" ]]; then
        log "⚠️  Källa saknas, hoppar över: $src"
        return 0
    fi

    # Se till att målkatalog finns eller fråga om den ska skapas
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
log "pack upp startar (DRY_RUN=$DRY_RUN)"
log "Felfil (tar): $ERROR_LOG"
log "Mål för tar-uppackning (dest): $TAR_DEST"
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
log "Återställer config från USB → HOME, just nu utkommenterat /aw 251122"

#rsync_restore "${USB_MOUNT}/dot-mixxx/"     "${HOME_DIR}/.mixxx/"
#rsync_restore "${USB_MOUNT}/dot-cache/"     "${HOME_DIR}/.cache/"
#rsync_restore "${USB_MOUNT}/dot-darktable/" "${HOME_DIR}/snap/darktable/"
#rsync_restore "${USB_MOUNT}/dot-config/"    "${HOME_DIR}/.config/"

# ===========================
# 2. Återställ my_bin och my_etc från USB
# ===========================
log "Återställer my_bin och my_etc från USB"

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

    # Kontrollera att dest-katalogen finns
    if [[ ! -d "$TAR_DEST" ]]; then
        log "❌ Målkatalog (dest) saknas: $TAR_DEST"
        log "   Skapa den först, eller kör med annan --dest=/sökväg"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "🟡 DRY-RUN: Skippar faktisk uppackning av tar."
            log "  (Skulle ha kört: tar xf \"$LATEST_TAR\" -C \"$TAR_DEST\" --transform=\"s|^${TAR_OLD}/|${TAR_NEW}/|\")"
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
                tar xf "$LATEST_TAR" \
                    -C "$TAR_DEST" \
                    --transform="s|^${TAR_OLD}/|${TAR_NEW}/|" \
                    2> "$ERROR_LOG"
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

