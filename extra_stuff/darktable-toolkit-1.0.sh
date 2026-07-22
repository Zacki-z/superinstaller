#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0"
TITLE="Darktable Toolkit $VERSION"
BIN_DIR="${MY_BIN_DIR:-$HOME/my_bin}"
BACKUP_DIR="${DARKTABLE_BACKUP_DIR:-$HOME/bup_darktable}"

BACKUP_SCRIPT="$BIN_DIR/backup_darktable-5.1.sh"
RESTORE_SCRIPT="$BIN_DIR/restore_darktable-1.0.sh"
MIGRATE_SCRIPT="$BIN_DIR/migrate_darktable-6.2.sh"
OPENCL_SCRIPT="$BIN_DIR/ensure_darktable_opencl-1.0.sh"

BLUE=$'\e[34m'
RED=$'\e[31m'
RESET=$'\e[0m'

pause_terminal() { echo; read -r -p "Tryck ENTER för att återgå till menyn..." _; }

require_whiptail() {
    command -v whiptail >/dev/null 2>&1 && return 0
    echo "Installerar whiptail..."
    sudo apt update
    sudo apt install -y whiptail
}

ensure_sqlite3() {
    command -v sqlite3 >/dev/null 2>&1 && return 0
    whiptail --title "sqlite3 saknas" \
        --yesno "sqlite3 behövs för databasverktygen.\n\nInstallera paketet sqlite3 nu?" 12 70 || return 1
    sudo apt update
    sudo apt install -y sqlite3
}

valid_config() {
    local dir="$1"
    [[ -d "$dir" && -f "$dir/darktablerc" &&
       -f "$dir/library.db" && -f "$dir/data.db" ]]
}

detect_config() {
    local rev=""
    if valid_config "$HOME/snap/darktable/current"; then
        printf '%s\n' "$HOME/snap/darktable/current"; return 0
    fi
    if [[ -d "$HOME/snap/darktable" ]]; then
        rev="$(find "$HOME/snap/darktable" -mindepth 1 -maxdepth 1 -type d \
            -printf '%f\n' 2>/dev/null | awk '/^[0-9]+$/' | sort -n | tail -n1)"
        if [[ -n "$rev" ]] && valid_config "$HOME/snap/darktable/$rev"; then
            printf '%s\n' "$HOME/snap/darktable/$rev"; return 0
        fi
    fi
    if valid_config "$HOME/.var/app/org.darktable.Darktable/config/darktable"; then
        printf '%s\n' "$HOME/.var/app/org.darktable.Darktable/config/darktable"; return 0
    fi
    if valid_config "$HOME/.config/darktable"; then
        printf '%s\n' "$HOME/.config/darktable"; return 0
    fi
    return 1
}

darktable_running() {
    pgrep -u "$(id -u)" -x darktable >/dev/null 2>&1 ||
    ps -u "$(id -u)" -o args= | grep -Eqi '[d]arktable.*AppImage|[A]ppRun.*darktable'
}

run_external() {
    local script="$1" title="$2"
    shift 2 || true
    clear
    printf '%s▶ %s%s\n\n' "$BLUE" "$title" "$RESET"
    if [[ ! -f "$script" ]]; then
        printf '%sFilen saknas:%s\n%s\n' "$RED" "$RESET" "$script"
        pause_terminal
        return 0
    fi
    if [[ -x "$script" ]]; then "$script" "$@"; else bash "$script" "$@"; fi
    pause_terminal
}

run_dry_menu() {
    local script="$1" title="$2" choice
    choice=$(whiptail --title "$title" --menu "Välj körläge:" 15 72 5 \
        "1" "Normal körning" \
        "2" "Dry-run – gör inga ändringar" \
        "b" "Tillbaka" 3>&1 1>&2 2>&3) || return 0
    case "$choice" in
        1) run_external "$script" "$title" ;;
        2) run_external "$script" "$title – dry-run" --dry-run ;;
    esac
}

show_text() {
    whiptail --title "$1" --scrolltext --textbox "$2" 30 105
}

database_check() {
    local cfg db result tmp
    ensure_sqlite3 || return 0
    cfg="$(detect_config)" || {
        whiptail --title "Darktable saknas" --msgbox \
            "Ingen giltig Darktable-konfiguration hittades." 10 68
        return 0
    }
    tmp="$(mktemp)"
    {
        echo "DARKTABLE DATABASKONTROLL"
        echo "Konfiguration: $cfg"
        echo
        for db in library.db data.db; do
            echo "=== $db ==="
            result="$(sqlite3 -readonly "$cfg/$db" 'PRAGMA quick_check;' 2>&1 || true)"
            echo "$result"
            echo
        done
    } > "$tmp"
    show_text "Kontrollera databaser" "$tmp"
    rm -f "$tmp"
}

missing_files_report() {
    local cfg db tmp count=0 folder filename full
    ensure_sqlite3 || return 0
    cfg="$(detect_config)" || {
        whiptail --title "Darktable saknas" --msgbox \
            "Ingen giltig Darktable-konfiguration hittades." 10 68
        return 0
    }
    db="$cfg/library.db"
    tmp="$(mktemp)"
    {
        echo "SAKNADE BILDFILER"
        echo "Databas: $db"
        echo
    } > "$tmp"

    while IFS=$'\t' read -r folder filename; do
        [[ -n "$folder" && -n "$filename" ]] || continue
        full="${folder%/}/$filename"
        if [[ ! -e "$full" ]]; then
            printf '%s\n' "$full" >> "$tmp"
            ((count+=1))
        fi
    done < <(
        sqlite3 -readonly -separator $'\t' "$db" \
        "SELECT film_rolls.folder, images.filename
         FROM images JOIN film_rolls ON images.film_id=film_rolls.id
         ORDER BY film_rolls.folder, images.filename;" 2>/dev/null
    )

    if ((count == 0)); then
        echo "Inga saknade bildfiler hittades." >> "$tmp"
    else
        sed -i "4iAntal saknade filer: $count\n" "$tmp"
    fi
    show_text "Kontrollera bildfiler" "$tmp"
    rm -f "$tmp"
}

optimize_databases() {
    local cfg db before after
    ensure_sqlite3 || return 0
    cfg="$(detect_config)" || {
        whiptail --title "Darktable saknas" --msgbox \
            "Ingen giltig Darktable-konfiguration hittades." 10 68
        return 0
    }
    if darktable_running; then
        whiptail --title "Darktable körs" --msgbox \
            "Stäng Darktable helt innan databaserna optimeras." 10 70
        return 0
    fi
    whiptail --title "Optimera databaser" --yesno \
        "Detta kör PRAGMA optimize, ANALYZE och VACUUM på library.db och data.db.\n\nEn backup bör finnas först. Fortsätta?" 14 76 || return 0
    clear
    for db in library.db data.db; do
        before="$(du -h "$cfg/$db" | awk '{print $1}')"
        echo "Optimerar $db ..."
        sqlite3 "$cfg/$db" 'PRAGMA optimize; ANALYZE; VACUUM;'
        after="$(du -h "$cfg/$db" | awk '{print $1}')"
        echo "  Storlek: $before → $after"
    done
    echo
    echo "Databaserna är optimerade."
    pause_terminal
}

remove_lock_files() {
    local cfg tmp count
    cfg="$(detect_config)" || {
        whiptail --title "Darktable saknas" --msgbox \
            "Ingen giltig Darktable-konfiguration hittades." 10 68
        return 0
    }
    if darktable_running; then
        whiptail --title "Darktable körs" --msgbox \
            "Låsfiler får inte tas bort medan Darktable körs." 10 68
        return 0
    fi
    tmp="$(mktemp)"
    find "$cfg" -maxdepth 1 -type f \( -name '*.lock' -o -name '*-lock' \) -print > "$tmp"
    count="$(wc -l < "$tmp")"
    if ((count == 0)); then
        whiptail --title "Låsfiler" --msgbox "Inga låsfiler hittades i:\n\n$cfg" 11 72
        rm -f "$tmp"; return 0
    fi
    whiptail --title "Ta bort låsfiler" --yesno \
        "Följande $count låsfil(er) hittades:\n\n$(cat "$tmp")\n\nTa bort dem?" 20 90 || {
            rm -f "$tmp"; return 0;
        }
    xargs -r rm -f -- < "$tmp"
    rm -f "$tmp"
    whiptail --title "Låsfiler" --msgbox "$count låsfil(er) togs bort." 9 58
}

show_paths() {
    local cfg tmp install="Okänd"
    cfg="$(detect_config 2>/dev/null || true)"
    command -v darktable >/dev/null 2>&1 && install="$(command -v darktable)"
    tmp="$(mktemp)"
    {
        echo "DARKTABLE – SÖKVÄGAR OCH VERSION"
        echo
        echo "Körbar fil:       $install"
        echo "Konfiguration:    ${cfg:-Hittades inte}"
        echo "Backupkatalog:    $BACKUP_DIR"
        echo "Toolkit:          $0"
        echo
        echo "Version:"
        if command -v darktable >/dev/null 2>&1; then
            darktable --version 2>&1 | head -n 5
        else
            echo "darktable finns inte i PATH."
        fi
        echo
        echo "Databasfiler:"
        if [[ -n "$cfg" ]]; then
            ls -lh "$cfg/library.db" "$cfg/data.db" 2>/dev/null || true
        fi
    } > "$tmp"
    show_text "Darktable-information" "$tmp"
    rm -f "$tmp"
}

snapshot_report() {
    local cfg tmp snaps latest
    ensure_sqlite3 || return 0
    cfg="$(detect_config 2>/dev/null || true)"
    tmp="$(mktemp)"
    snaps=0
    [[ -d "$BACKUP_DIR" ]] &&
        snaps="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' 2>/dev/null | grep -Ec '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$' || true)"
    latest="$(
        find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null |
        grep -E '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$' | sort -r | head -n1 || true
    )"
    {
        echo "DARKTABLE-RAPPORT"
        echo "Skapad: $(date '+%F %T')"
        echo
        echo "Konfiguration: ${cfg:-Hittades inte}"
        echo "Snapshots:     $snaps"
        echo "Senaste:       ${latest:-Ingen}"
        echo
        if [[ -n "$cfg" ]]; then
            echo "Konfigurationsstorlek: $(du -sh "$cfg" | awk '{print $1}')"
            echo "Filmrullar: $(sqlite3 -readonly "$cfg/library.db" \
                'SELECT count(*) FROM film_rolls;' 2>/dev/null || echo okänd)"
            echo "Bilder i databasen: $(sqlite3 -readonly "$cfg/library.db" \
                'SELECT count(*) FROM images;' 2>/dev/null || echo okänd)"
        fi
        echo
        echo "Backupkatalog:"
        du -sh "$BACKUP_DIR" 2>/dev/null || echo "Finns inte"
    } > "$tmp"
    show_text "Darktable-rapport" "$tmp"
    rm -f "$tmp"
}

start_darktable() {
    if command -v darktable >/dev/null 2>&1; then
        nohup darktable >/dev/null 2>&1 &
    else
        whiptail --title "Darktable" --msgbox \
            "Darktable hittades inte i PATH.\nStarta AppImage-versionen från dess vanliga programikon." 11 72
    fi
}

main_menu() {
    local choice
    while true; do
        choice=$(whiptail --title "$TITLE" \
            --menu "Välj Darktable-verktyg:" 28 92 18 \
            "1"  "Backup – skapa ny snapshot" \
            "2"  "Restore – återställ en snapshot" \
            "3"  "Migrera Darktable-konfiguration" \
            "4"  "Kontrollera/fixa OpenCL" \
            "5"  "Kontrollera library.db och data.db" \
            "6"  "Kontrollera om bildfiler saknas" \
            "7"  "Optimera SQLite-databaser" \
            "8"  "Ta bort kvarlämnade låsfiler" \
            "9"  "Visa sökvägar och Darktable-version" \
            "10" "Visa Darktable-rapport" \
            "11" "Öppna backupkatalogen" \
            "12" "Starta Darktable" \
            "b"  "Avsluta / tillbaka" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1) run_dry_menu "$BACKUP_SCRIPT" "Backup Darktable 5.1" ;;
            2) run_dry_menu "$RESTORE_SCRIPT" "Restore Darktable 1.0" ;;
            3) run_dry_menu "$MIGRATE_SCRIPT" "Migrera Darktable 6.2" ;;
            4) run_external "$OPENCL_SCRIPT" "Kontrollera/fixa Darktable OpenCL" ;;
            5) database_check ;;
            6) missing_files_report ;;
            7) optimize_databases ;;
            8) remove_lock_files ;;
            9) show_paths ;;
            10) snapshot_report ;;
            11) mkdir -p "$BACKUP_DIR"; xdg-open "$BACKUP_DIR" >/dev/null 2>&1 & ;;
            12) start_darktable ;;
            b) return 0 ;;
        esac
    done
}

require_whiptail
main_menu
