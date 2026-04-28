const std = @import("std");
const App = @import("../app.zig").App;
const scanner = @import("../scanner.zig");
const converter = @import("mowen-parser");
const metadata = @import("../metadata.zig");
const types = @import("../core/api.zig");
const freeNoteAtom = @import("helpers.zig").freeNoteAtom;
const normalizePath = @import("helpers.zig").normalizePath;

pub fn run(app: *App, args: *std.process.Args.Iterator) !void {
    const allocator = app.allocator;
    const io = app.io;

    var dry_run = false;
    var tags_str: ?[]const u8 = null;
    var auto_publish = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--auto-publish")) {
            auto_publish = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            _ = args.next() orelse {
                std.debug.print("Error: --api-key requires a value\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--tags")) {
            tags_str = args.next() orelse {
                std.debug.print("Error: --tags requires a value\n", .{});
                return error.InvalidArgument;
            };
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }

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

    // Scan markdown files
    const files = try scanner.scanMarkdownFiles(allocator, io, ".");
    defer {
        for (files) |file| allocator.free(file);
        allocator.free(files);
    }

    if (files.len == 0) {
        std.debug.print("No markdown files found in current directory.\n", .{});
        return;
    }

    std.debug.print("Found {d} markdown file(s)\n", .{files.len});

    if (dry_run) {
        std.debug.print("\n[DRY RUN MODE - No files will be uploaded]\n\n", .{});
        for (files) |file| {
            std.debug.print("  - {s}\n", .{file});
        }
        return;
    }

    // Init metadata
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(io);
    try meta_store.load(io);

    var success_count: usize = 0;
    var fail_count: usize = 0;

    for (files, 0..) |file, idx| {
        std.debug.print("\r[{d}/{d}] Uploading {s}...", .{ idx + 1, files.len, file });

        const content = scanner.readFileContent(allocator, io, file) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
        };
        defer allocator.free(content);

        const note_atom = converter.convert(allocator, content) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
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

        const settings = types.NoteRequest.NoteSettings{
            .autoPublish = if (auto_publish) true else app.config.auto_publish,
            .tags = tags.items,
        };

        const note_id = app.api.createNote(note_atom.doc.content, settings) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
        };
        defer allocator.free(note_id);

        std.debug.print(" OK (ID: {s})\n", .{note_id});
        success_count += 1;

        // Save metadata
        const abs_path = std.Io.Dir.cwd().realPathFileAlloc(io, file, allocator) catch |err| {
            std.debug.print("  Warning: Failed to get absolute path: {s}\n", .{@errorName(err)});
            if (idx + 1 < files.len) {
                io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
            }
            continue;
        };
        defer allocator.free(abs_path);

        const np = normalizePath(allocator, abs_path) catch |err| {
            std.debug.print("  Warning: Failed to normalize path: {s}\n", .{@errorName(err)});
            if (idx + 1 < files.len) {
                io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
            }
            continue;
        };
        defer allocator.free(np);

        // Check if metadata already exists
        var found = false;
        for (meta_store.notes.items) |*note| {
            if (std.mem.eql(u8, note.filePath, np)) {
                allocator.free(note.noteId);
                note.noteId = try allocator.dupe(u8, note_id);
                const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
                note.updatedAt = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
                found = true;
                break;
            }
        }

        if (!found) {
            const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
            const now = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
            const note_meta = metadata.NoteMetadata{
                .filePath = try allocator.dupe(u8, np),
                .noteId = try allocator.dupe(u8, note_id),
                .createdAt = now,
                .updatedAt = now,
            };
            try meta_store.notes.append(allocator, note_meta);
        }

        // Rate limiting
        if (idx + 1 < files.len) {
            io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
        }
    }

    if (success_count > 0) {
        meta_store.save(io) catch |err| {
            std.debug.print("\nWarning: Failed to save metadata: {s}\n", .{@errorName(err)});
            std.debug.print("Note IDs were not saved. You won't be able to use 'edit' or 'set-privacy' commands.\n", .{});
        };
    }

    std.debug.print("\n✓ Upload complete: {d} succeeded, {d} failed\n", .{ success_count, fail_count });
    if (success_count > 0) {
        std.debug.print("  Metadata saved to .mowen/metadata.json\n", .{});
        std.debug.print("  You can now use 'edit' and 'set-privacy' commands on these files.\n", .{});
    }
}
