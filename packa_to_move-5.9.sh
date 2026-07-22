#!/usr/bin/env bash
# ============================================================
# packa_to_move-5.9.sh
# ============================================================
# Packar valda filer/kataloger och kopierar dem till USB.
#
# Nytt i 5.9:
#   - Kontrollerar ledigt utrymme på USB före kopiering.
#   - Beräknar behovet från det färdiga tar-arkivet och uppskattade
#     rsync-överföringar.
#   - Kan automatiskt radera de äldsta flytta-arkiven vid platsbrist.
#   - Raderar endast:
#       flytta-*.tar.zst
#       flytta-*.tar.gz
#   - Behåller som standard högst 3 arkiv på USB.
#   - Skyddar som standard minst 1 tidigare arkiv vid platsrensning.
#   - Lämnar som standard 1024 MiB ledigt efter körningen.
#   - Verifierar att USB-sökvägen ligger på ett monterat filsystem.
#   - Giltig shebang ligger nu på första raden.
#
# Kör som vanlig användare.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="5.9"
RELEASE_DATE="2026-07-20"
SCRIPT_NAME="$(basename "$0")"

DRY_RUN=false
AUTO_CLEAN_USB=true

USB_KEEP=3
USB_MIN_KEEP=1
USB_RESERVE_MIB=1024

USER_NAME="${USER:-$(id -un)}"
HOME_DIR="${HOME:-/home/$USER_NAME}"
USB_MOUNT="/media/${USER_NAME}/move_stuff"
DOT_DIR="${HOME_DIR}/dot-files"
LOG="/tmp/flytta-${USER_NAME}.log"
TAR_LIST_FILE="${HOME_DIR}/my_bin/etc/tar_dirs.txt"

ERROR_LOG=""
TAR_LIST=""
TARFILE=""
USB_COPY_OK=false

show_help() {
    cat <<EOF
$SCRIPT_NAME – backup/packscript version $VERSION ($RELEASE_DATE)

Användning:
  $SCRIPT_NAME [alternativ]

Alternativ:
  -h, --help
      Visa hjälptexten.

  -n, --dry-run
      Simulera körningen. Inga arkiv kopieras eller raderas.

  --usb-mount=PATH
      Sökväg till USB-disken.
      Standard: $USB_MOUNT

  --tar-list=PATH
      Lista över poster som ska packas.
      Standard: $TAR_LIST_FILE

  --usb-keep=ANTAL
      Maximalt antal flytta-arkiv som ska finnas kvar på USB
      efter en lyckad körning.
      Standard: $USB_KEEP

  --usb-min-keep=ANTAL
      Minsta antal tidigare flytta-arkiv som inte får tas bort
      automatiskt för att skapa utrymme.
      Standard: $USB_MIN_KEEP

  --usb-reserve-mib=ANTAL
      Ledigt utrymme som ska återstå på USB efter beräknad kopiering.
      Standard: $USB_RESERVE_MIB MiB

  --no-usb-clean
      Radera inte gamla arkiv automatiskt. Avbryt i stället om
      utrymmet inte räcker.

  --usb-clean
      Aktivera automatisk rensning, vilket är standard.

Exempel:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --usb-keep=5
  $SCRIPT_NAME --usb-reserve-mib=2048
  $SCRIPT_NAME --no-usb-clean

Säkerhetsregler:
  - Automatisk rensning sker endast i USB-katalogen tar_files.
  - Endast flytta-*.tar.zst och flytta-*.tar.gz kan tas bort.
  - Övriga filer på USB-disken berörs inte.
EOF
}

die() {
    log "❌ $*"
    exit 1
}

log() {
    printf '%s\n' "$*" | tee -a "$LOG"
}

human_bytes() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        printf '%s byte' "$bytes"
    fi
}

validate_uint() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[0-9]+$ ]] ||
        die "$name måste vara ett heltal som är noll eller större. Angivet: $value"
}

cleanup_temp() {
    local status=$?

    [[ -n "$TAR_LIST" ]] && rm -f -- "$TAR_LIST" 2>/dev/null || true

    if ((status != 0)) && [[ -n "$TARFILE" && -f "$TARFILE" ]]; then
        printf '\nDen lokala arkivfilen behålls efter felet:\n  %s\n' "$TARFILE" >&2
    fi

    return "$status"
}

trap cleanup_temp EXIT

while (($# > 0)); do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            ;;
        --usb-mount=*)
            USB_MOUNT="${1#*=}"
            ;;
        --tar-list=*)
            TAR_LIST_FILE="${1#*=}"
            ;;
        --usb-keep=*)
            USB_KEEP="${1#*=}"
            ;;
        --usb-min-keep=*)
            USB_MIN_KEEP="${1#*=}"
            ;;
        --usb-reserve-mib=*)
            USB_RESERVE_MIB="${1#*=}"
            ;;
        --no-usb-clean)
            AUTO_CLEAN_USB=false
            ;;
        --usb-clean)
            AUTO_CLEAN_USB=true
            ;;
        *)
            printf 'Okänt alternativ: %s\n\n' "$1" >&2
            show_help >&2
            exit 2
            ;;
    esac
    shift
done

: >"$LOG"
ERROR_LOG="$(mktemp /tmp/flytta_errors_XXXXXX)"

validate_uint "--usb-keep" "$USB_KEEP"
validate_uint "--usb-min-keep" "$USB_MIN_KEEP"
validate_uint "--usb-reserve-mib" "$USB_RESERVE_MIB"

((USB_KEEP >= 1)) || die "--usb-keep måste vara minst 1."
((USB_MIN_KEEP <= USB_KEEP)) ||
    die "--usb-min-keep kan inte vara större än --usb-keep."

RSYNC_OPTS=(-a --delete --info=progress2)
if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

require_commands() {
    local -a required=(tar rsync du df find sort stat awk grep sed cut tee mktemp mkdir rm cp)
    local -a missing=()
    local command

    for command in "${required[@]}"; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done

    if ((${#missing[@]} > 0)); then
        die "Följande kommandon saknas: ${missing[*]}"
    fi
}

check_usb_target() {
    local mount_target=""

    [[ -d "$USB_MOUNT" ]] ||
        die "USB-sökvägen finns inte: $USB_MOUNT"

    # Testläget används bara för automatiserad funktionstestning.
    if [[ "${PACKA_ALLOW_NON_MOUNT:-0}" == "1" ]]; then
        log "VARNING: kontroll av monterat filsystem är förbikopplad."
        return 0
    fi

    if command -v findmnt >/dev/null 2>&1; then
        mount_target="$(findmnt -n -o TARGET -T "$USB_MOUNT" 2>/dev/null || true)"

        [[ -n "$mount_target" ]] ||
            die "Kunde inte fastställa filsystemet för: $USB_MOUNT"

        if [[ "$mount_target" == "/" ]]; then
            die "USB-sökvägen ligger på rotfilsystemet och verkar inte vara monterad som USB: $USB_MOUNT"
        fi

        log "USB-filsystemets monteringspunkt: $mount_target"
    elif command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$USB_MOUNT" ||
            die "Sökvägen verkar inte vara en monterad USB-disk: $USB_MOUNT"
    else
        log "⚠️  Varken findmnt eller mountpoint finns; monteringen kunde inte verifieras."
    fi
}

source_size_bytes() {
    local source="$1"

    [[ -e "$source" ]] || {
        printf '0\n'
        return 0
    }

    du -sb -- "$source" 2>/dev/null | awk 'NR==1 {print $1+0}'
}

estimate_rsync_bytes() {
    local source="$1"
    local destination="$2"
    local output=""
    local bytes=""

    [[ -d "$source" ]] || {
        printf '0\n'
        return 0
    }

    # Om destinationen inte finns är hela källan en säker uppskattning.
    if [[ ! -d "$destination" ]]; then
        source_size_bytes "$source"
        return 0
    fi

    output="$(
        LC_ALL=C rsync -a --delete --dry-run --stats \
            "$source" "$destination" 2>/dev/null || true
    )"

    bytes="$(
        printf '%s\n' "$output" |
            awk -F': ' '
                /Total transferred file size:/ {
                    value=$2
                    gsub(/[^0-9]/, "", value)
                    print value+0
                    found=1
                }
                END {
                    if (!found) print 0
                }
            '
    )"

    printf '%s\n' "${bytes:-0}"
}

rsync_mirror() {
    local source="$1"
    local destination="$2"

    if [[ ! -d "$source" ]]; then
        log "⏭ Hoppar över saknad katalog: $source"
        return 0
    fi

    log "  rsync: $source → $destination"

    if [[ "$DRY_RUN" == true && ! -d "$destination" ]]; then
        log "  DRY-RUN: destinationen finns inte; skulle skapa och spegla hela källan."
        return 0
    fi

    rsync "${RSYNC_OPTS[@]}" "$source" "$destination"
    echo
}

read_backup_items() {
    local line=""
    local full_path=""
    local -a missing=()

    BACKUP_ITEMS=()

    [[ -f "$TAR_LIST_FILE" ]] ||
        die "tar-listfil saknas: $TAR_LIST_FILE"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="$(
            printf '%s' "$line" |
                sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
        )"

        [[ -n "$line" ]] || continue
        [[ "$line" == \#* ]] && continue

        full_path="$HOME_DIR/$line"
        if [[ -e "$full_path" ]]; then
            BACKUP_ITEMS+=("$line")
        else
            missing+=("$line")
        fi
    done <"$TAR_LIST_FILE"

    if ((${#missing[@]} > 0)); then
        log "⚠️  Följande poster saknas och hoppas över:"
        printf '  - %s\n' "${missing[@]}" | tee -a "$LOG"
    fi

    ((${#BACKUP_ITEMS[@]} > 0)) ||
        die "Inga existerande filer eller kataloger hittades i tar-listan."
}

calculate_tar_source_size() {
    (
        cd "$HOME_DIR"
        du -cb -- "${BACKUP_ITEMS[@]}" 2>/dev/null |
            awk 'END {print $1+0}'
    )
}

list_usb_archives_oldest() {
    local archive_dir="$USB_MOUNT/tar_files"

    [[ -d "$archive_dir" ]] || return 0

    find "$archive_dir" \
        -maxdepth 1 \
        -type f \
        \( -name 'flytta-*.tar.zst' -o -name 'flytta-*.tar.gz' \) \
        -printf '%T@|%p\n' 2>/dev/null |
        sort -n |
        cut -d '|' -f 2-
}

available_usb_bytes() {
    if [[ -n "${PACKA_TEST_AVAILABLE_BYTES:-}" ]]; then
        printf '%s\n' "$PACKA_TEST_AVAILABLE_BYTES"
        return 0
    fi

    df -PB1 "$USB_MOUNT" | awk 'NR==2 {print $4+0}'
}

estimate_usb_mirror_bytes() {
    local total=0
    local value=0

    value="$(estimate_rsync_bytes "$HOME_DIR/.mixxx/" "$USB_MOUNT/dot-mixxx/")"
    total=$((total + value))

    value="$(estimate_rsync_bytes "$HOME_DIR/.cache/" "$USB_MOUNT/dot-cache/")"
    total=$((total + value))

    if [[ -d "$HOME_DIR/snap/darktable" ]]; then
        value="$(estimate_rsync_bytes "$HOME_DIR/snap/darktable/" "$USB_MOUNT/dot-darktable/")"
        total=$((total + value))
    fi

    value="$(estimate_rsync_bytes "$HOME_DIR/.config/" "$USB_MOUNT/dot-config/")"
    total=$((total + value))

    value="$(estimate_rsync_bytes "$HOME_DIR/my_bin/" "$USB_MOUNT/my_bin/")"
    total=$((total + value))

    value="$(estimate_rsync_bytes "$HOME_DIR/my_etc/" "$USB_MOUNT/my_etc/")"
    total=$((total + value))

    printf '%s\n' "$total"
}

ensure_usb_space() {
    local archive_bytes="$1"
    local mirror_bytes="$2"
    local reserve_bytes=$((USB_RESERVE_MIB * 1024 * 1024))
    local required=$((archive_bytes + mirror_bytes + reserve_bytes))
    local available
    local shortage
    local -a archives=()
    local deletable_count
    local archive
    local archive_size

    available="$(available_usb_bytes)"

    log "------------------------------------------------------------"
    log "USB-utrymmeskontroll"
    log "Arkiv som ska kopieras:       $(human_bytes "$archive_bytes")"
    log "Uppskattad rsync-överföring:  $(human_bytes "$mirror_bytes")"
    log "Reserverat ledigt utrymme:    $(human_bytes "$reserve_bytes")"
    log "Totalt beräknat behov:        $(human_bytes "$required")"
    log "Ledigt på USB nu:             $(human_bytes "$available")"

    if ((available >= required)); then
        log "✅ USB-disken har tillräckligt med utrymme."
        return 0
    fi

    shortage=$((required - available))
    log "⚠️  Det saknas ungefär $(human_bytes "$shortage")."

    if [[ "$AUTO_CLEAN_USB" != true ]]; then
        die "Utrymmet räcker inte och automatisk USB-rensning är avstängd."
    fi

    mapfile -t archives < <(list_usb_archives_oldest)
    deletable_count=$((${#archives[@]} - USB_MIN_KEEP))
    ((deletable_count < 0)) && deletable_count=0

    if ((deletable_count == 0)); then
        die "Utrymmet räcker inte och inga äldre arkiv får tas bort. Skyddat antal: $USB_MIN_KEEP."
    fi

    log "Rensar de äldsta flytta-arkiven tills utrymmet räcker."
    log "Minst $USB_MIN_KEEP tidigare arkiv skyddas."

    for ((i=0; i<deletable_count; i++)); do
        archive="${archives[$i]}"
        archive_size="$(stat -c '%s' "$archive" 2>/dev/null || printf '0')"

        if [[ "$DRY_RUN" == true ]]; then
            log "DRY-RUN: skulle ta bort: $archive ($(human_bytes "$archive_size"))"
            available=$((available + archive_size))
        else
            log "🗑️  Tar bort gammalt arkiv: $archive ($(human_bytes "$archive_size"))"
            rm -f -- "$archive"
            available="$(available_usb_bytes)"
        fi

        if ((available >= required)); then
            log "✅ Beräknat utrymme räcker efter rensningen."
            return 0
        fi
    done

    shortage=$((required - available))
    die "Utrymmet räcker fortfarande inte. Ungefär $(human_bytes "$shortage") saknas."
}

rotate_usb_archives() {
    local -a archives=()
    local remove_count
    local archive

    mapfile -t archives < <(list_usb_archives_oldest)

    if ((${#archives[@]} <= USB_KEEP)); then
        log "USB-rotation: ${#archives[@]} arkiv finns; inget behöver tas bort."
        return 0
    fi

    remove_count=$((${#archives[@]} - USB_KEEP))
    log "USB-rotation: behåller de $USB_KEEP senaste flytta-arkiven."

    for ((i=0; i<remove_count; i++)); do
        archive="${archives[$i]}"

        if [[ "$DRY_RUN" == true ]]; then
            log "DRY-RUN: skulle ta bort vid rotation: $archive"
        else
            log "🗑️  Rotation tar bort: $archive"
            rm -f -- "$archive"
        fi
    done
}

require_commands

: >"$LOG"
date >>"$LOG"
log "$SCRIPT_NAME – version $VERSION ($RELEASE_DATE)"
log "DRY_RUN=$DRY_RUN"
log "USB_MOUNT=$USB_MOUNT"
log "USB_KEEP=$USB_KEEP"
log "USB_MIN_KEEP=$USB_MIN_KEEP"
log "USB_RESERVE_MIB=$USB_RESERVE_MIB"
log "AUTO_CLEAN_USB=$AUTO_CLEAN_USB"
log "Felfil för tar: $ERROR_LOG"

check_usb_target
read_backup_items

log "Följande poster kommer att packas:"
printf '  - %s\n' "${BACKUP_ITEMS[@]}" | tee -a "$LOG"
echo

# ------------------------------------------------------------
# 1. Uppdatera lokala dot-files före packning
# ------------------------------------------------------------
log "Speglar lokala konfigurationer till $DOT_DIR"

if [[ "$DRY_RUN" == false ]]; then
    mkdir -p \
        "$DOT_DIR/dot-mixxx" \
        "$DOT_DIR/dot-cache" \
        "$DOT_DIR/dot-darktable" \
        "$DOT_DIR/dot-config"
fi

rsync_mirror "$HOME_DIR/.mixxx/" "$DOT_DIR/dot-mixxx/"
rsync_mirror "$HOME_DIR/.cache/" "$DOT_DIR/dot-cache/"

if [[ -d "$HOME_DIR/snap/darktable" ]]; then
    rsync_mirror "$HOME_DIR/snap/darktable/" "$DOT_DIR/dot-darktable/"
else
    log "⏭ Hoppar över Darktable Snap; katalogen saknas."
fi

rsync_mirror "$HOME_DIR/.config/" "$DOT_DIR/dot-config/"

# ------------------------------------------------------------
# 2. Skapa lokalt tar-arkiv, eller uppskatta storleken i dry-run
# ------------------------------------------------------------
TIMESTAMP="$(date +'%Y-%m-%d_%H%M%S')"

if command -v zstd >/dev/null 2>&1; then
    COMPRESSOR="zstd"
    EXT="tar.zst"
else
    COMPRESSOR="gzip"
    EXT="tar.gz"
fi

TARFILE="$HOME_DIR/flytta-$TIMESTAMP.$EXT"
TOTAL_SOURCE_SIZE="$(calculate_tar_source_size)"

log "Komprimeringsmetod: $COMPRESSOR"
log "Okomprimerad källstorlek: $(human_bytes "$TOTAL_SOURCE_SIZE")"

if [[ "$DRY_RUN" == true ]]; then
    # Konservativ uppskattning: arkivet antas kunna bli lika stort
    # som den okomprimerade källan.
    ARCHIVE_SIZE="$TOTAL_SOURCE_SIZE"
    log "DRY-RUN: inget arkiv skapas."
    log "Beräknad maximal arkivstorlek: $(human_bytes "$ARCHIVE_SIZE")"
else
    TAR_LIST="$(mktemp /tmp/flytta_tarlist_XXXXXX)"
    printf '%s\n' "${BACKUP_ITEMS[@]}" >"$TAR_LIST"

    log "Skapar lokalt arkiv: $TARFILE"

    if command -v pv >/dev/null 2>&1; then
        if [[ "$COMPRESSOR" == "zstd" ]]; then
            (
                cd "$HOME_DIR"
                tar --verbatim-files-from --no-unquote -cf - -T "$TAR_LIST" \
                    2>"$ERROR_LOG"
            ) | pv -s "$TOTAL_SOURCE_SIZE" |
                zstd -T0 -q -c >"$TARFILE"
        else
            (
                cd "$HOME_DIR"
                tar --verbatim-files-from --no-unquote -cf - -T "$TAR_LIST" \
                    2>"$ERROR_LOG"
            ) | pv -s "$TOTAL_SOURCE_SIZE" |
                gzip -c >"$TARFILE"
        fi
    else
        if [[ "$COMPRESSOR" == "zstd" ]]; then
            (
                cd "$HOME_DIR"
                tar --verbatim-files-from --no-unquote -cf - -T "$TAR_LIST" \
                    2>"$ERROR_LOG"
            ) | zstd -T0 -q -c >"$TARFILE"
        else
            (
                cd "$HOME_DIR"
                tar --verbatim-files-from --no-unquote -cf - -T "$TAR_LIST" \
                    2>"$ERROR_LOG"
            ) | gzip -c >"$TARFILE"
        fi
    fi

    [[ -s "$TARFILE" ]] ||
        die "Det skapade arkivet saknas eller är tomt: $TARFILE"

    ARCHIVE_SIZE="$(stat -c '%s' "$TARFILE")"
    log "✅ Lokalt arkiv skapat: $(human_bytes "$ARCHIVE_SIZE")"
fi

# ------------------------------------------------------------
# 3. Kontrollera/rensa USB-utrymme innan något kopieras dit
# ------------------------------------------------------------
MIRROR_BYTES="$(estimate_usb_mirror_bytes)"
ensure_usb_space "$ARCHIVE_SIZE" "$MIRROR_BYTES"

if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: skulle därefter spegla konfigurationer och kopiera arkivet."
    rotate_usb_archives
    log "✅ Dry-run klar. Inga USB-filer ändrades."
    exit 0
fi

mkdir -p \
    "$USB_MOUNT/dot-mixxx" \
    "$USB_MOUNT/dot-cache" \
    "$USB_MOUNT/dot-darktable" \
    "$USB_MOUNT/dot-config" \
    "$USB_MOUNT/tar_files" \
    "$USB_MOUNT/my_bin" \
    "$USB_MOUNT/my_etc"

# ------------------------------------------------------------
# 4. Spegla konfigurationer till USB
# ------------------------------------------------------------
log "Speglar konfigurationer till USB"

rsync_mirror "$HOME_DIR/.mixxx/" "$USB_MOUNT/dot-mixxx/"
rsync_mirror "$HOME_DIR/.cache/" "$USB_MOUNT/dot-cache/"

if [[ -d "$HOME_DIR/snap/darktable" ]]; then
    rsync_mirror "$HOME_DIR/snap/darktable/" "$USB_MOUNT/dot-darktable/"
fi

rsync_mirror "$HOME_DIR/.config/" "$USB_MOUNT/dot-config/"
rsync_mirror "$HOME_DIR/my_bin/" "$USB_MOUNT/my_bin/"
rsync_mirror "$HOME_DIR/my_etc/" "$USB_MOUNT/my_etc/"

# ------------------------------------------------------------
# 5. Kopiera och verifiera tar-arkivet
# ------------------------------------------------------------
DEST_TAR="$USB_MOUNT/tar_files/$(basename "$TARFILE")"
log "Kopierar arkivet till USB: $DEST_TAR"

if command -v pv >/dev/null 2>&1; then
    pv "$TARFILE" >"$DEST_TAR"
else
    cp -- "$TARFILE" "$DEST_TAR"
fi

SOURCE_SIZE="$(stat -c '%s' "$TARFILE")"
DEST_SIZE="$(stat -c '%s' "$DEST_TAR")"

if [[ "$SOURCE_SIZE" != "$DEST_SIZE" ]]; then
    rm -f -- "$DEST_TAR"
    die "Storlekskontrollen av USB-kopian misslyckades."
fi

USB_COPY_OK=true
log "✅ USB-kopian verifierades med filstorlek: $(human_bytes "$DEST_SIZE")"

# ------------------------------------------------------------
# 6. Rotation och lokal städning
# ------------------------------------------------------------
rotate_usb_archives

if [[ "$USB_COPY_OK" == true ]]; then
    rm -f -- "$TARFILE"
    TARFILE=""
    log "Den lokala tillfälliga arkivfilen är borttagen."
fi

log "✅ Klart."
date >>"$LOG"
log "Tar-fel och varningar finns vid behov i: $ERROR_LOG"
