#!/bin/sh
# Check that every private symbol bgdisplay imports is still exported by the installed
# CoreDevice frameworks. Run after an Xcode update, before touching a phone.
set -eu
cd "$(dirname "$0")"
PF=/Library/Developer/PrivateFrameworks
BIN=.build/bgdisplay
[ -x "$BIN" ] || ./build.sh >/dev/null
EXPORTS=$(mktemp)
for f in "$PF/CoreDevice.framework/Versions/A/CoreDevice" \
         "$PF/CoreDeviceUtilities.framework/Versions/A/CoreDeviceUtilities" \
         "$PF/CoreDevice.framework/Versions/A/Frameworks/CoreDeviceMediaStreamSupport.framework/Versions/A/CoreDeviceMediaStreamSupport"; do
  nm -gU "$f" | awk '{print $3}' >> "$EXPORTS"
done
sort -u -o "$EXPORTS" "$EXPORTS"
missing=0; total=0
for s in $(nm -u "$BIN" | grep -E '^_\$s(10CoreDevice|28CoreDeviceMediaStreamSupport|19CoreDeviceProtocols)'); do
  total=$((total+1))
  grep -qxF "$s" "$EXPORTS" || { echo "MISSING $(echo "$s" | xcrun swift-demangle)"; missing=$((missing+1)); }
done
rm -f "$EXPORTS"
echo "CoreDevice $(defaults read $PF/CoreDevice.framework/Versions/A/Resources/Info.plist CFBundleShortVersionString): $total private symbols imported, $missing missing"
[ "$missing" -eq 0 ]
