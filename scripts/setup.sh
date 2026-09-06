#!/bin/sh
# Adds the sc1r3x pacman repository. Safe to run more than once.
# Automatically updates any existing [archrepo] installation to [sc1r3x].
set -e
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
curl -s https://pkg.scirex.me/sc1r3x.pub.asc | pacman-key --add -
pacman-key --lsign-key 8A17827692EECC3C5270DA9D1CE75EC9217912BA

if grep -q '^\[archrepo\]' /etc/pacman.conf; then
  sed -i 's/^\[archrepo\]/[sc1r3x]/' /etc/pacman.conf
  rm -f /var/lib/pacman/sync/archrepo.*
elif ! grep -q '^\[sc1r3x\]' /etc/pacman.conf; then
  printf '\n[sc1r3x]\nServer = https://pkg.scirex.me\n' >> /etc/pacman.conf
fi

pacman -Sy
echo "sc1r3x repo ready. Try: sudo pacman -S openbangla-keyboard"
