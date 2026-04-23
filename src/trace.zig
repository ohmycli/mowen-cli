const std = @import("std");
const logging = @import("zig-logging");

var global_trace_id: ?[]const u8 = null;
var trace_id_buffer: [32]u8 = undefined;
var trace_mutex: std.atomic.Mutex = .unlocked;

pub fn generateTraceId() ![]const u8 {
    while (!trace_mutex.tryLock()) {}
    defer trace_mutex.unlock();

    const io = std.Io.Threaded.global_single_threaded.*.io();
    const ts = std.Io.Timestamp.now(io, .real);
    const timestamp = @as(u64, @intCast(@divFloor(ts.nanoseconds, 1_000_000)));

    var prng = std.Random.DefaultPrng.init(@intCast(timestamp));
    const random = prng.random();
    const rand_value = random.int(u32);

    const trace_id = try std.fmt.bufPrint(&trace_id_buffer, "{d}-{x:0>8}", .{ timestamp, rand_value });
    global_trace_id = trace_id;
    return trace_id;
}

pub fn getCurrentTraceId() ?[]const u8 {
    while (!trace_mutex.tryLock()) {}
    defer trace_mutex.unlock();
    return global_trace_id;
}

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

var global_provider: TraceProvider = .{};

pub fn getGlobalProvider() *TraceProvider {
    return &global_provider;
}
