#!/usr/bin/env bash
# Prepare the BUILT GalaxyPadEngine.framework for visionOS codesign/embedding.
# - removes the built framework's Licenses/ folder (codesign rejects it; sources untouched)
# - fixes Info.plist (platform keys, MinimumOSVersion, bundle keys)
# Usage: package-visionos-framework.sh <path/to/GalaxyPadEngine.framework> [min-os]
set -euo pipefail
fw="${1:?framework path}"
minos="${2:-2.0}"
plist="$fw/Info.plist"
[ -f "$plist" ] || { echo "no Info.plist in $fw" >&2; exit 1; }
rm -rf "$fw/Licenses"
pb=/usr/libexec/PlistBuddy
setkey() { # key type value
  "$pb" -c "Delete :$1" "$plist" >/dev/null 2>&1 || true
  "$pb" -c "Add :$1 $2 $3" "$plist"
}
setkey CFBundleExecutable string GalaxyPadEngine
setkey CFBundleIdentifier string org.galaxypad.engine
setkey CFBundleName string GalaxyPadEngine
setkey CFBundlePackageType string FMWK
setkey CFBundleVersion string 1
setkey CFBundleShortVersionString string 0.1.0
setkey MinimumOSVersion string "$minos"
"$pb" -c "Delete :CFBundleSupportedPlatforms" "$plist" >/dev/null 2>&1 || true
"$pb" -c "Add :CFBundleSupportedPlatforms array" "$plist"
"$pb" -c "Add :CFBundleSupportedPlatforms:0 string XROS" "$plist"
"$pb" -c "Delete :CFBundleIconFile" "$plist" >/dev/null 2>&1 || true
"$pb" -c "Delete :CFBundleSignature" "$plist" >/dev/null 2>&1 || true
"$pb" -c "Delete :CSResourcesFileMapped" "$plist" >/dev/null 2>&1 || true
echo "Packaged $fw"
