#!/bin/sh
# Nightly: merge upstream KytyPS5 into the submodule's ps5plus branch, build and test it on this Mac,
# then publish. Pushing PS5Plus main makes CI release a Linux build that Fenrir stages for g913.
#
# Skips (exit 75) rather than disturbing work in progress. A conflict or failed build leaves
# everything unpublished; a failed build keeps the merge on a nightly/failed-* branch.
set -eu
. "$(dirname "$0")/common.sh"
exec >> "$work/logs/nightly-$(date +%Y%m%d).log" 2>&1
say "Nightly upstream sync"
lock

if ! reason="$(require_clean 2>&1)"; then
    notify "Nightly merge skipped" "$reason"
    exit 75
fi
git -C "$submodule" fetch --quiet --prune upstream
git -C "$submodule" merge --quiet --ff-only origin/ps5plus || { notify "Nightly merge skipped" "ps5plus has diverged from GitHub"; exit 75; }
if [ -n "$(git -C "$submodule" rev-list origin/ps5plus..ps5plus)" ]; then
    notify "Nightly merge skipped" "ps5plus has unpushed commits; publish them with validate-g913.sh first"
    exit 75
fi

# The fork's main mirrors upstream so that main...ps5plus shows exactly the PS5Plus changes.
git -C "$submodule" push --quiet origin refs/remotes/upstream/main:refs/heads/main ||
    say "WARNING: could not fast-forward the fork's main to upstream"

upstream="$(git -C "$submodule" rev-parse --short upstream/main)"
if git -C "$submodule" merge-base --is-ancestor upstream/main ps5plus; then
    say "ps5plus already contains upstream $upstream"
    exit 0
fi

before="$(git -C "$submodule" rev-parse HEAD)"
if ! git -C "$submodule" merge --no-edit -m "Merge upstream KytyPS5 $upstream into ps5plus" upstream/main; then
    conflicts="$(git -C "$submodule" diff --name-only --diff-filter=U | head -5 | tr '\n' ' ')"
    git -C "$submodule" merge --abort
    notify "Nightly merge conflict" "upstream $upstream conflicts in: $conflicts"
    exit 1
fi
git -C "$submodule" submodule update --init --recursive --jobs 8

if [ "${PS5PLUS_SKIP_BUILD:-0}" != 1 ] && ! "$root/scripts/build-macos.sh"; then
    failed="nightly/failed-$(date +%Y%m%d)-$upstream"
    git -C "$submodule" branch -f "$failed" HEAD
    git -C "$submodule" reset --quiet --hard "$before"
    git -C "$submodule" submodule update --init --recursive --jobs 8
    notify "Nightly build failed" "upstream $upstream kept on local branch $failed; ps5plus unchanged"
    exit 1
fi

git -C "$submodule" push --quiet origin ps5plus
git -C "$root" add KytyPS5
git -C "$root" commit --quiet -m "chore: merge upstream KytyPS5 $upstream"
git -C "$root" push --quiet origin main
notify "Nightly merge published" "upstream $upstream merged; CI is building the Linux release"
