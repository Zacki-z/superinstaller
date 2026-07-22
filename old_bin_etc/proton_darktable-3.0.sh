#!/bin/bash

timeout=10

echo -n "Vill skicka till Proton? (y/n) [auto n om $timeout sek]: "
read -t "$timeout" svar

# Om inget svar ges – anta n
svar=${svar:-n}

if [ "$svar" = "y" ] || [ "$svar" = "Y" ]; then
    echo "✔ Fortsätter..."
else
    echo "✖ Avbryter."
    exit 1
fi
echo "########################################"
SRC="/home/alain/bup_darktable/current"
DEST="q:backups/dark_table"
EXCLUDE_FILE="/home/alain/my_bin/exclude_darktable.txt"
LOG_DIR="/home/alain/bup_darktable/bup_logs"
DATE=$(date +"%Y-%m-%d_%H-%M")
LOG_FILE="$LOG_DIR/backup_darktable_$DATE.log"

# Skapa loggmapp om den inte finns
mkdir -p "$LOG_DIR"

echo -e "\033[1;34m[INFO]\033[0m Startar Darktable-backup: $(date)"
echo -e "\033[1;34m[INFO]\033[0m Loggfil: $LOG_FILE"
echo -e "\033[1;34m[INFO]\033[0m Källa: $SRC"
echo -e "\033[1;34m[INFO]\033[0m Mål:   $DEST"
echo

rclone sync "$SRC" "$DEST" \
  --skip-links \
  --exclude-from "$EXCLUDE_FILE" \
  --retries 10 --low-level-retries 20 \
  --retries-sleep 20s \
  --transfers 1 --checkers 2 --tpslimit 2 \
  --timeout 2m --contimeout 15s \
  --protondrive-replace-existing-draft=true \
  --progress \
  --log-file "$LOG_FILE" \
  --log-level INFO

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\n\033[1;32m✔ Backup klar utan fel.\033[0m"
else
    echo -e "\n\033[1;31m✖ Backupen misslyckades (kod $EXIT_CODE).\033[0m"
    echo "Se loggfilen: $LOG_FILE"
fi
