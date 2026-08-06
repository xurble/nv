#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
hotkey_directory="$repository_root/Apps/macOS/Dependencies/PTHotKeys"
test_binary=/tmp/SpiralHotKeyTests

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -Wno-deprecated-declarations \
    -I "$hotkey_directory" \
    -framework AppKit \
    -framework Carbon \
    -framework Foundation \
    "$hotkey_directory/PTKeyCombo.m" \
    "$hotkey_directory/PTKeyBroadcaster.m" \
    "$script_directory/PTKeyComboTests.m" \
    -o "$test_binary"

"$test_binary"
