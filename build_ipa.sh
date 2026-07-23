#!/bin/bash

set -e

echo "🧹 正在清理旧环境..."
flutter clean
flutter pub get

echo "📦 正在构建 iOS Release..."
flutter build ios --release

DATE_STR=$(date +%Y%m%d)
IPA_NAME="JeffNotes_${DATE_STR}.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"

echo "📁 正在封装 IPA..."
rm -rf "Payload" "$IPA_NAME"
mkdir "Payload"
cp -r "$APP_PATH" "Payload/"
zip -qr "$IPA_NAME" "Payload"
rm -rf "Payload"

echo "--------------------------------------------------"
echo "✅ $IPA_NAME 已生成"
echo "--------------------------------------------------"
