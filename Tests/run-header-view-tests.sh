#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname -- "$script_directory")
test_binary=/tmp/SpiralHeaderViewTests

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -I "$project_directory" \
    -framework AppKit \
    -framework Foundation \
    "$project_directory/HeaderViewWIthMenu.m" \
    "$project_directory/Tests/HeaderViewWithMenuTests.m" \
    -o "$test_binary"

"$test_binary"
