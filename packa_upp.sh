#!/bin/bash
# Strikt läge men med bättre felhantering:
# -E  = traps triggas även i funk­tioner/subshells
# -e  = avbryt vid fel
# -u  = fel vid användning av odefinierade variabler
# -o pipefail = fel i piped kommandon propag­eras
set -Eeuo pipefail

# Enkel felfälla som berättar var det small
trap 'echo -e "\e[31mEtt fel inträffade (rad $LINENO). Avbryter.\e[0m" >&2' ERR

# packa_upp.sh
# Packar upp en tar-fil och kan byta namn på toppkatalogen
#
# Användning:
#   packa_upp.sh arkiv.tar[.gz|.xz|.bz2] [mål-katalog]
#
# Exempel:
#   packa_upp.sh backup.tar
#   packa_upp.sh backup.tar ~/restore

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Användning:${NC} $0 arkiv.tar[.gz|.xz|.bz2] [mål-katalog]"
  exit 1
fi

ARCHIVE="$1"
TARGET_DIR="${2:-$PWD}"

if [[ ! -f "$ARCHIVE" ]]; then
  echo -e "${RED}Fel:${NC} Arkivfilen '$ARCHIVE' finns inte."
  exit 1
fi

mkdir -p "$TARGET_DIR"

echo -e "${BLUE}▶ Arkiv:${NC}      $ARCHIVE"
echo -e "${BLUE}▶ Mål-katalog:${NC} $TARGET_DIR"
echo

# Hämta toppnivå-namn i arkivet (första komponenten före /)
mapfile -t TOPS < <(tar -tf "$ARCHIVE" | awk -F/ '{print $1}' | sort -u)

if [[ ${#TOPS[@]} -eq 0 ]]; then
  echo -e "${RED}Fel:${NC} Arkivet verkar vara tomt."
  exit 1
fi

echo -e "${BLUE}Toppnivå i arkivet:${NC}"
for t in "${TOPS[@]}"; do
  echo "  - $t"
done
echo

TRANSFORM=""
ROOT_NAME=""

if [[ ${#TOPS[@]} -eq 1 ]]; then
  ROOT_NAME="${TOPS[0]}"
  echo -e "${BLUE}Endast en toppkatalog hittad:${NC} $ROOT_NAME"
  read -r -p "Vill du extrahera den med ett annat namn? (t.ex. 'hem') [tom = behåll '$ROOT_NAME']: " NEWNAME

  if [[ -n "$NEWNAME" && "$NEWNAME" != "$ROOT_NAME" ]]; then
    echo -e "${YELLOW}OK, byter namn vid extrahering:${NC} '$ROOT_NAME' → '$NEWNAME'"
    # Byt bara i början av sökvägen
    TRANSFORM="--transform=s%^${ROOT_NAME}%${NEWNAME}%"
  else
    echo "Behåller namn: $ROOT_NAME"
  fi
else
  echo -e "${YELLOW}Flera toppkataloger hittades.${NC}"
  echo "Ingen automatisk namnändring görs."
fi

echo
read -r -p "Fortsätta extrahera till '$TARGET_DIR'? (y/N): " ANSWER
ANSWER="${ANSWER:-N}"

if [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]]; then
  echo "Avbryter."
  exit 0
fi

echo
echo -e "${BLUE}▶ Extraherar...${NC}"
cd "$TARGET_DIR"

if [[ -n "$TRANSFORM" ]]; then
  tar $TRANSFORM -xpf "$ARCHIVE"
else
  tar -xpf "$ARCHIVE"
fi

echo
echo -e "${GREEN}✔ Klar.${NC} Innehållet är uppackat i: $TARGET_DIR"

