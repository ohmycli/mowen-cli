#!/bin/bash
# 发布新版本：自动生成 CHANGELOG、更新版本号、打 tag、推送触发 GitHub Release
# 用法：
#   ./release.sh patch    # v2.1.0 -> v2.1.1
#   ./release.sh minor    # v2.1.0 -> v2.2.0
#   ./release.sh major    # v2.1.0 -> v3.0.0
#   ./release.sh 2.5.0    # 直接指定版本号

set -e

BUMP="${1:-patch}"
REPO_URL="https://github.com/ohmycli/mowen-cli"

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
DATE=$(date +%Y-%m-%d)

echo "当前版本: v${LATEST}"
echo "新版本:   ${VERSION}"
echo ""

# 生成本次 changelog
generate_changelog() {
  local prev_tag="v${LATEST}"
  local range="${prev_tag}..HEAD"

  # 如果没有上一个 tag，取所有提交
  if ! git rev-parse "${prev_tag}" >/dev/null 2>&1; then
    range="HEAD"
  fi

  local feat="" fix="" docs="" refactor="" perf="" test="" build="" ci="" chore="" style=""

  while IFS= read -r line; do
    hash="${line%% *}"
    msg="${line#* }"
    short="${hash:0:7}"
    link="[${short}](${REPO_URL}/commit/${hash})"

    case "$msg" in
      feat*)    feat="${feat}\n- ${msg#feat: } (${link})" ;;
      feat\(*) feat="${feat}\n- ${msg#feat*: } (${link})" ;;
      fix*)     fix="${fix}\n- ${msg#fix: } (${link})" ;;
      fix\(*)  fix="${fix}\n- ${msg#fix*: } (${link})" ;;
      docs*)    docs="${docs}\n- ${msg#docs: } (${link})" ;;
      docs\(*) docs="${docs}\n- ${msg#docs*: } (${link})" ;;
      refactor*) refactor="${refactor}\n- ${msg#refactor*: } (${link})" ;;
      perf*)    perf="${perf}\n- ${msg#perf*: } (${link})" ;;
      test*)    test="${test}\n- ${msg#test*: } (${link})" ;;
      build*)   build="${build}\n- ${msg#build*: } (${link})" ;;
      ci*)      ci="${ci}\n- ${msg#ci*: } (${link})" ;;
      style*)   style="${style}\n- ${msg#style*: } (${link})" ;;
      chore*)   chore="${chore}\n- ${msg#chore*: } (${link})" ;;
      *)        chore="${chore}\n- ${msg} (${link})" ;;
    esac
  done <<< "$(git log --format="%H %s" ${range} --no-merges)"

  local entry="## [${VERSION}](${REPO_URL}/compare/v${LATEST}...${VERSION}) (${DATE})\n"

  [ -n "$feat" ]     && entry="${entry}\n### ✨ 新功能\n${feat}\n"
  [ -n "$fix" ]      && entry="${entry}\n### 🐛 Bug 修复\n${fix}\n"
  [ -n "$docs" ]     && entry="${entry}\n### 📝 文档\n${docs}\n"
  [ -n "$style" ]    && entry="${entry}\n### 💄 样式\n${style}\n"
  [ -n "$refactor" ] && entry="${entry}\n### ♻️ 重构\n${refactor}\n"
  [ -n "$perf" ]     && entry="${entry}\n### ⚡ 性能优化\n${perf}\n"
  [ -n "$test" ]     && entry="${entry}\n### ✅ 测试\n${test}\n"
  [ -n "$build" ]    && entry="${entry}\n### 📦 构建\n${build}\n"
  [ -n "$ci" ]       && entry="${entry}\n### 👷 CI/CD\n${ci}\n"
  [ -n "$chore" ]    && entry="${entry}\n### 🔧 其他\n${chore}\n"

  echo -e "$entry"
}

# 预览 changelog
echo "--- CHANGELOG 预览 ---"
CHANGELOG_ENTRY=$(generate_changelog)
echo -e "$CHANGELOG_ENTRY"
echo "----------------------"
echo ""

# 确认
read -p "确认发布 ${VERSION}? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "已取消"
  exit 0
fi

# 更新 CHANGELOG.md
if [ -f CHANGELOG.md ]; then
  # 在 header 后插入新版本
  TEMP=$(mktemp)
  head -4 CHANGELOG.md > "$TEMP"
  echo "" >> "$TEMP"
  echo -e "$CHANGELOG_ENTRY" >> "$TEMP"
  tail -n +5 CHANGELOG.md >> "$TEMP"
  mv "$TEMP" CHANGELOG.md
else
  cat > CHANGELOG.md << HEADER
# Changelog

All notable changes to this project will be documented in this file.

HEADER
  echo -e "$CHANGELOG_ENTRY" >> CHANGELOG.md
fi

# 更新 build.zig.zon 中的版本号
sed -i "s/\.version = \"[^\"]*\"/.version = \"${MAJOR}.${MINOR}.${PATCH}\"/" build.zig.zon

# 提交
git add CHANGELOG.md build.zig.zon
git commit -m "chore(release): ${VERSION}"

# 打 tag 并推送
git tag "${VERSION}"
git push origin HEAD
git push origin "${VERSION}"

echo ""
echo "✓ ${VERSION} 已发布！"
echo "  CHANGELOG: CHANGELOG.md 已更新"
echo "  GitHub Actions: ${REPO_URL}/actions"
echo "  Release: ${REPO_URL}/releases"
