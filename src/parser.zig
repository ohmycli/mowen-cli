const std = @import("std");
const NoteAtom = @import("note_atom.zig").NoteAtom;

pub const Token = union(enum) {
    heading: struct { level: u8, text: []const u8 },
    paragraph: []const u8,
    bold: []const u8,
    link: struct { text: []const u8, url: []const u8 },
    quote: []const u8,
    text: []const u8,
    code_block: struct { language: []const u8, code: []const u8 },
    horizontal_rule: void,
};

pub fn tokenize(allocator: std.mem.Allocator, content: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_para = std.ArrayList(u8).empty;
    defer current_para.deinit(allocator);

    var in_code_block = false;
    var code_language = std.ArrayList(u8).empty;
    defer code_language.deinit(allocator);
    var code_content = std.ArrayList(u8).empty;
    defer code_content.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Code block fence
        if (std.mem.startsWith(u8, trimmed, "```")) {
            if (current_para.items.len > 0) {
                try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
                current_para.clearRetainingCapacity();
            }

            if (!in_code_block) {
                // Start of code block
                in_code_block = true;
                const lang = std.mem.trim(u8, trimmed[3..], " ");
                try code_language.appendSlice(allocator, lang);
            } else {
                // End of code block
                in_code_block = false;
                try tokens.append(allocator, .{ .code_block = .{
                    .language = try code_language.toOwnedSlice(allocator),
                    .code = try code_content.toOwnedSlice(allocator),
                } });
                code_language.clearRetainingCapacity();
                code_content.clearRetainingCapacity();
            }
            continue;
        }

        // Inside code block
        if (in_code_block) {
            if (code_content.items.len > 0) {
                try code_content.append(allocator, '\n');
            }
            try code_content.appendSlice(allocator, line);
            continue;
        }

        // Horizontal rule
        if (std.mem.eql(u8, trimmed, "---") or std.mem.eql(u8, trimmed, "***") or std.mem.eql(u8, trimmed, "___")) {
            if (current_para.items.len > 0) {
                try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
                current_para.clearRetainingCapacity();
            }
            try tokens.append(allocator, .{ .horizontal_rule = {} });
            continue;
        }

        if (trimmed.len == 0) {
            if (current_para.items.len > 0) {
                try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
                current_para.clearRetainingCapacity();
            }
            continue;
        }

        // Heading
        if (std.mem.startsWith(u8, trimmed, "#")) {
            if (current_para.items.len > 0) {
                try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
                current_para.clearRetainingCapacity();
            }

            var level: u8 = 0;
            var i: usize = 0;
            while (i < trimmed.len and trimmed[i] == '#' and level < 6) : (i += 1) {
                level += 1;
            }

            const text = std.mem.trim(u8, trimmed[i..], " ");
            try tokens.append(allocator, .{ .heading = .{ .level = level, .text = try allocator.dupe(u8, text) } });
            continue;
        }

        // Quote
        if (std.mem.startsWith(u8, trimmed, ">")) {
            if (current_para.items.len > 0) {
                try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
                current_para.clearRetainingCapacity();
            }

            const text = std.mem.trim(u8, trimmed[1..], " ");
            try tokens.append(allocator, .{ .quote = try allocator.dupe(u8, text) });
            continue;
        }

        // Regular paragraph line
        if (current_para.items.len > 0) {
            try current_para.append(allocator, ' ');
        }
        try current_para.appendSlice(allocator, trimmed);
    }

    if (current_para.items.len > 0) {
        try tokens.append(allocator, .{ .paragraph = try current_para.toOwnedSlice(allocator) });
    }

    return tokens.toOwnedSlice(allocator);
}

fn parseInlineMarkup(allocator: std.mem.Allocator, text: []const u8) ![]NoteAtom {
    var atoms = std.ArrayList(NoteAtom).empty;
    errdefer atoms.deinit(allocator);

    var i: usize = 0;
    var current_text = std.ArrayList(u8).empty;
    defer current_text.deinit(allocator);

    while (i < text.len) {
        // Bold **text**
        if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
            if (current_text.items.len > 0) {
                try atoms.append(allocator, .{ .text = .{ .text = try current_text.toOwnedSlice(allocator) } });
                current_text.clearRetainingCapacity();
            }

            i += 2;
            const start = i;
            while (i + 1 < text.len) : (i += 1) {
                if (text[i] == '*' and text[i + 1] == '*') break;
            }

            if (i + 1 < text.len) {
                const bold_text = try allocator.dupe(u8, text[start..i]);
                const marks = try allocator.alloc(NoteAtom.Mark, 1);
                marks[0] = .{ .bold = {} };
                try atoms.append(allocator, .{ .text = .{
                    .text = bold_text,
                    .marks = marks,
                } });
                i += 2;
            }
            continue;
        }

        // Link [text](url)
        if (text[i] == '[') {
            if (current_text.items.len > 0) {
                try atoms.append(allocator, .{ .text = .{ .text = try current_text.toOwnedSlice(allocator) } });
                current_text.clearRetainingCapacity();
            }

            i += 1;
            const text_start = i;
            while (i < text.len and text[i] != ']') : (i += 1) {}

            if (i < text.len and i + 1 < text.len and text[i + 1] == '(') {
                const link_text = text[text_start..i];
                i += 2;
                const url_start = i;
                while (i < text.len and text[i] != ')') : (i += 1) {}

                if (i < text.len) {
                    const url = try allocator.dupe(u8, text[url_start..i]);
                    const link_text_copy = try allocator.dupe(u8, link_text);
                    const marks = try allocator.alloc(NoteAtom.Mark, 1);
                    marks[0] = .{ .link = .{ .href = url } };
                    try atoms.append(allocator, .{ .text = .{
                        .text = link_text_copy,
                        .marks = marks,
                    } });
                    i += 1;
                }
            }
            continue;
        }

        try current_text.append(allocator, text[i]);
        i += 1;
    }

    if (current_text.items.len > 0) {
        try atoms.append(allocator, .{ .text = .{ .text = try current_text.toOwnedSlice(allocator) } });
    }

    return atoms.toOwnedSlice(allocator);
}

pub fn tokensToNoteAtoms(allocator: std.mem.Allocator, tokens: []Token) ![]NoteAtom {
    var atoms = std.ArrayList(NoteAtom).empty;
    errdefer atoms.deinit(allocator);

    for (tokens) |token| {
        switch (token) {
            .heading => |h| {
                const inline_content = try parseInlineMarkup(allocator, h.text);
                try atoms.append(allocator, .{ .paragraph = .{ .content = inline_content } });
                // 释放原始 heading.text，因为 parseInlineMarkup 创建了新的副本
                allocator.free(h.text);
            },
            .paragraph => |p| {
                const inline_content = try parseInlineMarkup(allocator, p);
                try atoms.append(allocator, .{ .paragraph = .{ .content = inline_content } });
                // 释放原始 paragraph 字符串
                allocator.free(p);
            },
            .quote => |q| {
                const inline_content = try parseInlineMarkup(allocator, q);
                const quote_content = try allocator.alloc(NoteAtom, 1);
                quote_content[0] = .{ .paragraph = .{ .content = inline_content } };
                try atoms.append(allocator, .{ .quote = .{ .content = quote_content } });
                // 释放原始 quote 字符串
                allocator.free(q);
            },
            .code_block => |cb| {
                // Create text node for code content
                const code_text = try allocator.alloc(NoteAtom, 1);
                code_text[0] = .{ .text = .{ .text = cb.code } };
                try atoms.append(allocator, .{ .codeblock = .{
                    .attrs = .{ .language = cb.language },
                    .content = code_text,
                } });
                // cb.code 和 cb.language 的所有权已转移到 NoteAtom，不需要释放
            },
            .horizontal_rule => {
                try atoms.append(allocator, .{ .horizontal_rule = {} });
            },
            else => {},
        }
    }

    return atoms.toOwnedSlice(allocator);
}
