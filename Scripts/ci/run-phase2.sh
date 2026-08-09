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

cd "$repository_root"
xcrun swift test \
    --package-path Shared/SpiralCore \
    --configuration "$package_configuration"

"$script_directory/run-phase1.sh" "$configuration"
