#!/usr/bin/env bash
# === darktable_tools-1.0.sh ===
# Enkel meny för Darktable-backup & restore:
#  - Kör backup_darktable-4.0.sh (backup)
#  - Kör restore_darktable-3.0.sh (restore)
#  - Visa backup-logg

set -euo pipefail

have_whiptail() {
    command -v whiptail >/dev/null 2>&1
}

if ! have_whiptail; then
    echo "whiptail saknas. Installera med:"
    echo "  sudo apt install whiptail"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUP_SCRIPT="$SCRIPT_DIR/backup_darktable-4.0.sh"
RESTORE_SCRIPT="$SCRIPT_DIR/restore_darktable-3.0.sh"
LOG_FILE="$HOME/bup_darktable/backup_rotate.log"

[ -x "$BUP_SCRIPT" ] || { echo "Hittar inte eller kan inte köra $BUP_SCRIPT"; exit 1; }
[ -x "$RESTORE_SCRIPT" ] || { echo "Hittar inte eller kan inte köra $RESTORE_SCRIPT"; exit 1; }

while true; do
    CHOICE=$(
        whiptail --title "Darktable Tools" --menu "Välj ett alternativ" 20 70 10 \
            "1" "Backup (normal)" \
            "2" "Backup (DRY RUN)" \
            "3" "Restore (interaktiv, normal)" \
            "4" "Restore (interaktiv, DRY RUN)" \
            "5" "Visa backup-logg" \
            "6" "Avsluta" \
            3>&1 1>&2 2>&3
    ) || exit 0

    case "$CHOICE" in
        1)
            whiptail --title "Backup" --msgbox "Kör backup (bup_darktable-8.1.sh)" 8 60
            bash "$BUP_SCRIPT"
            whiptail --title "Backup" --msgbox "Backup färdig.\nSe logg i $LOG_FILE" 10 70
            ;;
        2)
            whiptail --title "Backup (dry-run)" --msgbox "Kör backup i DRY RUN-läge.\nInga riktiga ändringar görs." 10 70
            bash "$BUP_SCRIPT" --dry-run | less
            ;;
        3)
            whiptail --title "Restore" --msgbox "Restore (interaktiv snapshot-väljare)" 8 60
            bash "$RESTORE_SCRIPT"
            whiptail --title "Restore" --msgbox "Restore-försök klart.\nStarta Darktable och kontrollera resultatet." 10 70
            ;;
        4)
            whiptail --title "Restore (dry-run)" --msgbox "Restore DRY RUN.\nInga filer ändras, bara kommandon visas." 10 70
            bash "$RESTORE_SCRIPT" --dry-run | less
            ;;
        5)
            if [ -f "$LOG_FILE" ]; then
                whiptail --title "Backup-logg" --textbox "$LOG_FILE" 25 80
            else
                whiptail --title "Backup-logg" --msgbox "Ingen logg hittad:\n$LOG_FILE" 10 70
            fi
            ;;
        6)
            exit 0
            ;;
        *)
            exit 0
            ;;
    esac
done

