#!/usr/bin/env bash
# ============================================================
# packa_upp_move-6.6.sh
# ============================================================
# Säker återställning från flyttpaket på USB.
#
# Nytt i 6.5:
#   - Korrekt stöd för flytta-*.tar.zst och flytta-*.tar.gz.
#   - Standardmål är användarens hemkatalog, inte rotkatalogen /.
#   - Kan hitta USB-disken automatiskt under /media eller /run/media.
#   - USB-sökvägen kan anges med --usb-mount=PATH.
#   - Kontrollerar att USB-sökvägen verkligen ligger på ett monterat
#     filsystem och inte bara är en tom katalog på systemdisken.
#   - Installerar automatiskt pv via apt-get om det saknas.
#   - Använder pv för att visa förloppet vid uppackning.
#   - Okända argument ger tydligt fel.
#   - Dry-run listar vad som skulle återställas utan att skriva något.
#
# Kör som vanlig användare.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="6.6"
SCRIPT_NAME="$(basename "$0")"

USER_NAME="${USER:-$(id -un)}"
HOME_DIR="${HOME:-/home/$USER_NAME}"

DRY_RUN=false
USB_MOUNT="/media/${USER_NAME}/move_stuff"
USB_MOUNT_EXPLICIT=false
TAR_DEST="$HOME_DIR"
RESTORE_CONFIG=false

LOG="/tmp/packupp-${USER_NAME}.log"
ERROR_LOG=""

usage() {
    cat <<EOF
$SCRIPT_NAME – återställ flyttpaket, version $VERSION

Användning:
  $SCRIPT_NAME [alternativ]

Alternativ:
  -n, --dry-run
      Simulera återställningen. Inga filer skrivs eller ändras.

  --usb-mount=PATH
      Ange USB-diskens monteringspunkt.
      Standardförsök: /media/$USER_NAME/move_stuff
      Skriptet kan även söka automatiskt under /media och /run/media.

  --dest=PATH
      Katalog där flyttarkivet ska packas upp.
      Standard: $HOME_DIR

  --restore-config
      Återställ även speglade konfigurationer från USB:
        dot-mixxx    -> ~/.mixxx
        dot-config   -> ~/.config
        dot-darktable -> ~/snap/darktable
      Detta är avstängt som standard.

  -h, --help
      Visa hjälptexten.

Exempel:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --usb-mount="/media/$USER_NAME/move_stuff" --dry-run
  $SCRIPT_NAME --dest="$HOME_DIR"
EOF
}

log() {
    printf '%s\n' "$*" | tee -a "$LOG"
}

die() {
    log "❌ $*"
    exit 1
}

ensure_pv() {
    local -a privilege_cmd=()

    if command -v pv >/dev/null 2>&1; then
        log "✅ pv finns redan: $(command -v pv)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: pv saknas. Skulle installera paketet 'pv' via apt-get."
        return 0
    fi

    command -v apt-get >/dev/null 2>&1 ||
        die "pv saknas och apt-get finns inte. Installera pv manuellt."

    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 ||
            die "pv saknas, skriptet körs inte som root och sudo saknas."
        privilege_cmd=(sudo)
    fi

    log "pv saknas. Installerar paketet pv..."
    "${privilege_cmd[@]}" apt-get update
    "${privilege_cmd[@]}" apt-get install -y pv

    command -v pv >/dev/null 2>&1 ||
        die "Installationen avslutades, men kommandot pv hittas fortfarande inte."

    log "✅ pv installerades: $(command -v pv)"
}

cleanup() {
    local status=$?
    [[ -n "$ERROR_LOG" ]] && rm -f -- "$ERROR_LOG" 2>/dev/null || true
    return "$status"
}
trap cleanup EXIT

while (($# > 0)); do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            ;;
        --usb-mount=*)
            USB_MOUNT="${1#*=}"
            USB_MOUNT_EXPLICIT=true
            ;;
        --dest=*)
            TAR_DEST="${1#*=}"
            ;;
        --restore-config)
            RESTORE_CONFIG=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Okänt argument: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

ERROR_LOG="$(mktemp /tmp/packupp_errors_XXXXXX)"
: >"$LOG"

RSYNC_OPTS=(-a -h --info=progress2)
if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

is_mounted_storage() {
    local path="$1"
    local target=""

    [[ -d "$path" ]] || return 1

    # Endast för isolerade automatiska tester.
    if [[ "${PACKUP_ALLOW_NON_MOUNT:-0}" == "1" ]]; then
        return 0
    fi

    if command -v findmnt >/dev/null 2>&1; then
        target="$(findmnt -n -o TARGET -T "$path" 2>/dev/null || true)"
        [[ -n "$target" && "$target" != "/" ]]
        return
    fi

    # Fallback: en katalog under /media eller /run/media antas vara
    # extern endast om den förekommer i den aktuella mount-listan.
    mount | grep -Fq " on $path "
}

archive_exists_in_mount() {
    local mount_path="$1"

    [[ -d "$mount_path/tar_files" ]] || return 1

    find "$mount_path/tar_files" \
        -maxdepth 1 \
        -type f \
        \( -name 'flytta-*.tar.zst' -o -name 'flytta-*.tar.gz' \) \
        -print -quit 2>/dev/null |
        grep -q .
}

resolve_usb_mount() {
    local -a candidates=()
    local candidate=""
    local -a matches=()

    if [[ "$USB_MOUNT_EXPLICIT" == true ]]; then
        [[ -d "$USB_MOUNT" ]] ||
            die "Angiven USB-sökväg finns inte: $USB_MOUNT"

        is_mounted_storage "$USB_MOUNT" ||
            die "Angiven USB-sökväg verkar inte vara en monterad extern disk: $USB_MOUNT"

        return 0
    fi

    if is_mounted_storage "$USB_MOUNT" &&
       archive_exists_in_mount "$USB_MOUNT"
    then
        return 0
    fi

    shopt -s nullglob
    candidates=(
        "/media/$USER_NAME"/*
        "/run/media/$USER_NAME"/*
    )
    shopt -u nullglob

    for candidate in "${candidates[@]}"; do
        [[ -d "$candidate" ]] || continue

        if is_mounted_storage "$candidate" &&
           archive_exists_in_mount "$candidate"
        then
            matches+=("$candidate")
        fi
    done

    case "${#matches[@]}" in
        0)
            log "Tillgängliga kataloger under /media/$USER_NAME:"
            find "/media/$USER_NAME" \
                -mindepth 1 -maxdepth 1 -type d -printf '  %p\n' \
                2>/dev/null | tee -a "$LOG" || true

            die "Ingen monterad USB-disk med katalogen tar_files och ett flytta-arkiv hittades. Anslut disken eller använd --usb-mount=PATH."
            ;;
        1)
            USB_MOUNT="${matches[0]}"
            log "USB-disken hittades automatiskt: $USB_MOUNT"
            ;;
        *)
            log "Flera möjliga USB-diskar hittades:"
            printf '  %s\n' "${matches[@]}" | tee -a "$LOG"
            die "Ange rätt disk med --usb-mount=PATH."
            ;;
    esac
}

find_latest_archive() {
    local tar_dir="$USB_MOUNT/tar_files"

    [[ -d "$tar_dir" ]] || return 1

    find "$tar_dir" \
        -maxdepth 1 \
        -type f \
        \( -name 'flytta-*.tar.zst' -o -name 'flytta-*.tar.gz' \) \
        -printf '%T@|%p\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d '|' -f 2-
}

check_archive_support() {
    local archive="$1"

    case "$archive" in
        *.tar.zst)
            if command -v zstd >/dev/null 2>&1; then
                return 0
            fi

            if tar --help 2>/dev/null | grep -q -- '--zstd'; then
                return 0
            fi

            die "Arkivet är zstd-komprimerat, men zstd-stöd saknas. Installera med: sudo apt install zstd"
            ;;
        *.tar.gz)
            command -v gzip >/dev/null 2>&1 ||
                die "gzip saknas. Installera paketet gzip."
            ;;
        *)
            die "Arkivtypen stöds inte: $archive"
            ;;
    esac
}

ask_create_dir() {
    local dir="$1"

    if [[ -d "$dir" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: skulle skapa katalog: $dir"
        return 0
    fi

    read -r -p "Katalogen saknas: $dir. Skapa den? [j/N] " answer
    case "$answer" in
        j|J|ja|JA|Ja|y|Y|yes|YES)
            mkdir -p -- "$dir"
            log "Skapade katalog: $dir"
            ;;
        *)
            return 1
            ;;
    esac
}

rsync_restore() {
    local source="$1"
    local destination="$2"

    if [[ ! -e "$source" ]]; then
        log "⏭ Källa saknas, hoppar över: $source"
        return 0
    fi

    if ! ask_create_dir "$destination"; then
        log "⏭ Målkatalogen skapades inte, hoppar över: $destination"
        return 0
    fi

    log "rsync: $source → $destination"

    # Vid dry-run och helt saknad destination kan rsync inte alltid
    # simulera skapandet. Då räcker det att redovisa åtgärden.
    if [[ "$DRY_RUN" == true && ! -d "$destination" ]]; then
        log "DRY-RUN: skulle återställa hela källan till den nya katalogen."
        return 0
    fi

    rsync "${RSYNC_OPTS[@]}" "$source" "$destination"
}

list_archive_preview() {
    local archive="$1"
    local preview=""

    preview="$(
        tar -tf "$archive" 2>"$ERROR_LOG" |
            head -n 40 || true
    )"

    if [[ -n "$preview" ]]; then
        log "De första posterna i arkivet:"
        printf '%s\n' "$preview" | sed 's/^/  /' | tee -a "$LOG"
    else
        die "Kunde inte läsa arkivets innehåll. Se: $ERROR_LOG"
    fi
}

extract_archive() {
    local archive="$1"
    local destination="$2"

    case "$archive" in
        *.tar.zst)
            if command -v pv >/dev/null 2>&1; then
                pv "$archive" |
                    zstd -dc |
                    tar -xf - -C "$destination" 2>"$ERROR_LOG"
            else
                zstd -dc "$archive" |
                    tar -xf - -C "$destination" 2>"$ERROR_LOG"
            fi
            ;;
        *.tar.gz)
            if command -v pv >/dev/null 2>&1; then
                pv "$archive" |
                    gzip -dc |
                    tar -xf - -C "$destination" 2>"$ERROR_LOG"
            else
                gzip -dc "$archive" |
                    tar -xf - -C "$destination" 2>"$ERROR_LOG"
            fi
            ;;
        *)
            return 2
            ;;
    esac
}

date >>"$LOG"
log "$SCRIPT_NAME – version $VERSION"
log "DRY_RUN=$DRY_RUN"
log "Önskat mål för uppackning: $TAR_DEST"

ensure_pv
resolve_usb_mount
TAR_DIR="$USB_MOUNT/tar_files"

log "USB-sökväg: $USB_MOUNT"
log "Arkivkatalog: $TAR_DIR"

LATEST_TAR="$(find_latest_archive || true)"
[[ -n "$LATEST_TAR" ]] ||
    die "Inget flytta-arkiv av typen .tar.zst eller .tar.gz hittades i: $TAR_DIR"

check_archive_support "$LATEST_TAR"

log "Senaste flyttarkiv: $LATEST_TAR"
list_archive_preview "$LATEST_TAR"

if [[ "$RESTORE_CONFIG" == true ]]; then
    log "Återställer speglade programkonfigurationer."

    rsync_restore "$USB_MOUNT/dot-mixxx/" "$HOME_DIR/.mixxx/"
    rsync_restore "$USB_MOUNT/dot-config/" "$HOME_DIR/.config/"
    rsync_restore "$USB_MOUNT/dot-darktable/" "$HOME_DIR/snap/darktable/"
else
    log "Speglade programkonfigurationer återställs inte. Använd --restore-config för detta."
fi

log "Återställer my_bin och my_etc från USB."
rsync_restore "$USB_MOUNT/my_bin/" "$HOME_DIR/my_bin/"
rsync_restore "$USB_MOUNT/my_etc/" "$HOME_DIR/my_etc/"

if ! ask_create_dir "$TAR_DEST"; then
    die "Målkatalogen finns inte och skapades inte: $TAR_DEST"
fi

if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: skulle packa upp arkivet till:"
    log "  $TAR_DEST"
    log "Uppackningen skulle använda pv för förloppsvisning om kommandot finns."
    log "✅ Dry-run klar. Inga filer ändrades."
    exit 0
fi

echo
echo "VARNING: Arkivet kommer att packas upp och kan skriva över filer."
echo "Arkiv: $LATEST_TAR"
echo "Mål:   $TAR_DEST"
echo
read -r -p "Skriv exakt yes för att fortsätta: " confirm

if [[ "$confirm" != "yes" ]]; then
    log "Återställningen avbröts av användaren."
    exit 0
fi

log "Packar upp arkivet till: $TAR_DEST"

if ! extract_archive "$LATEST_TAR" "$TAR_DEST"; then
    log "❌ Uppackningen misslyckades. Felmeddelanden:"
    sed 's/^/  /' "$ERROR_LOG" | tee -a "$LOG"
    exit 1
fi

log "✅ Återställningen är klar."
date >>"$LOG"
