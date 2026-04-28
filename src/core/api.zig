pub const NoteAtom = @import("mowen-parser").NoteAtom;

pub const NoteRequest = struct {
    body: NoteAtom,
    settings: NoteSettings,

    pub const NoteSettings = struct {
        autoPublish: bool = false,
        tags: [][]const u8 = &[_][]const u8{},
    };
};

pub const Api = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        create_note: *const fn (ptr: *anyopaque, content: []NoteAtom, settings: NoteRequest.NoteSettings) anyerror![]const u8,
        edit_note: *const fn (ptr: *anyopaque, note_id: []const u8, content: []NoteAtom) anyerror![]const u8,
        set_privacy: *const fn (ptr: *anyopaque, note_id: []const u8, is_public: []const u8) anyerror![]const u8,
    };

    pub fn createNote(self: Api, content: []NoteAtom, settings: NoteRequest.NoteSettings) ![]const u8 {
        return self.vtable.create_note(self.ptr, content, settings);
    }

    pub fn editNote(self: Api, note_id: []const u8, content: []NoteAtom) ![]const u8 {
        return self.vtable.edit_note(self.ptr, note_id, content);
    }

    pub fn setPrivacy(self: Api, note_id: []const u8, is_public: []const u8) ![]const u8 {
        return self.vtable.set_privacy(self.ptr, note_id, is_public);
    }
};
