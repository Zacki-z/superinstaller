#!/usr/bin/env bash
# dt-start.sh — starta Darktable med ren GTK-miljö och logga OpenCL-status
set -euo pipefail

LOG="${HOME}/darktable-opencl.log"
CLEAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clear-kernels) CLEAR=1; shift ;;
    *) echo "Användning: $0 [--clear-kernels]"; exit 1 ;;
  esac
done

echo "== $(date) ==" | tee -a "$LOG"

# 1) Om Snap-version: koppla användbara interfaces (tyst om snap saknas)
if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | grep -q '^darktable '; then
  echo "[i] Snap-detekterad Darktable – kopplar interfaces (om ej redan)..." | tee -a "$LOG"
  sudo snap connect darktable:opengl       || true
  sudo snap connect darktable:removable-media || true
  KERNEL_DIR="${HOME}/snap/darktable/common/.cache/darktable"
else
  # Flatpak/AppImage/APT
  KERNEL_DIR="${HOME}/.cache/darktable"
fi

# 2) Valfritt: rensa tidigare kernel-cache
if [[ $CLEAR -eq 1 ]]; then
  echo "[i] Rensar OpenCL-kernelcache..." | tee -a "$LOG"
  rm -rf "${KERNEL_DIR}/cached_v5_kernels_for_"* 2>/dev/null || true
fi

# 3) Skriv lite miljöinfo
echo "[i] PATH: $PATH"                    | tee -a "$LOG"
echo "[i] OpenCL bibliotek: libOpenCL.so.1" | tee -a "$LOG"

# 4) Snabb OpenCL-detektering
if command -v clinfo >/dev/null 2>&1; then
  echo "[i] clinfo (plattform & enhet):" | tee -a "$LOG"
  clinfo | grep -E 'Platform Name|Device Name|Version' | tee -a "$LOG" || true
fi

# 5) Starta Darktable med GTK_MODULES avstängd och debug för OpenCL
echo "[i] Startar Darktable..." | tee -a "$LOG"
env -u GTK_MODULES darktable -d opencl 2>&1 | tee -a "$LOG"

