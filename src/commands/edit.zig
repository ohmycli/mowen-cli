const std = @import("std");
const App = @import("../app.zig").App;
const scanner = @import("../scanner.zig");
const converter = @import("mowen-parser");
const metadata = @import("../metadata.zig");
const log = @import("../log.zig");
const logging = @import("zig-logging");
const freeNoteAtom = @import("helpers.zig").freeNoteAtom;
const normalizePath = @import("helpers.zig").normalizePath;

pub fn run(app: *App, args: *std.process.Args.Iterator) !void {
    const allocator = app.allocator;
    const io = app.io;

    var file_path: ?[]const u8 = null;
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
        } else if (file_path == null) {
            file_path = arg;
        } else {
            std.debug.print("Error: Unexpected argument '{s}'\n", .{arg});
            return error.InvalidArgument;
        }
    }

    const file = file_path orelse {
        std.debug.print("Error: Missing file path\n", .{});
        std.debug.print("Usage: mowen-cli edit <file> [options]\n", .{});
        return error.MissingArgument;
    };

    std.Io.Dir.cwd().access(io, file, .{}) catch |err| {
        std.debug.print("Error: File '{s}' not found or not accessible: {s}\n", .{ file, @errorName(err) });
        return error.FileNotFound;
    };

    // Init metadata
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(io);
    try meta_store.load(io);

    // Get absolute path
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(io, file, allocator);
    defer allocator.free(abs_path);

    const normalized_path = try normalizePath(allocator, abs_path);
    defer allocator.free(normalized_path);

    // Find metadata
    var note_meta: ?*metadata.NoteMetadata = null;
    for (meta_store.notes.items) |*note| {
        if (std.mem.eql(u8, note.filePath, normalized_path)) {
            note_meta = note;
            break;
        }
    }

    const meta = note_meta orelse {
        std.debug.print("Error: No metadata found for '{s}'\n", .{file});
        std.debug.print("\nPossible reasons:\n", .{});
        std.debug.print("  1. This file has not been created yet\n", .{});
        std.debug.print("  2. The file was moved or renamed after creation\n", .{});
        std.debug.print("\nSolutions:\n", .{});
        std.debug.print("  - Use 'mowen-cli create {s}' to create a new note\n", .{file});
        std.debug.print("  - If the file was moved, manually edit .mowen/metadata.json to update the path\n", .{});
        return error.MetadataNotFound;
    };

    if (dry_run) {
        std.debug.print("[DRY RUN] Would edit note '{s}'\n", .{meta.noteId});
        std.debug.print("  File: {s}\n", .{file});
        std.debug.print("  Note ID: {s}\n", .{meta.noteId});
        return;
    }

    // Read file
    const content = scanner.readFileContent(allocator, io, file) catch |err| {
        std.debug.print("Error: Failed to read file '{s}': {s}\n", .{ file, @errorName(err) });
        return err;
    };
    defer allocator.free(content);

    // Convert
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

    try meta_store.ensureRateLimit(io);

    log.info("edit", "Editing note", &.{
        logging.LogField.string("note_id", meta.noteId),
        logging.LogField.string("file", file),
    });

    std.debug.print("Editing note '{s}'...\n", .{meta.noteId});
    const note_id = app.api.editNote(meta.noteId, note_atom.doc.content) catch |err| {
        log.err("edit", "Failed to edit note", &.{
            logging.LogField.string("note_id", meta.noteId),
            logging.LogField.string("error", @errorName(err)),
        });
        std.debug.print("Error: Failed to edit note: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(note_id);

    log.info("edit", "Note edited successfully", &.{
        logging.LogField.string("note_id", note_id),
        logging.LogField.string("file", file),
    });

    // Update metadata
    const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    meta.updatedAt = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
    try meta_store.save(io);

    std.debug.print("✓ Note edited successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  File: {s}\n", .{normalized_path});
}

fn printHelp() void {
    std.debug.print(
        \\mowen-cli edit - Edit an existing note
        \\
        \\USAGE:
        \\    mowen-cli edit <file> [OPTIONS]
        \\
        \\ARGUMENTS:
        \\    <file>                     Path to the markdown file (must have been created before)
        \\
        \\OPTIONS:
        \\    --help, -h                 Show this help message
        \\    --api-key <KEY>            Override API key from config/env
        \\    --dry-run                  Show what would be done without actually editing
        \\
    , .{});
}
