const std = @import("std");
const builtin = @import("builtin");

// Configuration error types
pub const ConfigError = error{
    ConfigNotFound,
    ConfigInvalid,
    ApiKeyMissing,
    HomeNotFound,
    InvalidUrl,
};

// CLI arguments structure
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

    // Create default configuration
    pub fn default(allocator: std.mem.Allocator) !Config {
        return Config{
            .api_key = try allocator.dupe(u8, ""),
            .api_endpoint = try allocator.dupe(u8, "https://open.mowen.cn/api/open/api/v1/note/create"),
            .timeout_ms = 30000,
            .default_tags = &[_][]const u8{},
            .auto_publish = false,
            .allocator = allocator,
        };
    }

    // Deep clone configuration
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

// Get default configuration file path
// Returns config.json in the current working directory (same as exe location when run from there)
pub fn getDefaultConfigPath(allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    _ = environ_map; // Not needed for current directory path

    // Simply return "config.json" - will be resolved relative to current working directory
    // When the exe is run from zig-out/bin/, it will look for zig-out/bin/config.json
    return try allocator.dupe(u8, "config.json");
}

// Load configuration from JSON file
fn loadFromFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Config {
    const file_content = std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        std.Io.Limit.limited(1024 * 1024), // Max 1MB
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

    // Parse api_key (required)
    const api_key_value = root.get("api_key") orelse {
        return ConfigError.ApiKeyMissing;
    };
    const api_key = try allocator.dupe(u8, api_key_value.string);

    // Parse api_endpoint (optional)
    const api_endpoint = if (root.get("api_endpoint")) |endpoint|
        try allocator.dupe(u8, endpoint.string)
    else
        try allocator.dupe(u8, "https://open.mowen.cn/api/open/api/v1/note/create");

    // Parse default_tags (optional)
    var tags: [][]const u8 = &[_][]const u8{};
    if (root.get("default_tags")) |tags_value| {
        const tags_array = tags_value.array;
        tags = try allocator.alloc([]const u8, tags_array.items.len);
        for (tags_array.items, 0..) |tag, i| {
            tags[i] = try allocator.dupe(u8, tag.string);
        }
    }

    // Parse auto_publish (optional)
    const auto_publish = if (root.get("auto_publish")) |ap| ap.bool else false;

    // Parse timeout_ms (optional, default 30000)
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

// Merge configuration from environment variables
fn mergeFromEnv(config: *Config, environ_map: *const std.process.Environ.Map) !void {
    const allocator = config.allocator;

    // Read MOWEN_API_KEY
    if (environ_map.get("MOWEN_API_KEY")) |api_key| {
        allocator.free(config.api_key);
        config.api_key = try allocator.dupe(u8, api_key);
    }

    // Read MOWEN_API_ENDPOINT
    if (environ_map.get("MOWEN_API_ENDPOINT")) |api_endpoint| {
        allocator.free(config.api_endpoint);
        config.api_endpoint = try allocator.dupe(u8, api_endpoint);
    }
}

// Merge configuration from CLI arguments
fn mergeFromCli(config: *Config, cli_args: CliArgs) !void {
    const allocator = config.allocator;

    // Override api_key if provided
    if (cli_args.api_key) |api_key| {
        allocator.free(config.api_key);
        config.api_key = try allocator.dupe(u8, api_key);
    }

    // Override api_endpoint if provided
    if (cli_args.api_endpoint) |api_endpoint| {
        allocator.free(config.api_endpoint);
        config.api_endpoint = try allocator.dupe(u8, api_endpoint);
    }

    // Override auto_publish if provided
    if (cli_args.auto_publish) |auto_publish| {
        config.auto_publish = auto_publish;
    }

    // Override tags if provided
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

// Validate configuration
pub fn validateConfig(config: *const Config) !void {
    // Validate api_key is not empty
    if (config.api_key.len == 0) {
        return ConfigError.ApiKeyMissing;
    }

    // Validate api_key is not whitespace only
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

    // Validate api_endpoint is a valid URL (basic check)
    if (config.api_endpoint.len > 0) {
        if (!std.mem.startsWith(u8, config.api_endpoint, "http://") and
            !std.mem.startsWith(u8, config.api_endpoint, "https://"))
        {
            return ConfigError.InvalidUrl;
        }
    }

    // Validate timeout_ms is within valid range (1000-300000ms)
    if (config.timeout_ms < 1000 or config.timeout_ms > 300000) {
        return ConfigError.ConfigInvalid;
    }
}

// Main configuration loading function
pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map, cli_args: ?CliArgs) !Config {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    // Determine config file path
    const config_path = if (cli_args) |args| blk: {
        if (args.config_path) |path| {
            break :blk try temp_allocator.dupe(u8, path);
        }
        break :blk try getDefaultConfigPath(temp_allocator, environ_map);
    } else try getDefaultConfigPath(temp_allocator, environ_map);

    // 1. Load from file (or use default if not found)
    var config = loadFromFile(allocator, io, config_path) catch |err| blk: {
        if (err == ConfigError.ConfigNotFound) {
            break :blk try Config.default(allocator);
        } else {
            return err;
        }
    };

    // 2. Merge from environment variables
    try mergeFromEnv(&config, environ_map);

    // 3. Merge from CLI arguments
    if (cli_args) |args| {
        try mergeFromCli(&config, args);
    }

    // 4. Validate final configuration
    validateConfig(&config) catch |err| {
        config.deinit();
        return err;
    };

    return config;
}
