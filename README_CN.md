中文 | [English](README.md)

# Mowen CLI

一个用 Zig 编写的命令行工具，用于管理墨问平台的 Markdown 笔记。支持单文件管理和批量上传，**所有模式都支持元数据追踪和后续编辑**。

## 特性

- ✅ **单文件管理**：创建、编辑、设置隐私
- ✅ **批量上传**：自动扫描并上传所有 .md 文件
- ✅ **元数据追踪**：所有上传方式都保存 noteId，支持后续编辑
- ✅ **自动限速**：1 秒/文件，避免触发 API 限制
- ✅ **标签管理**：支持为笔记添加标签
- ✅ **灵活配置**：配置文件/环境变量/命令行参数
- ✅ **预览模式**：dry-run 模式，不实际上传
- ✅ **零依赖**：单文件可执行程序
- ✅ **跨平台**：Windows/Linux/macOS

## 快速开始

### 1. 下载

从 [Releases](https://github.com/ohmycli/mowen-cli/releases) 页面下载对应平台的可执行文件。

或者从源码编译：

```bash
# 需要 Zig 0.16.0
git clone https://github.com/ohmycli/mowen-cli.git
cd mowen-cli
zig build
```

编译后的可执行文件位于 `zig-out/bin/mowen-cli.exe`（Windows）或 `zig-out/bin/mowen-cli`（Linux/macOS）。

### 2. 配置

在可执行文件所在目录创建 `config.json` 文件：

```json
{
  "api_key": "your-api-key-here",
  "api_endpoint": "https://open.mowen.cn/api/open/api/v1",
  "timeout_ms": 30000,
  "default_tags": ["技术", "笔记"],
  "auto_publish": false
}
```

**配置项说明：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `api_key` | string | 是 | 墨问平台的 API 密钥 |
| `api_endpoint` | string | 是 | API 端点地址 |
| `timeout_ms` | number | 是 | 请求超时时间（毫秒），范围 1000-300000 |
| `default_tags` | array | 否 | 默认标签列表 |
| `auto_publish` | boolean | 否 | 是否自动发布笔记 |

**获取 API Key：**

1. 登录墨问平台
2. 进入个人设置 → API 管理
3. 创建新的 API 密钥
4. 复制密钥到配置文件

### 3. 使用

Mowen CLI 提供两种使用模式：

## 使用模式

### 模式一：单文件管理（推荐）

适合日常笔记管理，支持后续编辑和隐私设置。

#### 创建笔记

```bash
# 创建新笔记
mowen-cli create README.md

# 创建并自动发布
mowen-cli create README.md --auto-publish

# 创建并添加标签
mowen-cli create README.md --tags "技术,教程"

# 组合使用
mowen-cli create README.md --tags "博客,Zig" --auto-publish
```

创建成功后，笔记 ID 会自动保存到 `.mowen/metadata.json`，方便后续编辑。

#### 编辑笔记

```bash
# 编辑已创建的笔记（自动查找 noteId）
mowen-cli edit README.md

# 预览模式
mowen-cli edit README.md --dry-run
```

**注意**：只能编辑通过 `create` 命令创建的笔记。

#### 设置隐私

```bash
# 设置为私密
mowen-cli set-privacy README.md --privacy private

# 设置为公开
mowen-cli set-privacy README.md --privacy public

# 设置为规则可见
mowen-cli set-privacy README.md --privacy rule
```

### 模式二：批量上传

适合一次性导入大量文件，**现在也支持保存元数据**，可以后续编辑。

#### 基本批量上传

```bash
# 上传当前目录下所有 .md 文件
mowen-cli upload
```

输出示例：
```
Found 5 markdown file(s)

[1/5] Uploading ./README.md... OK (ID: note_abc123)
[2/5] Uploading ./guide.md... OK (ID: note_def456)
[3/5] Uploading ./tutorial.md... FAILED (FileReadError)
[4/5] Uploading ./api.md... OK (ID: note_ghi789)
[5/5] Uploading ./faq.md... OK (ID: note_jkl012)

✓ Upload complete: 4 succeeded, 1 failed
  Metadata saved to .mowen/metadata.json
  You can now use 'edit' and 'set-privacy' commands on these files.
```

**新特性**：批量上传后，所有成功上传的文件的 noteId 都会自动保存到 `.mowen/metadata.json`，你可以后续使用 `edit` 和 `set-privacy` 命令！

#### 预览模式

```bash
# 只扫描文件，不实际上传
mowen-cli upload --dry-run
```

输出示例：
```
Found 3 markdown file(s)

[DRY RUN MODE - No files will be uploaded]

  - ./README.md
  - ./guide.md
  - ./tutorial.md
```

#### 添加标签

```bash
# 为上传的笔记添加标签
mowen-cli upload --tags "博客,技术分享,Zig"
```

#### 自动发布

```bash
# 上传后自动发布笔记
mowen-cli upload --auto-publish
```

#### 组合使用

```bash
# 批量上传并自动发布，添加自定义标签
mowen-cli upload --auto-publish --tags "技术,笔记"

# 使用临时 API Key
mowen-cli upload --api-key YOUR_API_KEY --tags "重要"
```

### 两种模式对比

| 功能 | 单文件管理 (`create`/`edit`/`set-privacy`) | 批量上传 (`upload`) |
|------|-------------------------------------------|-------------------|
| **文件数量** | 单个文件 | 当前目录所有 .md 文件 |
| **元数据管理** | ✅ 保存到 `.mowen/metadata.json` | ✅ 保存到 `.mowen/metadata.json` |
| **后续编辑** | ✅ 支持 `edit` 命令 | ✅ 支持 `edit` 命令 |
| **隐私设置** | ✅ 支持 `set-privacy` 命令 | ✅ 支持 `set-privacy` 命令 |
| **使用场景** | 日常笔记管理 | 一次性批量导入 |
| **推荐度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**好消息**：现在两种模式都支持完整的元数据管理！你可以放心使用批量上传，之后依然可以编辑和设置隐私。

**建议**：
- 日常单个文件操作：使用 `create`/`edit`/`set-privacy` 命令
- 首次导入大量文件：使用 `upload` 命令，快速批量上传

## 配置优先级

当同一个配置项在多个地方都有设置时，优先级如下（从高到低）：

1. **命令行参数**：`--api-key`、`--auto-publish` 等
2. **环境变量**：`MOWEN_API_KEY`、`MOWEN_API_ENDPOINT`
3. **配置文件**：`config.json`
4. **默认值**

### 环境变量

支持以下环境变量：

```bash
# Windows PowerShell
$env:MOWEN_API_KEY="your-api-key"
$env:MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1"

# Linux/macOS
export MOWEN_API_KEY="your-api-key"
export MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1"
```

## 命令行参考

### 全局选项

```bash
mowen-cli --help              # 显示帮助信息
mowen-cli --version           # 显示版本信息
```

### create 命令

创建新笔记。

```bash
mowen-cli create <file> [options]

Options:
  --api-key <KEY>           覆盖配置的 API Key
  --tags <TAG1,TAG2>        添加标签（逗号分隔）
  --auto-publish            自动发布笔记
  --dry-run                 预览模式，不实际上传

Examples:
  mowen-cli create README.md
  mowen-cli create guide.md --tags "tech,tutorial" --auto-publish
  mowen-cli create doc.md --dry-run
```

### edit 命令

编辑已创建的笔记。

```bash
mowen-cli edit <file> [options]

Options:
  --api-key <KEY>           覆盖配置的 API Key
  --dry-run                 预览模式，不实际上传

Examples:
  mowen-cli edit README.md
  mowen-cli edit guide.md --dry-run
```

### set-privacy 命令

设置笔记隐私。

```bash
mowen-cli set-privacy <file> --privacy <public|private|rule> [options]

Options:
  --privacy <TYPE>          隐私类型：public（公开）、private（私密）、rule（规则可见）
  --api-key <KEY>           覆盖配置的 API Key
  --dry-run                 预览模式，不实际操作

Examples:
  mowen-cli set-privacy README.md --privacy private
  mowen-cli set-privacy guide.md --privacy public
```

### upload 命令

批量上传当前目录所有 .md 文件。

```bash
mowen-cli upload [options]

Options:
  --api-key <KEY>           覆盖配置的 API Key
  --tags <TAG1,TAG2>        添加标签（逗号分隔）
  --auto-publish            自动发布笔记
  --dry-run                 预览模式，不实际上传

Examples:
  mowen-cli upload
  mowen-cli upload --dry-run
  mowen-cli upload --tags "blog,tech" --auto-publish
  mowen-cli upload --api-key YOUR_KEY
```

## 支持的 Markdown 语法

目前支持以下 Markdown 语法：

- ✅ 标题（H1-H6）
- ✅ 段落
- ✅ 粗体、斜体
- ✅ 链接
- ✅ 列表（有序、无序）
- ✅ 代码块
- ✅ 引用
- ✅ 分隔线

## 常见问题

### Q: 上传失败怎么办？

A: 检查以下几点：
1. API Key 是否正确
2. 网络连接是否正常
3. API 端点地址是否正确
4. Markdown 文件格式是否正确

### Q: `create` 和 `upload` 有什么区别？

A: 
- **`create`**：单文件操作，适合日常笔记管理
- **`upload`**：批量操作，适合一次性导入大量文件

**现在两者都支持元数据保存**，都可以后续使用 `edit` 和 `set-privacy` 命令！

### Q: 批量上传后可以编辑吗？

A: **可以！** 从 v0.1.0 开始，`upload` 命令会自动保存所有成功上传文件的 noteId 到 `.mowen/metadata.json`。批量上传后，你可以使用：

```bash
# 编辑批量上传的文件
mowen-cli edit README.md

# 设置隐私
mowen-cli set-privacy README.md --privacy private
```

### Q: 为什么 `edit` 命令提示找不到元数据？

A: 可能的原因：
1. 文件从未通过 `create` 或 `upload` 命令上传过
2. `.mowen/metadata.json` 文件被删除或损坏
3. 文件路径发生了变化（移动或重命名）

**解决方案**：
- 如果是新文件，使用 `mowen-cli create <file>` 创建
- 如果文件已上传但元数据丢失，重新 `create` 会覆盖原笔记

### Q: 元数据保存在哪里？

A: 元数据保存在当前目录的 `.mowen/metadata.json` 文件中，记录了文件路径和对应的 noteId。

### Q: 可以上传子目录中的文件吗？

A: 
- **`create`/`edit`/`set-privacy`**：支持任意路径的文件
- **`upload`**：只扫描当前目录，不包括子目录

### Q: 上传速度为什么这么慢？

A: 为了避免触发 API 限流，程序会自动限速为每秒 1 个文件。这是正常行为。

### Q: 如何批量删除已上传的笔记？

A: 目前工具只支持上传功能，删除操作请在墨问平台网页端进行。

### Q: 配置文件必须和可执行文件在同一目录吗？

A: 是的。程序会在当前工作目录查找 `config.json`。建议将可执行文件和配置文件放在同一目录，并从该目录运行程序。

### Q: 批量上传时某个文件失败了怎么办？

A: 单个文件失败不会影响其他文件继续上传。上传完成后会显示成功和失败的数量。可以检查失败原因后重新运行。

## 开发

### 环境要求

- Zig 0.16.0 或更高版本

### 编译

```bash
# 开发模式编译
zig build

# 发布模式编译（优化）
zig build -Doptimize=ReleaseFast

# 运行测试
zig build test
```

### 项目结构

```
mowen-cli/
├── src/
│   ├── main.zig           # 主程序入口（CLI 命令处理）
│   ├── config.zig         # 配置管理（文件/环境变量/命令行）
│   ├── scanner.zig        # 文件扫描和读取
│   ├── parser.zig         # Markdown 词法和语法解析
│   ├── converter.zig      # Markdown → NoteAtom 转换
│   ├── note_atom.zig      # 墨问笔记格式定义和 JSON 序列化
│   ├── uploader.zig       # API 调用（create/edit/set-privacy）
│   └── metadata.zig       # 元数据管理（noteId 追踪）
├── tests/
│   ├── config_test.zig    # 配置模块测试
│   ├── parser_test.zig    # 解析器测试
│   └── scanner_test.zig   # 扫描器测试
├── build.zig              # 构建脚本
├── config.example.json    # 配置文件示例
└── README.md              # 本文档
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 更新日志

### v0.3.1 (2026-04-29)

**改进**
- ✅ 控制台和 trace 日志现在默认输出 ANSI 颜色。
- ✅ `mowen-cli --version` 现在显示 `0.3.1`。

### v0.1.0 (2026-04-22)

**核心功能**
- ✅ 单文件管理：`create`、`edit`、`set-privacy` 命令
- ✅ 批量上传：`upload` 命令，自动扫描当前目录
- ✅ **元数据管理**：`upload` 命令现在也会保存 noteId，支持后续编辑！
- ✅ Markdown 解析：支持标题、段落、粗体、链接、引用、代码块、分隔线
- ✅ 配置管理：支持配置文件、环境变量、命令行参数
- ✅ 限频控制：自动 1秒/次，避免触发 API 限制
- ✅ 预览模式：dry-run 支持

**测试**
- ✅ 27 个单元测试，全部通过
- ✅ 配置管理测试
- ✅ Markdown 解析器测试
- ✅ 文件扫描器测试

**重要改进**
- 🎉 批量上传现在也支持元数据保存，可以后续编辑和设置隐私

---

**注意**：本工具仅供学习和个人使用，请遵守墨问平台的使用条款和 API 限制。
