const std = @import("std");
const builtin = @import("builtin");
const NoteAtom = @import("mowen-parser").NoteAtom;

pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        const normalized = try allocator.alloc(u8, path.len);
        for (path, 0..) |c, i| {
            normalized[i] = if (c == '\\') '/' else c;
        }
        return normalized;
    } else {
        return try allocator.dupe(u8, path);
    }
}

/// Delegates to NoteAtom.deinit — single source of truth for cleanup.
pub fn freeNoteAtom(allocator: std.mem.Allocator, atom: NoteAtom) void {
    atom.deinit(allocator);
}
