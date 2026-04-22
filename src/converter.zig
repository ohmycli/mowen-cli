const std = @import("std");
const parser = @import("parser.zig");
const NoteAtom = @import("note_atom.zig").NoteAtom;

pub fn convertMarkdownToNoteAtom(allocator: std.mem.Allocator, markdown: []const u8) !NoteAtom {
    const tokens = try parser.tokenize(allocator, markdown);
    defer allocator.free(tokens);
    // Note: Don't free token contents here - they are transferred to NoteAtom
    // and will be freed by freeNoteAtom in main.zig

    const atoms = try parser.tokensToNoteAtoms(allocator, tokens);

    return NoteAtom{ .doc = .{ .content = atoms } };
}
