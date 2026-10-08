#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_work="$(mktemp -d "${TMPDIR:-/tmp}/julia-vpn-tests.XXXXXX")"
trap 'rm -rf "$test_work"' EXIT
cd "$repo_root"
xcodebuild -project julia.xcodeproj -scheme julia -configuration Debug \
    -destination 'platform=macOS' -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO build > "$test_work/build.log" 2>&1 || {
    cat "$test_work/build.log"
    exit 1
}
xcodebuild -project julia.xcodeproj -scheme julia -configuration Debug \
    -destination 'platform=macOS' -disableAutomaticPackageResolution \
    -showBuildSettings > "$test_work/settings.log" 2>&1
products_dir="$(awk '/ BUILT_PRODUCTS_DIR = / { sub(/^.* BUILT_PRODUCTS_DIR = /, ""); print; exit }' "$test_work/settings.log")"
xcrun swiftc -parse-as-library -default-isolation MainActor \
    -I "$products_dir" "$products_dir/Alamofire.o" \
    julia/ai/Jev.swift julia/settings/VPN.swift julia/settings/Apps.swift \
    julia/sdk/AudioKit.swift julia/sdk/FocusKit.swift tests/VPNTests.swift \
    -o "$test_work/vpn-tests"
"$test_work/vpn-tests"
