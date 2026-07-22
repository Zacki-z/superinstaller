#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_DIR="$HOME/Applications"
BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/state/appimage-tools"
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
GEARLEVER_ID="it.mijorus.gearlever"

SKIP_UPGRADE=0
INSTALL_GEARLEVER=1

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32mOK:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mVARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFEL:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Förbereder Ubuntu 26.04 för AppImage.

Kör:
  chmod +x ubuntu-26-appimage-max-setup.sh
  ./ubuntu-26-appimage-max-setup.sh

Alternativ:
  --skip-upgrade    Hoppa över apt full-upgrade
  --no-gearlever    Installera inte Gear Lever
  --help            Visa hjälp
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-upgrade) SKIP_UPGRADE=1 ;;
    --no-gearlever) INSTALL_GEARLEVER=0 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Okänt alternativ: $arg" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "Kör skriptet som vanlig användare, inte med sudo."
[[ -r /etc/os-release ]] || die "Kan inte läsa /etc/os-release."

# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || die "Skriptet är avsett för Ubuntu."
if [[ "${VERSION_ID:-}" != "26.04" ]]; then
  warn "Du kör ${PRETTY_NAME:-okänd version}, inte Ubuntu 26.04."
fi

mkdir -p "$APP_DIR" "$BIN_DIR" "$STATE_DIR" "$HOME/.local/share/applications"

say "Verifierar sudo"
sudo -v

say "Aktiverar Universe och uppdaterar paketlistan"
sudo add-apt-repository -y universe
sudo apt-get update

if (( ! SKIP_UPGRADE )); then
  say "Installerar tillgängliga systemuppdateringar"
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
else
  warn "Full systemuppgradering hoppades över."
fi

say "Installerar AppImage-stöd och verktyg"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libfuse2t64 \
  fuse3 \
  flatpak \
  apparmor \
  apparmor-utils \
  desktop-file-utils \
  shared-mime-info \
  xdg-utils \
  file \
  curl \
  ca-certificates \
  coreutils

say "Laddar FUSE"
sudo modprobe fuse || warn "FUSE-modulen kunde inte laddas eller är redan inbyggd."

if ! grep -qxF fuse /etc/modules 2>/dev/null; then
  echo fuse | sudo tee -a /etc/modules >/dev/null
fi

say "Konfigurerar Flathub"
flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL"

if (( INSTALL_GEARLEVER )); then
  say "Installerar Gear Lever"
  flatpak install --user -y flathub "$GEARLEVER_ID"
fi

say "Installerar hjälpfunktioner"

cat > "$BIN_DIR/appimage-install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

die(){ printf 'FEL: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "Användning: appimage-install FIL.AppImage"

src="$(readlink -f -- "$1")"
[[ -f "$src" ]] || die "Filen finns inte: $1"

desc="$(file -b "$src" 2>/dev/null || true)"

case "$(uname -m)" in
  x86_64)
    [[ "$desc" != *"ARM"* && "$desc" != *"aarch64"* ]] || die "Filen verkar vara byggd för ARM."
    ;;
  aarch64|arm64)
    [[ "$desc" != *"x86-64"* ]] || die "Filen verkar vara byggd för x86_64."
    ;;
esac

mkdir -p "$HOME/Applications"

base="$(basename -- "$src")"
safe="$(printf '%s' "$base" | sed -E 's/[^A-Za-z0-9._+-]+/-/g')"
[[ "$safe" == *.AppImage ]] || safe="${safe}.AppImage"
dest="$HOME/Applications/$safe"

if [[ "$src" != "$dest" ]]; then
  if [[ -e "$dest" ]]; then
    dest="$HOME/Applications/${safe%.AppImage}-$(date +%Y%m%d-%H%M%S).AppImage"
  fi
  install -m 0755 -- "$src" "$dest"
else
  chmod 0755 "$dest"
fi

echo
echo "Installerad:"
echo "  $dest"
echo
echo "SHA256:"
sha256sum "$dest"
echo
printf 'Starta med:\n  appimage-run %q\n' "$dest"
echo
echo "Öppna Gear Lever för menyintegration."
EOF

cat > "$BIN_DIR/appimage-run" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -ge 1 ]] || { echo "Användning: appimage-run FIL.AppImage [argument]" >&2; exit 1; }

app="$(readlink -f -- "$1")"
shift

[[ -f "$app" ]] || { echo "Filen finns inte: $app" >&2; exit 1; }
[[ -x "$app" ]] || chmod u+x "$app"

if "$app" "$@"; then
  exit 0
fi

rc=$?
echo "Normal start misslyckades med felkod $rc." >&2
echo "Provar FUSE-fritt reservläge..." >&2
exec "$app" --appimage-extract-and-run "$@"
EOF

cat > "$BIN_DIR/appimage-diagnose" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { echo "Användning: appimage-diagnose FIL.AppImage" >&2; exit 1; }

app="$(readlink -f -- "$1")"
[[ -f "$app" ]] || { echo "Filen finns inte: $app" >&2; exit 1; }

mkdir -p "$HOME/.local/state/appimage-tools"
log="$HOME/.local/state/appimage-tools/diagnos-$(date +%Y%m%d-%H%M%S).txt"

{
  echo "AppImage-diagnos"
  echo "Datum: $(date --iso-8601=seconds)"
  echo "System: $(. /etc/os-release; echo "${PRETTY_NAME:-okänt}")"
  echo "Kärna: $(uname -a)"
  echo "Arkitektur: $(uname -m)"
  echo "Skrivbord: ${XDG_CURRENT_DESKTOP:-okänt}"
  echo "Session: ${XDG_SESSION_TYPE:-okänt}"
  echo "Fil: $app"
  echo
  echo "== filtyp =="
  file "$app" || true
  echo
  echo "== rättigheter =="
  ls -l "$app" || true
  echo
  echo "== FUSE-paket =="
  dpkg-query -W -f='${binary:Package}\t${Status}\t${Version}\n' libfuse2t64 fuse3 2>&1 || true
  echo
  echo "== libfuse.so.2 =="
  ldconfig -p 2>/dev/null | grep 'libfuse\.so\.2' || true
  echo
  echo "== FUSE-modul =="
  lsmod | grep '^fuse' || true
  echo
  echo "== AppArmor =="
  aa-enabled 2>&1 || true
  echo
  echo "== senaste AppArmor/userns-fel =="
  journalctl -k --since '-10 minutes' --no-pager 2>/dev/null |
    grep -Ei 'apparmor|userns|namespace|denied' || true
  echo
  echo "== teststart, max 20 sekunder =="
  chmod u+x "$app"
  timeout 20s "$app" 2>&1 || true
  echo
  echo "== FUSE-fritt test =="
  timeout 20s "$app" --appimage-extract-and-run 2>&1 || true
} | tee "$log"

echo
echo "Diagnosen sparades i:"
echo "  $log"
echo
echo "Vid AppArmor DENIED och userns_create:"
printf '  appimage-userns-allow %q\n' "$app"
EOF

cat > "$BIN_DIR/appimage-userns-allow" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { echo "Användning: appimage-userns-allow FIL.AppImage" >&2; exit 1; }

app="$(readlink -f -- "$1")"
[[ -f "$app" ]] || { echo "Filen finns inte: $app" >&2; exit 1; }

case "$app" in
  "$HOME/Applications/"*.AppImage) ;;
  *)
    echo "Av säkerhetsskäl måste filen ligga direkt i $HOME/Applications." >&2
    exit 1
    ;;
esac

id="$(printf '%s' "$app" | sha256sum | cut -c1-16)"
name="local-appimage-$id"
profile="/etc/apparmor.d/$name"
escaped="${app//\"/\\\"}"

echo "Detta skapar en AppArmor-profil endast för:"
echo "  $app"
echo
read -r -p "Fortsätt? [j/N] " svar

case "$svar" in
  j|J|ja|JA|Ja) ;;
  *) echo "Avbrutet."; exit 0 ;;
esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<PROFILE
abi <abi/4.0>,
include <tunables/global>

profile $name "$escaped" flags=(unconfined) {
    userns,
}
PROFILE

sudo install -m 0644 "$tmp" "$profile"
sudo apparmor_parser -r "$profile"

echo
echo "Profilen är installerad:"
echo "  $profile"
EOF

cat > "$BIN_DIR/appimage-userns-remove" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { echo "Användning: appimage-userns-remove FIL.AppImage" >&2; exit 1; }

app="$(readlink -f -- "$1")"
id="$(printf '%s' "$app" | sha256sum | cut -c1-16)"
name="local-appimage-$id"
profile="/etc/apparmor.d/$name"

[[ -f "$profile" ]] || { echo "Ingen profil hittades: $profile" >&2; exit 1; }

sudo apparmor_parser -R "$profile" 2>/dev/null || true
sudo rm -f "$profile"

echo "Profilen togs bort:"
echo "  $profile"
EOF

cat > "$BIN_DIR/appimage-list" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

files=("$HOME/Applications/"*.AppImage)

if (( ${#files[@]} == 0 )); then
  echo "Inga AppImages finns i $HOME/Applications"
  exit 0
fi

for app in "${files[@]}"; do
  printf '%s  %s\n' "$(du -h "$app" | cut -f1)" "$app"
done
EOF

chmod 0755 \
  "$BIN_DIR/appimage-install" \
  "$BIN_DIR/appimage-run" \
  "$BIN_DIR/appimage-diagnose" \
  "$BIN_DIR/appimage-userns-allow" \
  "$BIN_DIR/appimage-userns-remove" \
  "$BIN_DIR/appimage-list"

say "Lägger ~/.local/bin i PATH"
if ! grep -Fq '.local/bin' "$HOME/.profile" 2>/dev/null; then
  cat >> "$HOME/.profile" <<'EOF'

# Lokala användarkommandon
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
EOF
fi

export PATH="$BIN_DIR:$PATH"

say "Uppdaterar skrivbordsdatabaser"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true

say "Kontrollerar installationen"

ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2' \
  && ok "FUSE 2-kompatibilitet finns." \
  || warn "libfuse.so.2 hittades inte."

command -v fusermount3 >/dev/null \
  && ok "FUSE 3 finns." \
  || warn "FUSE 3 hittades inte."

flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub \
  && ok "Flathub är konfigurerat." \
  || warn "Flathub kunde inte verifieras."

if (( INSTALL_GEARLEVER )); then
  flatpak info --user "$GEARLEVER_ID" >/dev/null 2>&1 \
    && ok "Gear Lever är installerat." \
    || warn "Gear Lever kunde inte verifieras."
fi

aa-enabled >/dev/null 2>&1 \
  && ok "AppArmor är aktivt." \
  || warn "AppArmor verkar inte vara aktivt."

cat <<EOF

Klart.

Efter omstart eller utloggning/inloggning:

Installera en AppImage:
  appimage-install ~/Hämtningar/Program.AppImage

Starta den:
  appimage-run ~/Applications/Program.AppImage

Felsök:
  appimage-diagnose ~/Applications/Program.AppImage

Endast vid dokumenterat AppArmor/userns-fel:
  appimage-userns-allow ~/Applications/Program.AppImage

Visa installerade AppImages:
  appimage-list

AppImage-katalog:
  $APP_DIR
EOF
