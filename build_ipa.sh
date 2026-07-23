#!/bin/bash

# Jeff Notes 一键打包脚本 (IPA with Code Signing)
# 功能：清理环境、构建 iOS 工程并封装为 .ipa 文件（含 Widget Extension 签名）

set -e

echo "🧹 正在清理旧环境..."
flutter clean
flutter pub get

echo "📦 正在构建 iOS Release (自动签名)..."
flutter build ios --release

echo "📦 正在构建 Widget Extension (自动签名)..."
xcodebuild -project ios/Runner.xcodeproj -target Widget -configuration Release -sdk iphoneos DEVELOPMENT_TEAM=U78542Q47D > /dev/null 2>&1

DATE_STR=$(date +%Y%m%d)
IPA_NAME="JeffNotes_${DATE_STR}.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"
WIDGET_APPEX="ios/build/Release-iphoneos/Widget.appex"
PAYLOAD_DIR="Payload"

echo "📁 正在封装 IPA..."

rm -rf "$PAYLOAD_DIR" "$IPA_NAME"
mkdir "$PAYLOAD_DIR"
cp -r "$APP_PATH" "$PAYLOAD_DIR/"

mkdir -p "$PAYLOAD_DIR/Runner.app/PlugIns"
cp -r "$WIDGET_APPEX" "$PAYLOAD_DIR/Runner.app/PlugIns/"
echo "   ✅ Widget Extension 已嵌入（已签名）"

zip -qr "$IPA_NAME" "$PAYLOAD_DIR"
rm -rf "$PAYLOAD_DIR"

echo "--------------------------------------------------"
echo "✅ $IPA_NAME 已生成（已签名，含 Live Activity Widget）"
echo "--------------------------------------------------"
