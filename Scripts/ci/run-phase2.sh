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
derived_data=$(mktemp -d "${TMPDIR:-/tmp}/SpiralPhase2-${configuration}.XXXXXX")
build_log="$derived_data/xcodebuild.log"

cleanup() {
    case "${derived_data:?}" in
        "${TMPDIR:-/tmp}"/SpiralPhase2-*) ;;
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
xcrun swift test \
    --package-path Shared/SpiralCore \
    --configuration "$package_configuration"

if ! xcodebuild build \
    -project Notation.xcodeproj \
    -scheme Notation \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=$architecture" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES >"$build_log" 2>&1; then
    tail -n 200 "$build_log" >&2
    exit 1
fi

"$repository_root/Tests/macOS/LegacyMigration/run-legacy-archive-migration-tests.sh" \
    "$derived_data/Build/Products/$configuration/Spiral.app"

"$script_directory/run-phase1.sh" "$configuration"
