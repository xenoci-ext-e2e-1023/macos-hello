#!/bin/bash
# eas-1024 bench: Expo prebuild -> pod install -> xcodebuild iOS Simulator Release, one TIMING line per stage.
set -euo pipefail
MODE=${1:-cold}
t(){ perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
d(){ perl -e "printf '%.1f', $2-$1"; }
S=$(t)
echo "HW $(sysctl -n hw.model) ncpu=$(sysctl -n hw.ncpu) mem=$(sysctl -n hw.memsize) macos=$(sw_vers -productVersion) mode=$MODE"
xcodebuild -version | tr '\n' ' '; echo
echo "TOOLS node=$(node -v) npm=$(npm -v) pod=$(pod --version 2>/dev/null || echo none) ruby=$(ruby -v | cut -d' ' -f2)"
a=$(t); npm ci --no-audit --no-fund > npm.log 2>&1 || { tail -40 npm.log; exit 3; }
b=$(t); echo "TIMING npm_ci $(d $a $b)"
a=$(t); npx expo prebuild --platform ios --no-install > prebuild.log 2>&1 || { tail -40 prebuild.log; exit 4; }
b=$(t); echo "TIMING expo_prebuild $(d $a $b)"
a=$(t); (cd ios && pod install --verbose) > pod.log 2>&1 || { tail -60 pod.log; exit 5; }
b=$(t); echo "TIMING pod_install $(d $a $b)"
grep -E "Pod installation complete|Installing|Downloading" pod.log | tail -3 || true
WS=$(ls -d ios/*.xcworkspace | head -1); SCHEME=$(basename "$WS" .xcworkspace)
echo "WORKSPACE $WS scheme=$SCHEME"
a=$(t)
xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build > xcodebuild.log 2>&1 || { grep -E "error:|BUILD FAILED" xcodebuild.log | head -40; tail -40 xcodebuild.log; exit 6; }
b=$(t); echo "TIMING xcodebuild $(d $a $b)"
tail -3 xcodebuild.log
APP=$(ls -d build/dd/Build/Products/Release-iphonesimulator/*.app | head -1)
test -f "$APP/main.jsbundle" && echo "JSBUNDLE_OK $(stat -f %z "$APP/main.jsbundle")" || echo "JSBUNDLE_MISSING"
mkdir -p build/logs; cp npm.log prebuild.log pod.log xcodebuild.log build/logs/ 2>/dev/null || true
tar -czf build/app-sim.tar.gz -C "$(dirname "$APP")" "$(basename "$APP")"; rm -rf build/dd
echo "APP_TGZ $(stat -f %z build/app-sim.tar.gz)"
echo "TIMING total $(d $S $(t))"
