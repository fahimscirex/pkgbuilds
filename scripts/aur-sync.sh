#!/usr/bin/bash
# Checks packages/*/ against upstream AUR repositories.
# Opens a GitHub PR when an update is found.
set -euo pipefail
cd "$(dirname "$0")/.."
trap 'git checkout -q main 2>/dev/null || true' EXIT

target="${1:-}"
if [[ -n "$target" ]]; then
  target="${target#packages/}"
  target="${target%/}"
  targets=("packages/$target/")
else
  targets=(packages/*/)
fi

for dir in "${targets[@]}"; do
  pkg="${dir%/}"
  pkg="${pkg##*/}"
  [[ -f "$dir/.aurcommit" ]] || continue   # not an AUR-tracked package
  aur_url="https://aur.archlinux.org/${pkg}.git"

  remote_commit=$(git ls-remote "$aur_url" HEAD 2>/dev/null | awk '{print $1; exit}')
  [[ -n "$remote_commit" ]] || { echo "==> could not fetch AUR ref for $pkg, skipping"; continue; }

  current_commit=$(head -n 1 "$dir/.aurcommit")

  if [[ "$current_commit" == "$remote_commit" ]]; then
    echo "==> $pkg is up to date with AUR (${remote_commit:0:7})"
    continue
  fi

  echo "==> AUR update found for $pkg: ${current_commit:0:7} -> ${remote_commit:0:7}"
  branch="aur-update/$pkg"

  git checkout -B "$branch"

  tmp=$(mktemp -d)
  git clone --depth 1 "$aur_url" "$tmp"
  rm -rf "$tmp/.git" "$tmp/.gitignore"

  cp -a "$tmp"/. "$dir/"
  echo "$remote_commit" > "$dir/.aurcommit"
  rm -rf "$tmp"

  diff_files=$(git status --porcelain -- "$dir")   # status, not diff: a file upstream added is still untracked
  if [[ -z "$diff_files" ]]; then
    echo "==> no actual file differences for $pkg"
    git checkout main
    continue
  fi

  git add "$dir"
  git commit -m "chore($pkg): update from AUR (${remote_commit:0:7})"
  git push -f origin "$branch"

  existing_pr=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || true)
  if [[ -z "$existing_pr" ]]; then
    gh pr create \
      --head "$branch" \
      --base main \
      --title "AUR update: $pkg" \
      --body "$(cat <<EOF
Automated update for \`$pkg\` from [AUR]($aur_url).

**Upstream AUR commit**: \`$remote_commit\`

Please review the diff to ensure any local patches or configurations are preserved before merging.
EOF
)"
  else
    echo "==> PR #$existing_pr already exists for $branch"
  fi

  git checkout main
done

# Check upstream GitHub Actions builds for custom nightly packages (NFGram)
if [[ -z "$target" || "$target" == "nfgram-desktop-bin" ]]; then
  nf_dir="packages/nfgram-desktop-bin"
  if [[ -d "$nf_dir" ]]; then
    echo "==> checking upstream runs for frknkrc44/NFGram..."
    latest_run=$(gh api "repos/frknkrc44/NFGram/actions/workflows/linux.yml/runs?status=success&per_page=1" \
      --jq '.workflow_runs[0] | {id: .id, commit: .head_sha, title: .display_title}' 2>/dev/null || true)

    if [[ -n "$latest_run" ]]; then
      run_id=$(jq -r .id <<<"$latest_run")
      head_commit=$(jq -r .commit <<<"$latest_run")
      title=$(jq -r .title <<<"$latest_run")
      current_run=$(awk -F'=' '/^_run_id=/{print $2}' "$nf_dir/PKGBUILD")

      if [[ "$current_run" != "$run_id" && -n "$run_id" ]]; then
        echo "==> new NFGram run found: $current_run -> $run_id ($head_commit)"
        branch="upstream-update/nfgram-desktop-bin"
        git checkout -B "$branch"

        app_ver=$(gh api "repos/frknkrc44/NFGram/contents/Telegram/build/version?ref=${head_commit}" \
          --jq '.content' | base64 -d | awk '/^AppVersionStr /{print $2; exit}')
        [[ -n "$app_ver" ]] || { echo "==> could not read AppVersionStr for $head_commit"; exit 1; }

        sed -i "s|^pkgver=.*|pkgver=${app_ver}.r${run_id}|" "$nf_dir/PKGBUILD"
        sed -i "s|^_run_id=.*|_run_id=${run_id}|" "$nf_dir/PKGBUILD"
        sed -i "s|^_commit=.*|_commit=${head_commit}|" "$nf_dir/PKGBUILD"
        # sha256sums are refreshed by build.sh (updpkgsums) on the runner

        # makepkg refuses to run as root (CI container), pacman 7 has no --asroot,
        # and it needs a writable builddir, so build the srcinfo from a temp copy
        si_tmp=$(mktemp -d)
        cp "$nf_dir/PKGBUILD" "$si_tmp/"
        chown -R nobody "$si_tmp"
        (cd "$si_tmp" && runuser -u nobody -- makepkg --printsrcinfo) > "$nf_dir/.SRCINFO"
        rm -rf "$si_tmp"

        git add "$nf_dir"
        git commit -m "chore(nfgram-desktop-bin): update to run $run_id (${head_commit:0:7})"
        git push -f origin "$branch"

        existing_pr=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || true)
        if [[ -z "$existing_pr" ]]; then
          gh pr create \
            --head "$branch" \
            --base main \
            --title "Upstream update: nfgram-desktop-bin (${head_commit:0:7})" \
            --body "Automated update for \`nfgram-desktop-bin\` from [frknkrc44/NFGram](https://github.com/frknkrc44/NFGram) run \`$run_id\`."
        fi
        git checkout main
      else
        echo "==> nfgram-desktop-bin is up to date (run $current_run)"
      fi
    fi
  fi
fi

