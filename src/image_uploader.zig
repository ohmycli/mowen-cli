const std = @import("std");
const converter = @import("mowen-parser");
const Api = @import("core/api.zig").Api;
const metadata = @import("metadata.zig");
const log = @import("log.zig");
const logging = @import("zig-logging");

pub const ImageUploader = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api: Api,
    rate_limiter: *metadata.MetadataStore,
    cache: std.StringHashMap([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        api: Api,
        rate_limiter: *metadata.MetadataStore,
    ) ImageUploader {
        return .{
            .allocator = allocator,
            .io = io,
            .api = api,
            .rate_limiter = rate_limiter,
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
    }

    pub fn resolver(self: *ImageUploader) converter.ImageResolver {
        return .{
            .ctx = @ptrCast(self),
            .resolve = resolveThunk,
        };
    }

    fn resolveThunk(ctx: *anyopaque, source: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *ImageUploader = @ptrCast(@alignCast(ctx));
        return try self.resolve(source);
    }

    fn resolve(self: *ImageUploader, source: []const u8) ![]const u8 {
        // Check cache first
        if (self.cache.get(source)) |cached| {
            return try self.allocator.dupe(u8, cached);
        }

        // Only handle remote URLs
        if (!std.mem.startsWith(u8, source, "http://") and !std.mem.startsWith(u8, source, "https://")) {
            log.err("image_uploader", "Local images not supported in this version", &.{
                logging.LogField.string("source", source),
            });
            return error.UnsupportedImageType;
        }

        try self.rate_limiter.ensureRateLimit(self.io);

        log.info("image_uploader", "Uploading image from URL", &.{
            logging.LogField.string("url", source),
        });

        const file_id = try self.api.uploadImageFromUrl(source);
        errdefer self.allocator.free(file_id);

        // Cache the result
        const cache_key = try self.allocator.dupe(u8, source);
        try self.cache.put(cache_key, file_id);

        return try self.allocator.dupe(u8, file_id);
    }
};

/// A dummy resolver for dry-run mode that returns a placeholder UUID.
pub const DryRunResolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DryRunResolver {
        return .{ .allocator = allocator };
    }

    pub fn resolver(self: *DryRunResolver) converter.ImageResolver {
        return .{
            .ctx = @ptrCast(self),
            .resolve = resolveThunk,
        };
    }

    fn resolveThunk(ctx: *anyopaque, source: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *DryRunResolver = @ptrCast(@alignCast(ctx));
        return try std.fmt.allocPrint(self.allocator, "dry-run:{s}", .{source});
    }
};
