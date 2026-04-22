const std = @import("std");
const config = @import("config.zig");
const scanner = @import("scanner.zig");
const converter = @import("converter.zig");
const uploader = @import("uploader.zig");
const NoteRequest = @import("note_atom.zig").NoteRequest;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iter.deinit();

    var show_help = false;
    var show_version = false;
    var dry_run = false;
    var api_key_override: ?[]const u8 = null;
    var tags_str: ?[]const u8 = null;
    var auto_publish = false;

    _ = args_iter.next(); // Skip program name

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            show_version = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--auto-publish")) {
            auto_publish = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            const key = args_iter.next() orelse {
                std.debug.print("Error: --api-key requires a value\n", .{});
                return error.InvalidArgument;
            };
            api_key_override = key;
        } else if (std.mem.eql(u8, arg, "--tags")) {
            const tags = args_iter.next() orelse {
                std.debug.print("Error: --tags requires a value\n", .{});
                return error.InvalidArgument;
            };
            tags_str = tags;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }

    if (show_help) {
        printHelp();
        return;
    }

    if (show_version) {
        printVersion();
        return;
    }

    // Load config
    const cli_args = config.CliArgs{
        .api_key = api_key_override,
        .auto_publish = if (auto_publish) true else null,
        .tags = null, // Will parse tags separately
    };

    var cfg = config.loadConfig(allocator, init.io, init.environ_map, cli_args) catch |err| {
        if (err == config.ConfigError.ApiKeyMissing) {
            std.debug.print("Error: No API key found. Please set MOWEN_API_KEY environment variable or use --api-key flag.\n", .{});
            return error.NoApiKey;
        }
        return err;
    };
    defer cfg.deinit();

    // Parse tags
    var tags: std.ArrayList([]const u8) = .empty;
    defer {
        for (tags.items) |tag| {
            allocator.free(tag);
        }
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
    const files = try scanner.scanMarkdownFiles(allocator, init.io, ".");
    defer {
        for (files) |file| {
            allocator.free(file);
        }
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

    // Upload files
    var upload_client = uploader.Uploader.init(allocator, init.io, cfg.api_key, cfg.api_endpoint);

    var success_count: usize = 0;
    var fail_count: usize = 0;

    for (files, 0..) |file, idx| {
        std.debug.print("\r[{d}/{d}] Uploading {s}...", .{ idx + 1, files.len, file });

        const content = scanner.readFileContent(allocator, init.io, file) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
        };
        defer allocator.free(content);

        const note_atom = converter.convertMarkdownToNoteAtom(allocator, content) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
        };
        defer {
            switch (note_atom) {
                .doc => |doc| {
                    for (doc.content) |atom| {
                        freeNoteAtom(allocator, atom);
                    }
                    allocator.free(doc.content);
                },
                else => {},
            }
        }

        const settings = NoteRequest.NoteSettings{
            .autoPublish = cfg.auto_publish,
            .tags = tags.items,
        };

        const note_id = upload_client.upload(note_atom.doc.content, settings) catch |err| {
            std.debug.print(" FAILED ({s})\n", .{@errorName(err)});
            fail_count += 1;
            continue;
        };
        defer allocator.free(note_id);

        std.debug.print(" OK (ID: {s})\n", .{note_id});
        success_count += 1;

        // Rate limiting: 1 request per second
        if (idx + 1 < files.len) {
            init.io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
        }
    }

    std.debug.print("\n✓ Upload complete: {d} succeeded, {d} failed\n", .{ success_count, fail_count });
}

fn freeNoteAtom(allocator: std.mem.Allocator, atom: @import("note_atom.zig").NoteAtom) void {
    switch (atom) {
        .paragraph => |para| {
            for (para.content) |item| {
                freeNoteAtom(allocator, item);
            }
            allocator.free(para.content);
        },
        .text => |txt| {
            allocator.free(txt.text);
            for (txt.marks) |mark| {
                switch (mark) {
                    .link => |link| allocator.free(link.href),
                    else => {},
                }
            }
            allocator.free(txt.marks);
        },
        .quote => |quote| {
            for (quote.content) |item| {
                freeNoteAtom(allocator, item);
            }
            allocator.free(quote.content);
        },
        .codeblock => |cb| {
            allocator.free(cb.attrs.language);
            for (cb.content) |item| {
                freeNoteAtom(allocator, item);
            }
            allocator.free(cb.content);
        },
        else => {},
    }
}

fn printHelp() void {
    const help_text =
        \\Usage: mowen-cli [options]
        \\
        \\Upload Markdown files from current directory to Mowen platform.
        \\
        \\Options:
        \\  -h, --help           Show this help message
        \\  -v, --version        Show version information
        \\  --dry-run            Preview files without uploading
        \\  --api-key <key>      Specify API key (overrides config/env)
        \\  --tags <tags>        Comma-separated tags (e.g., "tag1,tag2")
        \\  --auto-publish       Auto-publish uploaded notes
        \\
        \\Configuration:
        \\  API key can be provided via:
        \\    1. --api-key flag
        \\    2. MOWEN_API_KEY environment variable
        \\    3. ~/.mowen/config.json file
        \\
        \\Examples:
        \\  mowen-cli                              # Upload all .md files
        \\  mowen-cli --dry-run                    # Preview without uploading
        \\  mowen-cli --tags "blog,tech"           # Add tags
        \\  mowen-cli --api-key YOUR_KEY           # Specify API key
        \\
    ;
    std.debug.print("{s}\n", .{help_text});
}

fn printVersion() void {
    std.debug.print("mowen-cli version 0.1.0\n", .{});
}
