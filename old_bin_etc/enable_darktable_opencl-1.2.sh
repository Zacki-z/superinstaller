#!/usr/bin/env bash
set -euo pipefail

say() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }

LOG_DIR="${HOME}"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/darktable-opencl-${TS}.log"

disable_bad_ppas() {
  say "Steg 0: letar efter kända trasiga PPA och stänger av dem temporärt …"
  shopt -s nullglob
  for f in /etc/apt/sources.list.d/*.list; do
    case "$f" in
      *scribus*|*appimagelauncher*|*inkscape*|*mixxx*|*kicad-8.0*|*kicad-9.0*)
        sudo sed -i 's/^[[:space:]]*deb /# deb /' "$f" || true
        echo "  - inaktiverad: $f"
      ;;
    esac
  done
  shopt -u nullglob
}

apt_update_safe() {
  say "apt update (rensar källor + uppdaterar index)"
  sudo apt-get -y update || true

  local badlists
  badlists=$(grep -RIl "Release' does not have a Release file" /var/lib/apt/lists 2>/dev/null || true)
  if [[ -n "${badlists}" ]]; then
    say "Upptäckte arkiv utan Release file – inaktiverar motsv. .list"
    for dom in $(echo "$badlists" | sed -E 's|.*/([^_/]+)_.*|\1|' | sort -u); do
      for f in /etc/apt/sources.list.d/*.list; do
        if grep -qi "$dom" "$f"; then
          sudo sed -i 's/^[[:space:]]*deb /# deb /' "$f" || true
          echo "  - auto-inaktiverad: $f"
        fi
      done
    done
    sudo apt-get update || true
  fi
}

ensure_opencl_packages() {
  say "Steg 1: kollar OpenCL i systemet"
  if ! command -v clinfo >/dev/null 2>&1; then
    sudo apt-get -y install clinfo
  fi

  say "Steg 2: installerar Intel OpenCL ICD om det behövs"
  sudo apt-get -y install intel-opencl-icd ocl-icd-libopencl1 || true

  say "Systemets OpenCL-enheter (kort utdrag):"
  clinfo | grep -E "Platform Version|Device Name|Device Version|OpenCL [0-9]" || true
}

run_darktable_with_log() {
  say "Steg 3: startar Darktable med OpenCL-debug (logg: ${LOG_FILE})"
  : > "${LOG_FILE}"

  if command -v flatpak >/dev/null 2>&1 && flatpak list | grep -q org.darktable.Darktable; then
    flatpak override --user --device=all --env=LIBVA_DRIVER_NAME=iHD org.darktable.Darktable
    set +e
    # logga både till skärm och fil
    flatpak run org.darktable.Darktable -d opencl 2>&1 | tee -a "${LOG_FILE}"
    rc=${PIPESTATUS[0]}
    set -e
  else
    export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
    set +e
    darktable -d opencl 2>&1 | tee -a "${LOG_FILE}"
    rc=${PIPESTATUS[0]}
    set -e
  fi

  echo
  echo "Darktable avslutades (exitkod: ${rc}). Logg sparad i: ${LOG_FILE}"
}

summarize_log() {
  say "Sammanfattning (ur loggen)"
  local devices count enabled
  devices=$(grep -E "Iris|NVIDIA|AMD|OpenCL device|device .*: " -i "${LOG_FILE}" | sed -E 's/^[[:space:]]+//g' | sort -u || true)
  count=$(grep -iE "found .* OpenCL device|found [0-9]+ suitable OpenCL device" "${LOG_FILE}" | tail -n1 | grep -oE '[0-9]+' || echo "0")
  if grep -qi "using OpenCL device" "${LOG_FILE}"; then enabled="JA"; else enabled="OKLART/NEJ"; fi

  echo "• Antal hittade OpenCL-enheter: ${count}"
  echo "• OpenCL aktivt i pipeline: ${enabled}"
  echo "• Enheter:"
  if [[ -n "$devices" ]]; then
    echo "$devices" | sed 's/^/   - /'
  else
    echo "   - (inga enheter hittade i loggen)"
  fi
}

post_prompt() {
  echo
  read -rp "Vill du avsluta scriptet nu? (j/n): " svar
  case "$svar" in
    [JjYy]* ) echo "Avslutar scriptet. Logg: ${LOG_FILE} 👋"; exit 0 ;;
    * )
      echo "Vill du öppna Darktable igen och fortsätta logga till samma fil? (j/n)"
      read -r svar2
      if [[ "$svar2" =~ ^[JjYy] ]]; then
        run_darktable_with_log
        summarize_log
        post_prompt
      else
        echo "Klart. Logg finns i: ${LOG_FILE}"
      fi
    ;;
  esac
}

main() {
  disable_bad_ppas
  apt_update_safe
  ensure_opencl_packages
  run_darktable_with_log
  summarize_log
  post_prompt
}

main "$@"

