const std = @import("std");
const builtin = @import("builtin");

pub const ConfigError = error{
    ConfigNotFound,
    ConfigInvalid,
    ApiKeyMissing,
    HomeNotFound,
    InvalidUrl,
};

pub const CliArgs = struct {
    api_key: ?[]const u8 = null,
    api_endpoint: ?[]const u8 = null,
    config_path: ?[]const u8 = null,
    auto_publish: ?bool = null,
    tags: ?[][]const u8 = null,
};

pub const Config = struct {
    api_key: []const u8,
    api_endpoint: []const u8,
    timeout_ms: u32,
    default_tags: [][]const u8,
    auto_publish: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.api_endpoint);
        for (self.default_tags) |tag| {
            self.allocator.free(tag);
        }
        self.allocator.free(self.default_tags);
    }

    pub fn default(allocator: std.mem.Allocator) !Config {
        return Config{
            .api_key = try allocator.dupe(u8, ""),
            .api_endpoint = try allocator.dupe(u8, "https://open.mowen.cn/api/open/api/v1"),
            .timeout_ms = 30000,
            .default_tags = &[_][]const u8{},
            .auto_publish = false,
            .allocator = allocator,
        };
    }

    pub fn clone(self: *const Config, allocator: std.mem.Allocator) !Config {
        const api_key_copy = try allocator.dupe(u8, self.api_key);
        const api_endpoint_copy = try allocator.dupe(u8, self.api_endpoint);

        var tags_copy = try allocator.alloc([]const u8, self.default_tags.len);
        for (self.default_tags, 0..) |tag, i| {
            tags_copy[i] = try allocator.dupe(u8, tag);
        }

        return Config{
            .api_key = api_key_copy,
            .api_endpoint = api_endpoint_copy,
            .timeout_ms = self.timeout_ms,
            .default_tags = tags_copy,
            .auto_publish = self.auto_publish,
            .allocator = allocator,
        };
    }
};

pub fn getDefaultConfigPath(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) ![]const u8 {
    _ = environ_map;
    const exe_dir_path = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(exe_dir_path);
    return try std.fs.path.join(allocator, &[_][]const u8{ exe_dir_path, "config.json" });
}

fn loadFromFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Config {
    const file_content = std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        std.Io.Limit.limited(1024 * 1024),
    ) catch |err| {
        if (err == error.FileNotFound) {
            return ConfigError.ConfigNotFound;
        }
        return err;
    };
    defer allocator.free(file_content);

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        file_content,
        .{},
    ) catch {
        return ConfigError.ConfigInvalid;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const api_key_value = root.get("api_key") orelse {
        return ConfigError.ApiKeyMissing;
    };
    const api_key = try allocator.dupe(u8, api_key_value.string);

    const api_endpoint = if (root.get("api_endpoint")) |endpoint|
        try allocator.dupe(u8, endpoint.string)
    else
        try allocator.dupe(u8, "https://open.mowen.cn/api/open/api/v1");

    var tags: [][]const u8 = &[_][]const u8{};
    if (root.get("default_tags")) |tags_value| {
        const tags_array = tags_value.array;
        tags = try allocator.alloc([]const u8, tags_array.items.len);
        for (tags_array.items, 0..) |tag, i| {
            tags[i] = try allocator.dupe(u8, tag.string);
        }
    }

    const auto_publish = if (root.get("auto_publish")) |ap| ap.bool else false;
    const timeout_ms = if (root.get("timeout_ms")) |tm| @as(u32, @intCast(tm.integer)) else 30000;

    return Config{
        .api_key = api_key,
        .api_endpoint = api_endpoint,
        .timeout_ms = timeout_ms,
        .default_tags = tags,
        .auto_publish = auto_publish,
        .allocator = allocator,
    };
}

fn mergeFromEnv(config: *Config, environ_map: *const std.process.Environ.Map) !void {
    const allocator = config.allocator;

    if (environ_map.get("MOWEN_API_KEY")) |api_key| {
        allocator.free(config.api_key);
        config.api_key = try allocator.dupe(u8, api_key);
    }

    if (environ_map.get("MOWEN_API_ENDPOINT")) |api_endpoint| {
        allocator.free(config.api_endpoint);
        config.api_endpoint = try allocator.dupe(u8, api_endpoint);
    }
}

fn mergeFromCli(config: *Config, cli_args: CliArgs) !void {
    const allocator = config.allocator;

    if (cli_args.api_key) |api_key| {
        allocator.free(config.api_key);
        config.api_key = try allocator.dupe(u8, api_key);
    }

    if (cli_args.api_endpoint) |api_endpoint| {
        allocator.free(config.api_endpoint);
        config.api_endpoint = try allocator.dupe(u8, api_endpoint);
    }

    if (cli_args.auto_publish) |auto_publish| {
        config.auto_publish = auto_publish;
    }

    if (cli_args.tags) |tags| {
        for (config.default_tags) |tag| {
            allocator.free(tag);
        }
        allocator.free(config.default_tags);

        var tags_copy = try allocator.alloc([]const u8, tags.len);
        for (tags, 0..) |tag, i| {
            tags_copy[i] = try allocator.dupe(u8, tag);
        }
        config.default_tags = tags_copy;
    }
}

pub fn validateConfig(config: *const Config) !void {
    if (config.api_key.len == 0) {
        return ConfigError.ApiKeyMissing;
    }

    var all_whitespace = true;
    for (config.api_key) |c| {
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
            all_whitespace = false;
            break;
        }
    }
    if (all_whitespace) {
        return ConfigError.ApiKeyMissing;
    }

    if (config.api_endpoint.len > 0) {
        if (!std.mem.startsWith(u8, config.api_endpoint, "http://") and
            !std.mem.startsWith(u8, config.api_endpoint, "https://"))
        {
            return ConfigError.InvalidUrl;
        }
    }

    if (config.timeout_ms < 1000 or config.timeout_ms > 300000) {
        return ConfigError.ConfigInvalid;
    }
}

pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, cli_args: ?CliArgs) !Config {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    const config_path = if (cli_args) |args| blk: {
        if (args.config_path) |path| {
            break :blk try temp_allocator.dupe(u8, path);
        }
        break :blk try getDefaultConfigPath(temp_allocator, io, environ_map);
    } else try getDefaultConfigPath(temp_allocator, io, environ_map);

    var config = loadFromFile(allocator, io, config_path) catch |err| blk: {
        if (err == ConfigError.ConfigNotFound) {
            break :blk try Config.default(allocator);
        } else {
            return err;
        }
    };

    try mergeFromEnv(&config, environ_map);

    if (cli_args) |args| {
        try mergeFromCli(&config, args);
    }

    validateConfig(&config) catch |err| {
        config.deinit();
        return err;
    };

    return config;
}
