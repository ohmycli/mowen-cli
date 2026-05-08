const std = @import("std");
const metadata = @import("../metadata.zig");

/// Parse comma-separated tags string into allocated slice.
pub fn parseTags(allocator: std.mem.Allocator, tags_str: ?[]const u8) !std.ArrayList([]const u8) {
    var tags: std.ArrayList([]const u8) = .empty;
    if (tags_str) |ts| {
        var iter = std.mem.splitScalar(u8, ts, ',');
        while (iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                try tags.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    }
    return tags;
}

/// Free a tags list.
pub fn freeTags(allocator: std.mem.Allocator, tags: *std.ArrayList([]const u8)) void {
    for (tags.items) |tag| allocator.free(tag);
    tags.deinit(allocator);
}

/// Get current time in milliseconds.
pub fn nowMillis(io: std.Io) i64 {
    const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    return @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
}

/// Build a NoteMetadata entry for a file.
pub fn buildNoteMetadata(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, note_id: []const u8) !metadata.NoteMetadata {
    const now = nowMillis(io);
    return metadata.NoteMetadata{
        .filePath = try allocator.dupe(u8, file_path),
        .noteId = try allocator.dupe(u8, note_id),
        .createdAt = now,
        .updatedAt = now,
    };
}
