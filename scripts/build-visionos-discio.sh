#!/usr/bin/env bash
# Builds visionos/DiscIO (a small Dolphin DiscIO subset) as libgvdiscio.a for visionOS devices.
# Needs ref/ModernGekko and its vendor/dolphin submodule checked out.
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build="$root/generated/build/visionos-device-discio"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET
cmake -S "$root/visionos/DiscIO" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$root/scripts/visionos-device-toolchain.cmake" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build" --target gvdiscio
