# 墨问 CLI 工具 - 设计文档

## 1. 系统架构

### 1.1 整体架构

```
                    mowen-cli
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   ┌─────────┐    ┌──────────┐    ┌─────────┐
   │  CLI    │    │  Core    │    │ Effects │
   │ Layer   │───▶│ Business │───▶│ Layer   │
   └─────────┘    └──────────┘    └─────────┘
        │              │                │
        │              │                │
   参数解析        业务逻辑          外部依赖
   帮助信息        数据转换          (HTTP/FS)
```

### 1.2 分层设计

#### CLI Layer (用户交互层)
负责与用户交互，处理命令行参数，格式化输出。

**模块**:
- `main.zig` - 程序入口
- `cli_args.zig` - 命令行参数解析
- `cli_output.zig` - 输出格式化（进度、结果）

#### 进度显示实现

```zig
// cli_output.zig

// 显示进度（同行更新）
pub fn printProgress(current: usize, total: usize, file: []const u8) void {
    std.debug.print("\r[{d}/{d}] {s} ...", .{current, total, file});
}

// 显示成功
pub fn printSuccess(current: usize, total: usize, file: []const u8, note_id: []const u8) void {
    std.debug.print("\r[{d}/{d}] {s} ✓ (note_id: {s})\n", .{current, total, file, note_id});
}

// 显示失败
pub fn printFailure(current: usize, total: usize, file: []const u8, error_msg: []const u8) void {
    std.debug.print("\r[{d}/{d}] {s} ✗ (错误: {s})\n", .{current, total, file, error_msg});
}

// 显示警告
pub fn printWarning(current: usize, total: usize, file: []const u8, warning_msg: []const u8) void {
    std.debug.print("\r[{d}/{d}] {s} ⚠ (警告: {s})\n", .{current, total, file, warning_msg});
}
```

#### Core Business Layer (核心业务层)
实现核心业务逻辑，不依赖具体的外部实现。

**模块**:
- `config.zig` - 配置管理
- `scanner.zig` - 文件扫描
- `md_parser.zig` - Markdown 解析器
- `note_atom.zig` - NoteAtom 数据结构
- `converter.zig` - MD → NoteAtom 转换
- `uploader.zig` - 上传协调器
- `result.zig` - 结果汇总

#### Effects Layer (外部依赖层)
封装外部依赖，提供统一接口。

**依赖**:
- `http_client.zig` - HTTP 客户端 (from zig-framework)
- `file_system.zig` - 文件系统 (from zig-framework)
- `logger.zig` - 日志 (from zig-framework)

## 2. 核心模块设计

### 2.1 配置管理 (config.zig)

#### 数据结构

```zig
pub const Config = struct {
    api_key: []const u8,
    api_endpoint: []const u8,  // 默认: https://open.mowen.cn
    timeout_ms: u32,            // 默认: 30000
    
    pub fn deinit(self: *Config, allocator: Allocator) void;
};
```

#### 功能接口

```zig
// 从配置文件加载
pub fn loadConfig(allocator: Allocator, path: ?[]const u8) !Config;

// 验证配置有效性
pub fn validateConfig(config: *const Config) !void;

// 获取默认配置文件路径（跨平台）
pub fn getDefaultConfigPath(allocator: Allocator) ![]const u8;
```

#### 跨平台配置路径

```zig
pub fn getDefaultConfigPath(allocator: Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        // Windows: %USERPROFILE%\.mowen\config.json
        const home = std.os.getenv("USERPROFILE") orelse return error.HomeNotFound;
        return std.fs.path.join(allocator, &[_][]const u8{ home, ".mowen", "config.json" });
    } else {
        // Unix: ~/.mowen/config.json
        const home = std.os.getenv("HOME") orelse return error.HomeNotFound;
        return std.fs.path.join(allocator, &[_][]const u8{ home, ".mowen", "config.json" });
    }
}
```

#### 配置文件格式

```json
{
  "api_key": "your-api-key-here",
  "api_endpoint": "https://open.mowen.cn",
  "timeout_ms": 30000
}
```

### 2.2 文件扫描 (scanner.zig)

#### 数据结构

```zig
pub const ScanResult = struct {
    files: [][]const u8,  // 文件路径列表
    count: usize,
    
    pub fn deinit(self: *ScanResult, allocator: Allocator) void;
};
```

#### 功能接口

```zig
// 扫描指定目录的 .md 文件
pub fn scanMarkdownFiles(
    allocator: Allocator,
    dir_path: []const u8
) !ScanResult;

// 检查文件是否为 .md 文件
fn isMarkdownFile(file_name: []const u8) bool;

// 检查文件是否为空
fn isEmptyFile(file_path: []const u8) !bool;
```

#### 特殊处理

- **空文件**: 跳过空文件（大小为 0），记录警告信息
- **隐藏文件**: 跳过以 `.` 开头的文件（Unix 风格）
- **权限错误**: 跳过无法读取的文件，记录错误

### 2.3 Markdown 解析器 (md_parser.zig)

这是最复杂的模块，负责将 Markdown 文本解析为 AST。

#### 数据结构

```zig
pub const MdNode = union(enum) {
    document: Document,
    heading: Heading,
    paragraph: Paragraph,
    text: Text,
    bold: Bold,
    link: Link,
    quote: Quote,
    
    pub fn deinit(self: *MdNode, allocator: Allocator) void;
};

pub const Document = struct {
    children: []MdNode,
};

pub const Heading = struct {
    level: u8,  // 1-6
    children: []MdNode,
};

pub const Paragraph = struct {
    children: []MdNode,
};

pub const Text = struct {
    content: []const u8,
};

pub const Bold = struct {
    children: []MdNode,
};

pub const Link = struct {
    url: []const u8,
    children: []MdNode,
};

pub const Quote = struct {
    children: []MdNode,
};
```

#### 功能接口

```zig
// 解析 Markdown 文本
pub fn parse(allocator: Allocator, content: []const u8) !MdNode;

// 词法分析
fn tokenize(allocator: Allocator, content: []const u8) ![]Token;

// 语法分析
fn parseTokens(allocator: Allocator, tokens: []Token) !MdNode;
```

#### 支持的语法

| Markdown 语法 | 示例 | 说明 |
|--------------|------|------|
| 标题 | `# 标题` | H1-H6 |
| 段落 | 普通文本 | 空行分隔 |
| 粗体 | `**文本**` | 双星号 |
| 链接 | `[文本](url)` | 标准链接 |
| 引用 | `> 文本` | 引用块 |

**注意**: MVP 版本暂不支持斜体 `*文本*`，因为单星号与粗体的双星号容易冲突，会增加解析复杂度。

#### 解析失败降级

当解析失败时，自动降级为纯文本模式：
```zig
pub fn parseWithFallback(allocator: Allocator, content: []const u8) !MdNode {
    return parse(allocator, content) catch |err| {
        // 降级为纯文本
        std.log.warn("MD parse failed, fallback to plain text: {}", .{err});
        return createPlainTextDocument(allocator, content);
    };
}

fn createPlainTextDocument(allocator: Allocator, content: []const u8) !MdNode {
    // 整个内容作为单个段落
    const text_node = MdNode{ .text = .{ .content = content } };
    const para_node = MdNode{ .paragraph = .{ .children = &[_]MdNode{text_node} } };
    return MdNode{ .document = .{ .children = &[_]MdNode{para_node} } };
}
```

### 2.4 NoteAtom 数据结构 (note_atom.zig)

#### 数据结构

```zig
pub const NoteAtom = struct {
    type: []const u8,           // "doc", "paragraph", "text", etc.
    text: ?[]const u8,          // 文本内容
    content: ?[]NoteAtom,       // 子节点
    marks: ?[]NoteAtom,         // 样式标记
    attrs: ?std.StringHashMap([]const u8),  // 属性
    
    pub fn deinit(self: *NoteAtom, allocator: Allocator) void;
};
```

#### 构造函数

```zig
// 创建 doc 节点
pub fn createDoc(allocator: Allocator, content: []NoteAtom) !NoteAtom;

// 创建 paragraph 节点
pub fn createParagraph(allocator: Allocator, content: []NoteAtom) !NoteAtom;

// 创建 text 节点
pub fn createText(
    allocator: Allocator,
    text: []const u8,
    marks: ?[]NoteAtom
) !NoteAtom;

// 创建 bold 标记
pub fn createBoldMark(allocator: Allocator) !NoteAtom;

// 创建 link 标记
pub fn createLinkMark(allocator: Allocator, href: []const u8) !NoteAtom;

// 创建 highlight 标记
pub fn createHighlightMark(allocator: Allocator) !NoteAtom;

// 创建 quote 节点
pub fn createQuote(allocator: Allocator, content: []NoteAtom) !NoteAtom;
```

#### JSON 序列化

```zig
// 转换为 JSON 字符串
pub fn toJson(
    self: *const NoteAtom,
    allocator: Allocator
) ![]const u8;
```

**实现注意事项**:

由于 NoteAtom 是递归结构，不能直接使用 `std.json.stringify()`，需要实现自定义序列化：

```zig
pub fn toJson(self: *const NoteAtom, allocator: Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try serializeNoteAtom(self, buffer.writer());
    return buffer.toOwnedSlice();
}

fn serializeNoteAtom(atom: *const NoteAtom, writer: anytype) !void {
    try writer.writeAll("{");
    
    // type 字段（必需）
    try writer.print("\"type\":\"{s}\"", .{atom.type});
    
    // text 字段（可选）
    if (atom.text) |text| {
        try writer.print(",\"text\":\"{s}\"", .{escapeJson(text)});
    }
    
    // content 字段（可选，递归）
    if (atom.content) |content| {
        try writer.writeAll(",\"content\":[");
        for (content, 0..) |child, i| {
            if (i > 0) try writer.writeAll(",");
            try serializeNoteAtom(&child, writer);
        }
        try writer.writeAll("]");
    }
    
    // marks 字段（可选，递归）
    if (atom.marks) |marks| {
        try writer.writeAll(",\"marks\":[");
        for (marks, 0..) |mark, i| {
            if (i > 0) try writer.writeAll(",");
            try serializeNoteAtom(&mark, writer);
        }
        try writer.writeAll("]");
    }
    
    // attrs 字段（可选）
    if (atom.attrs) |attrs| {
        try writer.writeAll(",\"attrs\":{");
        var iter = attrs.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try writer.writeAll(",");
            try writer.print("\"{s}\":\"{s}\"", .{entry.key_ptr.*, entry.value_ptr.*});
            first = false;
        }
        try writer.writeAll("}");
    }
    
    try writer.writeAll("}");
}

// JSON 字符串转义
fn escapeJson(text: []const u8) []const u8 {
    // 转义 ", \, 换行等特殊字符
    // 简化实现，实际需要完整的转义逻辑
    return text;
}
```

### 2.5 MD → NoteAtom 转换器 (converter.zig)

#### 功能接口

```zig
// 转换 MD AST 为 NoteAtom
pub fn convert(
    allocator: Allocator,
    md_ast: *const MdNode
) !NoteAtom;

// 转换单个节点
fn convertNode(
    allocator: Allocator,
    node: *const MdNode
) !NoteAtom;
```

#### 转换规则

| MD Node | NoteAtom |
|---------|----------|
| Document | `{ type: "doc", content: [...] }` |
| Heading | `{ type: "paragraph", content: [{ type: "text", text: "...", marks: [{ type: "bold" }] }] }` |
| Paragraph | `{ type: "paragraph", content: [...] }` |
| Text | `{ type: "text", text: "..." }` |
| Bold | `marks: [{ type: "bold" }]` |
| Link | `marks: [{ type: "link", attrs: { href: "..." } }]` |
| Quote | `{ type: "quote", content: [...] }` |

### 2.6 上传器 (uploader.zig)

#### 数据结构

```zig
pub const UploadRequest = struct {
    body: NoteAtom,
    settings: ?Settings,
};

pub const Settings = struct {
    auto_publish: bool = false,
    tags: ?[][]const u8 = null,
};

pub const UploadResult = struct {
    success: bool,
    note_id: ?[]const u8,
    error_msg: ?[]const u8,
    
    pub fn deinit(self: *UploadResult, allocator: Allocator) void;
};
```

#### 功能接口

```zig
// 上传笔记
pub fn upload(
    allocator: Allocator,
    client: HttpClient,
    config: *const Config,
    request: UploadRequest
) !UploadResult;

// 构建 HTTP 请求
fn buildHttpRequest(
    allocator: Allocator,
    config: *const Config,
    request: UploadRequest
) !HttpRequest;

// 解析 HTTP 响应
fn parseHttpResponse(
    allocator: Allocator,
    response: HttpResponse
) !UploadResult;
```

### 2.7 结果汇总 (result.zig)

#### 数据结构

```zig
pub const BatchResult = struct {
    total: usize,
    success: usize,
    failed: usize,
    results: []FileResult,
    
    pub fn deinit(self: *BatchResult, allocator: Allocator) void;
};

pub const FileResult = struct {
    file_path: []const u8,
    success: bool,
    note_id: ?[]const u8,
    error_msg: ?[]const u8,
};
```

#### 功能接口

```zig
// 创建结果收集器
pub fn init(allocator: Allocator) BatchResult;

// 添加单个文件结果
pub fn addResult(
    self: *BatchResult,
    file_path: []const u8,
    result: UploadResult
) !void;

// 获取汇总信息
pub fn getSummary(self: *const BatchResult) Summary;

// 打印报告
pub fn printReport(self: *const BatchResult, writer: anytype) !void;
```

## 3. 数据流设计

### 3.1 初始化阶段

```
┌──────────┐
│ 读取配置 │
└────┬─────┘
     │
     ▼
┌──────────┐
│ 验证配置 │
└────┬─────┘
     │
     ▼
┌──────────┐
│扫描文件  │
└────┬─────┘
     │
     ▼
[file1.md, file2.md, ...]
```

### 3.2 处理阶段 (for each file)

```
┌──────────┐
│读取文件  │
└────┬─────┘
     │
     ▼
┌──────────┐
│解析 MD   │ ← md_parser.parse()
└────┬─────┘
     │
     ▼
┌──────────┐
│转换为    │ ← converter.convert()
│NoteAtom  │
└────┬─────┘
     │
     ▼
┌──────────┐
│序列化    │ ← note_atom.toJson()
│JSON      │
└────┬─────┘
     │
     ▼
┌──────────┐
│HTTP POST │ ← uploader.upload()
└────┬─────┘
     │
     ▼
┌──────────┐
│记录结果  │ ← result.addResult()
└────┬─────┘
     │
     ▼
┌──────────┐
│ Sleep 1s │ ← 限频控制
└──────────┘
```

### 3.3 汇总阶段

```
┌──────────┐
│生成报告  │ ← result.getSummary()
└────┬─────┘
     │
     ▼
┌──────────┐
│打印结果  │ ← result.printReport()
└──────────┘
```

## 4. 错误处理设计

### 4.1 错误类型定义

```zig
pub const MowenError = error {
    // 配置错误
    ConfigNotFound,
    ConfigInvalid,
    ApiKeyMissing,
    
    // 文件错误
    FileNotFound,
    FileReadError,
    InvalidMarkdown,
    
    // 网络错误
    NetworkError,
    TimeoutError,
    
    // API 错误
    AuthenticationError,    // 401
    RateLimitError,         // 429
    QuotaExceededError,     // 403 + Quota
    ServerError,            // 500
    
    // 解析错误
    JsonParseError,
    InvalidResponse,
};
```

### 4.2 错误处理策略

| 错误类型 | 处理方式 |
|---------|---------|
| 配置错误 | 立即退出，提示用户 |
| 文件错误 | 跳过该文件，记录到失败列表 |
| 网络错误 | 跳过该文件，记录到失败列表 |
| API 限频 (429) | 等待后重试 |
| API 配额不足 (403) | 停止上传，提示配额不足 |
| 其他 API 错误 | 跳过该文件，记录错误信息 |

### 4.3 错误信息格式

```zig
pub const ErrorInfo = struct {
    error_type: []const u8,
    error_reason: []const u8,
    suggestion: []const u8,
};
```

## 5. API 集成设计

### 5.1 请求格式

```json
POST /api/open/api/v1/note/create
Headers:
  Authorization: Bearer {API_KEY}
  Content-Type: application/json

Body:
{
  "body": {
    "type": "doc",
    "content": [...]
  },
  "settings": {
    "autoPublish": true,
    "tags": ["tag1", "tag2"]
  }
}
```

### 5.2 响应格式

**成功 (200)**:
```json
{
  "noteId": "abc123"
}
```

**失败 (4xx/5xx)**:
```json
{
  "code": 404,
  "reason": "NOT_FOUND",
  "message": "详细错误信息",
  "metadata": {}
}
```

### 5.3 限频控制

```zig
// 上传后等待 1 秒
fn rateLimitDelay() void {
    std.time.sleep(1 * std.time.ns_per_s);
}
```

### 5.4 重试策略

#### API 限频重试 (429)

```zig
pub fn uploadWithRetry(
    allocator: Allocator,
    client: HttpClient,
    config: *const Config,
    request: UploadRequest,
) !UploadResult {
    const retry_delays = [_]u64{ 2, 5, 10 }; // 秒
    
    var attempt: usize = 0;
    while (attempt <= retry_delays.len) : (attempt += 1) {
        const result = upload(allocator, client, config, request) catch |err| {
            if (err == error.RateLimitError and attempt < retry_delays.len) {
                const delay_sec = retry_delays[attempt];
                std.log.warn("Rate limited, retry after {d}s (attempt {d}/3)", .{delay_sec, attempt + 1});
                std.time.sleep(delay_sec * std.time.ns_per_s);
                continue;
            }
            return err;
        };
        return result;
    }
    
    return error.RateLimitExceeded;
}
```

#### 网络错误重试

```zig
pub fn uploadWithNetworkRetry(
    allocator: Allocator,
    client: HttpClient,
    config: *const Config,
    request: UploadRequest,
) !UploadResult {
    return upload(allocator, client, config, request) catch |err| {
        if (err == error.TimeoutError) {
            std.log.warn("Timeout, retry once after 3s", .{});
            std.time.sleep(3 * std.time.ns_per_s);
            return upload(allocator, client, config, request);
        }
        return err;
    };
}
```

## 6. 性能优化

### 6.1 内存管理

- 使用 Arena Allocator 管理临时内存
- 及时释放不再使用的资源
- 避免大文件一次性加载到内存

### 6.2 并发处理

当前版本不支持并发（受限于 API 限频 1次/秒），未来可考虑：
- 多文件并行解析
- 异步 I/O

### 6.3 缓存策略

- 配置文件只读取一次
- HTTP 连接复用

## 7. 测试策略

### 7.1 单元测试

每个模块都应有单元测试：
- `config_test.zig`
- `scanner_test.zig`
- `md_parser_test.zig`
- `note_atom_test.zig`
- `converter_test.zig`
- `uploader_test.zig`

### 7.2 集成测试

测试端到端流程：
- 读取配置 → 扫描文件 → 解析 → 转换 → 上传
- 使用 mock HTTP 客户端

### 7.3 真实 API 测试

使用真实的墨问 API 进行测试：
- 准备测试账号和 API Key
- 测试各种场景（成功、失败、限频等）

## 8. 项目结构

```
mowen-cli/
├── build.zig              # 构建脚本
├── build.zig.zon          # 依赖配置
├── README.md              # 项目说明
├── docs/                  # 文档目录
│   ├── requirements.md    # 需求文档
│   ├── design.md          # 设计文档
│   └── tasks.md           # 任务列表
├── src/                   # 源代码
│   ├── main.zig           # 程序入口
│   ├── cli_args.zig       # CLI 参数解析
│   ├── cli_output.zig     # 输出格式化
│   ├── config.zig         # 配置管理
│   ├── scanner.zig        # 文件扫描
│   ├── md_parser.zig      # Markdown 解析
│   ├── note_atom.zig      # NoteAtom 结构
│   ├── converter.zig      # 转换器
│   ├── uploader.zig       # 上传器
│   └── result.zig         # 结果汇总
└── tests/                 # 测试代码
    ├── config_test.zig
    ├── scanner_test.zig
    ├── md_parser_test.zig
    ├── note_atom_test.zig
    ├── converter_test.zig
    └── integration_test.zig
```

## 9. 依赖管理

### 9.1 外部依赖

```zig
// build.zig.zon
.{
    .name = "mowen-cli",
    .version = "0.1.0",
    .dependencies = .{
        .framework = .{
            .path = "../zig-framework",
        },
    },
}
```

### 9.2 框架能力复用

从 zig-framework 复用：
- `HttpClient` - HTTP 客户端
- `FileSystem` - 文件系统操作
- `Logger` - 日志记录
- `AppContext` - 应用上下文

## 10. 安全考虑

### 10.1 API Key 保护

- 不硬编码在代码中
- 从配置文件读取
- 建议用户设置文件权限 (chmod 600)

### 10.2 输入验证

- 验证配置文件格式
- 验证文件路径
- 验证 API 响应

### 10.3 错误信息

- 不在日志中输出 API Key
- 不在错误信息中泄露敏感信息

## 11. 扩展性设计

### 11.1 插件化

未来可考虑支持插件：
- 自定义 Markdown 解析器
- 自定义转换规则
- 自定义上传策略

### 11.2 配置扩展

支持更多配置项：
- 代理设置
- 重试策略
- 日志级别

### 11.3 输出格式

支持多种输出格式：
- 文本格式（默认）
- JSON 格式
- CSV 格式
