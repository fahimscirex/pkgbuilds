#!/usr/bin/bash
# Builds every packages/*/PKGBUILD whose pkgname-version is not already in the repo
# in a clean devtools chroot, signs, repo-adds into repo/, then syncs to R2.
# Runs as the unprivileged "builder" user (passwordless sudo, needed by the chroot).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=sc1r3x
BUCKET=pkgbuilds
OUT=$PWD/repo
CHROOT=/var/lib/archbuild
mkdir -p "$OUT"

sync() {
  if [[ -f ~/.config/rclone/rclone.conf ]]; then rclone sync -L "$@"; else echo "==> no rclone config, skipping sync $*"; fi
}

sync "r2:$BUCKET" "$OUT"
if [[ ! -f $OUT/$REPO.db.tar.zst && -f $OUT/archrepo.db.tar.zst ]]; then
  cp -f "$OUT/archrepo.db.tar.zst" "$OUT/$REPO.db.tar.zst"
  [[ -f $OUT/archrepo.db.tar.zst.sig ]] && cp -f "$OUT/archrepo.db.tar.zst.sig" "$OUT/$REPO.db.tar.zst.sig"
fi
[[ -f $OUT/$REPO.db.tar.zst ]] || repo-add --sign "$OUT/$REPO.db.tar.zst"
ln -sf "$REPO.db.tar.zst" "$OUT/$REPO.db"
[[ -f $OUT/$REPO.db.tar.zst.sig ]] && ln -sf "$REPO.db.tar.zst.sig" "$OUT/$REPO.db.sig"
[[ -f $OUT/$REPO.files.tar.zst ]] && ln -sf "$REPO.files.tar.zst" "$OUT/$REPO.files"
[[ -f $OUT/$REPO.files.tar.zst.sig ]] && ln -sf "$REPO.files.tar.zst.sig" "$OUT/$REPO.files.sig"
sudo mkdir -p "$CHROOT" && sudo mkarchroot -C /etc/pacman.conf -M /etc/makepkg.conf "$CHROOT/root" base-devel

target="${1:-}"
target="${target#packages/}"
target="${target%/}"
if [[ -n "$target" ]]; then
  [[ -d "packages/$target" ]] || { echo "==> error: package '$target' not found in packages/"; exit 1; }
  targets=("packages/$target/")
else
  targets=(packages/*/)
fi

declare -A SRCINFO
for d in packages/*/; do SRCINFO[$d]=$(cd "$d" && makepkg --printsrcinfo); done
failed=()

for dir in "${targets[@]}"; do   # ponytail: alphabetical; order deps by naming or a list if one local package needs another
  srcinfo=${SRCINFO[$dir]}
  ver=$(awk '/^\tpkgver = /{v=$3} /^\tpkgrel = /{r=$3} /^\tepoch = /{e=$3":"} END{print e v "-" r}' <<<"$srcinfo")
  names=$(awk '/^pkgname = /{print $3}' <<<"$srcinfo")
  need=0
  head_sha=""

  if [[ "$dir" == *-git/ ]]; then
    # ponytail: check upstream commit so unchanged git packages don't rebuild every run
    gitsrc=$(awk '/^\tsource = (.*::)?git\+/{sub(/^\tsource = (.*::)?git\+/, ""); print; exit}' <<<"$srcinfo")
    if [[ -n "$gitsrc" ]]; then
      url="${gitsrc%%#*}"
      frag="${gitsrc#$url}"; frag="${frag###}"
      ref="HEAD"
      [[ "$frag" =~ ^branch=(.*) ]] && ref="${BASH_REMATCH[1]}"
      [[ "$frag" =~ ^tag=(.*) ]] && ref="refs/tags/${BASH_REMATCH[1]}"
      [[ "$frag" =~ ^commit=(.*) ]] && ref="${BASH_REMATCH[1]}"
      head_sha=$(git ls-remote "$url" "$ref" 2>/dev/null | awk '{print $1; exit}')
    fi

    if [[ -n "$head_sha" ]]; then
      short="${head_sha:0:7}"
      for name in $names; do
        ls "$OUT/$name-"*"$short"*.pkg.tar.zst >/dev/null 2>&1 || need=1
      done
    else
      need=1
    fi
  else
    for name in $names; do ls "$OUT/$name-$ver-"*.pkg.tar.zst >/dev/null 2>&1 || need=1; done
  fi

  [[ -n "$target" ]] && need=1
  ((need)) || { echo "==> $dir ${head_sha:-$ver} up to date"; continue; }

  echo "==> building $dir ($ver)"   # -git packages report a static pkgver here and so rebuild every run
  tmp=$(mktemp -d)
  # one broken package must not block the others or the publish; failures are reported and exit 1 at the end
  # (whole chain under `if !` because errexit is off for a tested command)
  # nightly.link artifacts are unsigned CI zips, so pin whatever the runner downloads instead of a hand-committed hash
  if ! (cd "$dir" && { [[ $dir != packages/nfgram-desktop-bin/ ]] || updpkgsums; } && PKGDEST=$tmp makechrootpkg -c -r "$CHROOT"); then
    echo "==> BUILD FAILED: $dir"; failed+=("$dir"); rm -rf "$tmp"; continue
  fi
  built=()
  for p in "$tmp"/*.pkg.tar.zst; do
    mv -f "$p" "$OUT/"; p=$OUT/${p##*/}
    gpg --yes --detach-sign --no-armor "$p"
    built+=("$p")
  done
  repo-add --sign --remove "$OUT/$REPO.db.tar.zst" "${built[@]}"   # after each build so later packages can depend on it
done

# drop anything the PKGBUILDs no longer produce (removed packages, -debug packages)
keep=$(for d in packages/*/; do awk '/^pkgname = /{print $3}' <<<"${SRCINFO[$d]}"; done)
for f in "$OUT"/*.pkg.tar.zst; do
  [[ -e $f ]] || break
  n=${f##*/}; name=${n%-*-*-*}
  grep -qx "$name" <<<"$keep" || { repo-remove --sign "$OUT/$REPO.db.tar.zst" "$name"; rm -f "$f" "$f.sig"; }
done

# maintain backward compatibility for existing installations using [archrepo]
for ext in db db.sig db.tar.zst db.tar.zst.sig files files.sig files.tar.zst files.tar.zst.sig; do
  [[ -f "$OUT/$REPO.$ext" ]] && ln -sf "$REPO.$ext" "$OUT/archrepo.$ext"
done
cp sc1r3x.pub.asc scripts/setup.sh "$OUT/"
ln -sf sc1r3x.pub.asc "$OUT/archrepo.pub.asc"
rm -f "$OUT"/*.old "$OUT"/*.old.sig
sync --exclude "*.old*" "$OUT" "r2:$BUCKET"
# delete any existing .old files from R2
if [[ -f ~/.config/rclone/rclone.conf ]]; then
  rclone delete "r2:$BUCKET" --include "*.old*" || true
fi
((${#failed[@]})) && { echo "==> FAILED: ${failed[*]}"; exit 1; }
exit 0
