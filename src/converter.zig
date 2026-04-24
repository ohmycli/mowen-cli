const std = @import("std");
const parser = @import("parser.zig");
pub const NoteAtom = @import("core/types.zig").NoteAtom;

pub fn convertMarkdownToNoteAtom(allocator: std.mem.Allocator, markdown: []const u8) !NoteAtom {
    return try convertMarkdownToNoteAtomWithResolver(allocator, markdown, null);
}

pub fn convertMarkdownToNoteAtomWithResolver(
    allocator: std.mem.Allocator,
    markdown: []const u8,
    image_resolver: ?parser.ImageResolver,
) !NoteAtom {
    const tokens = try parser.tokenize(allocator, markdown);
    defer allocator.free(tokens);

    const atoms = try parser.tokensToNoteAtomsWithResolver(allocator, tokens, image_resolver);

    return NoteAtom{ .doc = .{ .content = atoms } };
}
