#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)

framework_path="$repository_root/Apps/macOS/Dependencies/Frameworks/Sparkle.framework"
signature_path="$repository_root/Apps/macOS/Resources/dsa_pub.pem"
project_path="$repository_root/Notation.xcodeproj/project.pbxproj"
info_path="$repository_root/Apps/macOS/SupportingFiles/Info.plist"
controller_path="$repository_root/Apps/macOS/Sources/AppController.m"

if [ -e "$framework_path" ]; then
    echo "FAIL: the bundled Sparkle framework still exists" >&2
    exit 1
fi

if [ -e "$signature_path" ]; then
    echo "FAIL: the obsolete Sparkle DSA key still exists" >&2
    exit 1
fi

if rg -q 'Sparkle\.framework|dsa_pub\.pem' "$project_path"; then
    echo "FAIL: the Xcode project still packages Sparkle assets" >&2
    exit 1
fi

if rg -q 'SU(CheckAtStartup|FeedURL|PublicDSAKeyFile|ScheduledCheckInterval)' "$info_path"; then
    echo "FAIL: Info.plist still contains Sparkle update metadata" >&2
    exit 1
fi

if rg -q 'SUUpdater|checkForUpdates:|Sparkle\.framework' "$controller_path"; then
    echo "FAIL: AppController still loads or invokes Sparkle" >&2
    exit 1
fi

echo "Sparkle removal checks passed."
