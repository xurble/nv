#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 Debug|Release" >&2
    exit 64
fi

configuration=$1
case "$configuration" in
    Debug) package_configuration=debug ;;
    Release) package_configuration=release ;;
    *) echo "unsupported configuration: $configuration" >&2; exit 64 ;;
esac

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
architecture=$(uname -m)
derived_data=$(mktemp -d "${TMPDIR:-/tmp}/SpiralPhase3-${configuration}.XXXXXX")

cleanup() {
    case "${derived_data:?}" in
        "${TMPDIR:-/tmp}"/SpiralPhase3-*) ;;
        *) echo "Refusing to clean unexpected path: $derived_data" >&2; return ;;
    esac
    if [ -L "$derived_data" ]; then
        echo "Refusing to clean a symbolic link: $derived_data" >&2
        return
    fi
    rm -rf -- "${derived_data:?}"
}
trap cleanup EXIT HUP INT TERM

cd "$repository_root"

"$script_directory/run-phase2.sh" "$configuration"

xcrun swift test \
    --package-path Shared/SpiralFeature \
    --configuration "$package_configuration"

xcodebuild build \
    -project Notation.xcodeproj \
    -scheme SpiralMobile \
    -configuration "$configuration" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$derived_data/mobile-device" \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing \
    -project Notation.xcodeproj \
    -scheme SpiralMobile \
    -configuration "$configuration" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data/mobile-tests" \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing \
    -project Notation.xcodeproj \
    -scheme SpiralMacTestHarness \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=$architecture" \
    -derivedDataPath "$derived_data/mac-tests" \
    CODE_SIGNING_ALLOWED=NO
