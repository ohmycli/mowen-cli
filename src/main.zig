const std = @import("std");
const config = @import("config.zig");
const log = @import("log.zig");
const logging = @import("zig-logging");
const trace_module = @import("trace.zig");
const App = @import("app.zig").App;
const HttpApi = @import("infra/http_api.zig").HttpApi;
const create = @import("commands/create.zig");
const edit = @import("commands/edit.zig");
const set_privacy = @import("commands/set_privacy.zig");
const upload = @import("commands/upload.zig");

const CommandEntry = struct {
    name: []const u8,
    run: *const fn (*App, *std.process.Args.Iterator) anyerror!void,
};

const commands = [_]CommandEntry{
    .{ .name = "create", .run = create.run },
    .{ .name = "edit", .run = edit.run },
    .{ .name = "set-privacy", .run = set_privacy.run },
    .{ .name = "upload", .run = upload.run },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    try log.init(allocator, .info, .trace);
    defer log.deinit();

    _ = try trace_module.generateTraceId();
    log.info("app", "mowen-cli started", &.{});

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip program name

    const first_arg = args_iter.next() orelse {
        printHelp();
        return;
    };

    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        printHelp();
        return;
    }
    if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-v")) {
        std.debug.print("mowen-cli version 0.1.0\n", .{});
        return;
    }

    // Find command in table
    const cmd_fn = for (&commands) |*entry| {
        if (std.mem.eql(u8, first_arg, entry.name)) break entry.run;
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{first_arg});
        std.debug.print("Run 'mowen-cli --help' for usage information.\n", .{});
        return error.InvalidCommand;
    };

    // Peek for --api-key in remaining args (we need it for config)
    // We'll let commands handle their own arg parsing; config uses env/file
    const cli_args = config.CliArgs{};

    var cfg = config.loadConfig(allocator, init.io, init.environ_map, cli_args) catch |err| {
        if (err == config.ConfigError.ApiKeyMissing) {
            std.debug.print("Error: No API key found. Please set MOWEN_API_KEY environment variable or use --api-key flag.\n", .{});
            return error.NoApiKey;
        }
        return err;
    };
    defer cfg.deinit();

    var http_api = HttpApi.init(allocator, init.io, cfg.api_key, cfg.api_endpoint);
    var app = App.initFromInit(init, cfg, http_api.api());

    log.info("app", "Executing command", &.{
        logging.LogField.string("command", first_arg),
    });

    try cmd_fn(&app, &args_iter);
}

fn printHelp() void {
    std.debug.print(
        \\mowen-cli - Upload markdown files to Mowen platform
        \\
        \\USAGE:
        \\    mowen-cli <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    create <file>              Create a new note from a markdown file
        \\    edit <file>                Edit an existing note
        \\    set-privacy <file>         Set privacy for an existing note
        \\    upload                     Batch upload all markdown files (legacy)
        \\
        \\OPTIONS:
        \\    --help, -h                 Show this help message
        \\    --version, -v              Show version information
        \\
        \\For more information, visit: https://github.com/ohmycli/mowen-cli
        \\
    , .{});
}
