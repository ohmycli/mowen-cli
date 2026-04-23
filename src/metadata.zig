const std = @import("std");
const builtin = @import("builtin");

pub const NoteMetadata = struct {
    filePath: []const u8,
    noteId: []const u8,
    createdAt: i64,
    updatedAt: i64,

    pub fn deinit(self: *NoteMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.filePath);
        allocator.free(self.noteId);
    }
};

pub const MetadataStore = struct {
    allocator: std.mem.Allocator,
    notes: std.ArrayList(NoteMetadata),
    last_api_call_time: ?i64,
    lock_file: ?std.Io.File,

    pub fn init(allocator: std.mem.Allocator) MetadataStore {
        return .{
            .allocator = allocator,
            .notes = .empty,
            .last_api_call_time = null,
            .lock_file = null,
        };
    }

    pub fn normalizePath(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
        const real_path = std.Io.Dir.cwd().realpathAlloc(io, allocator, path) catch |err| blk: {
            if (err == error.AccessDenied or err == error.NotSupported) {
                std.debug.print("[WARN] Failed to resolve symlink, falling back to absolute path: {s}\n", .{@errorName(err)});
                break :blk try std.Io.Dir.cwd().realpathAlloc(io, allocator, path);
            }
            return err;
        };

        if (builtin.os.tag == .windows) {
            for (real_path) |*c| {
                if (c.* == '\\') c.* = '/';
            }
        }
        return real_path;
    }

    pub fn load(self: *MetadataStore, io: std.Io) !void {
        const metadata_dir = ".mowen";
        const metadata_file = ".mowen/metadata.json";
        const lock_file_path = ".mowen/metadata.lock";
        const tmp_file_path = ".mowen/metadata.json.tmp";

        std.Io.Dir.cwd().createDirPath(io, metadata_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        std.Io.Dir.cwd().deleteFile(io, tmp_file_path) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("[WARN] Failed to clean up temp file: {s}\n", .{@errorName(err)});
            }
        };

        const lock_file = try std.Io.Dir.cwd().createFile(io, lock_file_path, .{ .read = true });
        lock_file.lock(io, .exclusive) catch |err| {
            lock_file.close(io);
            if (err == error.WouldBlock) {
                std.debug.print("Error: Another mowen-cli instance is running. Please wait for it to finish.\n", .{});
                return error.ConcurrentAccess;
            }
            return err;
        };
        self.lock_file = lock_file;

        const file = std.Io.Dir.cwd().openFile(io, metadata_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try self.createEmptyMetadata(io, metadata_file);
                return;
            }
            return err;
        };
        defer file.close(io);

        const stat = try file.stat(io);
        if (stat.size > 10 * 1024 * 1024) {
            std.debug.print("[WARN] Metadata file is larger than 10MB ({} bytes). Consider running 'mowen-cli cleanup' to remove invalid entries.\n", .{stat.size});
        }

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        const content = try file_reader.interface.allocRemaining(self.allocator, std.Io.Limit.limited(100 * 1024 * 1024));
        defer self.allocator.free(content);

        self.parseMetadata(content) catch |err| {
            std.debug.print("[WARN] Failed to parse metadata: {s}, attempting recovery from backup...\n", .{@errorName(err)});
            try self.recoverFromBackup(io);
        };
    }

    fn createEmptyMetadata(_: *MetadataStore, io: std.Io, path: []const u8) !void {
        const empty_json = "{\"notes\":[],\"last_api_call_time\":null}";
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);
        try writer.interface.writeAll(empty_json);
        try writer.flush();
    }

    fn parseMetadata(self: *MetadataStore, content: []const u8) !void {
        const parsed = try std.json.parseFromSlice(
            struct {
                notes: []struct {
                    filePath: []const u8,
                    noteId: []const u8,
                    createdAt: i64,
                    updatedAt: i64,
                },
                last_api_call_time: ?i64,
            },
            self.allocator,
            content,
            .{},
        );
        defer parsed.deinit();

        self.last_api_call_time = parsed.value.last_api_call_time;

        for (parsed.value.notes) |note| {
            try self.notes.append(self.allocator, .{
                .filePath = try self.allocator.dupe(u8, note.filePath),
                .noteId = try self.allocator.dupe(u8, note.noteId),
                .createdAt = note.createdAt,
                .updatedAt = note.updatedAt,
            });
        }
    }

    fn recoverFromBackup(self: *MetadataStore, io: std.Io) !void {
        const backup_path = ".mowen/metadata.json.bak";
        const file = std.Io.Dir.cwd().openFile(io, backup_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("[WARN] No backup found. Creating empty metadata.\n", .{});
                try self.createEmptyMetadata(io, ".mowen/metadata.json");
                return;
            }
            return err;
        };
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        const content = try file_reader.interface.allocRemaining(self.allocator, std.Io.Limit.limited(100 * 1024 * 1024));
        defer self.allocator.free(content);

        self.parseMetadata(content) catch |err| {
            std.debug.print("[ERROR] Backup is also corrupted: {s}. Creating empty metadata. Historical data is lost.\n", .{@errorName(err)});
            try self.createEmptyMetadata(io, ".mowen/metadata.json");
            return;
        };

        std.debug.print("[INFO] Successfully recovered from backup.\n", .{});
    }

    pub fn save(self: *MetadataStore, io: std.Io) !void {
        const metadata_file = ".mowen/metadata.json";
        const backup_file = ".mowen/metadata.json.bak";
        const tmp_file = ".mowen/metadata.json.tmp";

        std.Io.Dir.cwd().copyFile(metadata_file, std.Io.Dir.cwd(), backup_file, io, .{}) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("[WARN] Failed to create backup: {s}\n", .{@errorName(err)});
            }
        };

        var json_buffer: std.ArrayList(u8) = .empty;
        defer json_buffer.deinit(self.allocator);

        try json_buffer.appendSlice(self.allocator, "{\"notes\":[");

        for (self.notes.items, 0..) |note, i| {
            if (i > 0) try json_buffer.appendSlice(self.allocator, ",");
            const note_json = try std.fmt.allocPrint(self.allocator, "{{\"filePath\":\"{s}\",\"noteId\":\"{s}\",\"createdAt\":{},\"updatedAt\":{}}}", .{
                note.filePath,
                note.noteId,
                note.createdAt,
                note.updatedAt,
            });
            defer self.allocator.free(note_json);
            try json_buffer.appendSlice(self.allocator, note_json);
        }

        try json_buffer.appendSlice(self.allocator, "],\"last_api_call_time\":");
        if (self.last_api_call_time) |time| {
            const time_str = try std.fmt.allocPrint(self.allocator, "{}", .{time});
            defer self.allocator.free(time_str);
            try json_buffer.appendSlice(self.allocator, time_str);
        } else {
            try json_buffer.appendSlice(self.allocator, "null");
        }
        try json_buffer.appendSlice(self.allocator, "}");

        {
            const file = try std.Io.Dir.cwd().createFile(io, tmp_file, .{});
            defer file.close(io);

            var buffer: [4096]u8 = undefined;
            var file_writer = file.writer(io, &buffer);
            try file_writer.interface.writeAll(json_buffer.items);
            try file_writer.flush();
        }

        try std.Io.Dir.cwd().rename(tmp_file, std.Io.Dir.cwd(), metadata_file, io);
    }

    pub fn findByPath(self: *MetadataStore, path: []const u8) ?[]const u8 {
        for (self.notes.items) |note| {
            if (std.mem.eql(u8, note.filePath, path)) {
                return note.noteId;
            }
        }
        return null;
    }

    pub fn upsert(self: *MetadataStore, path: []const u8, note_id: []const u8, created_at: i64, updated_at: i64) !void {
        for (self.notes.items) |*note| {
            if (std.mem.eql(u8, note.filePath, path)) {
                self.allocator.free(note.noteId);
                note.noteId = try self.allocator.dupe(u8, note_id);
                note.updatedAt = updated_at;
                return;
            }
        }

        try self.notes.append(self.allocator, .{
            .filePath = try self.allocator.dupe(u8, path),
            .noteId = try self.allocator.dupe(u8, note_id),
            .createdAt = created_at,
            .updatedAt = updated_at,
        });
    }

    pub fn deinit(self: *MetadataStore, io: std.Io) void {
        for (self.notes.items) |*note| {
            note.deinit(self.allocator);
        }
        self.notes.deinit(self.allocator);

        if (self.lock_file) |lock_file| {
            lock_file.unlock(io);
            lock_file.close(io);
            std.Io.Dir.cwd().deleteFile(io, ".mowen/metadata.lock") catch {};
        }
    }

    pub fn ensureRateLimit(self: *MetadataStore, io: std.Io) !void {
        if (self.last_api_call_time) |last_time| {
            const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
            const now: i64 = @intCast(@divFloor(now_ns, std.time.ns_per_ms));
            const elapsed = now - last_time;
            if (elapsed < 1000) {
                const wait_ms: u64 = @intCast(1000 - elapsed);
                const wait_ns: u64 = wait_ms * std.time.ns_per_ms;
                std.debug.print("[INFO] Rate limiting: waiting {}ms before API call...\n", .{wait_ms});
                const wait_duration = std.Io.Duration{ .nanoseconds = @intCast(wait_ns) };
                try io.sleep(wait_duration, .real);
            }
        }
        const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
        self.last_api_call_time = @intCast(@divFloor(now_ns, std.time.ns_per_ms));
        try self.save(io);
    }
};
