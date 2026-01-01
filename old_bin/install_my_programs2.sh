#!/bin/sh
sleep 2
echo "Kom ihåg att ladda ner och installera AppImagelanche, gå till url https://appimagelauncher.com/ "
sleep 10
sudo apt update
sudo apt install calibre
sudo add-apt-repository ppa:scribus/ppa
sudo apt install scribus
sudo add-apt-repository universe
sudo add-apt-repository ppa:inkscape.dev/stable
sudo apt-get update
sudo apt install inkscape
sudo add-apt-repository ppa:kicad/kicad-9.0-releases
sudo apt install kicad
sudo apt install krita
sudo snap refresh --list
#sudo snap install spotify
#sudo snap install vlc
sudo snap install audacity
sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.gnucash.GnuCash
sudo snap install deadbeef-vs
sudo snap install color-picker
sudo snap install arduino
sudo snap install s4a
sudo snap install slack
sudo snap install vcard-studio
echo "finished"
sleep 10
