# 墨问 CLI 工具 - 任务列表

## 任务概览

本文档将项目拆分为 9 个阶段，共 30+ 个具体任务。

**总工作量估算**:
- 乐观估计: 12-15 天
- 现实估计: 18-22 天
- 悲观估计: 25-30 天

**注意**: Markdown 解析器的复杂度较高，时间估算已相应调整。

## Phase 1: 项目基础设施

**预计时间**: 1-2 天

### Task 1.1: 创建项目结构

**描述**: 初始化项目目录和基础文件

**工作内容**:
- [ ] 创建项目目录结构
  ```
  mowen-cli/
  ├── build.zig
  ├── build.zig.zon
  ├── README.md
  ├── docs/
  ├── src/
  └── tests/
  ```
- [ ] 编写 `build.zig` 构建脚本
- [ ] 编写 `build.zig.zon` 依赖配置（引入 zig-framework）
- [ ] 创建 `README.md` 基础说明
- [ ] 验证项目可以编译

**验收标准**:
- 项目结构完整
- `zig build` 可以成功执行
- 依赖 zig-framework 正确引入

**优先级**: P0（必须）

---

### Task 1.2: 配置管理模块

**描述**: 实现配置文件的读取、验证和管理

**工作内容**:
- [ ] 创建 `src/config.zig`
- [ ] 定义 `Config` 数据结构
- [ ] 实现 `loadConfig()` - 从 JSON 文件读取配置
- [ ] 实现 `validateConfig()` - 验证配置有效性
- [ ] 实现 `getDefaultConfigPath()` - 获取默认配置路径
- [ ] 处理配置文件不存在的情况
- [ ] 处理配置格式错误的情况
- [ ] 编写单元测试 `tests/config_test.zig`

**技术细节**:
- 使用 `std.json.parseFromSlice()` 解析 JSON
- 配置文件路径: 
  - Linux/macOS: `~/.mowen/config.json`
  - Windows: `%USERPROFILE%\.mowen\config.json`
- 必需字段: `api_key`
- 可选字段: `api_endpoint`, `timeout_ms`
- 跨平台路径处理（见 design.md）

**验收标准**:
- 能够正确读取配置文件
- 配置验证逻辑完善
- 错误信息清晰友好
- 单元测试通过

**优先级**: P0（必须）

---

### Task 1.3: 错误处理框架

**描述**: 定义统一的错误类型和错误处理机制

**工作内容**:
- [ ] 定义 `MowenError` 错误类型
- [ ] 实现错误信息格式化函数
- [ ] 实现错误转换函数（HTTP 状态码 → MowenError）
- [ ] 定义错误处理策略

**技术细节**:
```zig
pub const MowenError = error {
    ConfigNotFound,
    ConfigInvalid,
    ApiKeyMissing,
    FileNotFound,
    FileReadError,
    InvalidMarkdown,
    NetworkError,
    TimeoutError,
    AuthenticationError,
    RateLimitError,
    QuotaExceededError,
    ServerError,
    JsonParseError,
    InvalidResponse,
};
```

**验收标准**:
- 错误类型定义完整
- 错误信息格式统一
- 错误处理策略清晰

**优先级**: P0（必须）

---

## Phase 2: 文件处理

**预计时间**: 2-3 天

### Task 2.1: 文件扫描器

**描述**: 实现扫描目录下 .md 文件的功能

**工作内容**:
- [ ] 创建 `src/scanner.zig`
- [ ] 定义 `ScanResult` 数据结构
- [ ] 实现 `scanMarkdownFiles()` - 扫描指定目录
- [ ] 实现 `isMarkdownFile()` - 判断文件是否为 .md
- [ ] 实现 `isEmptyFile()` - 检查文件是否为空
- [ ] 处理目录不存在的情况
- [ ] 处理权限错误的情况
- [ ] 跳过空文件和隐藏文件
- [ ] 编写单元测试 `tests/scanner_test.zig`

**技术细节**:
- 使用 `std.fs.cwd().openDir()` 打开目录
- 使用 `dir.iterate()` 遍历文件
- 只扫描当前目录，不递归子目录
- 过滤条件: 文件扩展名为 `.md`

**验收标准**:
- 能够正确扫描 .md 文件
- 返回文件路径列表
- 错误处理完善
- 单元测试通过

**优先级**: P0（必须）

---

### Task 2.2: 文件读取

**描述**: 实现读取文件内容的功能

**工作内容**:
- [ ] 使用 zig-framework 的 `FileSystem`
- [ ] 实现文件内容读取
- [ ] 处理文件不存在的情况
- [ ] 处理文件过大的情况（设置合理的大小限制）
- [ ] 处理编码问题（假设 UTF-8）

**技术细节**:
- 使用 `std.fs.cwd().readFileAlloc()` 读取文件
- 设置文件大小限制（如 10MB）
- 返回文件内容字符串

**验收标准**:
- 能够正确读取文件内容
- 错误处理完善
- 内存管理正确

**优先级**: P0（必须）

---

## Phase 3: Markdown 解析

**预计时间**: 5-8 天 ⚠️ **最复杂的部分**

**重要说明**: MVP 版本简化了语法支持，不支持斜体（`*`），以降低解析复杂度。

### Task 3.1: MD 词法分析器

**描述**: 实现 Markdown 的词法分析（Tokenizer）

**工作内容**:
- [ ] 创建 `src/md_parser.zig`
- [ ] 定义 `Token` 类型
- [ ] 实现 `tokenize()` 函数
- [ ] 识别以下标记:
  - 标题标记 (`#`, `##`, etc.)
  - 粗体标记 (`**`)
  - 链接标记 (`[`, `]`, `(`, `)`)
  - 引用标记 (`>`)
  - 换行符
  - 普通文本
- [ ] 编写单元测试

**注意**: MVP 版本不支持斜体 `*`，避免与粗体 `**` 冲突。

**技术细节**:
```zig
pub const TokenType = enum {
    heading,      // #, ##, ###, etc.
    bold_start,   // **
    bold_end,     // **
    link_start,   // [
    link_text_end,// ]
    link_url_start, // (
    link_url_end, // )
    quote,        // >
    newline,
    text,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    position: usize,
};
```

**注意**: 移除了 `italic_start` 和 `italic_end`，简化解析逻辑。

**验收标准**:
- 能够正确识别所有标记
- 处理边界情况（如嵌套、转义）
- 单元测试覆盖率 > 80%

**优先级**: P0（必须）

---

### Task 3.2: MD 语法解析器

**描述**: 实现 Markdown 的语法分析（Parser），构建 AST

**工作内容**:
- [ ] 定义 `MdNode` 数据结构
- [ ] 实现 `parseTokens()` 函数
- [ ] 实现各种节点的解析:
  - Document
  - Heading
  - Paragraph
  - Text
  - Bold
  - Link
  - Quote
- [ ] 处理嵌套结构（基本嵌套，不支持复杂嵌套）
- [ ] 实现解析失败降级机制
- [ ] 编写单元测试

**注意**: 移除了 Italic 节点，简化实现。

**技术细节**:
- 使用递归下降解析
- 构建树形结构
- 处理优先级和结合性

**验收标准**:
- 能够正确解析 Markdown 语法
- 生成正确的 AST
- 处理复杂嵌套情况
- 单元测试通过

**优先级**: P0（必须）

---

### Task 3.3: 解析器集成

**描述**: 整合词法分析器和语法分析器

**工作内容**:
- [ ] 实现 `parse()` 函数（对外接口）
- [ ] 整合 tokenize 和 parseTokens
- [ ] 端到端测试
- [ ] 性能测试

**技术细节**:
```zig
pub fn parse(allocator: Allocator, content: []const u8) !MdNode {
    const tokens = try tokenize(allocator, content);
    defer allocator.free(tokens);
    return try parseTokens(allocator, tokens);
}
```

**验收标准**:
- 能够从 Markdown 文本直接生成 AST
- 端到端测试通过
- 性能满足要求（< 1s for 1MB file）

**优先级**: P0（必须）

---

## Phase 4: NoteAtom 转换

**预计时间**: 2-3 天

### Task 4.1: NoteAtom 数据结构

**描述**: 实现 NoteAtom 数据结构和构造函数

**工作内容**:
- [ ] 创建 `src/note_atom.zig`
- [ ] 定义 `NoteAtom` 结构体
- [ ] 实现构造函数:
  - `createDoc()`
  - `createParagraph()`
  - `createText()`
  - `createBoldMark()`
  - `createLinkMark()`
  - `createHighlightMark()`
  - `createQuote()`
- [ ] 实现 `deinit()` 释放内存
- [ ] 编写单元测试

**技术细节**:
```zig
pub const NoteAtom = struct {
    type: []const u8,
    text: ?[]const u8,
    content: ?[]NoteAtom,
    marks: ?[]NoteAtom,
    attrs: ?std.StringHashMap([]const u8),
    
    pub fn deinit(self: *NoteAtom, allocator: Allocator) void;
};
```

**验收标准**:
- 数据结构定义正确
- 构造函数功能完整
- 内存管理正确
- 单元测试通过

**优先级**: P0（必须）

---

### Task 4.2: JSON 序列化

**描述**: 实现 NoteAtom 到 JSON 的序列化

**工作内容**:
- [ ] 实现 `toJson()` 函数
- [ ] 处理递归结构
- [ ] 处理可选字段（null 值）
- [ ] 格式化输出（可选）
- [ ] 编写单元测试

**技术细节**:
- 使用 `std.json.stringify()`
- 处理递归序列化
- 确保输出符合墨问 API 要求

**验收标准**:
- 能够正确序列化为 JSON
- 输出格式符合 API 要求
- 处理各种边界情况
- 单元测试通过

**优先级**: P0（必须）

---

### Task 4.3: MD → NoteAtom 转换器

**描述**: 实现 Markdown AST 到 NoteAtom 的转换

**工作内容**:
- [ ] 创建 `src/converter.zig`
- [ ] 实现 `convert()` 函数
- [ ] 实现各种节点的转换规则:
  - Document → doc
  - Heading → paragraph + bold
  - Paragraph → paragraph
  - Text → text
  - Bold → marks.bold
  - Link → marks.link
  - Quote → quote
- [ ] 处理嵌套和组合
- [ ] 编写单元测试
- [ ] 端到端测试

**技术细节**:
- 递归遍历 MD AST
- 映射到 NoteAtom 结构
- 处理样式组合（如粗体+链接）

**验收标准**:
- 转换规则正确
- 处理复杂嵌套情况
- 端到端测试通过
- 输出符合 API 要求

**优先级**: P0（必须）

---

## Phase 5: API 集成

**预计时间**: 2-3 天

### Task 5.1: HTTP 客户端封装

**描述**: 封装 zig-framework 的 HttpClient，适配墨问 API

**工作内容**:
- [ ] 使用 framework 的 `HttpClient`
- [ ] 封装墨问 API 调用
- [ ] 设置请求头（Authorization, Content-Type）
- [ ] 处理请求超时
- [ ] 编写单元测试（使用 mock）

**技术细节**:
```zig
const request = HttpRequest{
    .method = .POST,
    .url = "https://open.mowen.cn/api/open/api/v1/note/create",
    .headers = &[_]HttpHeader{
        .{ .name = "Authorization", .value = bearer_token },
        .{ .name = "Content-Type", .value = "application/json" },
    },
    .body = json_body,
    .timeout_ms = config.timeout_ms,
};
```

**验收标准**:
- HTTP 请求构建正确
- 请求头设置正确
- 超时处理正确
- 单元测试通过

**优先级**: P0（必须）

---

### Task 5.2: 上传器实现

**描述**: 实现笔记上传的核心逻辑

**工作内容**:
- [ ] 创建 `src/uploader.zig`
- [ ] 定义 `UploadRequest` 和 `UploadResult` 结构
- [ ] 实现 `upload()` 函数
- [ ] 构建请求体（body + settings）
- [ ] 解析响应（成功/失败）
- [ ] 处理各种 API 错误
- [ ] 编写单元测试

**技术细节**:
- 请求体格式:
  ```json
  {
    "body": { ... },
    "settings": {
      "autoPublish": true,
      "tags": ["tag1", "tag2"]
    }
  }
  ```
- 响应解析:
  - 200: 提取 `noteId`
  - 4xx/5xx: 提取错误信息

**验收标准**:
- 上传逻辑正确
- 错误处理完善
- 响应解析正确
- 单元测试通过

**优先级**: P0（必须）

---

### Task 5.3: 限频控制

**描述**: 实现 API 限频控制（1次/秒）

**工作内容**:
- [ ] 实现 `rateLimitDelay()` 函数
- [ ] 在每次上传后调用
- [ ] 处理限频错误（429）时的重试逻辑
- [ ] 编写测试

**技术细节**:
```zig
fn rateLimitDelay() void {
    std.time.sleep(1 * std.time.ns_per_s);
}
```

**验收标准**:
- 限频控制生效
- 不会触发 429 错误
- 重试逻辑正确

**优先级**: P0（必须）

---

## Phase 6: CLI 接口

**预计时间**: 1-2 天

### Task 6.1: 命令行参数解析

**描述**: 实现命令行参数的解析

**工作内容**:
- [ ] 创建 `src/cli_args.zig`
- [ ] 定义 `CliArgs` 结构
- [ ] 实现参数解析逻辑
- [ ] 支持以下选项:
  - `-h, --help`
  - `-v, --version`
  - `-d, --dir <PATH>`
  - `--config <PATH>`
  - `--auto-publish`
  - `--tags <TAG1,TAG2>`
  - `--dry-run`
  - `--verbose`
- [ ] 实现帮助信息显示
- [ ] 编写单元测试

**技术细节**:
- 使用 `std.process.args()`
- 手动解析参数（或使用第三方库）

**验收标准**:
- 参数解析正确
- 帮助信息清晰
- 错误提示友好
- 单元测试通过

**优先级**: P0（必须）

---

### Task 6.2: 输出格式化

**描述**: 实现友好的输出格式

**工作内容**:
- [ ] 创建 `src/cli_output.zig`
- [ ] 实现欢迎信息显示
- [ ] 实现进度显示（[1/5] file.md ✓）
- [ ] 实现结果汇总显示
- [ ] 实现失败列表显示
- [ ] 支持详细输出模式（--verbose）

**技术细节**:
- 使用 ANSI 颜色代码（可选）
- 格式化表格输出

**验收标准**:
- 输出格式美观
- 信息清晰易读
- 进度显示准确

**优先级**: P0（必须）

---

### Task 6.3: 主程序入口

**描述**: 实现 main 函数，整合所有模块

**工作内容**:
- [ ] 创建 `src/main.zig`
- [ ] 实现主流程:
  1. 解析命令行参数
  2. 读取配置
  3. 扫描文件
  4. 循环处理每个文件
  5. 生成汇总报告
- [ ] 处理各种错误
- [ ] 实现 dry-run 模式
- [ ] 集成测试

**技术细节**:
```zig
pub fn main() !void {
    // 1. 解析参数
    const args = try cli_args.parse();
    
    // 2. 读取配置
    const config = try config.loadConfig(args.config_path);
    
    // 3. 扫描文件
    const scan_result = try scanner.scanMarkdownFiles(args.dir);
    
    // 4. 处理文件
    var batch_result = result.init();
    for (scan_result.files) |file_path| {
        // 读取 → 解析 → 转换 → 上传
        // ...
        rateLimitDelay();
    }
    
    // 5. 打印报告
    try batch_result.printReport();
}
```

**验收标准**:
- 主流程正确
- 错误处理完善
- 集成测试通过

**优先级**: P0（必须）

---

## Phase 7: 结果汇总

**预计时间**: 1 天

### Task 7.1: 结果收集

**描述**: 实现结果收集器

**工作内容**:
- [ ] 创建 `src/result.zig`
- [ ] 定义 `BatchResult` 和 `FileResult` 结构
- [ ] 实现 `init()` 初始化
- [ ] 实现 `addResult()` 添加结果
- [ ] 实现 `getSummary()` 获取汇总
- [ ] 编写单元测试

**验收标准**:
- 结果收集正确
- 统计数据准确
- 单元测试通过

**优先级**: P1（重要）

---

### Task 7.2: 报告生成

**描述**: 实现汇总报告的生成和显示

**工作内容**:
- [ ] 实现 `printReport()` 函数
- [ ] 格式化输出:
  - 总计/成功/失败数量
  - 失败文件列表
  - 错误原因
- [ ] 支持不同输出格式（文本/JSON）
- [ ] 编写测试

**验收标准**:
- 报告格式清晰
- 信息完整准确
- 支持多种格式

**优先级**: P1（重要）

---

## Phase 8: 测试与优化

**预计时间**: 2-3 天

### Task 8.1: 集成测试

**描述**: 编写端到端集成测试

**工作内容**:
- [ ] 创建 `tests/integration_test.zig`
- [ ] 准备测试数据（示例 MD 文件）
- [ ] 测试完整流程
- [ ] 使用 mock HTTP 客户端
- [ ] 验证输出结果

**验收标准**:
- 集成测试覆盖主要流程
- 测试通过
- 测试数据完整

**优先级**: P1（重要）

---

### Task 8.2: 错误场景测试

**描述**: 测试各种错误场景

**工作内容**:
- [ ] 测试配置错误场景
- [ ] 测试文件错误场景
- [ ] 测试网络错误场景
- [ ] 测试 API 错误场景
- [ ] 验证错误处理逻辑

**测试场景**:
- 配置文件不存在
- API Key 错误
- 文件读取失败
- 网络超时
- API 限频 (429)
- API 配额不足 (403)

**验收标准**:
- 所有错误场景都有测试
- 错误处理正确
- 测试通过

**优先级**: P1（重要）

---

### Task 8.3: 性能优化

**描述**: 性能测试和优化

**工作内容**:
- [ ] 性能测试（处理大文件、多文件）
- [ ] 内存使用分析
- [ ] 优化热点代码
- [ ] 减少内存分配
- [ ] 优化 JSON 序列化

**验收标准**:
- 单文件处理时间 < 2s
- 内存占用合理
- 无内存泄漏

**优先级**: P1（重要）

---

## Phase 9: 文档与发布

**预计时间**: 1 天

### Task 9.1: 用户文档

**描述**: 编写用户文档

**工作内容**:
- [ ] 完善 `README.md`
  - 项目介绍
  - 安装说明
  - 使用示例
  - 配置说明
  - 常见问题
- [ ] 编写配置文件模板
- [ ] 编写使用教程

**验收标准**:
- 文档完整清晰
- 示例可运行
- 覆盖常见场景

**优先级**: P2（可选）

---

### Task 9.2: 构建与发布

**描述**: 准备发布流程

**工作内容**:
- [ ] 编写构建脚本
- [ ] 配置 CI/CD（可选）
- [ ] 准备发布包
- [ ] 编写发布说明

**验收标准**:
- 构建流程自动化
- 发布包可用
- 发布说明完整

**优先级**: P2（可选）

---

## 任务优先级总结

### P0 (必须完成)
- Phase 1: 项目基础设施
- Phase 2: 文件处理
- Phase 3: Markdown 解析 ⚠️ **最耗时**
- Phase 4: NoteAtom 转换
- Phase 5: API 集成
- Phase 6: CLI 接口

### P1 (重要)
- Phase 7: 结果汇总
- Phase 8: 测试与优化

### P2 (可选)
- Phase 9: 文档与发布

## 风险点

### ⚠️ Phase 3: Markdown 解析
**风险**: 这是最大的不确定性
- Zig 生态可能没有现成的 MD 解析库
- 需要自己实现，工作量大
- 语法复杂，边界情况多

**缓解措施**:
- 先实现简单版本，支持基本语法
- 逐步增加语法支持
- 充分测试，覆盖边界情况

### ⚠️ API 集成
**风险**: API 调用可能遇到各种问题
- 网络不稳定
- API 限频
- 响应格式变化

**缓解措施**:
- 完善错误处理
- 实现重试机制
- 充分测试各种场景

## 里程碑

### Milestone 1: 基础框架 (Day 3)
- 项目结构完成
- 配置管理完成
- 文件扫描完成

### Milestone 2: 核心功能 (Day 10)
- Markdown 解析完成
- NoteAtom 转换完成
- API 集成完成

### Milestone 3: 完整功能 (Day 15)
- CLI 接口完成
- 结果汇总完成
- 基本测试完成

### Milestone 4: 发布就绪 (Day 18)
- 所有测试通过
- 文档完成
- 可以发布

## 开发建议

1. **按顺序执行**: 任务之间有依赖关系，建议按 Phase 顺序执行
2. **测试驱动**: 每个模块都编写单元测试，确保质量
3. **增量开发**: 先实现简单版本，再逐步增强
4. **及时集成**: 完成一个模块后立即集成测试
5. **文档同步**: 边开发边更新文档

## 下一步

选择以下方式之一开始：

1. **退出探索模式，开始实施** - 从 Phase 1 Task 1.1 开始编码
2. **创建 OpenSpec 变更** - 将这些文档正式化为 OpenSpec 工件
3. **调整任务** - 如果有任何任务需要修改或细化
