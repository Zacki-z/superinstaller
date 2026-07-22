#!/usr/bin/env bash
set -euo pipefail

echo "== Steg 1: kolla OpenCL i systemet =="
if ! command -v clinfo >/dev/null; then
  sudo apt update
  sudo apt -y install clinfo
fi
clinfo | grep -E "Device Name|OpenCL [0-9]" || true

if flatpak list | grep -q org.darktable.Darktable; then
  echo "== Flatpak-upptäckt: ger GPU-åtkomst =="
  flatpak override --user --device=all org.darktable.Darktable
  flatpak override --user --env=LIBVA_DRIVER_NAME=iHD org.darktable.Darktable
  echo "== Startar Darktable (Flatpak) med OpenCL-debug =="
  exec flatpak run org.darktable.Darktable -d opencl
else
  echo "== Apt-upptäckt: installerar Intel OpenCL ICD om det saknas =="
  sudo apt update
  sudo apt -y install intel-opencl-icd ocl-icd-libopencl1 || true
  export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
  echo "== Startar Darktable (apt) med OpenCL-debug =="
  exec darktable -d opencl
fi
sleep 10
echo ""
read -rp "Vill du avsluta scriptet nu? (j/n): " svar
case "$svar" in
  [JjYy]* ) echo "Avslutar scriptet. Ha en fin dag! 👋"; exit 0 ;;
  * ) echo "Scriptet fortsätter att köras..."; sleep 2 ;;
esac

