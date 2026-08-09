#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
source_directory="$repository_root/Apps/macOS/Sources"
test_binary=/tmp/SpiralLegacyCryptoCompatibilityTests

if grep -Eiq 'libcrypto|/(opt/homebrew|usr/local)/opt/openssl' "$repository_root/Notation.xcodeproj/project.pbxproj"; then
    echo "FAIL: the Xcode project still contains a host-specific OpenSSL dependency" >&2
    exit 1
fi

xcrun clang \
    -arch arm64 \
    -arch x86_64 \
    -fno-objc-arc \
    -Wno-deprecated-declarations \
    -Wno-sizeof-pointer-memaccess \
    -I "$source_directory" \
    -include "$repository_root/Apps/macOS/SupportingFiles/Notation_Prefix.pch" \
    -framework AppKit \
    -framework Carbon \
    -framework Foundation \
    -framework WebKit \
    -lz \
    "$source_directory/NSData_transformations.m" \
    "$source_directory/pbkdf2.c" \
    "$source_directory/hmacsha1.c" \
    "$source_directory/broken_md5.c" \
    "$script_directory/LegacyCryptoCompatibilityTests.m" \
    -o "$test_binary"

xcrun lipo "$test_binary" -verify_arch arm64 x86_64
if xcrun otool -L "$test_binary" | grep -qi libcrypto; then
    echo "FAIL: the compatibility test binary still links libcrypto" >&2
    exit 1
fi
"$test_binary"
