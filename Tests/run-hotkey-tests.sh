#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname -- "$script_directory")
test_binary=/tmp/SpiralHotKeyTests

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -Wno-deprecated-declarations \
    -I "$project_directory/PTHotKeys" \
    -framework AppKit \
    -framework Carbon \
    -framework Foundation \
    "$project_directory/PTHotKeys/PTKeyCombo.m" \
    "$project_directory/PTHotKeys/PTKeyBroadcaster.m" \
    "$project_directory/Tests/PTKeyComboTests.m" \
    -o "$test_binary"

"$test_binary"
