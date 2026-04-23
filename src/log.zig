const std = @import("std");
const logging = @import("zig-logging");

var global_logger: ?logging.Logger = null;
var console_sink: logging.ConsoleSink = undefined;

pub fn init(min_level: logging.LogLevel) void {
    console_sink = logging.ConsoleSink.init(min_level, .pretty);
    global_logger = logging.Logger.init(console_sink.asLogSink(), min_level);
}

pub fn deinit() void {
    if (global_logger) |*l| {
        l.deinit();
        global_logger = null;
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
