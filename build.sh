#!/usr/bin/bash
# Builds every packages/*/PKGBUILD whose pkgname-version is not already in the repo
# in a clean devtools chroot, signs, repo-adds into repo/, then syncs to R2.
# Runs as the unprivileged "builder" user (passwordless sudo, needed by the chroot).
set -euo pipefail
cd "$(dirname "$0")"

REPO=archrepo
BUCKET=pkgbuilds
OUT=$PWD/repo
CHROOT=/var/lib/archbuild
mkdir -p "$OUT"

sync() {
  if [[ -f ~/.config/rclone/rclone.conf ]]; then rclone sync -L "$@"; else echo "==> no rclone config, skipping sync $*"; fi
}

sync "r2:$BUCKET" "$OUT"
[[ -f $OUT/$REPO.db.tar.zst ]] || repo-add --sign "$OUT/$REPO.db.tar.zst"
sudo mkdir -p "$CHROOT" && sudo mkarchroot -C /etc/pacman.conf -M /etc/makepkg.conf "$CHROOT/root" base-devel

for dir in packages/*/; do   # ponytail: alphabetical; order deps by naming or a list if one local package needs another
  srcinfo=$(cd "$dir" && makepkg --printsrcinfo)
  ver=$(awk '/^\tpkgver = /{v=$3} /^\tpkgrel = /{r=$3} /^\tepoch = /{e=$3":"} END{print e v "-" r}' <<<"$srcinfo")
  names=$(awk '/^pkgname = /{print $3}' <<<"$srcinfo")
  need=0
  for name in $names; do ls "$OUT/$name-$ver-"*.pkg.tar.zst >/dev/null 2>&1 || need=1; done
  ((need)) || { echo "==> $dir $ver up to date"; continue; }

  echo "==> building $dir ($ver)"   # -git packages report a static pkgver here and so rebuild every run
  tmp=$(mktemp -d)
  (cd "$dir" && PKGDEST=$tmp makechrootpkg -c -r "$CHROOT")
  built=()
  for p in "$tmp"/*.pkg.tar.zst; do
    mv -f "$p" "$OUT/"; p=$OUT/${p##*/}
    gpg --yes --detach-sign --no-armor "$p"
    built+=("$p")
  done
  repo-add --sign --remove "$OUT/$REPO.db.tar.zst" "${built[@]}"   # after each build so later packages can depend on it
done

# drop anything the PKGBUILDs no longer produce (removed packages, -debug packages)
keep=$(for d in packages/*/; do (cd "$d" && makepkg --printsrcinfo | awk '/^pkgname = /{print $3}'); done)
for f in "$OUT"/*.pkg.tar.zst; do
  [[ -e $f ]] || break
  n=${f##*/}; name=${n%-*-*-*}
  grep -qx "$name" <<<"$keep" || { repo-remove --sign "$OUT/$REPO.db.tar.zst" "$name"; rm -f "$f" "$f.sig"; }
done

cp archrepo.pub.asc "$OUT/"
sync "$OUT" "r2:$BUCKET"
