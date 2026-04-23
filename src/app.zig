const std = @import("std");
const config_mod = @import("config.zig");
const Api = @import("core/api.zig").Api;
const logging = @import("zig-logging");
const log = @import("log.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: config_mod.Config,
    api: Api,
    log: logging.SubsystemLogger,

    pub fn initFromInit(init: std.process.Init, cfg: config_mod.Config, api: Api) App {
        return .{
            .allocator = init.gpa,
            .io = init.io,
            .config = cfg,
            .api = api,
            .log = log.child("app"),
        };
    }
};
