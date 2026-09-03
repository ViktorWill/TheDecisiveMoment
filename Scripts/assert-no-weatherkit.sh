#!/bin/bash
#
# Build-level proof that the Free configuration carries no WeatherKit.
#
# `docs/SPEC-light.md`, "Sky, when there is no WeatherKit": a free Apple ID
# cannot be granted com.apple.developer.weatherkit, so the Free build must not
# ask for the entitlement and must not link the framework. A comment saying so
# is not a check; this reads the built binary and the entitlements file.
#
# Usage: Scripts/assert-no-weatherkit.sh [derived-data-path]
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${1:-$(mktemp -d)}"
SCHEME="The Decisive Moment (Free)"
ENTITLEMENTS="App/TheDecisiveMoment-Free.entitlements"

echo "==> The Free entitlements file asks for nothing"
# Strip XML comments first: the file documents the weatherkit key by name in
# prose, and a raw grep over the whole file would trip on that comment.
if perl -0777 -pe 's/<!--.*?-->//gs' "$ENTITLEMENTS" | grep -q "com.apple.developer.weatherkit"; then
    echo "FAIL: $ENTITLEMENTS declares WeatherKit; a free Apple ID cannot sign that." >&2
    exit 1
fi

echo "==> Building '$SCHEME'"
if ! xcodebuild build \
    -project TheDecisiveMoment.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Free \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    > "$DERIVED_DATA/build.log" 2>&1; then
    tail -50 "$DERIVED_DATA/build.log" >&2
    echo "FAIL: the Free configuration does not build." >&2
    exit 1
fi

APP_BINARY=$(find "$DERIVED_DATA/Build/Products" -type f -path '*The Decisive Moment.app/The Decisive Moment' | head -1)
if [ -z "$APP_BINARY" ]; then
    echo "FAIL: no Free build product to inspect." >&2
    exit 1
fi

echo "==> Reading the linked frameworks out of $APP_BINARY"
# An `import WeatherKit` anywhere in the app or its packages autolinks the
# framework, so its absence here is the whole assertion.
if otool -L "$APP_BINARY" | grep -i "WeatherKit"; then
    echo "FAIL: the Free build links WeatherKit. TDM_NO_WEATHERKIT did not reach every target." >&2
    exit 1
fi

# Belt and braces: Swift records the modules it imported in the binary, so a
# reference that survived the link would still show up here.
if strings "$APP_BINARY" | grep -qx "WeatherKit"; then
    echo "FAIL: the Free build still references WeatherKit." >&2
    exit 1
fi

echo "OK: the Free build carries no WeatherKit entitlement and links no WeatherKit."
