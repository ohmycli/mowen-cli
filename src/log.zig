const std = @import("std");
const logging = @import("zig-logging");
const trace_module = @import("trace.zig");

var managed_logger: ?logging.ManagedLogger = null;

pub const LogStyle = enum {
    pretty,
    compact,
    trace,
};

pub fn init(alloc: std.mem.Allocator, min_level: logging.LogLevel, style: LogStyle) !void {
    const trace_provider = trace_module.getGlobalProvider();

    const config: logging.LogConfig = switch (style) {
        .pretty => .{
            .level = min_level,
            .console = .{ .style = .pretty },
        },
        .compact => .{
            .level = min_level,
            .console = .{ .style = .compact },
        },
        .trace => .{
            .level = min_level,
            .trace_console = .{},
            .trace_file = .{
                .path = "mowen-cli.log",
                .max_bytes = null,
            },
            .trace_provider = trace_provider.asProvider(),
        },
    };

    managed_logger = try logging.create(alloc, config);
}

pub fn deinit() void {
    if (managed_logger) |*ml| {
        ml.deinit();
        managed_logger = null;
    }
}

pub fn getLogger() *logging.Logger {
    if (managed_logger) |*ml| {
        return &ml.logger;
    }
    @panic("Logger not initialized. Call log.init() first.");
}

pub fn child(name: []const u8) logging.SubsystemLogger {
    return getLogger().child(name);
}

pub fn trace(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).trace(message, fields);
}

pub fn debug(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).debug(message, fields);
}

pub fn info(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).info(message, fields);
}

pub fn warn(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).warn(message, fields);
}

pub fn err(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).@"error"(message, fields);
}

pub fn fatal(subsystem_name: []const u8, message: []const u8, fields: []const logging.LogField) void {
    child(subsystem_name).fatal(message, fields);
}
