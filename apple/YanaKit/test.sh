#!/bin/sh
# Runs `swift test`. With only the Command Line Tools installed, SwiftPM intermittently
# fails to locate the Swift Testing macro plugin, so pass its directory explicitly.
set -e
cd "$(dirname "$0")"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
