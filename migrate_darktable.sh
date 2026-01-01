#!/bin/bash
set -euo pipefail

# Migrera Darktable från Snap -> vanlig (AppImage/APT/Flatpak) som använder:
#  - ~/.config/darktable
#  - ~/.local/share/darktable
# OCH patcha darktablerc så OpenCL aktiveras.
# Kör när Darktable är AVSTÄNGT.

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*" >&2
}

SNAP_BASE="${HOME}/snap/darktable"
DEST_CONFIG="${HOME}/.config/darktable"
DEST_SHARE="${HOME}/.local/share/darktable"
BACKUP_BASE="${HOME}/darktable_migration_backup_$(date +%Y%m%d-%H%M%S)"

log "🔍 Letar efter Snap-installation i: $SNAP_BASE"

if [[ ! -d "$SNAP_BASE" ]]; then
  log "❌ Hittar ingen katalog: $SNAP_BASE"
  log "Avbryter. Är Darktable installerat som snap på denna användare?"
  exit 1
fi

# Försök först med 'current', annars ta senaste versionsmappen
SRC_DIR=""
if [[ -d "${SNAP_BASE}/current" ]]; then
  SRC_DIR="${SNAP_BASE}/current"
else
  mapfile -t REVS < <(find "$SNAP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -n)
  if [[ ${#REVS[@]} -eq 0 ]]; then
    log "❌ Hittade inga underkataloger i $SNAP_BASE"
    exit 1
  fi
  LAST="${REVS[-1]}"
  SRC_DIR="${SNAP_BASE}/${LAST}"
fi

log "✅ Använder Snap-källa: $SRC_DIR"

# Skapa backup av både Snap-källa och ev. befintlig config/share
log "📦 Skapar backup i: $BACKUP_BASE"
mkdir -p "$BACKUP_BASE"

log "📂 Backup av Snap-darktable → $BACKUP_BASE/snap_darktable"
cp -a "$SRC_DIR" "$BACKUP_BASE/snap_darktable"

if [[ -d "$DEST_CONFIG" ]]; then
  log "📂 Backup av befintlig ~/.config/darktable → $BACKUP_BASE/config_darktable"
  cp -a "$DEST_CONFIG" "$BACKUP_BASE/config_darktable"
fi

if [[ -d "$DEST_SHARE" ]]; then
  log "📂 Backup av befintlig ~/.local/share/darktable → $BACKUP_BASE/share_darktable"
  cp -a "$DEST_SHARE" "$BACKUP_BASE/share_darktable"
fi

# Skapa målmappar
log "📁 Skapar målmappar (om de saknas)..."
mkdir -p "$DEST_CONFIG"
mkdir -p "$DEST_SHARE"

# Funktioner för säker kopiering
copy_if_exists_file() {
  local src="$1"
  local dst_dir="$2"
  if [[ -f "$src" ]]; then
    log "➡️  Kopierar fil: $(basename "$src") → $dst_dir"
    cp -a "$src" "$dst_dir/"
  else
    log "ℹ️  Hoppar över (saknas): $src"
  fi
}

copy_if_exists_dir() {
  local src="$1"
  local dst="$2"
  if [[ -d "$src" ]]; then
    log "➡️  Kopierar katalog: $src → $dst"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  else
    log "ℹ️  Hoppar över katalog (saknas): $src"
  fi
}

log "📑 Kopierar konfig & databaser till ~/.config/darktable ..."
copy_if_exists_file "$SRC_DIR/darktablerc" "$DEST_CONFIG"
copy_if_exists_file "$SRC_DIR/data.db"    "$DEST_CONFIG"
copy_if_exists_file "$SRC_DIR/library.db" "$DEST_CONFIG"

log "🎨 Kopierar styles, lua, watermarks m.m. till ~/.local/share/darktable ..."
copy_if_exists_dir "$SRC_DIR/styles"     "$DEST_SHARE/styles"
copy_if_exists_dir "$SRC_DIR/lua"        "$DEST_SHARE/lua"
copy_if_exists_dir "$SRC_DIR/color"      "$DEST_SHARE/color"
copy_if_exists_dir "$SRC_DIR/watermarks" "$DEST_SHARE/watermarks"
copy_if_exists_dir "$SRC_DIR/presets"    "$DEST_SHARE/presets"

###############################################################################
# PATCHA darktablerc FÖR OPENCL
###############################################################################
DT_RC="${DEST_CONFIG}/darktablerc"

if [[ -f "$DT_RC" ]]; then
  log "🛠 Hittade darktablerc: $DT_RC"
  RC_BAK="${BACKUP_BASE}/darktablerc_pre_opencl"
  log "📂 Backup av darktablerc före patch → $RC_BAK"
  cp -a "$DT_RC" "$RC_BAK"

  # Funktion för att skriva/uppdatera KEY=VALUE
  ensure_kv() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -q -E "^${key}=" "$file"; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
      printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
  }

  log "⚙️  Patchar OpenCL-inställningar i darktablerc ..."

  ensure_kv "opencl"                    "TRUE"            "$DT_RC"
  ensure_kv "opencl_library"            "libOpenCL.so.1"  "$DT_RC"
  ensure_kv "opencl_device_priority"    "*/!0,*/*/*/!0,*" "$DT_RC"
  ensure_kv "opencl_scheduling_profile" "default"         "$DT_RC"
  ensure_kv "opencl_mandatory_timeout"  "400"             "$DT_RC"
  ensure_kv "opencl_tune_headroom"      "FALSE"           "$DT_RC"
  ensure_kv "opencl_async_pixelpipe"    "TRUE"            "$DT_RC"
  ensure_kv "opencl_micro_nap"          "TRUE"            "$DT_RC"
  ensure_kv "opencl_avoid_atomics"      "TRUE"            "$DT_RC"

  log "✅ darktablerc patchad för OpenCL."
else
  log "⚠️ Hittade ingen darktablerc i $DEST_CONFIG – hoppar över OpenCL-patch."
fi

log "🧹 Rör inte cache/kernels – AppImage får bygga om dem själv."
log "🎉 Migration + OpenCL-patch KLAR!"
log "💾 Backup finns i: $BACKUP_BASE"

###############################################################################
# Y/N – FRÅGA OM TEST
###############################################################################

echo
read -rp "Vill du testa OpenCL nu? (y/n): " answer
echo

case "$answer" in
  y|Y|yes|YES)
    log "▶️  Kör: darktable -d opencl | head -n 60"
    darktable -d opencl | head -n 60 || log "⚠️ darktable kunde inte startas för OpenCL-test."
    ;;
  *)
    log "⏭ Hoppar över OpenCL-test."
    ;;
esac

log "👌 Klart!"

