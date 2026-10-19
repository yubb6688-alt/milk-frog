#!/bin/zsh
# Build a clean, universal distribution; never copy the developer's app or settings.
set -eu
cd "$(dirname "$0")"
release_dir="$PWD/发布"
package_work="$(mktemp -d "${TMPDIR:-/tmp/}milkfrog-package.XXXXXX")"
trap 'rm -rf "$package_work"' EXIT
stage="$package_work/stage"
app_path="$stage/奶蛙.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$release_dir"
for cpu in arm64 x86_64; do
    xcrun swiftc Sources/*.swift -O -target "${cpu}-apple-macos12.0" \
        -framework AppKit -framework QuartzCore -framework ApplicationServices \
        -o "$package_work/MilkFrog-$cpu"
done
xcrun lipo -create "$package_work/MilkFrog-arm64" "$package_work/MilkFrog-x86_64" -output "$app_path/Contents/MacOS/MilkFrog"
cp Info.plist "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 12.0' "$app_path/Contents/Info.plist"
for frame in "兼容尺寸/待机/"scratch_0[1-4].png "兼容尺寸/欢呼/"cheer_0[1-4].png; do
    cp "$frame" "$app_path/Contents/Resources/"
done
for name in walk-cycle-v3-arms walk-passing-v4 click-hands-v1 typing-v1 thinking-hand-v2; do
    cp "Assets/$name.png" "$app_path/Contents/Resources/"
done
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
ln -s /Applications "$stage/Applications"
cp Packaging/安装与聊天配置.txt "$stage/安装与聊天配置.txt"
# Fail closed if a local configuration file or known key was ever accidentally included.
python3 - "$stage" <<'PY'
import json, pathlib, sys
stage = pathlib.Path(sys.argv[1])
local = pathlib.Path.home() / 'Library/Application Support/MilkFrog/deepseek.local.json'
key = json.loads(local.read_text()).get('apiKey', '') if local.exists() else ''
for file in stage.rglob('*'):
    if file.is_symlink() or not file.is_file():
        continue
    if file.name.startswith('.env') or file.name.endswith('.local.json'):
        raise SystemExit('Packaging stopped: local configuration in distribution.')
    if key and key.encode() in file.read_bytes():
        raise SystemExit('Packaging stopped: private API key in distribution.')
print('PASS: clean distribution; no local configuration or private API key.')
PY
hdiutil create -volname '奶蛙安装' -srcfolder "$stage" -format UDZO -ov "$release_dir/奶蛙-0.1.0-macOS-universal.dmg"
cp Packaging/安装与聊天配置.txt "$release_dir/安装与聊天配置.txt"
hdiutil verify "$release_dir/奶蛙-0.1.0-macOS-universal.dmg"
(cd "$release_dir" && shasum -a 256 奶蛙-0.1.0-macOS-universal.dmg > SHA256.txt)
print "安装包已生成：$release_dir/奶蛙-0.1.0-macOS-universal.dmg"
