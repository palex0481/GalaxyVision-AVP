#!/usr/bin/env bash
# visionOS (xros) build of the New engine as GalaxyPadEngine.framework.
# Adapted from build-ios-engine.sh. Dawn is built from source (no visionOS prebuilt).
# Skips dependency-lock.py (it needs the ModernGekko checkout, not used here).
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build="$root/generated/build/visionos-device-engine"
cmake -S "$root/ref/galaxypad-engine" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$root/scripts/visionos-device-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DPETARI_BUILD_GX_PROBE=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON -DCMAKE_DISABLE_FIND_PACKAGE_Freetype=ON \
  -DPETARI_PIPELINE_STAGE_SEEDS="$build/pipeline-seeds-source"
cmake --build "$build" --target GalaxyPadEngine --parallel "${GALAXYPAD_BUILD_JOBS:-6}" -- -k 0
echo "Built $build/native/app/GalaxyPadEngine.framework"
bash "$root/scripts/package-visionos-framework.sh" "$build/native/app/GalaxyPadEngine.framework" 2.0
