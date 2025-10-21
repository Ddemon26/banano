const std = @import("std");
const ManagedArrayList = std.array_list.Managed;
const terminal = @import("terminal.zig");

pub const EditorMode = enum {
    normal,
    search,
    command,
    prompt,
};

pub const EditorAction = union(enum) {
    quit,
    save,
    save_as,
    open,
    find,
    find_next,
    find_previous,
    goto_line,
    help,
    cut_line,
    copy_line,
    paste,
    undo,
    redo,

    // Movement
    move_up,
    move_down,
    move_left,
    move_right,
    move_word_left,
    move_word_right,
    move_line_start,
    move_line_end,
    move_page_up,
    move_page_down,
    move_file_start,
    move_file_end,

    // Text editing
    insert_char: u8,
    insert_newline,
    backspace,
    delete,
    cut_word_start,
    cut_word_end,

    // Search mode
    search_input: u8,
    search_submit,
    search_cancel,

    // Command/prompt mode
    prompt_input: u8,
    prompt_submit,
    prompt_cancel,
    cancel,

    // No action
    none,
};

pub const InputHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: EditorMode,
    prompt_buffer: ManagedArrayList(u8),
    search_buffer: ManagedArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        const prompt_buffer = ManagedArrayList(u8).init(allocator);
        const search_buffer = ManagedArrayList(u8).init(allocator);
        return Self{
            .allocator = allocator,
            .mode = .normal,
            .prompt_buffer = prompt_buffer,
            .search_buffer = search_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.prompt_buffer.deinit();
        self.search_buffer.deinit();
    }

    pub fn setMode(self: *Self, mode: EditorMode) void {
        self.mode = mode;

        // Clear appropriate buffers when switching modes
        switch (mode) {
            .normal => {
                self.prompt_buffer.clearAndFree();
                self.search_buffer.clearAndFree();
            },
            .search => {
                self.search_buffer.clearAndFree();
                self.prompt_buffer.clearAndFree();
            },
            .prompt, .command => {
                self.prompt_buffer.clearAndFree();
                self.search_buffer.clearAndFree();
            },
        }
    }

    pub fn getMode(self: Self) EditorMode {
        return self.mode;
    }

    pub fn getPromptText(self: Self) []const u8 {
        return self.prompt_buffer.items;
    }

    pub fn getSearchText(self: Self) []const u8 {
        return self.search_buffer.items;
    }

    pub fn processKey(self: *Self, key: terminal.Key) EditorAction {
        switch (self.mode) {
            .normal => return self.processNormalKey(key),
            .search => return self.processSearchKey(key),
            .prompt => return self.processPromptKey(key),
            .command => return self.processCommandKey(key),
        }
    }

    fn processNormalKey(_: Self, key: terminal.Key) EditorAction {
        return switch (key) {
            .char => |ch| blk: {
                if (ch >= 1 and ch <= 26) {
                    break :blk switch (ch) {
                        'a' - 1 => EditorAction.move_line_start, // Ctrl+A
                        'b' - 1 => EditorAction.move_left,       // Ctrl+B
                        'c' - 1 => EditorAction.cancel,          // Ctrl+C
                        'd' - 1 => EditorAction.delete,          // Ctrl+D
                        'e' - 1 => EditorAction.move_line_end,   // Ctrl+E
                        'f' - 1 => EditorAction.find,            // Ctrl+F
                        'g' - 1 => EditorAction.goto_line,       // Ctrl+G
                        'h' - 1 => EditorAction.backspace,       // Ctrl+H
                        'i' - 1 => EditorAction{ .insert_char = '\t' }, // Ctrl+I (Tab)
                        'k' - 1 => EditorAction.cut_line,        // Ctrl+K
                        'l' - 1 => EditorAction.move_right,      // Ctrl+L
                        'm' - 1 => EditorAction.insert_newline,  // Ctrl+M (Enter)
                        'n' - 1 => EditorAction.find_next,       // Ctrl+N
                        'o' - 1 => EditorAction.save,            // Ctrl+O
                        'p' - 1 => EditorAction.paste,           // Ctrl+P
                        'q' - 1 => EditorAction.quit,            // Ctrl+Q
                        'r' - 1 => EditorAction.find_previous,   // Ctrl+R
                        's' - 1 => EditorAction.save,            // Ctrl+S
                        'u' - 1 => EditorAction.undo,            // Ctrl+U
                        'v' - 1 => EditorAction.move_page_down,  // Ctrl+V
                        'w' - 1 => EditorAction.save_as,         // Ctrl+W
                        'x' - 1 => EditorAction.quit,            // Ctrl+X
                        'y' - 1 => EditorAction.copy_line,       // Ctrl+Y
                        'z' - 1 => EditorAction.undo,            // Ctrl+Z
                        else => EditorAction.none,
                    };
                }
                break :blk EditorAction{ .insert_char = ch };
            },
            .arrow_up => EditorAction.move_up,
            .arrow_down => EditorAction.move_down,
            .arrow_left => EditorAction.move_left,
            .arrow_right => EditorAction.move_right,
            .home => EditorAction.move_line_start,
            .end => EditorAction.move_line_end,
            .page_up => EditorAction.move_page_up,
            .page_down => EditorAction.move_page_down,
            .backspace => EditorAction.backspace,
            .delete => EditorAction.delete,
            .enter => EditorAction.insert_newline,
            .tab => EditorAction{ .insert_char = '\t' },
            .escape => EditorAction.cancel,
            else => EditorAction.none,
        };
    }

    fn processSearchKey(self: *Self, key: terminal.Key) EditorAction {
        return switch (key) {
            .char => |ch| blk: {
                if (ch >= 1 and ch <= 26) {
                    break :blk switch (ch) {
                        'c' - 1 => EditorAction.search_cancel,  // Ctrl+C
                        'g' - 1 => EditorAction.search_cancel,  // Ctrl+G
                        'm' - 1 => EditorAction.search_submit,  // Ctrl+M (Enter)
                        'r' - 1 => EditorAction.search_cancel,  // Ctrl+R
                        's' - 1 => EditorAction.search_submit,  // Ctrl+S
                        else => EditorAction.none,
                    };
                }
                self.search_buffer.append(ch) catch {};
                break :blk EditorAction{ .search_input = ch };
            },
            .enter => EditorAction.search_submit,
            .escape => EditorAction.search_cancel,
            .backspace => blk: {
                if (self.search_buffer.items.len > 0) {
                    _ = self.search_buffer.pop();
                    break :blk EditorAction{ .search_input = 0 };
                }
                break :blk EditorAction.none;
            },
            .delete => blk: {
                if (self.search_buffer.items.len > 0) {
                    _ = self.search_buffer.pop();
                    break :blk EditorAction{ .search_input = 0 };
                }
                break :blk EditorAction.none;
            },
            else => EditorAction.none,
        };
    }

    fn processPromptKey(self: *Self, key: terminal.Key) EditorAction {
        return switch (key) {
            .char => |ch| blk: {
                if (ch >= 1 and ch <= 26) {
                    break :blk switch (ch) {
                        'c' - 1 => EditorAction.prompt_cancel,   // Ctrl+C
                        'g' - 1 => EditorAction.prompt_cancel,   // Ctrl+G
                        'm' - 1 => EditorAction.prompt_submit,   // Ctrl+M (Enter)
                        else => EditorAction.none,
                    };
                }
                self.prompt_buffer.append(ch) catch {};
                break :blk EditorAction{ .prompt_input = ch };
            },
            .enter => EditorAction.prompt_submit,
            .escape => EditorAction.prompt_cancel,
            .backspace => blk: {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    break :blk EditorAction{ .prompt_input = 0 };
                }
                break :blk EditorAction.none;
            },
            .delete => blk: {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    break :blk EditorAction{ .prompt_input = 0 };
                }
                break :blk EditorAction.none;
            },
            else => EditorAction.none,
        };
    }

    fn processCommandKey(self: *Self, key: terminal.Key) EditorAction {
        return switch (key) {
            .char => |ch| blk: {
                if (ch >= 1 and ch <= 26) {
                    break :blk switch (ch) {
                        'c' - 1 => EditorAction.prompt_cancel,   // Ctrl+C
                        'g' - 1 => EditorAction.prompt_cancel,   // Ctrl+G
                        'm' - 1 => EditorAction.prompt_submit,   // Ctrl+M (Enter)
                        else => EditorAction.none,
                    };
                }
                self.prompt_buffer.append(ch) catch {};
                break :blk EditorAction{ .prompt_input = ch };
            },
            .enter => EditorAction.prompt_submit,
            .escape => EditorAction.prompt_cancel,
            .backspace => blk: {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    break :blk EditorAction{ .prompt_input = 0 };
                }
                break :blk EditorAction.none;
            },
            .delete => blk: {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    break :blk EditorAction{ .prompt_input = 0 };
                }
                break :blk EditorAction.none;
            },
            else => EditorAction.none,
        };
    }
};
