#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/Spiral.app" >&2
    exit 64
fi

app_path=$1
executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")
executable="$app_path/Contents/MacOS/$executable_name"
if [ ! -x "$executable" ]; then
    echo "Spiral executable not found at $executable" >&2
    exit 66
fi

probe_directory=$(mktemp -d "${TMPDIR:-/tmp}/SpiralLaunchTest.XXXXXX")
marker="$probe_directory/.spiral-launch-ok"
profile="$probe_directory/default.profraw"
cleanup() {
    if [ -f "$marker" ]; then rm -f "$marker"; fi
    if [ -f "$profile" ]; then rm -f "$profile"; fi
    rmdir "$probe_directory"
}
trap cleanup EXIT HUP INT TERM

LLVM_PROFILE_FILE="$profile" SPIRAL_DISPOSABLE_LAUNCH_DIRECTORY="$probe_directory" "$executable"

if [ ! -f "$marker" ]; then
    echo "Spiral did not complete the disposable-directory launch probe" >&2
    exit 1
fi
