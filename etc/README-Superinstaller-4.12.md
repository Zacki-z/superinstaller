# Superinstaller 4.12 - dokumentation

Superinstaller är en whiptail-baserad startcentral för systemflytt, programinstallation, backup, återställning och underhåll i Ubuntu.

## Nytt i 4.12

- `app_paths.txt` kan nu använda både vanliga mellanslag och tabbar mellan appnamn och sökväg.
- RawTherapee-AppImage kan hittas via `~/.config/RawTherapee-AppImage`.
- Packningskontrollen identifierar `--dry-run` eller `-n` och läser `tar_dirs.txt`.
- Utilities-menyn är rullbar och innehåller backup samt restore för Darktable och övriga program.

## Start

```bash
chmod +x ~/my_bin/superinstaller-4.12.sh
~/my_bin/superinstaller-4.12.sh
```

## Huvudmeny

1. **Flytta data** - kontroll, backup, flyttpaket och återställning.
2. **Installera program** - APT, AppImage, Flatpak, Snap, DEB och Proton.
3. **Utilities** - backup/restore, Darktable och andra verktyg.

## Rekommenderad systemflytt

1. Stäng Darktable, Mixxx och RawTherapee.
2. Kör **Kontrollera att allt är redo**.
3. Säkerhetskopiera Darktable, Mixxx och RawTherapee.
4. Säkerhetskopiera övriga programinställningar.
5. Kopiera backuper till en extern disk.
6. Kör kontroll före packning igen.
7. Skapa flyttpaketet.
8. Installera program på den nya datorn.
9. Packa upp flyttpaketet.
10. Återställ programinställningar och Darktable.

## RawTherapee-AppImage

`~/my_bin/etc/app_paths.txt` ska innehålla:

```text
rawtherapee ~/.config/RawTherapee-AppImage
```

Testa utan ändringar:

```bash
bash ~/my_bin/backup_appconfig-4.0.sh rawtherapee --dry-run --verbose
```

## Utilities

1. AppImage: skapa skrivbordsikoner
2. AppImage: förbered Ubuntu 26.04
3. Darktable: säkerhetskopiera konfiguration
4. Darktable: återställ konfiguration
5. Programinställningar: säkerhetskopiera
6. Programinställningar: återställ
7. Avinstallera apt-paket
8. Migrera Darktable 6.0
9. Kontrollera/fixa Darktable OpenCL
10. Surface tablet mode
11. Lösenordsgenerator
12. Montera Samba
13. Rätta framtida tidsstämplar
14. Kontrollera alla scriptsökvägar
15. Visa innehållet i my_bin

Menyn visar 13 poster åt gången. Använd piltangenterna för att rulla.

## Viktiga konfigurationsfiler

- `~/my_bin/etc/app_paths.txt`
- `~/my_bin/etc/repos.txt`
- `~/my_bin/etc/packages.txt`
- `~/my_bin/etc/deb_list.txt`
- `~/my_bin/etc/tar_dirs.txt`

Packlistan bör minst innehålla:

```text
bup_darktable
bup_appl_config
my_bin
```

## Kontrollrapporter

- **OK** - filen eller kontrollen är godkänd.
- **VARNING** - läs och bedöm innan du fortsätter.
- **FEL** - systemet markeras som inte redo att packa.
- **SAKNAS** - ett konfigurerat skript hittades inte.
- **SYNTAXFEL** - `bash -n` hittade fel.
- **EJ KÖRBAR** - kör `chmod +x` på filen.

Preflight-loggar sparas i:

```text
~/.local/state/superinstaller/
```

Den fullständiga dokumentationen finns i `Superinstaller-4.12-dokumentation.docx`.
