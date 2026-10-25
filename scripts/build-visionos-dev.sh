#!/bin/sh
# Builds the "GalaxyVision Dev" variant (separate bundle id + container) into .build/dd-dev.
set -e
cd "$(dirname "$0")/../visionos"
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
exec xcodebuild -project GalaxyVision.xcodeproj -scheme GalaxyVision -configuration Debug \
  -destination 'generic/platform=visionOS' -derivedDataPath .build/dd-dev \
  -xcconfig Dev.xcconfig -allowProvisioningUpdates build "$@"
