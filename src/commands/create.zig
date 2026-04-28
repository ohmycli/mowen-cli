const std = @import("std");
const App = @import("../app.zig").App;
const config = @import("../config.zig");
const scanner = @import("../scanner.zig");
const converter = @import("mowen-parser");
const metadata = @import("../metadata.zig");
const types = @import("../core/api.zig");
const log = @import("../log.zig");
const logging = @import("zig-logging");
const builtin = @import("builtin");
const freeNoteAtom = @import("../commands/helpers.zig").freeNoteAtom;
const normalizePath = @import("../commands/helpers.zig").normalizePath;

pub fn run(app: *App, args: *std.process.Args.Iterator) !void {
    const allocator = app.allocator;
    const io = app.io;

    var file_path: ?[]const u8 = null;
    var tags_str: ?[]const u8 = null;
    var auto_publish = false;
    var dry_run = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            _ = args.next() orelse {
                std.debug.print("Error: --api-key requires a value\n", .{});
                return error.InvalidArgument;
            };
            // api-key already loaded in config at main level
        } else if (std.mem.eql(u8, arg, "--tags")) {
            tags_str = args.next() orelse {
                std.debug.print("Error: --tags requires a value\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--auto-publish")) {
            auto_publish = true;
        } else if (file_path == null) {
            file_path = arg;
        } else {
            std.debug.print("Error: Unexpected argument '{s}'\n", .{arg});
            return error.InvalidArgument;
        }
    }

    const file = file_path orelse {
        std.debug.print("Error: Missing file path\n", .{});
        std.debug.print("Usage: mowen-cli create <file> [options]\n", .{});
        return error.MissingArgument;
    };

    std.Io.Dir.cwd().access(io, file, .{}) catch |err| {
        log.err("create", "File not accessible", &.{
            logging.LogField.string("file", file),
            logging.LogField.string("error", @errorName(err)),
        });
        std.debug.print("Error: File '{s}' not found or not accessible: {s}\n", .{ file, @errorName(err) });
        return error.FileNotFound;
    };

    log.info("create", "Creating note from file", &.{
        logging.LogField.string("file", file),
        logging.LogField.boolean("auto_publish", auto_publish),
        logging.LogField.boolean("dry_run", dry_run),
    });

    // Parse tags
    var tags: std.ArrayList([]const u8) = .empty;
    defer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit(allocator);
    }

    if (tags_str) |ts| {
        var iter = std.mem.splitScalar(u8, ts, ',');
        while (iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                try tags.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    }

    // Read file
    const content = scanner.readFileContent(allocator, io, file) catch |err| {
        std.debug.print("Error: Failed to read file '{s}': {s}\n", .{ file, @errorName(err) });
        return err;
    };
    defer allocator.free(content);

    // Convert to NoteAtom
    const note_atom = converter.convert(allocator, content) catch |err| {
        std.debug.print("Error: Failed to convert markdown: {s}\n", .{@errorName(err)});
        return err;
    };
    defer {
        switch (note_atom) {
            .doc => |doc| {
                for (doc.content) |atom| freeNoteAtom(allocator, atom);
                allocator.free(doc.content);
            },
            else => {},
        }
    }

    // Init metadata
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(io);
    try meta_store.load(io);

    if (dry_run) {
        std.debug.print("[DRY RUN] Would create note from '{s}'\n", .{file});
        std.debug.print("  Tags: {s}\n", .{if (tags_str) |ts| ts else "(none)"});
        std.debug.print("  Auto-publish: {}\n", .{auto_publish});
        std.debug.print("  Content length: {} bytes\n", .{content.len});
        return;
    }

    try meta_store.ensureRateLimit(io);

    const settings = types.NoteRequest.NoteSettings{
        .autoPublish = if (auto_publish) true else app.config.auto_publish,
        .tags = tags.items,
    };

    std.debug.print("Creating note from '{s}'...\n", .{file});
    const note_id = app.api.createNote(note_atom.doc.content, settings) catch |err| {
        log.err("create", "Failed to create note", &.{
            logging.LogField.string("file", file),
            logging.LogField.string("error", @errorName(err)),
        });
        std.debug.print("Error: Failed to create note: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(note_id);

    log.info("create", "Note created successfully", &.{
        logging.LogField.string("note_id", note_id),
        logging.LogField.string("file", file),
    });

    // Save metadata
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(io, file, allocator);
    defer allocator.free(abs_path);

    const normalized_path = try normalizePath(allocator, abs_path);
    defer allocator.free(normalized_path);

    const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    const now = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
    const note_meta = metadata.NoteMetadata{
        .filePath = try allocator.dupe(u8, normalized_path),
        .noteId = try allocator.dupe(u8, note_id),
        .createdAt = now,
        .updatedAt = now,
    };

    try meta_store.notes.append(allocator, note_meta);
    try meta_store.save(io);

    std.debug.print("✓ Note created successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  File: {s}\n", .{normalized_path});
}

fn printHelp() void {
    std.debug.print(
        \\mowen-cli create - Create a new note
        \\
        \\USAGE:
        \\    mowen-cli create <file> [OPTIONS]
        \\
        \\ARGUMENTS:
        \\    <file>                     Path to the markdown file to upload
        \\
        \\OPTIONS:
        \\    --help, -h                 Show this help message
        \\    --api-key <KEY>            Override API key from config/env
        \\    --tags <TAGS>              Comma-separated tags (e.g., "tech,tutorial")
        \\    --auto-publish             Automatically publish the note
        \\    --dry-run                  Show what would be done without actually creating
        \\
    , .{});
}
