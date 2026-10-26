#!/bin/bash
# 构建 TypeLearn.app（菜单栏应用包）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/TypeLearn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/TypeLearn" "$APP/Contents/MacOS/TypeLearn"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign "TypeLearn Dev" "$APP"

echo "Built: $APP"
