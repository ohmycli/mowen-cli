const std = @import("std");
const builtin = @import("builtin");
const converter = @import("mowen-parser");
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

pub fn freeNoteAtom(allocator: std.mem.Allocator, atom: NoteAtom) void {
    switch (atom) {
        .text => |text| {
            allocator.free(text.text);
            if (text.marks.len > 0) {
                for (text.marks) |mark| {
                    switch (mark) {
                        .link => |link| allocator.free(link.href),
                        .bold => {},
                    }
                }
                allocator.free(text.marks);
            }
        },
        .paragraph => |para| {
            for (para.content) |child| freeNoteAtom(allocator, child);
            allocator.free(para.content);
        },
        .codeblock => |cb| {
            allocator.free(cb.attrs.language);
            for (cb.content) |child| freeNoteAtom(allocator, child);
            allocator.free(cb.content);
        },
        .quote => |quote| {
            for (quote.content) |child| freeNoteAtom(allocator, child);
            allocator.free(quote.content);
        },
        .doc => |doc| {
            for (doc.content) |child| freeNoteAtom(allocator, child);
            allocator.free(doc.content);
        },
        .image => |img| {
            allocator.free(img.attrs.uuid);
            allocator.free(img.attrs.alt);
        },
        .horizontal_rule => {},
    }
}
