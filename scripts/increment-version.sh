#!/bin/bash
# Auto-increment version numbers for both iOS and Android builds
# Reads current versions, increments them, and writes back

set -e

PROJECT_FILE="src/ios/Minis.xcodeproj/project.pbxproj"
GRADLE_FILE="src/android/app/build.gradle.kts"
VERSION_FILE="VERSION.txt"

# === Read current iOS version ===
IOS_MARKETING=$(grep -m1 'MARKETING_VERSION' "$PROJECT_FILE" | sed 's/.*= *//;s/ *;//')
IOS_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT_FILE" | sed 's/.*= *//;s/ *;//')

# === Read current Android version ===
ANDROID_CODE=$(grep 'versionCode' "$GRADLE_FILE" | head -1 | sed 's/.*= *//;s/ *$//')
ANDROID_NAME=$(grep 'versionName' "$GRADLE_FILE" | head -1 | sed 's/.*= *//;s/"//g;s/ *$//')

echo "=== 版本递增脚本 ==="
echo "当前 iOS 版本: $IOS_MARKETING (Build: $IOS_BUILD)"
echo "当前 Android 版本: $ANDROID_NAME (Code: $ANDROID_CODE)"

# === Increment versions ===
# Split marketing version into major.minor.patch
IFS='.' read -r MAJOR MINOR PATCH <<< "$IOS_MARKETING"
PATCH=$((PATCH + 1))
NEW_IOS_MARKETING="${MAJOR}.${MINOR}.${PATCH}"
NEW_IOS_BUILD=$((IOS_BUILD + 1))

# Android: increment versionCode, keep versionName in sync with iOS
NEW_ANDROID_CODE=$((ANDROID_CODE + 1))
NEW_ANDROID_NAME="$NEW_IOS_MARKETING"

echo ""
echo "新 iOS 版本: $NEW_IOS_MARKETING (Build: $NEW_IOS_BUILD)"
echo "新 Android 版本: $NEW_ANDROID_NAME (Code: $NEW_ANDROID_CODE)"

# === Update iOS project.pbxproj ===
echo ""
echo "更新 iOS 版本号..."
sed -i.bak "s/MARKETING_VERSION = .*/MARKETING_VERSION = $NEW_IOS_MARKETING;/g" "$PROJECT_FILE" && rm -f "$PROJECT_FILE.bak"
sed -i.bak "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEW_IOS_BUILD;/g" "$PROJECT_FILE" && rm -f "$PROJECT_FILE.bak"

# === Update Android build.gradle.kts ===
echo "更新 Android 版本号..."
sed -i.bak "s/versionCode = .*/versionCode = $NEW_ANDROID_CODE/g" "$GRADLE_FILE" && rm -f "$GRADLE_FILE.bak"
sed -i.bak "s/versionName = .*/versionName = \"$NEW_ANDROID_NAME\"/g" "$GRADLE_FILE" && rm -f "$GRADLE_FILE.bak"

# === Write version file for other jobs to read ===
echo "$NEW_IOS_MARKETING" > "$VERSION_FILE"
echo "build=$NEW_IOS_BUILD" >> "$VERSION_FILE"
echo "android_code=$NEW_ANDROID_CODE" >> "$VERSION_FILE"

echo ""
echo "✓ 版本已更新: $NEW_IOS_MARKETING (Build: $NEW_IOS_BUILD)"
echo "完成！"
