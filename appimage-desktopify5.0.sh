#!/bin/bash
set -uo pipefail

###############################################################################
# appimage-desktopify.sh
#
# BEARBETAR ALLA APPIMAGES I ~/appimages_applications AUTOMATISKT
# - Skapar/uppdaterar symlänk i ~/.local/bin/<app-id>
# - Extraherar AppImage (ej i dry-run)
# - Hittar inbyggd .desktop-fil (om finns)
# - Fixar Exec= till ~/.local/bin/<app-id> %F
# - Hämtar ikon & installerar i ~/.local/share/icons/hicolor
# - Skapar slutlig .desktop i ~/.local/share/applications
#
# Kör:
#   ./appimage-desktopify.sh
#   ./appimage-desktopify.sh --dry-run
###############################################################################

DRYRUN=false
APPDIR="$HOME/appimages_applications"

ICON_BASE="$HOME/.local/share/icons/hicolor"
DESKTOP_DIR="$HOME/.local/share/applications"
BIN="$HOME/.local/bin"

mkdir -p "$ICON_BASE" "$DESKTOP_DIR" "$BIN"

# -----------------------------
# Färger
# -----------------------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

# -----------------------------
# Parsing av argument
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRYRUN=true ; shift ;;
    -h|--help)
      echo "Användning: $0 [--dry-run]"
      exit 0
      ;;
    *)
      echo -e "${RED}Okänt argument:${NC} $1"
      exit 1
      ;;
  esac
done

# -----------------------------
# Hjälpfunktioner
# -----------------------------
run() {
  if [[ "$DRYRUN" == true ]]; then
    echo "  🧪 (dry-run) $*"
  else
    "$@"
  fi
}

derive_app_id() {
  local base
  base="$(basename "$1")"
  base="${base%.AppImage}"
  base="${base%.appimage}"

  if [[ "$base" =~ ^(.+)-[0-9] ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$base"
  fi
}

find_desktop_file() {
  find "$1" -maxdepth 4 -type f -name "*.desktop" | head -n 1
}

find_icon_file() {
  local root="$1"
  local key="$2"

  # 1 – matcha ikon-namnet
  local match
  match=$(find "$root" -maxdepth 8 -type f \( -iname "${key}.png" -o -iname "${key}.svg" \) | head -n 1 || true)
  if [[ -n "$match" ]]; then
    echo "$match"
    return
  fi

  # 2 – ta största png/svg
  local biggest
  biggest=$(find "$root" -maxdepth 8 -type f \( -iname "*.png" -o -iname "*.svg" \) -printf '%s %p\n' 2>/dev/null | sort -nr | head -n1 | awk '{print $2}')
  echo "$biggest"
}

# -----------------------------
# Process-funktion
# -----------------------------
process_appimage() {
  local appimage="$1"
  echo -e "${BLUE}▶ Behandlar:${NC} $appimage"

  local abs_app
  abs_app="$(readlink -f "$appimage")"

  local app_id
  app_id="$(derive_app_id "$appimage")"
  echo "  App-ID: $app_id"

  # Symlänk i ~/.local/bin/app_id
  local bin_link="${BIN}/${app_id}"
  if [[ "$DRYRUN" == true ]]; then
    echo "  🧪 (dry-run) Skulle skapa/uppdatera symlänk: $bin_link → $abs_app"
  else
    ln -sf "$abs_app" "$bin_link"
    echo "  🔗 Symlänk: $bin_link → $abs_app"
  fi

  # Exec-kommandot vi vill använda i .desktop
  local exec_cmd="$bin_link"

  local tmpdir
  tmpdir="$(mktemp -d)"

  echo "  Extraherar..."

  if [[ "$DRYRUN" == false ]]; then
    (
      cd "$tmpdir"
      ARCH=x86_64 "$abs_app" --appimage-extract >/dev/null 2>&1 || {
        echo -e "  ${RED}❌ Misslyckad extraktion${NC}"
        rm -rf "$tmpdir"
        return
      }
    )
  else
    echo "  🧪 (dry-run) skulle köra --appimage-extract"
  fi

  local root="$tmpdir/squashfs-root"

  # Hitta inbyggd desktop
  local desktop_src=""
  if [[ "$DRYRUN" == false ]]; then
    desktop_src="$(find_desktop_file "$root")"
  fi

  local desktop_target="${DESKTOP_DIR}/${app_id}.desktop"

  # Skapa/justera .desktop
  if [[ -z "$desktop_src" && "$DRYRUN" == false ]]; then
    echo -e "  ${YELLOW}⚠ Ingen .desktop hittad – skapar grundfil${NC}"

    run bash -c "cat > '$desktop_target' <<EOF
[Desktop Entry]
Type=Application
Name=$app_id
Exec=$exec_cmd %F
Icon=$app_id
Terminal=false
Categories=Utility;
EOF"

  else
    echo "  .desktop-källa: ${desktop_src:-"(dry-run)"}"
    if [[ "$DRYRUN" == true ]]; then
      echo "  🧪 Skulle kopiera och anpassa .desktop → $desktop_target"
    else
      cp "$desktop_src" "$desktop_target"

      # Rensa TryExec
      sed -i '/^TryExec=/d' "$desktop_target"

      # Exec ska peka på symlänken i ~/.local/bin
      sed -i "s|^Exec=.*|Exec=$exec_cmd %F|" "$desktop_target"
      sed -i "s|^Comment=.*|Comment=AppImage ($app_id)|" "$desktop_target"
    fi
  fi

  # ------------------- Ikon -------------------
  echo "  Letar ikon..."
  local icon_key="$app_id"

  if [[ "$DRYRUN" == false && -f "$desktop_target" ]]; then
    local icon_line
    icon_line=$(grep '^Icon=' "$desktop_target" || true)
    if [[ -n "$icon_line" ]]; then
      icon_key="${icon_line#Icon=}"
    fi
  fi

  local icon_src=""
  if [[ "$DRYRUN" == false ]]; then
    icon_src="$(find_icon_file "$root" "$icon_key")"
  fi

  if [[ -z "$icon_src" ]]; then
    echo -e "  ${YELLOW}⚠ Ingen ikon hittad – ikonen blir generisk${NC}"
  else
    echo "  Ikon hittad: $icon_src"
    local icon_target_dir="${ICON_BASE}/256x256/apps"
    local ext="${icon_src##*.}"
    local icon_target="${icon_target_dir}/${icon_key}.${ext}"

    run mkdir -p "$icon_target_dir"
    run cp "$icon_src" "$icon_target"

    echo "  Ikon installerad → $icon_target"

    if [[ "$DRYRUN" == false ]]; then
      sed -i "s|^Icon=.*|Icon=${icon_key}|" "$desktop_target"
    fi
  fi

  if [[ "$DRYRUN" == false ]]; then
    chmod +x "$desktop_target"
  else
    echo "  🧪 (dry-run) Skulle göra chmod +x $desktop_target"
  fi

  echo -e "  ${GREEN}✔ Klar: $app_id${NC}"
  rm -rf "$tmpdir"
  echo
}

# -----------------------------
# Masskörning
# -----------------------------
echo -e "${BLUE}Söker efter AppImages i:${NC} $APPDIR"
shopt -s nullglob
appimages=("$APPDIR"/*.AppImage "$APPDIR"/*.appimage)
shopt -u nullglob

if [[ ${#appimages[@]} -eq 0 ]]; then
  echo -e "${YELLOW}Inga AppImages hittade i $APPDIR${NC}"
  exit 0
fi

for app in "${appimages[@]}"; do
  process_appimage "$app"
done

echo -e "${GREEN}✔ Alla AppImages bearbetade.${NC}"
echo "Om ikoner inte syns → logga ut/in eller kör:"
echo "  gtk-update-icon-theme ~/.local/share/icons/hicolor"

