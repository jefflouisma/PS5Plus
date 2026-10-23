#!/bin/sh
# Build and test the KytyPS5 submodule on this Mac.
# KytyPS5 runs x86-64 guest code natively, so macOS builds target x86_64 and run under Rosetta 2.
# The Qt launcher is skipped: Fenrir launches kyty_emulator directly.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
work="${PS5PLUS_WORK:-/Volumes/4TB_Drive/tmp/ps5plus}"
build="$work/build/macos"
source="$root/KytyPS5"
workflow="$source/.github/workflows/build.yml"
export TMPDIR="$work/tmp/"
export CCACHE_DIR="$work/ccache"
mkdir -p "$TMPDIR" "$CCACHE_DIR"

targets="kyty_emulator $(python3 "$root/scripts/upstream-ci.py" "$workflow" macos targets | tr ' ' '\n' | grep -vx launcher | tr '\n' ' ')"
tests="$(python3 "$root/scripts/upstream-ci.py" "$workflow" macos tests)"

cmake -S "$source" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DKYTY_BUILD_LAUNCHER=OFF \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
# shellcheck disable=SC2086 # targets is a word list
cmake --build "$build" --target $targets --parallel
ctest --test-dir "$build" --output-on-failure -R "$tests"
