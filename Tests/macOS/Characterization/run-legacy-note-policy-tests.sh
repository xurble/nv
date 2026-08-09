#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
source_directory="$repository_root/Apps/macOS/Sources"
test_binary="${TMPDIR:-/tmp}/SpiralLegacyNotePolicyTests"

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -I "$source_directory" \
    -framework Foundation \
    "$source_directory/LegacyNotePolicies.m" \
    "$script_directory/LegacyNotePolicyTests.m" \
    -o "$test_binary"

"$test_binary"
