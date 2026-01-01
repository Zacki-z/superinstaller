#!/usr/bin/env bash
set -euo pipefail

echo "== Kollar OpenCL =="
command -v clinfo >/dev/null || { sudo apt update; sudo apt -y install clinfo; }
clinfo | grep -E "Device Name|OpenCL [0-9]" || true

if flatpak list | grep -q org.darktable.Darktable; then
  echo "== Flatpak-upptäckt: ger GPU-åtkomst =="
  flatpak override --user --device=all --env=LIBVA_DRIVER_NAME=iHD org.darktable.Darktable
  echo "== Startar Darktable (Flatpak) med OpenCL-debug =="
  set +e
  flatpak run org.darktable.Darktable -d opencl
  rc=$?
  set -e
else
  echo "== Apt-upptäckt: installerar Intel OpenCL ICD om det saknas =="
  sudo apt update
  sudo apt -y install intel-opencl-icd ocl-icd-libopencl1 || true
  export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
  echo "== Startar Darktable (apt) med OpenCL-debug =="
  set +e
  darktable -d opencl
  rc=$?
  set -e
fi

echo ""
echo "Darktable avslutades (exitkod: $rc)."
read -rp "Vill du avsluta scriptet nu? (j/n): " svar
case "$svar" in
  [JjYy]* ) echo "Avslutar scriptet. 👋"; exit 0 ;;
  * ) echo "Scriptet fortsätter... (lägg fler kommandon här)";;
esac

