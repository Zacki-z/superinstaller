# Superinstaller 4.10 – dokumentation

Superinstaller är en whiptail-baserad startcentral för systemflytt, programinstallation, backup, återställning och underhåll i Ubuntu.

## Snabbstart

```bash
chmod +x ~/my_bin/superinstaller-4.10.sh
~/my_bin/superinstaller-4.10.sh
```

## Huvudmeny

1. **Flytta data** – förkontroll, backup, flyttpaket och återställning.
2. **Installera program** – APT, AppImage, Flatpak, Snap, DEB och Proton.
3. **Utilities** – backup/restore, Darktable och övriga verktyg.

## Viktiga filer

- `~/my_bin/etc/app_paths.txt`
- `~/my_bin/etc/repos.txt`
- `~/my_bin/etc/packages.txt`
- `~/my_bin/etc/deb_list.txt`

## Rekommenderad systemflytt

1. Stäng Darktable, Mixxx och RawTherapee.
2. Kör kontroll före flytt.
3. Skapa Darktable- och programbackuper.
4. Kör kontrollen igen.
5. Skapa flyttpaketet.
6. Installera program på den nya datorn.
7. Packa upp flyttpaketet.
8. Återställ programinställningar och Darktable.

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

Menyn är rullbar med piltangenterna.

## Kontrollrapport

- **OK** – filen finns, Bash-syntaxen är korrekt och den är körbar.
- **SAKNAS** – filen hittades inte.
- **SYNTAXFEL** – `bash -n` rapporterade ett fel.
- **EJ KÖRBAR** – kör `chmod +x` på filen.

## Viktiga begränsningar

- Dry-run och debug fungerar bara om underskriptet stöder argumenten.
- `main_install-1.0.sh` söker `setup.sh`, `install.sh` och `cleanup.sh` i `~/scripts`.
- `migrate_darktable-6.0.sh` är för Snap till AppImage/APT/Flatpak, inte AppImage till AppImage.
- Backuper bör även kopieras till en separat disk.

Den fullständiga dokumentationen finns i `Superinstaller-4.10-dokumentation.docx`.
