const std = @import("std");

pub const NoteAtom = union(enum) {
    doc: Doc,
    paragraph: Paragraph,
    text: Text,
    quote: Quote,
    codeblock: CodeBlock,
    horizontal_rule: void,

    pub const Doc = struct {
        content: []NoteAtom,
    };

    pub const Paragraph = struct {
        content: []NoteAtom,
    };

    pub const Text = struct {
        text: []const u8,
        marks: []Mark = &[_]Mark{},
    };

    pub const Quote = struct {
        content: []NoteAtom,
    };

    pub const CodeBlock = struct {
        attrs: Attrs,
        content: []NoteAtom,

        pub const Attrs = struct {
            language: []const u8,
        };
    };

    pub const Mark = union(enum) {
        bold: void,
        link: Link,

        pub const Link = struct {
            href: []const u8,
        };
    };

    pub fn jsonStringify(self: NoteAtom, writer: anytype) !void {
        switch (self) {
            .doc => |doc| {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("doc");
                try writer.objectField("content");
                try writer.beginArray();
                for (doc.content) |item| {
                    try item.jsonStringify(writer);
                }
                try writer.endArray();
                try writer.endObject();
            },
            .paragraph => |para| {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("paragraph");
                try writer.objectField("content");
                try writer.beginArray();
                for (para.content) |item| {
                    try item.jsonStringify(writer);
                }
                try writer.endArray();
                try writer.endObject();
            },
            .text => |txt| {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("text");
                try writer.objectField("text");
                try writer.write(txt.text);
                if (txt.marks.len > 0) {
                    try writer.objectField("marks");
                    try writer.beginArray();
                    for (txt.marks) |mark| {
                        try writer.beginObject();
                        switch (mark) {
                            .bold => {
                                try writer.objectField("type");
                                try writer.write("bold");
                            },
                            .link => |link| {
                                try writer.objectField("type");
                                try writer.write("link");
                                try writer.objectField("attrs");
                                try writer.beginObject();
                                try writer.objectField("href");
                                try writer.write(link.href);
                                try writer.endObject();
                            },
                        }
                        try writer.endObject();
                    }
                    try writer.endArray();
                }
                try writer.endObject();
            },
            .quote => |quote| {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("quote");
                try writer.objectField("content");
                try writer.beginArray();
                for (quote.content) |item| {
                    try item.jsonStringify(writer);
                }
                try writer.endArray();
                try writer.endObject();
            },
            .codeblock => |cb| {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("codeblock");
                try writer.objectField("attrs");
                try writer.beginObject();
                try writer.objectField("language");
                try writer.print("\"{s}\"", .{cb.attrs.language});
                try writer.endObject();
                try writer.objectField("content");
                try writer.beginArray();
                for (cb.content) |item| {
                    try item.jsonStringify(writer);
                }
                try writer.endArray();
                try writer.endObject();
            },
            .horizontal_rule => {
                try writer.beginObject();
                try writer.objectField("type");
                try writer.write("paragraph");
                try writer.objectField("content");
                try writer.beginArray();
                try writer.endArray();
                try writer.endObject();
            },
        }
    }
};

pub const NoteRequest = struct {
    body: NoteAtom,
    settings: NoteSettings,

    pub const NoteSettings = struct {
        autoPublish: bool = false,
        tags: [][]const u8 = &[_][]const u8{},
    };
};
