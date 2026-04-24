# 发布新版本：自动生成 CHANGELOG、更新版本号、打 tag、推送触发 GitHub Release
# 用法：
#   .\release.ps1 patch    # v2.1.0 -> v2.1.1
#   .\release.ps1 minor    # v2.1.0 -> v2.2.0
#   .\release.ps1 major    # v2.1.0 -> v3.0.0
#   .\release.ps1 2.5.0    # 直接指定版本号

param([string]$Bump = "patch")

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/ohmycli/mowen-cli"

# 获取最新 tag
$Latest = git describe --tags --abbrev=0 2>$null
if (-not $Latest) { $Latest = "v0.0.0" }
$Latest = $Latest -replace '^v', ''
$parts = $Latest -split '\.'
$Major = [int]$parts[0]; $Minor = [int]$parts[1]; $Patch = [int]$parts[2]

switch ($Bump) {
    "patch" { $Patch++ }
    "minor" { $Minor++; $Patch = 0 }
    "major" { $Major++; $Minor = 0; $Patch = 0 }
    default { $p = $Bump -split '\.'; $Major = [int]$p[0]; $Minor = [int]$p[1]; $Patch = [int]$p[2] }
}

$Version = "v${Major}.${Minor}.${Patch}"
$Date = Get-Date -Format "yyyy-MM-dd"

Write-Host "当前版本: v${Latest}"
Write-Host "新版本:   ${Version}"
Write-Host ""

# 生成 changelog
$range = "v${Latest}..HEAD"
$logs = git log --format="%H %s" $range --no-merges 2>$null
if (-not $logs) { $logs = git log --format="%H %s" --no-merges }

$sections = @{
    feat=@(); fix=@(); docs=@(); style=@(); refactor=@(); perf=@(); test=@(); build=@(); ci=@(); chore=@()
}
$sectionLabels = @{
    feat="### ✨ 新功能"; fix="### 🐛 Bug 修复"; docs="### 📝 文档"; style="### 💄 样式"
    refactor="### ♻️ 重构"; perf="### ⚡ 性能优化"; test="### ✅ 测试"
    build="### 📦 构建"; ci="### 👷 CI/CD"; chore="### 🔧 其他"
}

foreach ($line in $logs) {
    if ($line -match '^(\w+)\s+(.+)$') {
        $hash = $Matches[1]; $msg = $Matches[2]
        $short = $hash.Substring(0, 7)
        $link = "[$short]($RepoUrl/commit/$hash)"
        $type = if ($msg -match '^(\w+)') { $Matches[1] } else { "chore" }
        if (-not $sections.ContainsKey($type)) { $type = "chore" }
        $sections[$type] += "- $msg ($link)"
    }
}

$entry = "## [$Version]($RepoUrl/compare/v${Latest}...$Version) ($Date)`n"
foreach ($key in @("feat","fix","docs","style","refactor","perf","test","build","ci","chore")) {
    if ($sections[$key].Count -gt 0) {
        $entry += "`n$($sectionLabels[$key])`n`n"
        $entry += ($sections[$key] -join "`n") + "`n"
    }
}

Write-Host "--- CHANGELOG 预览 ---"
Write-Host $entry
Write-Host "----------------------"
Write-Host ""

$confirm = Read-Host "确认发布 ${Version}? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "已取消"; exit 0
}

# 更新 CHANGELOG.md
if (Test-Path CHANGELOG.md) {
    $old = Get-Content CHANGELOG.md -Raw
    $header = ($old -split "`n" | Select-Object -First 4) -join "`n"
    $rest = ($old -split "`n" | Select-Object -Skip 4) -join "`n"
    Set-Content CHANGELOG.md -Value "$header`n`n$entry`n$rest" -NoNewline
} else {
    Set-Content CHANGELOG.md -Value "# Changelog`n`nAll notable changes to this project will be documented in this file.`n`n$entry"
}

# 更新 build.zig.zon
(Get-Content build.zig.zon) -replace '\.version = "[^"]*"', ".version = `"${Major}.${Minor}.${Patch}`"" | Set-Content build.zig.zon

# 提交、打 tag、推送
git add CHANGELOG.md build.zig.zon
git commit -m "chore(release): ${Version}"
git tag $Version
git push origin HEAD
git push origin $Version

Write-Host ""
Write-Host "✓ ${Version} 已发布！"
Write-Host "  CHANGELOG: CHANGELOG.md 已更新"
Write-Host "  GitHub Actions: $RepoUrl/actions"
Write-Host "  Release: $RepoUrl/releases"
