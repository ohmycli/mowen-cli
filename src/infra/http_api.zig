const std = @import("std");
const builtin = @import("builtin");
const types = @import("../core/types.zig");
const Api = @import("../core/api.zig").Api;
const log = @import("../log.zig");
const logging = @import("zig-logging");

pub const HttpApi = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: []const u8) HttpApi {
        return .{
            .allocator = allocator,
            .io = io,
            .api_key = api_key,
            .base_url = base_url,
        };
    }

    fn apiBaseUrl(self: *const HttpApi) []const u8 {
        const suffixes = [_][]const u8{
            "/note/create",
            "/note/edit",
            "/note/set",
            "/upload/url",
            "/upload/prepare",
        };

        var base = self.base_url;
        inline for (suffixes) |suffix| {
            if (std.mem.endsWith(u8, base, suffix)) {
                base = base[0 .. base.len - suffix.len];
                break;
            }
        }

        while (base.len > 0 and base[base.len - 1] == '/') {
            base = base[0 .. base.len - 1];
        }
        return base;
    }

    pub fn api(self: *HttpApi) Api {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = Api.VTable{
        .create_note = createNoteImpl,
        .edit_note = editNoteImpl,
        .set_privacy = setPrivacyImpl,
        .upload_image_from_url = uploadImageFromUrlImpl,
        .upload_image_from_file = uploadImageFromFileImpl,
    };

    fn createNoteImpl(ptr: *anyopaque, content: []types.NoteAtom, settings: types.NoteRequest.NoteSettings) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));
        const note_request = types.NoteRequest{
            .body = .{ .doc = .{ .content = content } },
            .settings = settings,
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(note_request, .{})});
        defer self.allocator.free(json_str);

        log.debug("http_api", "Uploading note", &.{
            logging.LogField.string("url", self.apiBaseUrl()),
        });

        const url = try std.fmt.allocPrint(self.allocator, "{s}/note/create", .{self.apiBaseUrl()});
        defer self.allocator.free(url);

        const body = try self.post(url, "application/json", json_str);
        defer self.allocator.free(body);
        return try self.extractStringField(body, &.{ "noteId" });
    }

    fn editNoteImpl(ptr: *anyopaque, note_id: []const u8, content: []types.NoteAtom) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));
        const edit_request = struct {
            noteId: []const u8,
            body: types.NoteAtom,
        }{
            .noteId = note_id,
            .body = .{ .doc = .{ .content = content } },
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(edit_request, .{})});
        defer self.allocator.free(json_str);

        log.debug("http_api", "Editing note", &.{
            logging.LogField.string("note_id", note_id),
        });

        const edit_url = try std.fmt.allocPrint(self.allocator, "{s}/note/edit", .{self.apiBaseUrl()});
        defer self.allocator.free(edit_url);

        const body = try self.post(edit_url, "application/json", json_str);
        defer self.allocator.free(body);
        return try self.extractStringField(body, &.{ "noteId" });
    }

    fn setPrivacyImpl(ptr: *anyopaque, note_id: []const u8, is_public: []const u8) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));
        const json_str = try std.fmt.allocPrint(
            self.allocator,
            "{{\"noteId\":\"{s}\",\"isPublic\":{s}}}",
            .{ note_id, is_public },
        );
        defer self.allocator.free(json_str);

        log.debug("http_api", "Setting privacy", &.{
            logging.LogField.string("note_id", note_id),
        });

        const privacy_url = try std.fmt.allocPrint(self.allocator, "{s}/note/set", .{self.apiBaseUrl()});
        defer self.allocator.free(privacy_url);

        const body = try self.post(privacy_url, "application/json", json_str);
        defer self.allocator.free(body);
        return try self.extractStringField(body, &.{ "noteId" });
    }

    fn uploadImageFromUrlImpl(ptr: *anyopaque, image_url: []const u8) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));
        const file_name = try self.deriveFileNameFromSource(image_url);
        defer self.allocator.free(file_name);

        const request = struct {
            fileType: u8 = 1,
            url: []const u8,
            fileName: []const u8,
        }{
            .url = image_url,
            .fileName = file_name,
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(request, .{})});
        defer self.allocator.free(json_str);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/upload/url", .{self.apiBaseUrl()});
        defer self.allocator.free(url);

        const body = try self.post(url, "application/json", json_str);
        defer self.allocator.free(body);
        return try self.extractStringField(body, &.{ "file", "fileId" });
    }

    fn uploadImageFromFileImpl(ptr: *anyopaque, file_path: []const u8) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));

        const file_name = try self.deriveFileNameFromSource(file_path);
        defer self.allocator.free(file_name);

        const file = try std.Io.Dir.cwd().openFile(self.io, file_path, .{});
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        if (stat.size > 50 * 1024 * 1024) {
            return error.FileTooLarge;
        }

        const file_bytes = try readFileBytes(self, file);
        defer self.allocator.free(file_bytes);

        const prepare_request = struct {
            fileType: u8 = 1,
            fileName: []const u8,
        }{
            .fileName = file_name,
        };

        const prepare_json = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(prepare_request, .{})});
        defer self.allocator.free(prepare_json);

        const prepare_url = try std.fmt.allocPrint(self.allocator, "{s}/upload/prepare", .{self.apiBaseUrl()});
        defer self.allocator.free(prepare_url);

        const prepare_body = try self.post(prepare_url, "application/json", prepare_json);
        defer self.allocator.free(prepare_body);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, prepare_body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const endpoint_raw = try self.extractUploadEndpoint(parsed.value);
        defer self.allocator.free(endpoint_raw);
        const endpoint = try self.resolveUploadEndpoint(endpoint_raw);
        defer self.allocator.free(endpoint);
        const fields = try extractUploadFields(parsed.value);
        var file_id = try extractOptionalStringFieldFromValue(self.allocator, fields, &.{ "x:file_id" });
        if (file_id == null) {
            file_id = try extractOptionalStringFieldFromValue(self.allocator, fields, &.{ "fileId" });
        }
        if (file_id == null) {
            file_id = try extractOptionalStringFieldFromValue(self.allocator, fields, &.{ "file", "fileId" });
        }
        errdefer if (file_id) |id| self.allocator.free(id);

        const mime = guessMimeType(file_path);
        const multipart = try self.buildMultipartPayload(fields, file_name, mime, file_bytes);
        defer self.allocator.free(multipart.boundary);
        defer self.allocator.free(multipart.content_type);
        defer self.allocator.free(multipart.body);

        const upload_body = try self.post(endpoint, multipart.content_type, multipart.body);
        defer self.allocator.free(upload_body);
        if (file_id == null) {
            file_id = try self.extractStringField(upload_body, &.{ "file", "fileId" });
        }
        return file_id orelse error.JsonParseFailed;
    }

    fn post(self: *HttpApi, url: []const u8, content_type: []const u8, payload: []const u8) ![]const u8 {
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var client = std.http.Client{ .allocator = self.allocator, .io = self.io };
        defer client.deinit();

        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer response_writer.deinit();

        const result = try client.fetch(.{
            .method = .POST,
            .location = .{ .url = url },
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = content_type },
            },
            .payload = payload,
            .response_writer = &response_writer.writer,
        });

        log.debug("http_api", "Response received", &.{
            logging.LogField.int("status", @intFromEnum(result.status)),
        });

        const response_body = response_writer.writer.buffer[0..response_writer.writer.end];
        const copy = try self.allocator.dupe(u8, response_body);

        if (result.status != .ok) {
            if (result.status == .too_many_requests) {
                log.err("http_api", "Rate limit exceeded (429)", &.{});
                std.debug.print("Error: API rate limit exceeded (429). Please wait before retrying.\n", .{});
                std.debug.print("Rate limit: 1 request/second, Daily quota: 100 creates, 1000 edits, 100 privacy changes.\n", .{});
                self.allocator.free(copy);
                return error.RateLimitExceeded;
            }
            log.err("http_api", "HTTP request failed", &.{
                logging.LogField.int("status", @intFromEnum(result.status)),
            });
            self.allocator.free(copy);
            return error.UploadFailed;
        }

        if (copy.len == 0) {
            log.err("http_api", "Empty response body", &.{});
            self.allocator.free(copy);
            return error.EmptyResponse;
        }

        if (copy[0] != '{') {
            log.err("http_api", "Response is not JSON format", &.{});
            self.allocator.free(copy);
            return error.InvalidJsonResponse;
        }

        return copy;
    }

    fn extractStringField(self: *HttpApi, body: []const u8, path: []const []const u8) ![]const u8 {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return try extractStringFieldFromValue(self.allocator, parsed.value, path);
    }

    fn extractUploadEndpoint(self: *HttpApi, value: std.json.Value) ![]const u8 {
        if (findValue(value, &.{ "endpoint" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        if (findValue(value, &.{ "url" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        if (findValue(value, &.{ "action" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        if (findValue(value, &.{ "form", "endpoint" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        if (findValue(value, &.{ "form", "url" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        if (findValue(value, &.{ "form", "action" })) |endpoint| {
            return switch (endpoint) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => error.JsonParseFailed,
            };
        }

        return error.JsonParseFailed;
    }

    fn extractUploadFields(value: std.json.Value) !std.json.Value {
        if (findValue(value, &.{ "form", "fields" })) |fields| {
            switch (fields) {
                .object => return fields,
                else => {},
            }
        }

        if (findValue(value, &.{ "form" })) |form| {
            switch (form) {
                .object => return form,
                else => {},
            }
        }

        switch (value) {
            .object => return value,
            else => {},
        }

        return error.JsonParseFailed;
    }

    fn buildMultipartPayload(self: *HttpApi, fields: std.json.Value, file_name: []const u8, mime: []const u8, file_bytes: []const u8) !struct {
        boundary: []u8,
        content_type: []const u8,
        body: []u8,
    } {
        const boundary = try self.makeBoundary();
        errdefer self.allocator.free(boundary);

        var body: std.ArrayList(u8) = .empty;
        errdefer body.deinit(self.allocator);

        const object = fields.object;
        var it = object.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.eql(u8, key, "endpoint") or
                std.mem.eql(u8, key, "action") or
                std.mem.eql(u8, key, "url") or
                std.mem.eql(u8, key, "fields") or
                std.mem.eql(u8, key, "file"))
            {
                continue;
            }

            if (entry.value_ptr.* != .string) continue;

            try appendMultipartField(self.allocator, &body, boundary, key, entry.value_ptr.*.string);
        }

        try appendMultipartFile(self.allocator, &body, boundary, file_name, mime, file_bytes);
        const closing = try std.fmt.allocPrint(self.allocator, "--{s}--\r\n", .{boundary});
        defer self.allocator.free(closing);
        try body.appendSlice(self.allocator, closing);

        const content_type = try std.fmt.allocPrint(self.allocator, "multipart/form-data; boundary={s}", .{boundary});

        return .{
            .boundary = boundary,
            .content_type = content_type,
            .body = try body.toOwnedSlice(self.allocator),
        };
    }

    fn makeBoundary(self: *HttpApi) ![]u8 {
        const now_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        return try std.fmt.allocPrint(self.allocator, "----mowen-{x}", .{now_ns});
    }

    fn deriveFileNameFromSource(self: *HttpApi, source: []const u8) ![]const u8 {
        var end = source.len;
        if (std.mem.indexOfScalar(u8, source, '?')) |idx| end = @min(end, idx);
        if (std.mem.indexOfScalar(u8, source, '#')) |idx| end = @min(end, idx);

        const trimmed = source[0..end];
        const base = std.fs.path.basename(trimmed);
        if (base.len == 0) {
            return try self.allocator.dupe(u8, "image");
        }
        return try self.allocator.dupe(u8, base);
    }

    fn resolveUploadEndpoint(self: *HttpApi, endpoint: []const u8) ![]const u8 {
        if (std.mem.startsWith(u8, endpoint, "http://") or std.mem.startsWith(u8, endpoint, "https://")) {
            return try self.allocator.dupe(u8, endpoint);
        }

        if (std.mem.startsWith(u8, endpoint, "/")) {
            return try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.apiBaseUrl(), endpoint });
        }

        return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.apiBaseUrl(), endpoint });
    }
};

fn readFileBytes(self: *HttpApi, file: std.Io.File) ![]u8 {
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(self.io, &buffer);
    return try reader.interface.allocRemaining(self.allocator, .unlimited);
}

fn guessMimeType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".gif")) return "image/gif";
    if (std.ascii.eqlIgnoreCase(ext, ".jpg") or std.ascii.eqlIgnoreCase(ext, ".jpeg")) return "image/jpeg";
    if (std.ascii.eqlIgnoreCase(ext, ".png")) return "image/png";
    if (std.ascii.eqlIgnoreCase(ext, ".webp")) return "image/webp";
    return "application/octet-stream";
}

fn appendMultipartField(allocator: std.mem.Allocator, body: *std.ArrayList(u8), boundary: []const u8, name: []const u8, value: []const u8) !void {
    const field = try std.fmt.allocPrint(allocator,
        "--{s}\r\nContent-Disposition: form-data; name=\"{s}\"\r\n\r\n{s}\r\n",
        .{ boundary, name, value },
    );
    defer allocator.free(field);
    try body.appendSlice(allocator, field);
}

fn appendMultipartFile(allocator: std.mem.Allocator, body: *std.ArrayList(u8), boundary: []const u8, file_name: []const u8, mime: []const u8, file_bytes: []const u8) !void {
    const head = try std.fmt.allocPrint(
        allocator,
        "--{s}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{s}\"\r\nContent-Type: {s}\r\n\r\n",
        .{ boundary, file_name, mime },
    );
    defer allocator.free(head);
    try body.appendSlice(allocator, head);
    try body.appendSlice(allocator, file_bytes);
    try body.appendSlice(allocator, "\r\n");
}

fn findValue(value: std.json.Value, path: []const []const u8) ?std.json.Value {
    if (path.len == 0) return null;

    return switch (value) {
        .object => |object| {
            const next = object.get(path[0]) orelse return null;
            if (path.len == 1) return next;
            return findValue(next, path[1..]);
        },
        else => null,
    };
}

fn extractStringFieldFromValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    path: []const []const u8,
) ![]const u8 {
    const found = findValue(value, path) orelse return error.JsonParseFailed;
    return switch (found) {
        .string => |s| try allocator.dupe(u8, s),
        else => error.JsonParseFailed,
    };
}

fn extractOptionalStringFieldFromValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    path: []const []const u8,
) !?[]const u8 {
    const found = findValue(value, path) orelse return null;
    return switch (found) {
        .string => |s| try allocator.dupe(u8, s),
        else => error.JsonParseFailed,
    };
}

test "prepare reply exposes file id for local image upload" {
    const allocator = std.testing.allocator;
    const body =
        \\{"form":{"endpoint":"upload.example.com","x:file_id":"file-123","x:file_uid":"uid-456","x:file_name":"cover.png"}}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const form = findValue(parsed.value, &.{ "form" }) orelse return error.TestUnexpectedResult;
    const file_id = try extractOptionalStringFieldFromValue(allocator, form, &.{ "x:file_id" });
    defer if (file_id) |id| allocator.free(id);

    try std.testing.expect(file_id != null);
    try std.testing.expectEqualStrings("file-123", file_id.?);
}
