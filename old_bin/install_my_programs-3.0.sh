#!/bin/bash
set -e  # stoppa vid fel

# Gör apt icke-interaktivt
export DEBIAN_FRONTEND=noninteractive

echo "Uppdaterar paketindex..."
sudo apt update -y
sleep 2
echo "startar installtioner av program"
sleep 2
# ************** installationer via sapt *******************#
sudo apt update -y
sudo apt install -y calibre
sudo add-apt-repository ppa:scribus/ppa
sudo apt install -y scribus
sudo add-apt-repository universe
sudo add-apt-repository ppa:inkscape.dev/stable
sudo apt-get update -y
sudo apt install -y inkscape
sudo add-apt-repository ppa:kicad/kicad-9.0-releases
sudo apt install -y kicad
sudo apt install -y krita
sudo apt install -y remmina
sudo apt install -y intel-opencl-icd ocl-icd-libopencl1 clinfo

sudo add-apt-repository universe
sudo apt install vlc

# ************** installationer via snap *******************#
sudo snap refresh --list
sudo snap install spotify
sudo snap install darktable --yes
sudo snap install audacity --yes
sudo snap install deadbeef-vs --yes
sudo snap install color-picker --yes
sudo snap install arduino --yes
sudo snap install s4a --yes
sudo snap install slack --yes
sudo snap install vcard-studio --yes
sudo snap refresh --yes

# ************** installationer via snap *******************#
sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.gnucash.GnuCash -y
flatpak install flathub org.gimp.GIMP -y
echo "finished"
sleep 10
