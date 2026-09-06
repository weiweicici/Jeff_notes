#!/bin/bash

set -e

echo "🧹 正在清理旧环境..."
flutter clean
flutter pub get

echo "📦 正在构建 iOS Release..."
# Keep the IPA unsigned so Sideloadly can apply one consistent signing
# identity to both the iPhone and embedded Watch apps.
flutter build ios --release --no-codesign

DATE_STR=$(date +%Y%m%d)
IPA_NAME="JeffNotes_${DATE_STR}.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"

echo "📁 正在封装 IPA..."
rm -rf "Payload" "$IPA_NAME"
mkdir "Payload"
cp -r "$APP_PATH" "Payload/"
# AppleDouble/resource-fork sidecars such as Payload/._Runner.app are not
# application bundles and cause the iOS installer to reject the IPA.
COPYFILE_DISABLE=1 zip -Xqr "$IPA_NAME" "Payload" -x '*/._*' '*/.DS_Store' '__MACOSX/*'
rm -rf "Payload"

echo "--------------------------------------------------"
echo "✅ $IPA_NAME 已生成"
echo "--------------------------------------------------"
