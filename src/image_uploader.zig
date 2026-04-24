const std = @import("std");
const builtin = @import("builtin");
const metadata = @import("metadata.zig");
const parser = @import("parser.zig");
const Api = @import("core/api.zig").Api;

pub const ImageUploader = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api: Api,
    rate_limiter: *metadata.MetadataStore,
    base_dir: []const u8,
    cache: std.StringHashMap([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        api: Api,
        rate_limiter: *metadata.MetadataStore,
        base_dir: []const u8,
    ) !ImageUploader {
        return .{
            .allocator = allocator,
            .io = io,
            .api = api,
            .rate_limiter = rate_limiter,
            .base_dir = try allocator.dupe(u8, base_dir),
            .cache = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ImageUploader) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.cache.deinit();
        self.allocator.free(self.base_dir);
    }

    pub fn parserResolver(self: *ImageUploader) parser.ImageResolver {
        return .{
            .ctx = self,
            .resolve = resolveThunk,
        };
    }

    fn resolveThunk(ctx: *anyopaque, source: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *ImageUploader = @ptrCast(@alignCast(ctx));
        return try self.resolve(source);
    }

    pub fn resolve(self: *ImageUploader, source: []const u8) ![]const u8 {
        if (isRemoteSource(source)) {
            return try self.resolveRemote(source);
        }
        return try self.resolveLocal(source);
    }

    fn resolveRemote(self: *ImageUploader, source: []const u8) ![]const u8 {
        const cache_key = try self.allocator.dupe(u8, source);
        if (self.cache.get(cache_key)) |cached| {
            defer self.allocator.free(cache_key);
            return try self.allocator.dupe(u8, cached);
        }
        errdefer self.allocator.free(cache_key);

        try self.rate_limiter.ensureRateLimit(self.io);

        const file_id = try self.api.uploadImageFromUrl(source);
        errdefer self.allocator.free(file_id);

        try self.cache.put(cache_key, file_id);
        return try self.allocator.dupe(u8, file_id);
    }

    fn resolveLocal(self: *ImageUploader, source: []const u8) ![]const u8 {
        const resolved_path = try self.resolveLocalPath(source);
        defer self.allocator.free(resolved_path);

        const cache_key = try self.normalizeCacheKey(resolved_path);
        if (self.cache.get(cache_key)) |cached| {
            defer self.allocator.free(cache_key);
            return try self.allocator.dupe(u8, cached);
        }
        errdefer self.allocator.free(cache_key);

        try self.ensureSupportedLocalImage(resolved_path);
        try self.rate_limiter.ensureRateLimit(self.io);

        const file_id = try self.api.uploadImageFromFile(resolved_path);
        errdefer self.allocator.free(file_id);

        try self.cache.put(cache_key, file_id);
        return try self.allocator.dupe(u8, file_id);
    }

    fn resolveLocalPath(self: *ImageUploader, source: []const u8) ![:0]u8 {
        if (std.fs.path.isAbsolute(source)) {
            return try std.Io.Dir.cwd().realPathFileAlloc(self.io, source, self.allocator);
        }

        const joined = try std.fs.path.join(self.allocator, &[_][]const u8{ self.base_dir, source });
        defer self.allocator.free(joined);

        return try std.Io.Dir.cwd().realPathFileAlloc(self.io, joined, self.allocator);
    }

    fn normalizeCacheKey(self: *ImageUploader, path: []const u8) ![]const u8 {
        if (builtin.os.tag == .windows) {
            const normalized = try self.allocator.alloc(u8, path.len);
            for (path, 0..) |c, i| {
                normalized[i] = if (c == '\\') '/' else c;
            }
            return normalized;
        }
        return try self.allocator.dupe(u8, path);
    }

    fn ensureSupportedLocalImage(self: *ImageUploader, path: []const u8) !void {
        const ext = std.fs.path.extension(path);
        if (ext.len == 0) {
            return error.UnsupportedImageType;
        }

        if (!std.ascii.eqlIgnoreCase(ext, ".gif") and
            !std.ascii.eqlIgnoreCase(ext, ".jpg") and
            !std.ascii.eqlIgnoreCase(ext, ".jpeg") and
            !std.ascii.eqlIgnoreCase(ext, ".png") and
            !std.ascii.eqlIgnoreCase(ext, ".webp"))
        {
            return error.UnsupportedImageType;
        }

        const file = try std.Io.Dir.cwd().openFile(self.io, path, .{});
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        if (stat.size > 50 * 1024 * 1024) {
            return error.FileTooLarge;
        }
    }
};

pub const PreviewImageResolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PreviewImageResolver {
        return .{ .allocator = allocator };
    }

    pub fn parserResolver(self: *PreviewImageResolver) parser.ImageResolver {
        return .{
            .ctx = self,
            .resolve = resolveThunk,
        };
    }

    fn resolveThunk(ctx: *anyopaque, source: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *PreviewImageResolver = @ptrCast(@alignCast(ctx));
        return try self.resolve(source);
    }

    fn resolve(self: *PreviewImageResolver, source: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "dry-run:{s}", .{source});
    }
};

fn isRemoteSource(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "http://") or std.mem.startsWith(u8, source, "https://");
}
