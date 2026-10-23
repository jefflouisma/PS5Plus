#!/bin/sh
# Run the submodule's ps5plus branch on g913.
# Publishes ps5plus, waits for CI to release its Linux build, then has Fenrir stage and activate
# that exact release. Activation waits until no Moonlight session is running.
set -eu
. "$(dirname "$0")/common.sh"
repository=jefflouisma/PS5Plus
fenrir="${FENRIR_URL:-http://192.168.1.221:47989}"
lock

status() {
    json="$(curl -fsS --max-time 10 "$fenrir/api/updates")" || return 1
    printf '%s' "$json" | jq -r ".components.ps5plus.$1 | values | tostring"
}
post() { curl -sS --fail-with-body --max-time 10 -X POST -H 'Content-Type: application/json' -d '{}' "$fenrir/api/updates/ps5plus/$1" > /dev/null; }
# Poll until a ps5plus field has a value; brief API failures keep waiting until the deadline.
wait_until() {
    deadline=$(( $(date +%s) + $3 ))
    until [ "$(status "$1" 2>/dev/null)" = "$2" ]; do
        [ "$(date +%s)" -lt "$deadline" ] || return 1
        sleep 10
    done
}

curl -fsS --max-time 10 "$fenrir/api/updates" > /dev/null || { say "Fenrir Updates is unreachable at $fenrir. Is g913 up?"; exit 1; }
reason="$(require_clean 2>&1)" || { say "$reason"; exit 1; }

git -C "$submodule" push --quiet origin ps5plus
kyty="$(git -C "$submodule" rev-parse --short HEAD)"
if [ "$(git -C "$root" rev-parse HEAD:KytyPS5)" != "$(git -C "$submodule" rev-parse HEAD)" ]; then
    git -C "$root" add KytyPS5
    git -C "$root" commit --quiet -m "feat: build KytyPS5 $kyty ($(git -C "$submodule" log -1 --format=%s))"
    git -C "$root" push --quiet origin main
fi
commit="$(git -C "$root" rev-parse HEAD)"

release() { gh api "repos/$repository/releases?per_page=30" --jq ".[] | select(.target_commitish == \"$commit\") | .tag_name" | head -n 1; }
tag="$(release)"
if [ -z "$tag" ]; then
    say "Waiting for CI to build PS5Plus $(git -C "$root" rev-parse --short HEAD) (KytyPS5 $kyty)"
    run=""
    for _ in $(seq 30); do
        run="$(gh run list --repo "$repository" --workflow release.yml --commit "$commit" --event push --json databaseId --jq '.[0].databaseId // empty')"
        [ -n "$run" ] && break
        sleep 10
    done
    [ -n "$run" ] || { say "No CI run started for $commit"; exit 1; }
    gh run watch "$run" --repo "$repository" --exit-status --interval 60 > /dev/null || {
        say "CI failed: https://github.com/$repository/actions/runs/$run"; exit 1; }
    tag="$(release)"
    [ -n "$tag" ] || { say "CI finished without a release for $commit"; exit 1; }
fi
say "Release $tag"

if [ "$(status active)" != "$tag" ]; then
    if [ "$(status 'staged.version')" != "$tag" ]; then
        post check || say "A check is already running; waiting for it"
        wait_until busy false 1200 || { say "Fenrir is still checking after 20 minutes"; exit 1; }
        staged="$(status 'staged.version')"
        [ "$staged" = "$tag" ] || { say "Fenrir staged '${staged:-nothing}' instead of $tag. $(status error)"; exit 1; }
    fi
    post apply
    say "Activation queued. It waits for running sessions to close; quit Moonlight if a session is open."
    wait_until active "$tag" "${PS5PLUS_ACTIVATION_TIMEOUT:-1800}" ||
        { say "$tag is still queued. Fenrir activates it once sessions close. $(status error)"; exit 1; }
fi
say "PS5Plus $tag is active on g913."
say "In Moonlight, open EmuDeck and launch a game from 'Sony PlayStation 5 (PS5Plus)'."
say "Emulator logs in the session pod: /Volumes/4TB_Drive/tmp/ps5plus/logs"
