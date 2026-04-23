const std = @import("std");
const logging = @import("zig-logging");
const trace_module = @import("trace.zig");

var global_logger: ?logging.Logger = null;
var console_sink_storage: union(enum) {
    console: logging.ConsoleSink,
    trace: logging.TraceConsoleSink,
} = undefined;
var trace_file_sink: ?logging.TraceTextFileSink = null;
var multi_sink: ?logging.MultiSink = null;
var allocator: ?std.mem.Allocator = null;

pub const LogStyle = enum {
    pretty,    // ISO8601 时间戳格式（默认）
    compact,   // 紧凑格式
    trace,     // TraceText 格式（[HH:MM:SS LVL] TraceId:xxx|Message|Field:value）
};

pub fn init(alloc: std.mem.Allocator, min_level: logging.LogLevel, style: LogStyle) !void {
    allocator = alloc;
    
    switch (style) {
        .pretty, .compact => {
            const console_style: logging.ConsoleStyle = if (style == .pretty) .pretty else .compact;
            console_sink_storage = .{ .console = logging.ConsoleSink.init(min_level, console_style) };
            global_logger = logging.Logger.init(console_sink_storage.console.asLogSink(), min_level);
        },
        .trace => {
            // 创建 TraceConsoleSink 输出到控制台（trace 格式）
            console_sink_storage = .{ .trace = logging.TraceConsoleSink.init(min_level) };
            
            // 创建 TraceTextFileSink 输出到文件（相同格式）
            trace_file_sink = try logging.TraceTextFileSink.init(
                alloc,
                "mowen-cli.log",
                null, // 无大小限制
                .{},
            );
            
            // 组合两个 sink
            var sinks = [_]logging.LogSink{
                console_sink_storage.trace.asLogSink(),
                trace_file_sink.?.asLogSink(),
            };
            
            multi_sink = try logging.MultiSink.init(alloc, &sinks);
            
            // 使用 TraceContextProvider 初始化 Logger
            const trace_provider = trace_module.getGlobalProvider();
            global_logger = logging.Logger.initWithOptions(multi_sink.?.asLogSink(), .{
                .min_level = min_level,
                .trace_context_provider = trace_provider.asProvider(),
            });
        },
    }
}

pub fn deinit() void {
    if (global_logger) |*l| {
        l.deinit();
        global_logger = null;
    }
    
    if (multi_sink) |*ms| {
        ms.deinit();
        multi_sink = null;
    }
    
    if (trace_file_sink) |*ts| {
        ts.deinit();
        trace_file_sink = null;
    }
}

pub fn getLogger() *logging.Logger {
    if (global_logger) |*l| {
        return l;
    }
    @panic("Logger not initialized. Call log.init() first.");
}

pub fn subsystem(name: []const u8) logging.SubsystemLogger {
    return getLogger().subsystem(name);
}

// 便捷函数
pub fn trace(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).trace(message, fields);
}

pub fn debug(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).debug(message, fields);
}

pub fn info(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).info(message, fields);
}

pub fn warn(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).warn(message, fields);
}

pub fn err(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).@"error"(message, fields);
}

pub fn fatal(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    subsystem(subsystem_name).fatal(message, fields);
}
