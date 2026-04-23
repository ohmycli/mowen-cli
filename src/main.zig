const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const scanner = @import("scanner.zig");
const converter = @import("converter.zig");
const uploader = @import("uploader.zig");
const metadata = @import("metadata.zig");
const NoteRequest = @import("note_atom.zig").NoteRequest;
const log = @import("log.zig");
const logging = @import("zig-logging");

const Command = enum {
    create,
    edit,
    set_privacy,
    upload, // 保留旧的批量上传功能
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // 初始化日志系统
    log.init(.info);
    defer log.deinit();

    log.info("app", "mowen-cli started", &.{});

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iter.deinit();

    _ = args_iter.next(); // Skip program name

    const first_arg = args_iter.next();
    if (first_arg == null) {
        printHelp();
        return;
    }

    // 检查全局选项
    if (std.mem.eql(u8, first_arg.?, "--help") or std.mem.eql(u8, first_arg.?, "-h")) {
        printHelp();
        return;
    }
    if (std.mem.eql(u8, first_arg.?, "--version") or std.mem.eql(u8, first_arg.?, "-v")) {
        printVersion();
        return;
    }

    // 解析子命令
    const command = parseCommand(first_arg.?) orelse {
        log.err("app", "Unknown command", &.{
            logging.LogField.string("command", first_arg.?),
        });
        std.debug.print("Error: Unknown command '{s}'\n", .{first_arg.?});
        std.debug.print("Run 'mowen-cli --help' for usage information.\n", .{});
        return error.InvalidCommand;
    };

    log.info("app", "Executing command", &.{
        logging.LogField.string("command", @tagName(command)),
    });

    // 根据子命令分发
    switch (command) {
        .create => try handleCreate(init, &args_iter),
        .edit => try handleEdit(init, &args_iter),
        .set_privacy => try handleSetPrivacy(init, &args_iter),
        .upload => try handleUpload(init, &args_iter),
    }
}

fn parseCommand(cmd: []const u8) ?Command {
    if (std.mem.eql(u8, cmd, "create")) return .create;
    if (std.mem.eql(u8, cmd, "edit")) return .edit;
    if (std.mem.eql(u8, cmd, "set-privacy")) return .set_privacy;
    if (std.mem.eql(u8, cmd, "upload")) return .upload;
    return null;
}

/// 处理 create 子命令
fn handleCreate(init: std.process.Init, args_iter: *std.process.Args.Iterator) !void {
    const allocator = init.gpa;
    
    var file_path: ?[]const u8 = null;
    var api_key_override: ?[]const u8 = null;
    var tags_str: ?[]const u8 = null;
    var auto_publish = false;
    var dry_run = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printCreateHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            api_key_override = args_iter.next() orelse {
                std.debug.print("Error: --api-key requires a value\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--tags")) {
            tags_str = args_iter.next() orelse {
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

    // 检查文件是否存在
    std.Io.Dir.cwd().access(init.io, file, .{}) catch |err| {
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

    // 加载配置
    const cli_args = config.CliArgs{
        .api_key = api_key_override,
        .auto_publish = if (auto_publish) true else null,
        .tags = null,
    };

    var cfg = config.loadConfig(allocator, init.io, init.environ_map, cli_args) catch |err| {
        if (err == config.ConfigError.ApiKeyMissing) {
            std.debug.print("Error: No API key found. Please set MOWEN_API_KEY environment variable or use --api-key flag.\n", .{});
            return error.NoApiKey;
        }
        return err;
    };
    defer cfg.deinit();

    // 解析标签
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

    // 读取文件内容
    const content = scanner.readFileContent(allocator, init.io, file) catch |err| {
        std.debug.print("Error: Failed to read file '{s}': {s}\n", .{ file, @errorName(err) });
        return err;
    };
    defer allocator.free(content);

    // 转换为 NoteAtom
    const note_atom = converter.convertMarkdownToNoteAtom(allocator, content) catch |err| {
        std.debug.print("Error: Failed to convert markdown: {s}\n", .{@errorName(err)});
        return err;
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

    // 初始化元数据存储
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(init.io);

    try meta_store.load(init.io);

    if (dry_run) {
        std.debug.print("[DRY RUN] Would create note from '{s}'\n", .{file});
        std.debug.print("  Tags: {s}\n", .{if (tags_str) |ts| ts else "(none)"});
        std.debug.print("  Auto-publish: {}\n", .{auto_publish});
        std.debug.print("  Content length: {} bytes\n", .{content.len});
        return;
    }

    // 限频控制
    try meta_store.ensureRateLimit(init.io);

    // 上传笔记
    var upload_client = uploader.Uploader.init(allocator, init.io, cfg.api_key, cfg.api_endpoint);
    const settings = NoteRequest.NoteSettings{
        .autoPublish = cfg.auto_publish,
        .tags = tags.items,
    };

    std.debug.print("Creating note from '{s}'...\n", .{file});
    const note_id = upload_client.upload(note_atom.doc.content, settings) catch |err| {
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

    // 保存元数据
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, file, allocator);
    defer allocator.free(abs_path);

    const normalized_path = try normalizePath(allocator, abs_path);
    defer allocator.free(normalized_path);

    const now_ns = std.Io.Timestamp.now(init.io, .real).nanoseconds;
    const now = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms))); // 转换为毫秒
    const note_meta = metadata.NoteMetadata{
        .filePath = try allocator.dupe(u8, normalized_path),
        .noteId = try allocator.dupe(u8, note_id),
        .createdAt = now,
        .updatedAt = now,
    };

    try meta_store.notes.append(allocator, note_meta);
    try meta_store.save(init.io);

    std.debug.print("✓ Note created successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  File: {s}\n", .{normalized_path});
}

/// 处理 edit 子命令
fn handleEdit(init: std.process.Init, args_iter: *std.process.Args.Iterator) !void {
    const allocator = init.gpa;
    
    var file_path: ?[]const u8 = null;
    var api_key_override: ?[]const u8 = null;
    var dry_run = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printEditHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            api_key_override = args_iter.next() orelse {
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

    // 检查文件是否存在
    std.Io.Dir.cwd().access(init.io, file, .{}) catch |err| {
        std.debug.print("Error: File '{s}' not found or not accessible: {s}\n", .{ file, @errorName(err) });
        return error.FileNotFound;
    };

    // 加载配置
    const cli_args = config.CliArgs{
        .api_key = api_key_override,
        .auto_publish = null,
        .tags = null,
    };

    var cfg = config.loadConfig(allocator, init.io, init.environ_map, cli_args) catch |err| {
        if (err == config.ConfigError.ApiKeyMissing) {
            std.debug.print("Error: No API key found. Please set MOWEN_API_KEY environment variable or use --api-key flag.\n", .{});
            return error.NoApiKey;
        }
        return err;
    };
    defer cfg.deinit();

    // 初始化元数据存储
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(init.io);

    try meta_store.load(init.io);

    // 获取文件的绝对路径
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, file, allocator);
    defer allocator.free(abs_path);

    const normalized_path = try normalizePath(allocator, abs_path);
    defer allocator.free(normalized_path);

    // 查找元数据
    var note_meta: ?*metadata.NoteMetadata = null;
    for (meta_store.notes.items) |*note| {
        if (std.mem.eql(u8, note.filePath, normalized_path)) {
            note_meta = note;
            break;
        }
    }

    const meta = note_meta orelse {
        std.debug.print("Error: No metadata found for '{s}'\n", .{file});
        std.debug.print("\n", .{});
        std.debug.print("Possible reasons:\n", .{});
        std.debug.print("  1. This file has not been created yet\n", .{});
        std.debug.print("  2. The file was moved or renamed after creation\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Solutions:\n", .{});
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

    // 读取文件内容
    const content = scanner.readFileContent(allocator, init.io, file) catch |err| {
        std.debug.print("Error: Failed to read file '{s}': {s}\n", .{ file, @errorName(err) });
        return err;
    };
    defer allocator.free(content);

    // 转换为 NoteAtom
    const note_atom = converter.convertMarkdownToNoteAtom(allocator, content) catch |err| {
        std.debug.print("Error: Failed to convert markdown: {s}\n", .{@errorName(err)});
        return err;
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

    // 限频控制
    try meta_store.ensureRateLimit(init.io);

    // 编辑笔记
    var upload_client = uploader.Uploader.init(allocator, init.io, cfg.api_key, cfg.api_endpoint);

    log.info("edit", "Editing note", &.{
        logging.LogField.string("note_id", meta.noteId),
        logging.LogField.string("file", file),
    });

    std.debug.print("Editing note '{s}'...\n", .{meta.noteId});
    const note_id = upload_client.editNote(meta.noteId, note_atom.doc.content) catch |err| {
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

    // 更新元数据
    const now_ns = std.Io.Timestamp.now(init.io, .real).nanoseconds;
    meta.updatedAt = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms))); // 转换为毫秒
    try meta_store.save(init.io);

    std.debug.print("✓ Note edited successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  File: {s}\n", .{normalized_path});
}

/// 处理 set-privacy 子命令
fn handleSetPrivacy(init: std.process.Init, args_iter: *std.process.Args.Iterator) !void {
    const allocator = init.gpa;
    
    var file_path: ?[]const u8 = null;
    var privacy: ?[]const u8 = null;
    var api_key_override: ?[]const u8 = null;
    var dry_run = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printSetPrivacyHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            api_key_override = args_iter.next() orelse {
                std.debug.print("Error: --api-key requires a value\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--privacy")) {
            privacy = args_iter.next() orelse {
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

    // 检查文件是否存在
    std.Io.Dir.cwd().access(init.io, file, .{}) catch |err| {
        std.debug.print("Error: File '{s}' not found or not accessible: {s}\n", .{ file, @errorName(err) });
        return error.FileNotFound;
    };

    // 加载配置
    const cli_args = config.CliArgs{
        .api_key = api_key_override,
        .auto_publish = null,
        .tags = null,
    };

    var cfg = config.loadConfig(allocator, init.io, init.environ_map, cli_args) catch |err| {
        if (err == config.ConfigError.ApiKeyMissing) {
            std.debug.print("Error: No API key found. Please set MOWEN_API_KEY environment variable or use --api-key flag.\n", .{});
            return error.NoApiKey;
        }
        return err;
    };
    defer cfg.deinit();

    // 初始化元数据存储
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(init.io);

    try meta_store.load(init.io);

    // 获取文件的绝对路径
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, file, allocator);
    defer allocator.free(abs_path);

    const normalized_path = try normalizePath(allocator, abs_path);
    defer allocator.free(normalized_path);

    // 查找元数据
    var note_meta: ?*metadata.NoteMetadata = null;
    for (meta_store.notes.items) |*note| {
        if (std.mem.eql(u8, note.filePath, normalized_path)) {
            note_meta = note;
            break;
        }
    }

    const meta = note_meta orelse {
        std.debug.print("Error: No metadata found for '{s}'\n", .{file});
        std.debug.print("\n", .{});
        std.debug.print("Possible reasons:\n", .{});
        std.debug.print("  1. This file has not been created yet\n", .{});
        std.debug.print("  2. The file was moved or renamed after creation\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Solutions:\n", .{});
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

    // 限频控制
    try meta_store.ensureRateLimit(init.io);

    // 设置隐私
    var upload_client = uploader.Uploader.init(allocator, init.io, cfg.api_key, cfg.api_endpoint);

    std.debug.print("Setting privacy for note '{s}' to '{s}'...\n", .{ meta.noteId, priv });
    const note_id = upload_client.setNotePrivacy(meta.noteId, priv) catch |err| {
        std.debug.print("Error: Failed to set privacy: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(note_id);

    std.debug.print("✓ Privacy set successfully!\n", .{});
    std.debug.print("  Note ID: {s}\n", .{note_id});
    std.debug.print("  Privacy: {s}\n", .{priv});
}

/// 处理 upload 子命令（保留旧的批量上传功能）
fn handleUpload(init: std.process.Init, args_iter: *std.process.Args.Iterator) !void {
    const allocator = init.gpa;

    var dry_run = false;
    var api_key_override: ?[]const u8 = null;
    var tags_str: ?[]const u8 = null;
    var auto_publish = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) {
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

    // Initialize metadata store
    var meta_store = metadata.MetadataStore.init(allocator);
    defer meta_store.deinit(init.io);

    try meta_store.load(init.io);

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

        // Save metadata
        const abs_path = std.Io.Dir.cwd().realPathFileAlloc(init.io, file, allocator) catch |err| {
            std.debug.print("  Warning: Failed to get absolute path: {s}\n", .{@errorName(err)});
            // Continue without saving metadata for this file
            if (idx + 1 < files.len) {
                init.io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
            }
            continue;
        };
        defer allocator.free(abs_path);

        const normalized_path = normalizePath(allocator, abs_path) catch |err| {
            std.debug.print("  Warning: Failed to normalize path: {s}\n", .{@errorName(err)});
            if (idx + 1 < files.len) {
                init.io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
            }
            continue;
        };
        defer allocator.free(normalized_path);

        // Check if metadata already exists for this file
        var found = false;
        for (meta_store.notes.items) |*note| {
            if (std.mem.eql(u8, note.filePath, normalized_path)) {
                // Update existing metadata
                allocator.free(note.noteId);
                note.noteId = try allocator.dupe(u8, note_id);
                const now_ns = std.Io.Timestamp.now(init.io, .real).nanoseconds;
                note.updatedAt = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
                found = true;
                break;
            }
        }

        if (!found) {
            // Add new metadata
            const now_ns = std.Io.Timestamp.now(init.io, .real).nanoseconds;
            const now = @as(i64, @intCast(@divFloor(now_ns, std.time.ns_per_ms)));
            const note_meta = metadata.NoteMetadata{
                .filePath = try allocator.dupe(u8, normalized_path),
                .noteId = try allocator.dupe(u8, note_id),
                .createdAt = now,
                .updatedAt = now,
            };
            try meta_store.notes.append(allocator, note_meta);
        }

        // Rate limiting: 1 request per second
        if (idx + 1 < files.len) {
            init.io.sleep(std.Io.Duration.fromSeconds(1), .awake) catch {};
        }
    }

    // Save metadata to disk
    if (success_count > 0) {
        meta_store.save(init.io) catch |err| {
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

/// 规范化路径（Windows 反斜杠转正斜杠）
fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        const normalized = try allocator.alloc(u8, path.len);
        for (path, 0..) |c, i| {
            normalized[i] = if (c == '\\') '/' else c;
        }
        return normalized;
    } else {
        return try allocator.dupe(u8, path);
    }
}

/// 释放 NoteAtom 内存
fn freeNoteAtom(allocator: std.mem.Allocator, atom: converter.NoteAtom) void {
    switch (atom) {
        .text => |text| {
            allocator.free(text.text);
            if (text.marks.len > 0) {
                for (text.marks) |mark| {
                    switch (mark) {
                        .link => |link| allocator.free(link.href),
                        .bold => {},
                    }
                }
                allocator.free(text.marks);
            }
        },
        .paragraph => |para| {
            for (para.content) |child| {
                freeNoteAtom(allocator, child);
            }
            allocator.free(para.content);
        },
        .codeblock => |cb| {
            allocator.free(cb.attrs.language);
            for (cb.content) |child| {
                freeNoteAtom(allocator, child);
            }
            allocator.free(cb.content);
        },
        .quote => |quote| {
            for (quote.content) |child| {
                freeNoteAtom(allocator, child);
            }
            allocator.free(quote.content);
        },
        .doc => |doc| {
            for (doc.content) |child| {
                freeNoteAtom(allocator, child);
            }
            allocator.free(doc.content);
        },
        .horizontal_rule => {},
    }
}

fn printHelp() void {
    std.debug.print(
        \\mowen-cli - Upload markdown files to Mowen platform
        \\
        \\USAGE:
        \\    mowen-cli <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    create <file>              Create a new note from a markdown file
        \\    edit <file>                Edit an existing note
        \\    set-privacy <file>         Set privacy for an existing note
        \\    upload                     Batch upload all markdown files (legacy)
        \\
        \\OPTIONS:
        \\    --help, -h                 Show this help message
        \\    --version, -v              Show version information
        \\    --api-key <KEY>            Override API key from config/env
        \\    --tags <TAG1,TAG2>         Add tags to notes (create/upload only)
        \\    --auto-publish             Auto-publish notes (create/upload only)
        \\    --privacy <public|private|rule>  Privacy setting (set-privacy only)
        \\    --dry-run                  Show files without uploading (upload only)
        \\
        \\EXAMPLES:
        \\    # Create a new note
        \\    mowen-cli create README.md
        \\
        \\    # Edit an existing note
        \\    mowen-cli edit README.md
        \\
        \\    # Set note privacy
        \\    mowen-cli set-privacy README.md --privacy private
        \\
        \\    # Batch upload (legacy)
        \\    mowen-cli upload --tags "tech,tutorial" --auto-publish
        \\
        \\CONFIGURATION:
        \\    API key can be set via:
        \\    1. --api-key flag
        \\    2. MOWEN_API_KEY environment variable
        \\    3. config.json file in current directory
        \\
        \\For more information, visit: https://github.com/ohmycli/mowen-cli
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("mowen-cli version 0.1.0\n", .{});
}

fn printCreateHelp() void {
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
        \\EXAMPLES:
        \\    mowen-cli create README.md
        \\    mowen-cli create docs/guide.md --tags "documentation,guide" --auto-publish
        \\    mowen-cli create draft.md --dry-run
        \\
        \\NOTE:
        \\    This command creates a new note and stores its ID in .mowen/metadata.json.
        \\    Use 'mowen-cli edit' to update the note later.
        \\
    , .{});
}

fn printEditHelp() void {
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
        \\EXAMPLES:
        \\    mowen-cli edit README.md
        \\    mowen-cli edit docs/guide.md --api-key YOUR_API_KEY
        \\    mowen-cli edit draft.md --dry-run
        \\
        \\NOTE:
        \\    The file must have been previously created with 'mowen-cli create'.
        \\    The note ID is stored in .mowen/metadata.json.
        \\
    , .{});
}

fn printSetPrivacyHelp() void {
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
        \\EXAMPLES:
        \\    mowen-cli set-privacy README.md --privacy public
        \\    mowen-cli set-privacy docs/guide.md --privacy private
        \\    mowen-cli set-privacy draft.md --privacy public --dry-run
        \\
        \\NOTE:
        \\    The file must have been previously created with 'mowen-cli create'.
        \\    The note ID is stored in .mowen/metadata.json.
        \\
    , .{});
}
