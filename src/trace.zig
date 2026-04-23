const std = @import("std");
const logging = @import("zig-logging");

/// 全局 TraceId 生成器
var global_trace_id: ?[]const u8 = null;
var trace_id_buffer: [32]u8 = undefined;
var trace_mutex: std.atomic.Mutex = .unlocked;

/// 生成新的 TraceId（格式：timestamp-random）
pub fn generateTraceId() ![]const u8 {
    while (!trace_mutex.tryLock()) {}
    defer trace_mutex.unlock();

    const io = std.Io.Threaded.global_single_threaded.*.io();
    const ts = std.Io.Timestamp.now(io, .real);
    const timestamp = @as(u64, @intCast(@divFloor(ts.nanoseconds, 1_000_000))); // 毫秒

    // 生成随机数
    var prng = std.Random.DefaultPrng.init(@intCast(timestamp));
    const random = prng.random();
    const rand_value = random.int(u32);

    // 格式化为 TraceId：timestamp-random（例如：1234567890-abcd1234）
    const trace_id = try std.fmt.bufPrint(&trace_id_buffer, "{d}-{x:0>8}", .{ timestamp, rand_value });
    global_trace_id = trace_id;
    return trace_id;
}

/// 获取当前 TraceId
pub fn getCurrentTraceId() ?[]const u8 {
    while (!trace_mutex.tryLock()) {}
    defer trace_mutex.unlock();
    return global_trace_id;
}

/// TraceContextProvider 实现
pub const TraceProvider = struct {
    const Self = @This();

    pub fn asProvider(self: *Self) logging.TraceContextProvider {
        return logging.TraceContextProvider{
            .ptr = self,
            .current = currentImpl,
        };
    }

    fn currentImpl(ptr: *anyopaque) logging.TraceContext {
        _ = ptr;
        return logging.TraceContext{
            .trace_id = getCurrentTraceId(),
            .span_id = null,
            .request_id = null,
        };
    }
};

/// 全局 TraceProvider 实例
var global_provider: TraceProvider = .{};

pub fn getGlobalProvider() *TraceProvider {
    return &global_provider;
}
