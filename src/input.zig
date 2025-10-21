const std = @import("std");
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
    prompt_buffer: std.ArrayList(u8),
    search_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        const prompt_buffer = std.ArrayList(u8).init(allocator);
        const search_buffer = std.ArrayList(u8).init(allocator);
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
        switch (key) {
            // Nano-style shortcuts
            .char => |ch| {
                if (ch >= 1 and ch <= 26) {
                    // Control key
                    return switch (ch) {
                        'a' - 1 => .move_line_start,  // Ctrl+A
                        'b' - 1 => .move_left,         // Ctrl+B
                        'c' - 1 => .cancel,            // Ctrl+C
                        'd' - 1 => .delete,            // Ctrl+D
                        'e' - 1 => .move_line_end,    // Ctrl+E
                        'f' - 1 => .find,              // Ctrl+F
                        'g' - 1 => .goto_line,         // Ctrl+G
                        'h' - 1 => .backspace,         // Ctrl+H
                        'i' - 1 => .{ .insert_char = '\t' }, // Ctrl+I (Tab)
                        'k' - 1 => .cut_line,          // Ctrl+K
                        'l' - 1 => .move_right,        // Ctrl+L
                        'm' - 1 => .insert_newline,    // Ctrl+M (Enter)
                        'n' - 1 => .find_next,         // Ctrl+N
                        'o' - 1 => .save,              // Ctrl+O
                        'p' - 1 => .paste,             // Ctrl+P
                        'q' - 1 => .quit,              // Ctrl+Q
                        'r' - 1 => .find_previous,     // Ctrl+R
                        's' - 1 => .save,              // Ctrl+S
                        'u' - 1 => .undo,              // Ctrl+U
                        'v' - 1 => .move_page_down,    // Ctrl+V
                        'w' - 1 => .save_as,           // Ctrl+W
                        'x' - 1 => .quit,              // Ctrl+X
                        'y' - 1 => .copy_line,         // Ctrl+Y
                        'z' - 1 => .undo,              // Ctrl+Z
                        else => .none,
                    };
                } else {
                    // Regular character input
                    return .{ .insert_char = ch };
                }
            },

            // Special keys
            .arrow_up => .move_up,
            .arrow_down => .move_down,
            .arrow_left => .move_left,
            .arrow_right => .move_right,
            .home => .move_line_start,
            .end => .move_line_end,
            .page_up => .move_page_up,
            .page_down => .move_page_down,
            .backspace => .backspace,
            .delete => .delete,
            .enter => .insert_newline,
            .tab => .{ .insert_char = '\t' },
            .escape => .cancel,

            // Help key (F1)
            else => .none,
        }
    }

    fn processSearchKey(self: *Self, key: terminal.Key) EditorAction {
        switch (key) {
            .char => |ch| {
                if (ch >= 1 and ch <= 26) {
                    // Control key
                    return switch (ch) {
                        'c' - 1 => .search_cancel,      // Ctrl+C
                        'g' - 1 => .search_cancel,      // Ctrl+G
                        'm' - 1 => .search_submit,      // Ctrl+M (Enter)
                        'r' - 1 => .search_cancel,      // Ctrl+R
                        's' - 1 => .search_submit,      // Ctrl+S
                        else => .none,
                    };
                } else {
                    // Regular character - add to search buffer
                    self.search_buffer.append(ch) catch {};
                    return .{ .search_input = ch };
                }
            },

            .enter => .search_submit,
            .escape => .search_cancel,
            .backspace => {
                if (self.search_buffer.items.len > 0) {
                    _ = self.search_buffer.pop();
                    return .{ .search_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            .delete => {
                if (self.search_buffer.items.len > 0) {
                    _ = self.search_buffer.pop();
                    return .{ .search_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            else => .none,
        }
    }

    fn processPromptKey(self: *Self, key: terminal.Key) EditorAction {
        switch (key) {
            .char => |ch| {
                if (ch >= 1 and ch <= 26) {
                    // Control key
                    return switch (ch) {
                        'c' - 1 => .prompt_cancel,      // Ctrl+C
                        'g' - 1 => .prompt_cancel,      // Ctrl+G
                        'm' - 1 => .prompt_submit,      // Ctrl+M (Enter)
                        else => .none,
                    };
                } else {
                    // Regular character - add to prompt buffer
                    self.prompt_buffer.append(ch) catch {};
                    return .{ .prompt_input = ch };
                }
            },

            .enter => .prompt_submit,
            .escape => .prompt_cancel,
            .backspace => {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    return .{ .prompt_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            .delete => {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    return .{ .prompt_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            else => .none,
        }
    }

    fn processCommandKey(self: *Self, key: terminal.Key) EditorAction {
        switch (key) {
            .char => |ch| {
                if (ch >= 1 and ch <= 26) {
                    // Control key
                    return switch (ch) {
                        'c' - 1 => .prompt_cancel,      // Ctrl+C
                        'g' - 1 => .prompt_cancel,      // Ctrl+G
                        'm' - 1 => .prompt_submit,      // Ctrl+M (Enter)
                        else => .none,
                    };
                } else {
                    // Regular character - add to prompt buffer
                    self.prompt_buffer.append(ch) catch {};
                    return .{ .prompt_input = ch };
                }
            },

            .enter => .prompt_submit,
            .escape => .prompt_cancel,
            .backspace => {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    return .{ .prompt_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            .delete => {
                if (self.prompt_buffer.items.len > 0) {
                    _ = self.prompt_buffer.pop();
                    return .{ .prompt_input = 0 }; // Signal buffer update
                }
                return .none;
            },
            else => .none,
        }
    }
};