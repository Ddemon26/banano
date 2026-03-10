const std = @import("std");
const terminal = @import("terminal.zig");
const buffer = @import("buffer.zig");
const ManagedArrayList = std.array_list.Managed;

const SearchHighlight = struct {
    matches: []const buffer.SearchMatch,
    current_index: usize,
};

const StatusMode = union(enum) {
    normal,
    search: SearchHighlight,
};

pub const Display = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal_size: terminal.TerminalSize,
    status_bar_height: u16 = 2,
    frame_buffer: ManagedArrayList(u8),
    last_frame: ManagedArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !Self {
        const term_size = try terminal.Terminal.getSize();
        return Self{
            .allocator = allocator,
            .terminal_size = term_size,
            .frame_buffer = ManagedArrayList(u8).init(allocator),
            .last_frame = ManagedArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.frame_buffer.deinit();
        self.last_frame.deinit();
    }

    pub fn refreshTerminalSize(self: *Self) !void {
        self.terminal_size = try terminal.Terminal.getSize();
    }

    pub fn renderNormal(self: *Self, text_buffer: buffer.TextBuffer) !void {
        const scroll = try self.beginTextFrame(text_buffer, null);
        try self.drawStatusBar(text_buffer, .normal);
        try self.drawHelpBar();
        try self.positionCursor(text_buffer, scroll);
        try self.submitFrame();
    }

    pub fn renderPromptView(self: *Self, text_buffer: buffer.TextBuffer, prompt_label: []const u8, input_text: []const u8) !void {
        _ = try self.beginTextFrame(text_buffer, null);
        try self.drawStatusBar(text_buffer, .normal);
        const caret_col = try self.drawPrompt(prompt_label, input_text);
        try self.positionPromptCursor(caret_col);
        try self.submitFrame();
    }

    pub fn renderSearchView(
        self: *Self,
        text_buffer: buffer.TextBuffer,
        matches: []const buffer.SearchMatch,
        current_match: usize,
        prompt_label: []const u8,
        input_text: []const u8,
    ) !void {
        const highlight = SearchHighlight{ .matches = matches, .current_index = current_match };
        _ = try self.beginTextFrame(text_buffer, highlight);
        try self.drawStatusBar(text_buffer, .{ .search = highlight });
        const caret_col = try self.drawPrompt(prompt_label, input_text);
        try self.positionPromptCursor(caret_col);
        try self.submitFrame();
    }

    pub fn renderMessage(self: *Self, text_buffer: buffer.TextBuffer, message: []const u8) !void {
        const scroll = try self.beginTextFrame(text_buffer, null);
        try self.drawStatusBar(text_buffer, .normal);
        try self.drawMessageBar(message);
        try self.positionCursor(text_buffer, scroll);
        try self.submitFrame();
    }

    fn beginTextFrame(self: *Self, text_buffer: buffer.TextBuffer, highlight: ?SearchHighlight) !usize {
        self.frame_buffer.clearRetainingCapacity();
        try appendClearScreen(&self.frame_buffer);
        const viewport_height_u16: u16 = if (self.terminal_size.rows > self.status_bar_height)
            self.terminal_size.rows - self.status_bar_height
        else
            0;
        const viewport_height: usize = @intCast(viewport_height_u16);
        const line_count = text_buffer.getLineCount();
        const cursor_y = text_buffer.getCursor().y;

        var scroll_offset: usize = 0;
        if (line_count > viewport_height) {
            if (cursor_y >= viewport_height) {
                scroll_offset = cursor_y - viewport_height + 1;
            }
        }

        for (0..viewport_height) |row| {
            const line_index = row + scroll_offset;
            const row_pos: u16 = @intCast(row + 1);
            try appendMoveCursor(&self.frame_buffer, row_pos, 1);
            try appendClearLine(&self.frame_buffer);

            if (line_index < line_count) {
                if (text_buffer.getLine(line_index)) |line_content| {
                    if (highlight) |h| {
                        try self.drawLineWithHighlights(line_content, line_index, h);
                    } else {
                        try self.drawPlainLine(line_content);
                    }
                }
            }
        }

        return scroll_offset;
    }

    fn drawPlainLine(self: *Self, line_content: []const u8) !void {
        if (line_content.len > 0) {
            try self.frame_buffer.appendSlice(line_content);
        }
    }

    fn drawLineWithHighlights(self: *Self, line_content: []const u8, line_index: usize, highlight: SearchHighlight) !void {
        var col: usize = 0;
        for (highlight.matches, 0..) |match_info, idx| {
            if (match_info.line != line_index) continue;

            if (match_info.start > col) {
                const seg_len = match_info.start - col;
                const slice = line_content[col .. col + seg_len];
                try self.frame_buffer.appendSlice(slice);
                col += seg_len;
            }

            if (col >= line_content.len) break;
            const remaining = line_content.len - col;
            const match_len = @min(match_info.end - match_info.start, remaining);

            if (idx == highlight.current_index) {
                try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.BRIGHT_YELLOW_BG);
                try appendSetBold(&self.frame_buffer);
            } else {
                try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
            }

            const slice = line_content[col .. col + match_len];
            try self.frame_buffer.appendSlice(slice);
            try appendResetColor(&self.frame_buffer);
            col += match_len;
        }

        if (col < line_content.len) {
            try self.frame_buffer.appendSlice(line_content[col..]);
        }
    }

    fn drawStatusBar(self: *Self, text_buffer: buffer.TextBuffer, mode: StatusMode) !void {
        const status_row = self.terminal_size.rows - 1;
        try appendMoveCursor(&self.frame_buffer, status_row, 1);
        try appendClearLine(&self.frame_buffer);
        try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        try appendSetBold(&self.frame_buffer);

        var temp_buffer: [512]u8 = undefined;
        const content = switch (mode) {
            .normal => blk: {
                const filename = text_buffer.getFilename();
                const cursor = text_buffer.getCursor();
                const line_count = text_buffer.getLineCount();
                const dirty_marker: []const u8 = if (text_buffer.isDirty()) " *" else "";
                break :blk try std.fmt.bufPrint(
                    &temp_buffer,
                    " {s}{s} | Ln {d}/{d}, Col {d}",
                    .{
                        filename orelse "New Buffer",
                        dirty_marker,
                        cursor.y + 1,
                        line_count,
                        cursor.x + 1,
                    },
                );
            },
            .search => |info| blk: {
                break :blk try std.fmt.bufPrint(
                    &temp_buffer,
                    " Search: {d}/{d} matches | ^F Find Next  ^R Find Previous  ^C Cancel",
                    .{
                        if (info.matches.len == 0) 0 else info.current_index + 1,
                        info.matches.len,
                    },
                );
            },
        };

        const truncated_len = @min(content.len, self.terminal_size.cols);
        try self.frame_buffer.appendSlice(content[0..truncated_len]);

        if (truncated_len < self.terminal_size.cols) {
            try appendSpaces(&self.frame_buffer, self.terminal_size.cols - truncated_len);
        }

        try appendResetColor(&self.frame_buffer);
    }

    fn drawHelpBar(self: *Self) !void {
        const help_row = self.terminal_size.rows;
        try appendMoveCursor(&self.frame_buffer, help_row, 1);
        try appendClearLine(&self.frame_buffer);
        try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.BRIGHT_YELLOW_BG);
        try appendSetBold(&self.frame_buffer);

        const help_text = " ^X Exit  ^O Save  ^W Write As  ^F Find  ^G Go To Line  ^K Cut  ^U Paste  ^C Cancel ";
        const help_len = @min(help_text.len, self.terminal_size.cols);
        try self.frame_buffer.appendSlice(help_text[0..help_len]);
        if (help_len < self.terminal_size.cols) {
            try appendSpaces(&self.frame_buffer, self.terminal_size.cols - help_len);
        }

        try appendResetColor(&self.frame_buffer);
    }

    fn drawPrompt(self: *Self, prompt_label: []const u8, input_text: []const u8) !usize {
        const prompt_row = self.terminal_size.rows;
        try appendMoveCursor(&self.frame_buffer, prompt_row, 1);
        try appendClearLine(&self.frame_buffer);
        try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        try appendSetBold(&self.frame_buffer);

        const max_len: usize = if (self.terminal_size.cols > 2) self.terminal_size.cols - 2 else 0;
        const total_len = prompt_label.len + input_text.len;
        const display_len = if (max_len == 0) 0 else @min(total_len, max_len);
        const visible_input_len = if (display_len > prompt_label.len) display_len - prompt_label.len else 0;
        const input_slice = input_text[0..visible_input_len];

        try self.frame_buffer.appendSlice(" ");
        try self.frame_buffer.appendSlice(prompt_label);
        try self.frame_buffer.appendSlice(input_slice);

        try appendResetColor(&self.frame_buffer);

        const cols_usize: usize = @intCast(self.terminal_size.cols);
        const final_col = @min(1 + 1 + prompt_label.len + visible_input_len, cols_usize);
        return final_col;
    }

    fn drawMessageBar(self: *Self, message: []const u8) !void {
        const row = self.terminal_size.rows;
        try appendMoveCursor(&self.frame_buffer, row, 1);
        try appendClearLine(&self.frame_buffer);
        try appendSetColor(&self.frame_buffer, terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        try appendSetBold(&self.frame_buffer);

        const max_len = if (self.terminal_size.cols > 2) self.terminal_size.cols - 2 else 0;
        const display_len = @min(message.len, max_len);
        try self.frame_buffer.appendSlice(" ");
        try self.frame_buffer.appendSlice(message[0..display_len]);
        if (display_len < max_len) {
            try appendSpaces(&self.frame_buffer, max_len - display_len);
        }
        try appendResetColor(&self.frame_buffer);
    }

    fn positionCursor(self: *Self, text_buffer: buffer.TextBuffer, scroll_offset: usize) !void {
        const cursor = text_buffer.getCursor();
        const viewport_height_u16: u16 = if (self.terminal_size.rows > self.status_bar_height)
            self.terminal_size.rows - self.status_bar_height
        else
            0;
        const viewport_height: usize = @intCast(viewport_height_u16);
        const screen_row = @min(cursor.y - scroll_offset + 1, viewport_height);
        const cols_usize: usize = @intCast(self.terminal_size.cols);
        const screen_col = @min(cursor.x + 1, cols_usize);
        const row_pos: u16 = @intCast(screen_row);
        const col_pos: u16 = @intCast(screen_col);
        try appendMoveCursor(&self.frame_buffer, row_pos, col_pos);
    }

    fn positionPromptCursor(self: *Self, caret_col: usize) !void {
        const row = self.terminal_size.rows;
        const cols_usize: usize = @intCast(self.terminal_size.cols);
        const clamped = @min(caret_col, cols_usize);
        const col_pos: u16 = @intCast(clamped);
        try appendMoveCursor(&self.frame_buffer, row, col_pos);
    }

    fn submitFrame(self: *Self) !void {
        if (std.mem.eql(u8, self.frame_buffer.items, self.last_frame.items)) {
            return;
        }

        var stdout_file = std.fs.File.stdout();
        try stdout_file.writeAll(self.frame_buffer.items);

        self.last_frame.clearRetainingCapacity();
        try self.last_frame.appendSlice(self.frame_buffer.items);
    }
};

fn appendClearScreen(buf: *ManagedArrayList(u8)) !void {
    try buf.appendSlice("\x1b[2J");
}

fn appendClearLine(buf: *ManagedArrayList(u8)) !void {
    try buf.appendSlice("\x1b[K");
}

fn appendMoveCursor(buf: *ManagedArrayList(u8), row: u16, col: u16) !void {
    var seq: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&seq, "\x1b[{d};{d}H", .{ row, col });
    try buf.appendSlice(text);
}

fn appendSetColor(buf: *ManagedArrayList(u8), fg: u8, bg: u8) !void {
    var seq: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&seq, "\x1b[{d};{d}m", .{ fg, bg });
    try buf.appendSlice(text);
}

fn appendSetBold(buf: *ManagedArrayList(u8)) !void {
    try buf.appendSlice("\x1b[1m");
}

fn appendResetColor(buf: *ManagedArrayList(u8)) !void {
    try buf.appendSlice("\x1b[0m");
}

fn appendSpaces(buf: *ManagedArrayList(u8), count: usize) !void {
    if (count == 0) return;
    try buf.appendNTimes(' ', count);
}
