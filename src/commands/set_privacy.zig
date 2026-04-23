const std = @import("std");
const App = @import("../app.zig").App;
const metadata = @import("../metadata.zig");
const log = @import("../log.zig");
const normalizePath = @import("helpers.zig").normalizePath;

pub fn run(app: *App, args: *std.process.Args.Iterator) !void {
    const allocator = app.allocator;
    const io = app.io;

    var file_path: ?[]const u8 = null;
    var privacy: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, arg, "--privacy")) {
            privacy = args.next() orelse {
                std.debug.print("Error: --privacy requires a value\n", .{});
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
        std.debug.print("Usage: mowen-cli set-privacy <file> --privacy <public|private|rule> [options]\n", .{});
        return error.MissingArgument;
    };

    const priv = privacy orelse {
        std.debug.print("Error: Missing --privacy option\n", .{});
        std.debug.print("Usage: mowen-cli set-privacy <file> --privacy <public|private|rule> [options]\n", .{});
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
        std.debug.print("[DRY RUN] Would set privacy for note '{s}' to '{s}'\n", .{ meta.noteId, priv });
        std.debug.print("  File: {s}\n", .{file});
        std.debug.print("  Note ID: {s}\n", .{meta.noteId});
        return;
    }

    try meta_store.ensureRateLimit(io);

    std.debug.print("Setting privacy for note '{s}' to '{s}'...\n", .{ meta.noteId, priv });
    const note_id = app.api.setPrivacy(meta.noteId, priv) catch |err| {
        std.debug.print("Error: Failed to set privacy: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(note_id);

    std.debug.print("✓ Privacy set successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  Privacy: {s}\n", .{priv});
}

fn printHelp() void {
    std.debug.print(
        \\mowen-cli set-privacy - Set privacy level for an existing note
        \\
        \\USAGE:
        \\    mowen-cli set-privacy <file> --privacy <LEVEL> [OPTIONS]
        \\
        \\ARGUMENTS:
        \\    <file>                     Path to the markdown file (must have been created before)
        \\
        \\OPTIONS:
        \\    --help, -h                 Show this help message
        \\    --privacy <LEVEL>          Privacy level: "public" or "private" (required)
        \\    --api-key <KEY>            Override API key from config/env
        \\    --dry-run                  Show what would be done without actually changing privacy
        \\
    , .{});
}
