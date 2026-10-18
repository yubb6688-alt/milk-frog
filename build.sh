#!/bin/zsh
set -eu
cd "$(dirname "$0")"
app_path="$PWD/奶蛙.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
swiftc Sources/*.swift -framework AppKit -framework QuartzCore -framework ApplicationServices -o "$app_path/Contents/MacOS/MilkFrog"
cp Info.plist "$app_path/Contents/Info.plist"
for frame in "兼容尺寸/待机/"scratch_0[1-4].png; do
    cp "$frame" "$app_path/Contents/Resources/"
done
cp Assets/walk-cycle-v3-arms.png "$app_path/Contents/Resources/"
cp Assets/walk-passing-v4.png "$app_path/Contents/Resources/"
cp Assets/click-hands-v1.png "$app_path/Contents/Resources/"
cp Assets/typing-v1.png "$app_path/Contents/Resources/"
codesign --force --sign - "$app_path"
