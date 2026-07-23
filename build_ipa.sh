#!/bin/bash

set -e

echo "🧹 正在清理旧环境..."
flutter clean
flutter pub get

echo "📦 正在构建 iOS Release (自动签名)..."
flutter build ios --release

echo "📦 正在构建 Widget Extension (自动签名)..."
xcodebuild -project ios/Runner.xcodeproj -target Widget -configuration Release -sdk iphoneos -allowProvisioningUpdates > /dev/null 2>&1

DATE_STR=$(date +%Y%m%d)
IPA_NAME="JeffNotes_${DATE_STR}.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"
WIDGET_APPEX="ios/build/Release-iphoneos/Widget.appex"

echo "📁 正在封装 IPA..."
rm -rf "Payload" "$IPA_NAME"
mkdir "Payload"
cp -r "$APP_PATH" "Payload/"

mkdir -p "Payload/Runner.app/PlugIns"
cp -r "$WIDGET_APPEX" "Payload/Runner.app/PlugIns/"

zip -qr "$IPA_NAME" "Payload"
rm -rf "Payload"

echo "--------------------------------------------------"
echo "✅ $IPA_NAME 已生成（已签名，含 Live Activity Widget）"
echo "--------------------------------------------------"
