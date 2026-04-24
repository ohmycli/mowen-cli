#!/bin/bash
# 发布新版本：自动更新版本号、打 tag、推送触发 GitHub Release
# 用法：
#   ./release.sh patch    # v2.1.0 -> v2.1.1
#   ./release.sh minor    # v2.1.0 -> v2.2.0
#   ./release.sh major    # v2.1.0 -> v3.0.0
#   ./release.sh 2.5.0    # 直接指定版本号

set -e

BUMP="${1:-patch}"

# 获取最新 tag
LATEST=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
LATEST="${LATEST#v}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST"

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *)     IFS='.' read -r MAJOR MINOR PATCH <<< "$BUMP" ;;
esac

VERSION="v${MAJOR}.${MINOR}.${PATCH}"

echo "当前版本: v${LATEST}"
echo "新版本:   ${VERSION}"
echo ""

# 确认
read -p "确认发布 ${VERSION}? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "已取消"
  exit 0
fi

# 更新 build.zig.zon 中的版本号
sed -i "s/\.version = \"[^\"]*\"/.version = \"${MAJOR}.${MINOR}.${PATCH}\"/" build.zig.zon

# 提交版本号变更（如果有）
if ! git diff --quiet build.zig.zon; then
  git add build.zig.zon
  git commit -m "release: ${VERSION}"
fi

# 打 tag 并推送
git tag "${VERSION}"
git push origin HEAD
git push origin "${VERSION}"

echo ""
echo "✓ ${VERSION} 已发布！GitHub Actions 正在构建..."
echo "  https://github.com/ohmycli/mowen-cli/actions"
echo "  https://github.com/ohmycli/mowen-cli/releases"
