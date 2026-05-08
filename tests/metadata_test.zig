const std = @import("std");
const metadata = @import("metadata");

test "parseMetadata: valid JSON" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer {
        for (store.notes.items) |*note| note.deinit(allocator);
        store.notes.deinit(allocator);
    }

    const json =
        \\{"notes":[{"filePath":"/tmp/test.md","noteId":"abc123","createdAt":1000,"updatedAt":2000}],"last_api_call_time":3000}
    ;

    try store.parseMetadata(json);

    try std.testing.expectEqual(@as(usize, 1), store.notes.items.len);
    try std.testing.expectEqualStrings("/tmp/test.md", store.notes.items[0].filePath);
    try std.testing.expectEqualStrings("abc123", store.notes.items[0].noteId);
    try std.testing.expectEqual(@as(i64, 1000), store.notes.items[0].createdAt);
    try std.testing.expectEqual(@as(i64, 2000), store.notes.items[0].updatedAt);
    try std.testing.expectEqual(@as(?i64, 3000), store.last_api_call_time);
}

test "parseMetadata: empty notes" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer store.notes.deinit(allocator);

    const json =
        \\{"notes":[],"last_api_call_time":null}
    ;

    try store.parseMetadata(json);

    try std.testing.expectEqual(@as(usize, 0), store.notes.items.len);
    try std.testing.expectEqual(@as(?i64, null), store.last_api_call_time);
}

test "parseMetadata: multiple notes" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer {
        for (store.notes.items) |*note| note.deinit(allocator);
        store.notes.deinit(allocator);
    }

    const json =
        \\{"notes":[{"filePath":"a.md","noteId":"id1","createdAt":100,"updatedAt":200},{"filePath":"b.md","noteId":"id2","createdAt":300,"updatedAt":400}],"last_api_call_time":null}
    ;

    try store.parseMetadata(json);

    try std.testing.expectEqual(@as(usize, 2), store.notes.items.len);
    try std.testing.expectEqualStrings("a.md", store.notes.items[0].filePath);
    try std.testing.expectEqualStrings("b.md", store.notes.items[1].filePath);
}

test "parseMetadata: invalid JSON returns error" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer store.notes.deinit(allocator);

    const result = store.parseMetadata("not json");
    try std.testing.expectError(error.SyntaxError, result);
}

test "findByPath: existing path" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer {
        for (store.notes.items) |*note| note.deinit(allocator);
        store.notes.deinit(allocator);
    }

    try store.notes.append(allocator, .{
        .filePath = try allocator.dupe(u8, "/tmp/test.md"),
        .noteId = try allocator.dupe(u8, "note-123"),
        .createdAt = 1000,
        .updatedAt = 2000,
    });

    const result = store.findByPath("/tmp/test.md");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("note-123", result.?);
}

test "findByPath: non-existing path" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer store.notes.deinit(allocator);

    const result = store.findByPath("/tmp/nonexistent.md");
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "upsert: insert new" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer {
        for (store.notes.items) |*note| note.deinit(allocator);
        store.notes.deinit(allocator);
    }

    try store.upsert("/tmp/new.md", "new-id", 100, 200);

    try std.testing.expectEqual(@as(usize, 1), store.notes.items.len);
    try std.testing.expectEqualStrings("/tmp/new.md", store.notes.items[0].filePath);
    try std.testing.expectEqualStrings("new-id", store.notes.items[0].noteId);
}

test "upsert: update existing" {
    const allocator = std.testing.allocator;
    var store = metadata.MetadataStore.init(allocator);
    defer {
        for (store.notes.items) |*note| note.deinit(allocator);
        store.notes.deinit(allocator);
    }

    try store.upsert("/tmp/test.md", "old-id", 100, 200);
    try store.upsert("/tmp/test.md", "new-id", 100, 300);

    try std.testing.expectEqual(@as(usize, 1), store.notes.items.len);
    try std.testing.expectEqualStrings("new-id", store.notes.items[0].noteId);
    try std.testing.expectEqual(@as(i64, 300), store.notes.items[0].updatedAt);
}

test "NoteMetadata.deinit frees memory" {
    const allocator = std.testing.allocator;
    var note = metadata.NoteMetadata{
        .filePath = try allocator.dupe(u8, "test.md"),
        .noteId = try allocator.dupe(u8, "id-123"),
        .createdAt = 0,
        .updatedAt = 0,
    };
    note.deinit(allocator);
    // If no leak, test passes (testing.allocator detects leaks)
}
