#!/bin/bash
# Generate changelog from git commits for the release notes

set -e

VERSION="${1:-unknown}"
BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')
COMMIT_SHA=$(git rev-parse --short HEAD)
COMMIT_COUNT=$(git log --oneline -1 | wc -l | tr -d ' ')

# Get recent commits since last tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
    COMMITS=$(git log "$LAST_TAG..HEAD" --pretty=format:"- %s" --no-merges 2>/dev/null || echo "")
else
    COMMITS=$(git log -20 --pretty=format:"- %s" --no-merges 2>/dev/null || echo "")
fi

if [ -z "$COMMITS" ]; then
    COMMITS="- Initial release from OpenMinis source"
fi

# Count files changed
FILES_CHANGED=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | awk '{print $1}' || echo "N/A")

cat << CHANGELOG_EOF
## 版本 $VERSION ($BUILD_DATE)

**Commit:** \`$COMMIT_SHA\`

### 更新内容

$COMMITS

### 构建信息

| 项目 | 详情 |
|---|---|
| iOS 版本 | $VERSION |
| 平台 | iOS (iPhone/iPad), Android |
| iOS 安装方式 | TrollStore (巨魔) 安装 |
| Android 安装方式 | APK 直接安装 |
| 构建时间 | $BUILD_DATE |

### 下载安装说明

**iOS (TrollStore 安装):**
1. 确保设备已安装 TrollStore
2. 下载 Minis.ipa 文件
3. 通过 TrollStore 打开安装

**Android:**
1. 下载 app-debug.apk 文件
2. 允许未知来源安装
3. 点击安装

---
*本版本由 GitHub Actions 自动构建*
CHANGELOG_EOF
