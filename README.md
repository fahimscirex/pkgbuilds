# pkgbuilds

Personal Arch repo at https://pkg.scirex.me, built in a clean chroot by GitHub
Actions from `packages/*/PKGBUILD`.

## Setup

```sh
curl -s https://pkg.scirex.me/setup.sh | sudo sh
```

Then install with pacman as usual, e.g. `sudo pacman -S openbangla-keyboard`.

## Packages

`openbangla-keyboard`, `openbangla-keyboard-git`, `ibus-openbangla-git`, `fcitx5-openbangla-git`

## Adding a package

Put a `PKGBUILD` in `packages/<name>/` and push. Builds also run daily. Packages already in the repo at
the same version are skipped; `-git` packages always rebuild. Removing a
directory removes its packages from the repo on the next run.

Secrets: `GPG_PRIVATE_KEY`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`.
