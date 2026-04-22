const std = @import("std");
const NoteAtom = @import("note_atom.zig").NoteAtom;
const NoteRequest = @import("note_atom.zig").NoteRequest;

/// API 响应结构
pub const ApiResponse = struct {
    code: i32,
    msg: []const u8,
    data: ?ResponseData,
};

/// 创建笔记响应数据
pub const CreateResponseData = struct {
    noteId: []const u8,
};

/// 编辑笔记响应数据
pub const EditResponseData = struct {
    noteId: []const u8,
};

/// 设置隐私响应数据
pub const SetResponseData = struct {
    noteId: []const u8,
};

/// 通用响应数据
pub const ResponseData = union(enum) {
    create: CreateResponseData,
    edit: EditResponseData,
    set: SetResponseData,
};

pub const Uploader = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: []const u8) Uploader {
        return .{
            .allocator = allocator,
            .io = io,
            .api_key = api_key,
            .base_url = base_url,
        };
    }

    /// 通用 HTTP POST 请求，返回 noteId
    fn sendRequest(self: *Uploader, url: []const u8, json_payload: []const u8) ![]const u8 {
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

        std.debug.print("[DEBUG] Response status: {}\n", .{result.status});

        const response_body = response_writer.writer.buffer[0..response_writer.writer.end];
        std.debug.print("[DEBUG] Response body: {s}\n", .{response_body});

        if (result.status != .ok) {
            if (result.status == .too_many_requests) {
                std.debug.print("Error: API rate limit exceeded (429). Please wait before retrying.\n", .{});
                std.debug.print("Rate limit: 1 request/second, Daily quota: 100 creates, 1000 edits, 100 privacy changes.\n", .{});
                return error.RateLimitExceeded;
            }
            std.debug.print("Error: HTTP request failed with status {}\n", .{result.status});
            return error.UploadFailed;
        }

        if (response_body.len == 0) {
            std.debug.print("Error: Empty response body\n", .{});
            return error.EmptyResponse;
        }

        if (response_body[0] != '{') {
            std.debug.print("Error: Response is not JSON format\n", .{});
            return error.InvalidJsonResponse;
        }

        const parsed = std.json.parseFromSlice(
            struct {
                noteId: []const u8,
            },
            self.allocator,
            response_body,
            .{},
        ) catch |err| {
            std.debug.print("Error: Failed to parse JSON response: {s}\n", .{@errorName(err)});
            return error.JsonParseFailed;
        };
        defer parsed.deinit();

        return try self.allocator.dupe(u8, parsed.value.noteId);
    }

    pub fn upload(self: *Uploader, content: []NoteAtom, settings: NoteRequest.NoteSettings) ![]const u8 {
        const note_request = NoteRequest{
            .body = .{ .doc = .{ .content = content } },
            .settings = settings,
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(note_request, .{})});
        defer self.allocator.free(json_str);

        std.debug.print("\n[DEBUG] Uploading to: {s}\n", .{self.base_url});
        std.debug.print("[DEBUG] Request body: {s}\n", .{json_str});

        return try self.sendRequest(self.base_url, json_str);
    }

    /// 编辑笔记
    pub fn editNote(self: *Uploader, note_id: []const u8, content: []NoteAtom) ![]const u8 {
        const edit_request = struct {
            noteId: []const u8,
            body: NoteAtom,
        }{
            .noteId = note_id,
            .body = .{ .doc = .{ .content = content } },
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(edit_request, .{})});
        defer self.allocator.free(json_str);

        std.debug.print("\n[DEBUG] Editing note: {s}\n", .{note_id});
        std.debug.print("[DEBUG] Request body: {s}\n", .{json_str});

        const edit_url = try std.mem.replaceOwned(u8, self.allocator, self.base_url, "/note/create", "/note/edit");
        defer self.allocator.free(edit_url);

        return try self.sendRequest(edit_url, json_str);
    }

    /// 设置笔记隐私
    pub fn setNotePrivacy(self: *Uploader, note_id: []const u8, is_public: []const u8) ![]const u8 {
        const json_str = try std.fmt.allocPrint(
            self.allocator,
            "{{\"noteId\":\"{s}\",\"isPublic\":{s}}}",
            .{ note_id, is_public },
        );
        defer self.allocator.free(json_str);

        std.debug.print("\n[DEBUG] Setting privacy for note: {s}\n", .{note_id});
        std.debug.print("[DEBUG] Request body: {s}\n", .{json_str});

        const privacy_url = try std.mem.replaceOwned(u8, self.allocator, self.base_url, "/note/create", "/note/set");
        defer self.allocator.free(privacy_url);

        return try self.sendRequest(privacy_url, json_str);
    }
};
