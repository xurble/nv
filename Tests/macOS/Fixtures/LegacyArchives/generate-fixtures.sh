#!/bin/sh
# Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
# This file is part of Spiral, a fork of Notational Velocity.
#
# Spiral is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Spiral is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Spiral. If not, see <http://www.gnu.org/licenses/>.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../../.." && pwd)
source_directory="$repository_root/Apps/macOS/Sources"
generator=$(mktemp "${TMPDIR:-/tmp}/SpiralLegacyFixtureGenerator.XXXXXX")

cleanup() {
    if [ -f "$generator" ]; then rm -f "$generator"; fi
}
trap cleanup EXIT HUP INT TERM

xcrun clang \
    -fno-objc-arc \
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
    "$script_directory/GenerateLegacyArchiveFixtures.m" \
    -o "$generator"

for fixture in \
    notational-velocity-plaintext \
    nvalt-rich \
    encrypted-default-kdf \
    encrypted-alternate-kdf \
    wal-intact \
    wal-interrupted \
    damaged-archive
do
    fixture_path="$script_directory/$fixture"
    if [ -L "$fixture_path" ]; then
        echo "Refusing to replace fixture symlink: $fixture_path" >&2
        exit 1
    fi
    if [ -d "$fixture_path" ]; then
        find "$fixture_path" -type f -delete
        rmdir "$fixture_path"
    fi
done

"$generator" "$script_directory"
