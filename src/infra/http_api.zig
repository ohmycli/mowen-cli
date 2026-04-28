const std = @import("std");
const types = @import("../core/api.zig");
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
    };

    fn createNoteImpl(ptr: *anyopaque, content: []types.NoteAtom, settings: types.NoteRequest.NoteSettings) anyerror![]const u8 {
        const self: *HttpApi = @ptrCast(@alignCast(ptr));
        const note_request = types.NoteRequest{
            .body = .{ .doc = .{ .content = content } },
            .settings = settings,
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(note_request, .{})});
        defer self.allocator.free(json_str);

        log.debug("http_api", "Uploading to endpoint", &.{
            logging.LogField.string("url", self.base_url),
        });

        const url = try std.fmt.allocPrint(self.allocator, "{s}/note/create", .{self.base_url});
        defer self.allocator.free(url);
        return try self.sendRequest(url, json_str);
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

        const edit_url = try std.fmt.allocPrint(self.allocator, "{s}/note/edit", .{self.base_url});
        defer self.allocator.free(edit_url);

        return try self.sendRequest(edit_url, json_str);
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

        const privacy_url = try std.fmt.allocPrint(self.allocator, "{s}/note/set", .{self.base_url});
        defer self.allocator.free(privacy_url);

        return try self.sendRequest(privacy_url, json_str);
    }

    fn sendRequest(self: *HttpApi, url: []const u8, json_payload: []const u8) ![]const u8 {
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
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .payload = json_payload,
            .response_writer = &response_writer.writer,
        });

        log.debug("http_api", "Response received", &.{
            logging.LogField.int("status", @intFromEnum(result.status)),
        });

        const response_body = response_writer.writer.buffer[0..response_writer.writer.end];

        if (result.status != .ok) {
            if (result.status == .too_many_requests) {
                log.err("http_api", "Rate limit exceeded (429)", &.{});
                std.debug.print("Error: API rate limit exceeded (429). Please wait before retrying.\n", .{});
                std.debug.print("Rate limit: 1 request/second, Daily quota: 100 creates, 1000 edits, 100 privacy changes.\n", .{});
                return error.RateLimitExceeded;
            }
            log.err("http_api", "HTTP request failed", &.{
                logging.LogField.int("status", @intFromEnum(result.status)),
            });
            return error.UploadFailed;
        }

        if (response_body.len == 0) {
            log.err("http_api", "Empty response body", &.{});
            return error.EmptyResponse;
        }

        if (response_body[0] != '{') {
            log.err("http_api", "Response is not JSON format", &.{});
            return error.InvalidJsonResponse;
        }

        const parsed = std.json.parseFromSlice(
            struct { noteId: []const u8 },
            self.allocator,
            response_body,
            .{},
        ) catch |err| {
            log.err("http_api", "Failed to parse JSON response", &.{
                logging.LogField.string("error", @errorName(err)),
            });
            return error.JsonParseFailed;
        };
        defer parsed.deinit();

        return try self.allocator.dupe(u8, parsed.value.noteId);
    }
};
