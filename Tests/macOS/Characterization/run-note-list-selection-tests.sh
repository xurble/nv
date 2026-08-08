#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
source_directory="$repository_root/Apps/macOS/Sources"
test_binary=/tmp/SpiralNoteListSelectionTests

xcrun clang \
	-fno-objc-arc \
	-Wall \
	-Wextra \
	-Werror \
	-I "$source_directory" \
	-framework Foundation \
	"$script_directory/NoteListSelectionTests.m" \
	-o "$test_binary"

"$test_binary"
