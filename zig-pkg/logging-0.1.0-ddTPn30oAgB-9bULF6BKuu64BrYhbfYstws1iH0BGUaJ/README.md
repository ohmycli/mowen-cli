# zig-logging

轻量级、零依赖的 Zig 结构化日志库，从 [zig-framework](https://github.com/topaihub/zig-framework) 提取并适配 Zig 0.16.0。

## 特性

- ✅ **零框架依赖** - 仅依赖 Zig 标准库
- ✅ **多种输出格式** - Pretty、Compact、JSON
- ✅ **TraceTextFileSink** - 支持 hermes-zig 格式的 trace 日志（`[时间 级别] TraceId:xxx|Message|Field:value`）
- ✅ **结构化字段** - 支持 string、int、uint、float、bool、null
- ✅ **分布式追踪** - 支持 trace_id、span_id、request_id
- ✅ **敏感信息脱敏** - 自动识别并脱敏敏感字段（API key、token 等）
- ✅ **多种 Sink** - Console、JsonlFile、TraceTextFile、RotatingFile、MultiSink
- ✅ **子系统日志** - 支持按模块划分日志
- ✅ **线程安全** - 内置互斥锁保护

## 快速开始

### 安装

在 `build.zig.zon` 中添加依赖：

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .@"zig-logging" = .{
            .url = "https://github.com/topaihub/zig-logging/archive/refs/heads/main.tar.gz",
            .hash = "1220...", // 运行 zig build 时会提示正确的 hash
        },
    },
}
```

在 `build.zig` 中引入：

```zig
const logging = b.dependency("zig-logging", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zig-logging", logging.module("zig-logging"));
```

### 基本使用

```zig
const logging = @import("zig-logging");

pub fn main() !void {
    // 创建控制台 sink
    var console = logging.ConsoleSink.init(.info, .pretty);
    
    // 创建 logger
    var logger = logging.Logger.init(console.asLogSink(), .info);
    defer logger.deinit();

    // 记录日志
    const app = logger.child("app");
    app.info("Application started", &.{
        logging.LogField.string("version", "1.0.0"),
        logging.LogField.boolean("production", true),
    });

    // 使用子系统
    const db_logger = logger.child("database");
    db_logger.info("Connected to database", &.{
        logging.LogField.string("host", "localhost"),
        logging.LogField.uint("port", 5432),
    });
}
```

输出（Pretty 格式）：
```
[08:50:00 INF] app: Application started version="1.0.0" production=true
[08:50:00 INF] database: Connected to database host="localhost" port=5432
```

## 输出格式

### Pretty（推荐用于开发）
```
[08:50:00 INF] auth: User login attempt username="alice" attempt=1
[08:50:01 WRN] auth: Invalid password username="alice" attempt=2
[08:50:02 ERR] auth: Login failed username="alice" error="max_attempts_exceeded"
```

### Compact
```
[info] auth: User login attempt username="alice" attempt=1
[warn] auth: Invalid password username="alice" attempt=2
[error] auth: Login failed username="alice" error="max_attempts_exceeded"
```

### JSON
```json
{"tsUnixMs":1745308200123,"level":"info","kind":"generic","subsystem":"auth","message":"User login attempt","fields":[{"key":"username","value":"alice"},{"key":"attempt","value":1}]}
```

## TraceTextFileSink - hermes-zig 格式

TraceTextFileSink 生成与 hermes-zig 兼容的 trace 日志格式：

```zig
const allocator = std.heap.page_allocator;

// 创建 TraceTextFileSink
var trace_sink = try logging.TraceTextFileSink.init(
    allocator,
    "trace.log",
    null, // 无大小限制
    .{
        .include_observer = false,
        .include_runtime_dispatch = false,
        .include_framework_method_trace = true,
    },
);
defer trace_sink.deinit();

// 创建 TraceContextProvider
const SimpleTraceProvider = struct {
    trace_id: []const u8,

    fn getCurrent(ptr: *anyopaque) logging.TraceContext {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        return .{
            .trace_id = self.trace_id,
            .span_id = null,
            .request_id = null,
        };
    }

    pub fn provider(self: *@This()) logging.TraceContextProvider {
        return .{
            .ptr = @ptrCast(self),
            .current = getCurrent,
        };
    }
};

var trace_provider = SimpleTraceProvider{ .trace_id = "05b287fe7fd7d54b" };

// 创建带 TraceContextProvider 的 Logger
var logger = logging.Logger.initWithOptions(trace_sink.asLogSink(), .{
    .min_level = .debug,
    .trace_context_provider = trace_provider.provider(),
});
defer logger.deinit();

// Request trace
const request_logger = logger.child("request");
request_logger.logKind(.info, .request, "Request started", &.{
    logging.LogField.string("method", "CHAT"),
    logging.LogField.string("path", "/chat"),
});

// Method trace - ENTRY
const method_logger = logger.child("method");
method_logger.logKind(.debug, .method, "ENTRY", &.{
    logging.LogField.string("method", "AgentLoop.Run"),
    logging.LogField.string("params", "{\"messages\":2,\"tools\":23}"),
});

// Method trace - ERROR
method_logger.logKind(.@"error", .method, "ERROR", &.{
    logging.LogField.string("method", "AgentLoop.Run"),
    logging.LogField.string("status", "FAIL"),
    logging.LogField.uint("duration_ms", 2482),
    logging.LogField.string("error_code", "ResponsesEmptyOutput"),
});
```

输出到 `trace.log`：
```
[08:22:05 INF] TraceId:05b287fe7fd7d54b|Request started|Method:CHAT|Path:/chat
[08:22:05 DBG] TraceId:05b287fe7fd7d54b|ENTRY|AgentLoop.Run|Params:{"messages":2,"tools":23}
[08:22:07 ERR] TraceId:05b287fe7fd7d54b|ERROR|AgentLoop.Run|Status:FAIL|Duration:2482ms|Type:SYNC|ErrorCode:ResponsesEmptyOutput
```

## 文件日志

### JSONL 格式文件

```zig
var file_sink = try logging.JsonlFileSink.init(
    allocator,
    "logs/app.jsonl",
    10 * 1024 * 1024, // 10 MB 限制
);
defer file_sink.deinit();

var logger = logging.Logger.init(file_sink.asLogSink(), .info);
defer logger.deinit();

logger.child("app").info("Log to file", &.{});
```

### 轮转文件日志

```zig
var rotating_sink = try logging.RotatingFileSink.init(
    allocator,
    .{
        .base_path = "logs/app.log",
        .max_bytes = 10 * 1024 * 1024, // 10 MB
        .max_backups = 5,
        .format = .jsonl, // 或 .trace_text
    },
);
defer rotating_sink.deinit();
```

## 多 Sink 组合

同时输出到控制台和文件：

```zig
var console = logging.ConsoleSink.init(.info, .pretty);
var file_sink = try logging.TraceTextFileSink.init(allocator, "trace.log", null, .{});
defer file_sink.deinit();

var sinks = [_]logging.LogSink{
    console.asLogSink(),
    file_sink.asLogSink(),
};

var multi_sink = try logging.MultiSink.init(allocator, &sinks);
defer multi_sink.deinit();

var logger = logging.Logger.init(multi_sink.asLogSink(), .info);
defer logger.deinit();
```

## 敏感信息脱敏

```zig
var logger = logging.Logger.initWithOptions(console.asLogSink(), .{
    .min_level = .info,
    .redact_mode = .safe, // .off, .safe, .strict
});

logger.child("auth").info("User authenticated", &.{
    logging.LogField.string("api_key", "secret123"), // 自动脱敏
    logging.LogField.string("username", "alice"),    // 不脱敏
});
```

输出：
```
[08:50:00 INF] auth: User authenticated api_key="[REDACTED]" username="alice"
```

## API 文档

### 日志级别

```zig
pub const LogLevel = enum {
    trace,   // 最详细
    debug,   // 调试信息
    info,    // 一般信息
    warn,    // 警告
    @"error", // 错误
    fatal,   // 致命错误
    silent,  // 静默（不输出）
};
```

### 日志类型（LogRecordKind）

```zig
pub const LogRecordKind = enum {
    generic,  // 普通日志
    request,  // 请求日志（用于 TraceTextFileSink）
    method,   // 方法追踪（用于 TraceTextFileSink）
    step,     // 步骤日志（用于 TraceTextFileSink）
    summary,  // 摘要日志（用于 TraceTextFileSink）
};
```

### 字段类型

```zig
logging.LogField.string("key", "value")
logging.LogField.int("key", -123)
logging.LogField.uint("key", 456)
logging.LogField.float("key", 3.14)
logging.LogField.boolean("key", true)
logging.LogField.nullValue("key")
```

### SubsystemLogger 方法

```zig
const logger = logger.child("subsystem");

// 普通日志
logger.trace("message", &.{});
logger.debug("message", &.{});
logger.info("message", &.{});
logger.warn("message", &.{});
logger.@"error"("message", &.{});
logger.fatal("message", &.{});

// 带类型的日志（用于 TraceTextFileSink）
logger.logKind(.info, .request, "message", &.{});
logger.logKind(.debug, .method, "ENTRY", &.{});
logger.logKind(.error, .method, "ERROR", &.{});
```

## 示例

查看 `examples/` 目录获取更多示例：

- `basic.zig` - 基本使用示例
- `trace_format.zig` - TraceTextFileSink 完整示例
- `trace_example.zig` - 分布式追踪示例

运行示例：
```bash
zig build
zig build run-example
```

## 与 zig-framework 的关系

本库从 [zig-framework](https://github.com/topaihub/zig-framework) 的日志模块提取而来，移除了对 `std.Io.Threaded` 的强制依赖，使其可以独立使用。

主要改进：
- ✅ 修复了 Zig 0.16.0 中 `Writer.fromArrayList` 的使用问题
- ✅ 移除了框架依赖，可独立使用
- ✅ 保持了与 hermes-zig 的格式兼容性

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
