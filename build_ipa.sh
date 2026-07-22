#!/bin/bash

# Jeff Notes 一键打包脚本 (IPA Sideload Version)
# 功能：清理环境、构建 iOS 工程并封装为可侧载的 .ipa 文件

echo "🧹 正在清理旧环境..."
flutter clean
flutter pub get

echo "📦 正在构建 iOS Release (no-codesign)..."
flutter build ios --release --no-codesign

echo "📦 正在构建 Widget Extension (no-codesign)..."
xcodebuild -project ios/Runner.xcodeproj -target Widget -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO > /dev/null 2>&1

# 定义路径
DATE_STR=$(date +%Y%m%d)
IPA_NAME="JeffNotes_${DATE_STR}.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"
WIDGET_APPEX="ios/build/Release-iphoneos/Widget.appex"
PAYLOAD_DIR="Payload"

echo "📁 正在执行 IPA 封装逻辑..."

# 检查并清理旧文件
if [ -d "$PAYLOAD_DIR" ]; then
    rm -rf "$PAYLOAD_DIR"
fi

if [ -f "$IPA_NAME" ]; then
    rm "$IPA_NAME"
fi

# 创建 Payload 并拷贝 Runner.app
mkdir "$PAYLOAD_DIR"
cp -r "$APP_PATH" "$PAYLOAD_DIR/"

# 嵌入 Widget Extension
mkdir -p "$PAYLOAD_DIR/Runner.app/PlugIns"
cp -r "$WIDGET_APPEX" "$PAYLOAD_DIR/Runner.app/PlugIns/"
echo "   ✅ Widget Extension 已嵌入"

# 压缩为 IPA
echo "🤐 正在压缩..."
zip -qr "$IPA_NAME" "$PAYLOAD_DIR"

# 清理临时文件夹
rm -rf "$PAYLOAD_DIR"

echo "--------------------------------------------------"
echo "✅ $IPA_NAME 已生成在项目根目录 (含 Live Activity Widget)"
echo "--------------------------------------------------"
