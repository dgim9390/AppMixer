#!/bin/bash
# Release 빌드 → 배경 이미지 생성 → dist/AppMixer-<버전>.dmg
# 필요: Xcode, xcodegen, uv (dmgbuild는 uvx가 받아서 실행)
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project AppMixer.xcodeproj -scheme AppMixer -configuration Release -derivedDataPath build -quiet build
APP=build/Build/Products/Release/AppMixer.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift dmg/make-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff"

mkdir -p dist
uvx dmgbuild -s dmg/settings.py -D app="$APP" -D background="$WORK/background.tiff" AppMixer "dist/AppMixer-$VERSION.dmg"
echo "dist/AppMixer-$VERSION.dmg"
