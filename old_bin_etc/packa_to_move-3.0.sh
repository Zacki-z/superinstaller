#!/bin/sh
# set -x
set -eu pipefail
echo on	
cd ~
date >/tmp/flytta-time
echo  "sätt igång" >>/tmp/flytta-time 
sleep 2
echo "Rensar först"
echo "Rensar först">>/tmp/flytta-time
rm -fr /home/alain/dot-files/dot-darktable/d*
rm -fr /home/alain/dot-files/dot-mixxx/*
rm -fr /home/alain/dot-files/dot-cache/.c*
rm -fr /home/alain/dot-files/dot-config/c*
# exit
echo "sparar undan configfiler"
echo "sparar undan configfiler" >>/tmp/flytta-time 
sleep 2
cp -r ~/.mixxx /home/alain/dot-files/dot-mixxx
cp -r ~/.cache /home/alain/dot-files/dot-cache
cp -r /home/alain/snap/darktable/ /home/alain/dot-files/dot-darktable
cp -r ~/.config /home/alain/dot-files/dot-config
# exit
echo "Rensar usb disk"
echo "Rensar usb disk">>/tmp/flytta-time
sleep 2
rm -fr /media/alain/move_stuff/dot-darktable/d*
rm -fr /media/alain/move_stuff/dot-mixxx/.m*
rm -fr /media/alain/move_stuff/dot-cache/.c*
rm -fr /media/alain/move_stuff/dot-config/.c*
rm -fr /media/alain/move_stuff/my_bin/*
rm -fr /media/alain/move_stuff/my_etc/*
# exit
echo "sparar undan configfiler till usb disk"
echo "sparar undan configfiler till usb disk">>/tmp/flytta-time
sleep 2
cp -r ~/.cache /media/alain/move_stuff/dot-cache
cp -r ~/.mixxx /media/alain/move_stuff/dot-mixxx
cp -r /home/alain/snap/darktable/ /media/alain/move_stuff/dot-darktable
cp -r ~/.config /media/alain/move_stuff/dot-config
# exit
echo "start packa"
echo "start packa">>/tmp/flytta-time
sleep 2
tar cf flytta.tarz /home/alain/Dokument/ /home/alain/Documents/ /home/alain/Bilder/ /home/alain/Pictures/ /home/alain/Musik/ /home/alain/bup_darktable /home/alain/Skrivbord/ /home/alain/Desktop/ /home/alain/my_bin/ /home/alain/my_etc/ /home/alain/"Calibre Library" /home/alain/dot-files/ /home/alain/Arduino/ /home/alain/kicad_stuff /home/alain/Applications/ 2> /tmp/errors.txt
echo "flytta till disk"
cp -v flytta.tarz /media/alain/move_stuff/tar_files/
echo "flytta my_bin"
echo "flytta my_bin">>/tmp/flytta-time
sleep 2
cp -r /home/alain/my_bin /media/alain/move_stuff/
echo "flytta my_etc"
echo "flytta my_etc>>"/tmp/flytta-time
sleep 2
cp -r /home/alain/my_etc /media/alain/move_stuff/
cd ~
rm -i /home/alain/flytta.tarz
echo "klart" >>/tmp/flytta-time
date >>/tmp/flytta-time
