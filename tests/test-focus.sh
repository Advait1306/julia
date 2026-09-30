#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
focus_test_binary=$(mktemp -t julia-focus-tests)
trap 'rm -f "$focus_test_binary"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor julia/settings/Focus.swift tests/FocusTests.swift -o "$focus_test_binary"
"$focus_test_binary"
