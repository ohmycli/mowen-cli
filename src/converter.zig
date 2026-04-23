const std = @import("std");
const parser = @import("parser.zig");
pub const NoteAtom = @import("core/types.zig").NoteAtom;

pub fn convertMarkdownToNoteAtom(allocator: std.mem.Allocator, markdown: []const u8) !NoteAtom {
    const tokens = try parser.tokenize(allocator, markdown);
    defer allocator.free(tokens);

    const atoms = try parser.tokensToNoteAtoms(allocator, tokens);

    return NoteAtom{ .doc = .{ .content = atoms } };
}
