# Shared setup for PS5Plus scripts. Source it; do not execute it.
# shellcheck shell=sh

root="$(cd "$(dirname "$0")/.." && pwd)"
submodule="$root/KytyPS5"
work="${PS5PLUS_WORK:-/Volumes/4TB_Drive/tmp/ps5plus}"
export TMPDIR="$work/tmp/"
# launchd starts jobs with a minimal PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p "$TMPDIR" "$work/logs"

say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

notify() {
    say "$1: $2"
    osascript -e "display notification \"$(printf '%s' "$2" | tr '"' "'")\" with title \"PS5Plus\" subtitle \"$1\"" 2>/dev/null || true
}

# One PS5Plus script at a time: the nightly merge and a validation run both move the submodule.
lock() {
    if ! mkdir "$work/run.lock" 2>/dev/null; then
        say "Another PS5Plus run holds $work/run.lock ($(cat "$work/run.lock/owner" 2>/dev/null)). Remove it if that run is gone."
        exit 75
    fi
    echo "$$ $0" > "$work/run.lock/owner"
    trap 'rm -rf "$work/run.lock"' EXIT
    trap 'exit 130' INT TERM
}

# Refuse to touch work in progress: both repositories must be clean, on their branches, and not ahead of GitHub.
require_clean() {
    git -C "$root" fetch --quiet origin && git -C "$submodule" fetch --quiet origin || { echo "cannot fetch from GitHub"; return 1; }
    [ "$(git -C "$root" symbolic-ref --short HEAD)" = main ] || { echo "PS5Plus is not on main"; return 1; }
    [ "$(git -C "$submodule" symbolic-ref --short -q HEAD)" = ps5plus ] || { echo "KytyPS5 is not on the ps5plus branch"; return 1; }
    [ -z "$(git -C "$submodule" status --porcelain --untracked-files=no)" ] || { echo "KytyPS5 has uncommitted changes"; return 1; }
    [ -z "$(git -C "$root" status --porcelain --untracked-files=no --ignore-submodules=all)" ] || { echo "PS5Plus has uncommitted changes"; return 1; }
    git -C "$root" merge --quiet --ff-only origin/main || { echo "PS5Plus main has diverged from GitHub"; return 1; }
}
