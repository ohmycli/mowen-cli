const std = @import("std");

pub fn scanMarkdownFiles(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8) ![][]const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (files.items) |file| {
            allocator.free(file);
        }
        files.deinit(allocator);
    }

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.endsWith(u8, entry.name, ".md")) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            try files.append(allocator, full_path);
        }
    }

    return files.toOwnedSlice(allocator);
}

pub fn readFileContent(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.size == 0) {
        return error.EmptyFile;
    }

    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);

    return try file_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024));
}
