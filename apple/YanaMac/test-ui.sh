#!/bin/sh
# Runs the UI tests. XCUITest needs a signed runner; without a development team, sign ad hoc and leave out the
# iCloud entitlements (which need a provisioning profile). Extra arguments go to xcodebuild.
set -e
cd "$(dirname "$0")"
exec xcodebuild test -scheme YanaMacUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= "$@"
