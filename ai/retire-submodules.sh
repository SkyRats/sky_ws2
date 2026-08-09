#!/usr/bin/env bash
#
# retire-submodules.sh — remove the 3 git submodules from sky_ws2's index and
# hand their pinning over to sky_ws2.repos (vcstool). See ai/decisions.md #1.
#
# STATUS: NOT RUN. Blocked on src/outdoor_2025's 5 uncommitted files — once
# /src/* is ignored they vanish from main's `git status`, so commit and push
# them in outdoor_2025 first.
#
# Review this before running it. It does NOT touch any nested repo's branches:
# no checkout, switch, branch, reset, or submodule update.

set -euo pipefail
cd ~/sky_ws2

# 0. Refuse to run with anything already staged.
test -z "$(git diff --cached --name-only)" || { echo "index not clean"; exit 1; }

# 1. De-absorb. Each submodule's .git is currently a POINTER FILE into
#    ~/sky_ws2/.git/modules/src/<name>. Without this step `git rm --cached`
#    leaves the repos working but dependent on main's .git/modules, and a
#    re-clone of main orphans them.
for m in indoor_2026 sky_navigation sky_vision2; do
  src=".git/modules/src/$m"
  dst="src/$m/.git"
  test -d "$src" || { echo "missing $src"; exit 1; }
  test -f "$dst" || { echo "$dst is not a pointer file — already standalone?"; exit 1; }
  rm "$dst"
  mv "$src" "$dst"
  git -C "src/$m" config --unset core.worktree
  echo "de-absorbed src/$m"
done
rmdir .git/modules/src .git/modules 2>/dev/null || true

# 2. Drop the gitlinks. Worktrees are untouched.
git rm --cached src/indoor_2026 src/sky_navigation src/sky_vision2
git rm -f .gitmodules

# 3. Show what is staged — only the three deletions and .gitmodules may appear.
git status --porcelain

cat <<'EOF'

Review the above, then commit manually:
  git commit -m "chore: retire submodules; pin nested repos via sky_ws2.repos"

Then verify no gitlink remains (must print nothing):
  git ls-files -s | awk '$1=="160000"'
  test -f .gitmodules && echo "FAIL: .gitmodules still present" || echo "OK"

And that each repo kept its history and remote:
  for r in indoor_2026 sky_navigation sky_vision2; do
    git -C "src/$r" log --oneline -1; git -C "src/$r" remote -v | head -1
  done
EOF
