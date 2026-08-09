#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 Debug|Release /path/to/xcodebuild.log" >&2
    exit 64
fi

configuration=$1
build_log=$2
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
baseline_file="$repository_root/Config/WarningBaseline.txt"

maximum=$(awk -v configuration="$configuration" '$1 == configuration { print $2 }' "$baseline_file")
if [ -z "$maximum" ]; then
    echo "No warning baseline is recorded for $configuration" >&2
    exit 65
fi

actual=$(awk '
    /\/(Apps\/macOS|Shared)\/.*: warning:/ { count++ }
    END { print count + 0 }
' "$build_log")

echo "$configuration repository warning baseline: $actual observed, $maximum allowed"
if [ "$actual" -gt "$maximum" ]; then
    echo "The $configuration build introduced $((actual - maximum)) warning(s)." >&2
    awk '/\/(Apps\/macOS|Shared)\/.*: warning:/' "$build_log" >&2
    exit 1
fi
