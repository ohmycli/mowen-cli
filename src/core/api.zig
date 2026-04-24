const types = @import("types.zig");

pub const Api = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        create_note: *const fn (ptr: *anyopaque, content: []types.NoteAtom, settings: types.NoteRequest.NoteSettings) anyerror![]const u8,
        edit_note: *const fn (ptr: *anyopaque, note_id: []const u8, content: []types.NoteAtom) anyerror![]const u8,
        set_privacy: *const fn (ptr: *anyopaque, note_id: []const u8, is_public: []const u8) anyerror![]const u8,
        upload_image_from_url: *const fn (ptr: *anyopaque, image_url: []const u8) anyerror![]const u8,
        upload_image_from_file: *const fn (ptr: *anyopaque, file_path: []const u8) anyerror![]const u8,
    };

    pub fn createNote(self: Api, content: []types.NoteAtom, settings: types.NoteRequest.NoteSettings) ![]const u8 {
        return self.vtable.create_note(self.ptr, content, settings);
    }

    pub fn editNote(self: Api, note_id: []const u8, content: []types.NoteAtom) ![]const u8 {
        return self.vtable.edit_note(self.ptr, note_id, content);
    }

    pub fn setPrivacy(self: Api, note_id: []const u8, is_public: []const u8) ![]const u8 {
        return self.vtable.set_privacy(self.ptr, note_id, is_public);
    }

    pub fn uploadImageFromUrl(self: Api, image_url: []const u8) ![]const u8 {
        return self.vtable.upload_image_from_url(self.ptr, image_url);
    }

    pub fn uploadImageFromFile(self: Api, file_path: []const u8) ![]const u8 {
        return self.vtable.upload_image_from_file(self.ptr, file_path);
    }
};
