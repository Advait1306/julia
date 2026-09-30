#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
focus_jev_build_directory=$(mktemp -d -t julia-jev-focus-tests)
trap 'rm -rf "$focus_jev_build_directory"' EXIT
if ! xcodebuild -project julia.xcodeproj -scheme julia -configuration Debug -destination 'platform=macOS' -derivedDataPath "$focus_jev_build_directory" CODE_SIGNING_ALLOWED=NO build > "$focus_jev_build_directory/build.log" 2>&1; then
    cat "$focus_jev_build_directory/build.log"
    exit 1
fi
focus_jev_products="$focus_jev_build_directory/Build/Products/Debug"
xcrun swiftc -swift-version 6 -default-isolation MainActor -I "$focus_jev_products" julia/settings/Audio.swift julia/settings/Focus.swift julia/ai/Jev.swift tests/JevFocusTests.swift "$focus_jev_products/Alamofire.o" -o "$focus_jev_build_directory/jev-focus-tests"
"$focus_jev_build_directory/jev-focus-tests"
