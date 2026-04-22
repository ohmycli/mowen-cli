const std = @import("std");
const scanner = @import("scanner");
const testing = std.testing;

test "scanMarkdownFiles - basic functionality" {
    const allocator = testing.allocator;
    const io = std.testing.io;
    
    // Test with current directory - should not crash
    const files = scanner.scanMarkdownFiles(allocator, io, ".") catch |err| {
        // It's okay if it fails with FileNotFound or similar
        if (err == error.FileNotFound or err == error.AccessDenied) {
            return;
        }
        return err;
    };
    defer {
        for (files) |file| {
            allocator.free(file);
        }
        allocator.free(files);
    }
    
    // Just verify it returns a valid slice
    _ = files.len;
}

test "readFileContent - nonexistent file" {
    const allocator = testing.allocator;
    const io = std.testing.io;
    
    const result = scanner.readFileContent(allocator, io, "nonexistent_file_that_does_not_exist.md");
    try testing.expectError(error.FileNotFound, result);
}

