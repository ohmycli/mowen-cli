const std = @import("std");

pub const MODULE_NAME = "logging";

pub const level = @import("level.zig");
pub const record = @import("record.zig");
pub const sink = @import("sink.zig");
pub const memory_sink = @import("memory_sink.zig");
pub const console_sink = @import("console_sink.zig");
pub const file_sink = @import("file_sink.zig");
pub const trace_text_file_sink = @import("trace_text_file_sink.zig");
pub const multi_sink = @import("multi_sink.zig");
pub const redact = @import("redact.zig");
pub const rotating_file_sink = @import("rotating_file_sink.zig");
pub const logger = @import("logger.zig");

pub const LogLevel = level.LogLevel;
pub const LogRecordKind = record.LogRecordKind;
pub const LogField = record.LogField;
pub const LogFieldValue = record.LogFieldValue;
pub const LogRecord = record.LogRecord;
pub const LogSink = sink.LogSink;
pub const MemorySink = memory_sink.MemorySink;
pub const StoredLogRecord = memory_sink.StoredLogRecord;
pub const ConsoleStyle = console_sink.ConsoleStyle;
pub const ConsoleSink = console_sink.ConsoleSink;
pub const JsonlFileSink = file_sink.JsonlFileSink;
pub const JsonlFileSinkStatus = file_sink.JsonlFileSinkStatus;
pub const TraceTextFileSink = trace_text_file_sink.TraceTextFileSink;
pub const TraceTextFileSinkStatus = trace_text_file_sink.TraceTextFileSinkStatus;
pub const TraceTextFileSinkOptions = trace_text_file_sink.TraceTextFileSinkOptions;
pub const MultiSink = multi_sink.MultiSink;
pub const RedactMode = redact.RedactMode;
pub const RotatingFileSink = rotating_file_sink.RotatingFileSink;
pub const RotatingFileSinkConfig = rotating_file_sink.RotatingFileSinkConfig;
pub const RotatingFileSinkStatus = rotating_file_sink.RotatingFileSinkStatus;
pub const LogFormat = rotating_file_sink.LogFormat;
pub const Logger = logger.Logger;
pub const LoggerTruncationStats = logger.LoggerTruncationStats;
pub const LoggerOptions = logger.LoggerOptions;
pub const TraceContext = logger.TraceContext;
pub const TraceContextProvider = logger.TraceContextProvider;
pub const SubsystemLogger = logger.SubsystemLogger;

test {
    std.testing.refAllDecls(@This());
}

test "logging module exports are available" {
    try std.testing.expectEqualStrings("logging", MODULE_NAME);
    try std.testing.expectEqualStrings("info", LogLevel.info.asText());
    try std.testing.expect(ConsoleStyle.pretty == .pretty);
    try std.testing.expect(RedactMode.safe == .safe);
}


