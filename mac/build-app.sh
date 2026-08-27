#!/bin/sh
# Build VibePal.app — swift build + a hand-rolled bundle (no Xcode project).
set -e
cd "$(dirname "$0")"
CONF=${1:-debug}
swift build -c "$CONF"
BIN_DIR=$(swift build -c "$CONF" --show-bin-path)
BIN="$BIN_DIR/VibePal"
APP=build/VibePal.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VibePal"
cp Sources/VibePal/Resources/brand-logo.png "$APP/Contents/Resources/brand-logo.png"
if [ -d "$BIN_DIR/VibePal_VibePal.bundle" ]; then
  cp -R "$BIN_DIR/VibePal_VibePal.bundle" "$APP/"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>VibePal</string>
  <key>CFBundleDisplayName</key><string>VibePal</string>
  <key>CFBundleIdentifier</key><string>dev.mako.vibepal</string>
  <key>CFBundleExecutable</key><string>VibePal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>brand-logo.png</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- kwdm.dylib 会起 BLE 扫描线程(为 TC002 那条产品线),缺这个键 TCC 会直接杀进程 -->
  <key>NSBluetoothAlwaysUsageDescription</key><string>设备 SDK 会扫描蓝牙配件</string>
  <key>NSMicrophoneUsageDescription</key><string>显示语音键的输入电平</string>
  <key>NSInputMonitoringUsageDescription</key><string>读取 Vibe Key 的按键</string>
  <key>NSMicrophoneUsageDescription</key><string>用于测试 VibePal 麦克风输入电平。</string>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1 || true
test -f "$APP/VibePal_VibePal.bundle/device-source.png"
test -f "$APP/Contents/Resources/brand-logo.png"
echo "built $APP"
