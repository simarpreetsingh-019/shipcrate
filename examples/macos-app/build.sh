#!/bin/sh
# Build HelloShip.app with the Swift compiler (no Xcode project needed): build/HelloShip.app
set -eu
cd "$(dirname "$0")"
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
APP=build/HelloShip.app
rm -rf ./build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/HelloShip" Sources/*.swift updater/Updater.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1   # ad-hoc signature; use your Developer ID for real releases
echo "✓ $APP ($V)"
