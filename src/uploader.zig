const std = @import("std");
const NoteAtom = @import("note_atom.zig").NoteAtom;
const NoteRequest = @import("note_atom.zig").NoteRequest;

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

    pub fn upload(self: *Uploader, content: []NoteAtom, settings: NoteRequest.NoteSettings) ![]const u8 {
        const note_request = NoteRequest{
            .body = .{ .doc = .{ .content = content } },
            .settings = settings,
        };

        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(note_request, .{})});
        defer self.allocator.free(json_str);

        // Debug: print request details
        std.debug.print("\n[DEBUG] Uploading to: {s}\n", .{self.base_url});
        std.debug.print("[DEBUG] Request body: {s}\n", .{json_str});

        // base_url already contains the full endpoint path
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var client = std.http.Client{ .allocator = self.allocator, .io = self.io };
        defer client.deinit();

        const result = try client.fetch(.{
            .method = .POST,
            .location = .{ .url = self.base_url },
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .payload = json_str,
        });

        std.debug.print("[DEBUG] Response status: {}\n", .{result.status});

        if (result.status != .ok) {
            return error.UploadFailed;
        }

        // For now, just return a dummy note ID since we can't read the response body easily
        return try self.allocator.dupe(u8, "success");
    }
};
