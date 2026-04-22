# Mowen CLI

一个用 Zig 编写的命令行工具，用于将本地 Markdown 文件批量上传到墨问平台。

## 特性

- ✅ 自动扫描当前目录下的所有 Markdown 文件
- ✅ 批量上传，自动限速（1 秒/文件）
- ✅ 支持标签管理
- ✅ 灵活的配置方式（配置文件/环境变量/命令行参数）
- ✅ 预览模式（dry-run）
- ✅ 零依赖，单文件可执行程序
- ✅ 跨平台支持（Windows/Linux/macOS）

## 快速开始

### 1. 下载

从 [Releases](https://github.com/your-repo/mowen-cli/releases) 页面下载对应平台的可执行文件。

或者从源码编译：

```bash
# 需要 Zig 0.16.0
git clone https://github.com/your-repo/mowen-cli.git
cd mowen-cli
zig build
```

编译后的可执行文件位于 `zig-out/bin/mowen-cli.exe`（Windows）或 `zig-out/bin/mowen-cli`（Linux/macOS）。

### 2. 配置

在可执行文件所在目录创建 `config.json` 文件：

```json
{
  "api_key": "your-api-key-here",
  "api_endpoint": "https://open.mowen.cn/api/open/api/v1/note/create",
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

将 Markdown 文件放到可执行文件所在目录，然后运行：

```bash
# Windows
.\mowen-cli.exe

# Linux/macOS
./mowen-cli
```

## 使用示例

### 基本使用

```bash
# 上传当前目录下所有 .md 文件
mowen-cli
```

### 预览模式

```bash
# 只扫描文件，不实际上传
mowen-cli --dry-run
```

输出示例：
```
Found 3 markdown file(s)

[DRY RUN MODE - No files will be uploaded]

  - 文档1.md
  - 文档2.md
  - README.md
```

### 添加标签

```bash
# 为上传的笔记添加标签（会覆盖配置文件中的 default_tags）
mowen-cli --tags "博客,技术分享,Zig"
```

### 自动发布

```bash
# 上传后自动发布笔记
mowen-cli --auto-publish
```

### 临时指定 API Key

```bash
# 使用命令行参数指定 API Key（优先级最高）
mowen-cli --api-key YOUR_API_KEY
```

### 组合使用

```bash
# 上传并自动发布，添加自定义标签
mowen-cli --auto-publish --tags "重要,待办"
```

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
$env:MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1/note/create"

# Linux/macOS
export MOWEN_API_KEY="your-api-key"
export MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1/note/create"
```

## 命令行选项

```
Usage: mowen-cli [options]

Upload Markdown files from current directory to Mowen platform.

Options:
  -h, --help           显示帮助信息
  -v, --version        显示版本信息
  --dry-run            预览模式，不实际上传
  --api-key <key>      指定 API Key（覆盖配置文件和环境变量）
  --tags <tags>        指定标签，逗号分隔（例如："tag1,tag2"）
  --auto-publish       自动发布上传的笔记

Examples:
  mowen-cli                              # 上传所有 .md 文件
  mowen-cli --dry-run                    # 预览模式
  mowen-cli --tags "blog,tech"           # 添加标签
  mowen-cli --api-key YOUR_KEY           # 指定 API Key
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

### Q: 可以上传子目录中的文件吗？

A: 当前版本只扫描当前目录，不包括子目录。如需上传子目录文件，请先切换到对应目录。

### Q: 上传速度为什么这么慢？

A: 为了避免触发 API 限流，程序会自动限速为每秒 1 个文件。这是正常行为。

### Q: 如何批量删除已上传的笔记？

A: 目前工具只支持上传功能，删除操作请在墨问平台网页端进行。

### Q: 配置文件必须和可执行文件在同一目录吗？

A: 是的。程序会在当前工作目录查找 `config.json`。建议将可执行文件和配置文件放在同一目录，并从该目录运行程序。

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
│   ├── main.zig           # 主程序入口
│   ├── config.zig         # 配置管理
│   ├── scanner.zig        # 文件扫描
│   ├── converter.zig      # Markdown 转换
│   ├── note_atom.zig      # 墨问笔记格式定义
│   └── uploader.zig       # 上传逻辑
├── tests/
│   └── config_test.zig    # 配置模块测试
├── build.zig              # 构建脚本
├── config.example.json    # 配置文件示例
└── README.md              # 本文档
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 更新日志

### v0.1.0 (2024-01-XX)

- 初始版本
- 支持基本的 Markdown 上传功能
- 支持配置文件、环境变量、命令行参数
- 支持标签和自动发布
- 支持预览模式

---

**注意**：本工具仅供学习和个人使用，请遵守墨问平台的使用条款和 API 限制。
