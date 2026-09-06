#!/bin/sh
# Adds the archrepo pacman repository. Safe to run more than once.
set -e
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
curl -s https://pkg.scirex.me/archrepo.pub.asc | pacman-key --add -
pacman-key --lsign-key 8A17827692EECC3C5270DA9D1CE75EC9217912BA
grep -q '^\[archrepo\]' /etc/pacman.conf || printf '\n[archrepo]\nServer = https://pkg.scirex.me\n' >> /etc/pacman.conf
pacman -Sy
echo "archrepo ready. Try: sudo pacman -S openbangla-keyboard"
