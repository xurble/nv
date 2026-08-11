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

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/Spiral.app" >&2
    exit 64
fi

app_path=$1
executable="$app_path/Contents/MacOS/Spiral"
if [ ! -x "$executable" ]; then
    echo "Spiral executable not found: $executable" >&2
    exit 66
fi

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
fixtures="$repository_root/Tests/macOS/Fixtures/LegacyArchives"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/SpiralLegacyArchiveTests.XXXXXX")

cleanup() {
    case "${test_root:?}" in
        "${TMPDIR:-/tmp}"/SpiralLegacyArchiveTests.*) ;;
        *) echo "Refusing to clean unexpected path: $test_root" >&2; return ;;
    esac
    if [ -L "$test_root" ]; then
        echo "Refusing to clean a symbolic link: $test_root" >&2
        return
    fi
    rm -rf -- "${test_root:?}"
}
trap cleanup EXIT HUP INT TERM

stage_fixture() {
    fixture_name=$1
    case_name=$2
    case_root="$test_root/$case_name"
    mkdir -p "$case_root"
    cp -R "$fixtures/$fixture_name" "$case_root/source"
}

run_success() {
    fixture_name=$1
    encrypted=$2
    case_root="$test_root/success-$fixture_name"
    stage_fixture "$fixture_name" "success-$fixture_name"
    if [ "$encrypted" = 1 ]; then
        env \
            SPIRAL_LEGACY_MIGRATION_PROBE_SOURCE="$case_root/source" \
            SPIRAL_LEGACY_MIGRATION_PROBE_DESTINATION="$case_root/destination" \
            SPIRAL_LEGACY_MIGRATION_PROBE_REPORT="$case_root/report.json" \
            SPIRAL_LEGACY_MIGRATION_PROBE_ENCRYPTED=1 \
            SPIRAL_LEGACY_MIGRATION_PROBE_PASSPHRASE=fixture-passphrase \
            "$executable"
    else
        env \
            SPIRAL_LEGACY_MIGRATION_PROBE_SOURCE="$case_root/source" \
            SPIRAL_LEGACY_MIGRATION_PROBE_DESTINATION="$case_root/destination" \
            SPIRAL_LEGACY_MIGRATION_PROBE_REPORT="$case_root/report.json" \
            "$executable"
    fi
    test -s "$case_root/report.json"
    diff -qr "$case_root/source" "$case_root/destination/Retained Legacy Backup"
}

run_expected_failure() {
    fixture_name=$1
    expected_error=$2
    encrypted=$3
    passphrase=$4
    failure_after=$5
    case_root="$test_root/failure-$expected_error-$fixture_name"
    stage_fixture "$fixture_name" "failure-$expected_error-$fixture_name"
    log="$case_root/error.log"
    if env \
        SPIRAL_LEGACY_MIGRATION_PROBE_SOURCE="$case_root/source" \
        SPIRAL_LEGACY_MIGRATION_PROBE_DESTINATION="$case_root/destination" \
        SPIRAL_LEGACY_MIGRATION_PROBE_REPORT="$case_root/report.json" \
        SPIRAL_LEGACY_MIGRATION_PROBE_ENCRYPTED="$encrypted" \
        SPIRAL_LEGACY_MIGRATION_PROBE_PASSPHRASE="$passphrase" \
        SPIRAL_LEGACY_MIGRATION_PROBE_FAIL_AFTER="$failure_after" \
        "$executable" >"$log" 2>&1; then
        echo "Expected migration failure for $fixture_name" >&2
        exit 1
    fi
    grep -q "$expected_error" "$log"
    test ! -e "$case_root/report.json"
    diff -qr "$case_root/source" "$case_root/destination/Retained Legacy Backup"
    test ! -e "$case_root/destination/Documents"
    test ! -e "$case_root/destination/Private/Reconciliation"
    test ! -e "$case_root/destination/Cache/index.json"
}

run_success notational-velocity-plaintext 0
run_success nvalt-rich 0
run_success encrypted-default-kdf 1
run_success encrypted-alternate-kdf 1
run_success wal-intact 0
run_success wal-interrupted 0

run_expected_failure encrypted-default-kdf wrongPassphrase 1 incorrect-passphrase ""
run_expected_failure damaged-archive damagedArchive 0 "" ""
run_expected_failure notational-velocity-plaintext injectedFailure 0 "" 1

echo "Legacy archive migration tests passed"
