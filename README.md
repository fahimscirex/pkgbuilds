# pkgbuilds

Personal Arch repo at https://pkg.scirex.me, built in a clean chroot by GitHub
Actions from `packages/*/PKGBUILD`.

## Setup

```sh
curl -s https://pkg.scirex.me/setup.sh | sudo sh
```

Then install with pacman as usual, e.g. `sudo pacman -S openbangla-keyboard`.

## Packages

`ashell-git`, `bluetuith-git`, `openbangla-keyboard`, `openbangla-keyboard-git`, `ibus-openbangla-git`, `fcitx5-openbangla-git`, `rtw88-dkms-git`

## Adding a package

Put a `PKGBUILD` in `packages/<name>/` along with `.SRCINFO`. Builds run daily (cron) or via manual workflow dispatch:

```sh
gh workflow run build                     # build all needed packages
gh workflow run build -f package=<name>   # build a single package
```

Packages already in the repo at the same version or upstream git commit are skipped. Removing a directory removes its packages from the repo on the next run.

## Updates

- **AUR updates**: Daily workflow (`aur-updates`) checks the AUR for package updates and opens Pull Requests with the diffs.
- **`-git` packages**: Upstream git commits are checked on every build run; packages rebuild automatically when new commits are detected.

Secrets: `GPG_PRIVATE_KEY`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`.
