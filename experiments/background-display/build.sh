#!/bin/sh
# Build bgdisplay against the installed private CoreDevice frameworks.
# The stubs in ./Stubs declare only names; the linker binds them to Apple's binaries,
# so a stale or wrong declaration fails here, not on the phone.
set -eu
cd "$(dirname "$0")"
PF=/Library/Developer/PrivateFrameworks
NESTED=$PF/CoreDevice.framework/Versions/A/Frameworks
mkdir -p .build
swiftc -parse-as-library -O -target arm64-apple-macos27.0 \
  -I Stubs \
  -F "$PF" -framework CoreDevice \
  -F "$NESTED" -framework CoreDeviceMediaStreamSupport \
  -framework QuartzCore -framework ImageIO -framework UniformTypeIdentifiers \
  Sources/main.swift -o .build/bgdisplay
echo "built $(pwd)/.build/bgdisplay"
