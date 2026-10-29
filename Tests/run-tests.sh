#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/awdlcontrol-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_dir"

flags=(-fobjc-arc -fmodules "-fmodules-cache-path=$build_dir/modules"
       -mmacosx-version-min=13.0 -Wall -Wextra -Werror -IAWDLControl)
detector=(AWDLControl/ChromecastMonitor.m AWDLControl/ChromecastProcess.m)

fixture="$build_dir/Fixture.app/Contents/MacOS/ChromecastProcessFixture"
mkdir -p "$(dirname "$fixture")"
xcrun clang -mmacosx-version-min=13.0 -Wall -Wextra -Werror \
    Tests/ChromecastProcessFixture.c -o "$fixture"
xcrun clang "${flags[@]}" -framework Cocoa "${detector[@]}" \
    Tests/ChromecastMonitorTests.m -o "$build_dir/detector-tests"
"$build_dir/detector-tests" "$fixture"

# The existing app has unused delegate parameters and deprecated AppKit calls.
# Keep warnings fatal while excluding those existing categories for this harness.
xcrun clang "${flags[@]}" -Wno-unused-parameter -Wno-deprecated-declarations \
    -framework Cocoa -framework Network -framework ServiceManagement \
    -framework UserNotifications "${detector[@]}" \
    AWDLControl/AppDelegate.m AWDLControl/Reachability.m \
    Tests/AppDelegateTests.m -o "$build_dir/controller-tests"
"$build_dir/controller-tests"
