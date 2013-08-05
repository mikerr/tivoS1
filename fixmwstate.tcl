#!/bin/bash
#
# Fix the MWSTATE bug on 2.5.5 UK Thompson Tivos
mount -o remount -rw /
cd /tvbin
mv tivoapp tivoapp-bak
cp tivoapp-bak tivoapp
echo -n '1' | dd conv=notrunc of=tivoapp bs=1 seek=5137975 
echo ""
echo "MWSTATE bug fixed successfully"
echo ""
echo "Please restart tivo for this to take effect"
echo ""
echo "e.g. type reboot <enter> at the prompt"
