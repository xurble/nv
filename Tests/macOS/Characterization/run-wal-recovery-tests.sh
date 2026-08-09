#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
source_directory="$repository_root/Apps/macOS/Sources"
test_binary="${TMPDIR:-/tmp}/SpiralWALRecoveryTests"

xcrun clang \
    -fno-objc-arc \
    -Wall \
    -Wextra \
    -Werror \
    -Wno-deprecated-declarations \
    -Wno-implicit-fallthrough \
    -Wno-incompatible-pointer-types-discards-qualifiers \
    -Wno-sizeof-pointer-memaccess \
    -I "$source_directory" \
    -include "$repository_root/Apps/macOS/SupportingFiles/Notation_Prefix.pch" \
    -framework AppKit \
    -framework Carbon \
    -framework Foundation \
    -framework WebKit \
    -lz \
    "$source_directory/WALController.m" \
    "$source_directory/DeletedNoteObject.m" \
    "$source_directory/NSData_transformations.m" \
    "$source_directory/pbkdf2.c" \
    "$source_directory/hmacsha1.c" \
    "$source_directory/broken_md5.c" \
    "$script_directory/WALRecoveryTests.m" \
    -o "$test_binary"

"$test_binary"
