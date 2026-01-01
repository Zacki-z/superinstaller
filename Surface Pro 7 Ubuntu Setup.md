# Surface Pro 7+ – Ubuntu Setup Guide v1.0

Den här guiden hjälper dig installera Ubuntu på Microsoft Surface Pro 7+ och aktivera tablet-läge med touch, penna, rotation, skärmtangentbord och Surface-specifika drivrutiner.

---

## 1. Förberedelser

### Krav
- USB-sticka (8–16 GB)
- ISO-fil: Ubuntu 22.04 eller 24.04 LTS
- Etch­er eller Rufus (för att skapa installationsmedia)

### Stäng av Fast Startup i Windows
1. Öppna *Energialternativ*
2. “Välj vad strömknapparna gör”
3. Avmarkera **Snabbstart**

Detta gör dual-boot stabilare.

---

## 2. Starta från USB

1. Stoppa i USB-stickan
2. Håll **Volume Up + Power** → öppna Surface UEFI
3. Under *Boot Configuration*: ställ USB överst
4. Starta om

I bootmenyn: välj **Try/Install Ubuntu**

---

## 3. Installera Ubuntu

Vid partioneringen:
- Välj **Install Ubuntu alongside Windows** (dual boot)
- Eller radera disken om du inte vill ha Windows kvar

Följ installationen som vanligt.

---

## 4. Installera linux-surface-kärnan

Surface Pro 7+ fungerar bra utan detta,
men *mycket* bättre med.

```bash
curl -sL https://raw.githubusercontent.com/linux-surface/linux-surface/master/scripts/setup.sh | sudo bash
sudo apt update
sudo apt install linux-surface linux-surface-secureboot-mok iptsd libwacom-surface

