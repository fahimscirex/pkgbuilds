#!/usr/bin/bash
# Checks packages/*/ against upstream AUR repositories.
# Opens a GitHub PR when an update is found.
set -euo pipefail
cd "$(dirname "$0")"

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
  aur_url="https://aur.archlinux.org/${pkg}.git"

  remote_commit=$(git ls-remote "$aur_url" HEAD 2>/dev/null | awk '{print $1; exit}')
  [[ -n "$remote_commit" ]] || { echo "==> could not fetch AUR ref for $pkg, skipping"; continue; }

  current_commit=""
  [[ -f "$dir/.aurcommit" ]] && current_commit=$(head -n 1 "$dir/.aurcommit")

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

  cp -r "$tmp"/* "$dir/"
  echo "$remote_commit" > "$dir/.aurcommit"
  rm -rf "$tmp"

  diff_files=$(git diff --name-only)
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
