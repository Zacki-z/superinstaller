#!/usr/bin/env bash
# === ensure_darktable_opencl-1.0.sh ===
# Ser till att Darktable är konfigurerat för att använda OpenCL.
#
# Gör:
#   - Kollar att libOpenCL.so.1 finns i systemet.
#   - Hittar darktablerc för APT, Flatpak, Snap, AppImage.
#   - Tar backup på varje darktablerc innan ändring.
#   - Sätter opencl=TRUE och relaterade nycklar.
#
# Påverkar INTE paketinstallationer automatiskt, men ger kommandon
# att köra om OpenCL-bibliotek saknas.
#
# Användning:
#   ./ensure_darktable_opencl-1.0.sh

set -euo pipefail

echo "=== ensure_darktable_opencl-1.0.sh ==="
echo

# ------------------------------------------------------------
# 1. Kolla om libOpenCL.so.1 finns
# ------------------------------------------------------------

have_libopencl=false

if ldconfig -p 2>/dev/null | grep -q 'libOpenCL.so.1'; then
    have_libopencl=true
elif [ -f /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 ] || [ -f /usr/local/lib/libOpenCL.so.1 ]; then
    have_libopencl=true
fi

if $have_libopencl; then
    echo "✔ Hittade libOpenCL.so.1 i systemet."
else
    echo "⚠️  Hittade INTE libOpenCL.so.1 i ldconfig eller standardvägar."
    echo "    Darktable kan fortfarande starta, men OpenCL kommer troligen inte fungera."
    echo
    echo "På Ubuntu kan du prova (manuellt, med sudo):"
    echo "  sudo apt install ocl-icd-libopencl1 clinfo"
    echo "  sudo apt install intel-opencl-icd intel-level-zero-gpu intel-igc-opencl  # (Intel iGPU)"
    echo
fi

echo

# ------------------------------------------------------------
# 2. Hitta alla darktablerc som vi vill ändra
# ------------------------------------------------------------

RC_FILES=()

# APT / AppImage
if [ -f "$HOME/.config/darktable/darktablerc" ]; then
    RC_FILES+=("$HOME/.config/darktable/darktablerc")
fi

# Flatpak
if [ -f "$HOME/.var/app/org.darktable.Darktable/config/darktable/darktablerc" ]; then
    RC_FILES+=("$HOME/.var/app/org.darktable.Darktable/config/darktable/darktablerc")
fi

# Snap: current-länk
if [ -f "$HOME/snap/darktable/current/darktablerc" ]; then
    RC_FILES+=("$HOME/snap/darktable/current/darktablerc")
fi

# Snap: versionskataloger (t.ex. ~/snap/darktable/379/darktablerc)
for f in "$HOME"/snap/darktable/*/darktablerc; do
    [ -f "$f" ] && RC_FILES+=("$f")
done

# Rensa dubbletter
if [ "${#RC_FILES[@]}" -gt 0 ]; then
    # sort + uniq
    mapfile -t RC_FILES < <(printf "%s\n" "${RC_FILES[@]}" | sort -u)
fi

if [ "${#RC_FILES[@]}" -eq 0 ]; then
    echo "❌ Hittade ingen darktablerc att ändra."
    echo "   Starta Darktable minst en gång så att konfig-filerna skapas, och kör skriptet igen."
    exit 1
fi

echo "Hittade följande darktablerc-filer:"
for rc in "${RC_FILES[@]}"; do
    echo "  - $rc"
done
echo

# ------------------------------------------------------------
# 3. Hjälpfunktion: sätt/uppdatera nyckel i darktablerc
# ------------------------------------------------------------

set_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -q "^${key}=" "$file"; then
        # Ersätt befintlig rad
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        # Lägg till i slutet
        printf "%s=%s\n" "$key" "$value" >> "$file"
    fi
}

# ------------------------------------------------------------
# 4. Gå igenom alla darktablerc, ta backup och sätt OpenCL-nycklar
# ------------------------------------------------------------

TS=$(date '+%Y%m%d-%H%M%S')

for rc in "${RC_FILES[@]}"; do
    echo "----------------------------------------"
    echo "Bearbetar: $rc"

    if [ ! -f "$rc" ]; then
        echo "  ⚠️  Filen finns inte (skippas)."
        continue
    fi

    # Backup
    backup="${rc}.bak-${TS}"
    cp -a "$rc" "$backup"
    echo "  🛟 Backup skapad: $backup"

    # Sätt nycklar
    echo "  🔧 Sätter OpenCL-relaterade nycklar..."

    set_key "$rc" "opencl" "TRUE"
    set_key "$rc" "opencl_library" "libOpenCL.so.1"

    # Rekommenderade Intel/iGPU-inställningar (kan anpassas)
    set_key "$rc" "opencl_device_priority" "*/!0,*/*/*/!0,*"
    set_key "$rc" "opencl_scheduling_profile" "default"
    set_key "$rc" "opencl_mandatory_timeout" "400"
    set_key "$rc" "opencl_tune_headroom" "FALSE"
    set_key "$rc" "opencl_async_pixelpipe" "TRUE"
    set_key "$rc" "opencl_micro_nap" "TRUE"
    set_key "$rc" "opencl_avoid_atomics" "TRUE"

    echo "  ✔ Nycklar uppdaterade."
done

echo "----------------------------------------"
echo
echo "✅ Klart! Darktables konfigfiler är nu inställda för att använda OpenCL (opencl=TRUE)."
echo
echo "Nästa steg (manuellt):"
echo "  1) Se till att GPU/OpenCL-drivrutiner är installerade."
echo "  2) Starta Darktable från terminal med:"
echo "       darktable -d opencl"
echo "     eller om du kör Snap:"
echo "       snap run darktable -d opencl"
echo
echo "Titta efter rader som:"
echo "  'found 1 device'"
echo "  'device 0: <din GPU>'"
echo
echo "Om du får felmeddelanden om OpenCL-bibliotek:"
echo "  - kontrollera att libOpenCL.so.1 finns (clinfo kan hjälpa)."
echo "  - dubbelkolla eventuella snap-anslutningar:"
echo "      snap connections darktable | grep opengl"
echo "      sudo snap connect darktable:opengl"
echo
echo "Klart. 🙂"

