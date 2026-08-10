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
iphone_destination="${SPIRAL_UI_IPHONE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
ipad_destination="${SPIRAL_UI_IPAD_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest}"

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

xcodebuild test \
    -project Notation.xcodeproj \
    -scheme SpiralMacTestHarness \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=$architecture" \
    -derivedDataPath "$derived_data/mac-tests" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS= \
    PROVISIONING_PROFILE_SPECIFIER=

xcodebuild test \
    -project Notation.xcodeproj \
    -scheme SpiralMobile \
    -configuration "$configuration" \
    -destination "$iphone_destination" \
    -derivedDataPath "$derived_data/iphone-tests" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO

xcodebuild test \
    -project Notation.xcodeproj \
    -scheme SpiralMobile \
    -configuration "$configuration" \
    -destination "$ipad_destination" \
    -derivedDataPath "$derived_data/ipad-tests" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO
