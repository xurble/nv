#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname -- "$script_directory")
test_binary=/tmp/SpiralURLDetectionTests

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -I "$project_directory" \
    -framework AppKit \
    -framework Foundation \
    "$project_directory/URLDetection.m" \
    "$project_directory/Tests/URLDetectionTests.m" \
    -o "$test_binary"

"$test_binary"
