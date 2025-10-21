const std = @import("std");
const terminal = @import("terminal.zig");
const buffer = @import("buffer.zig");

pub const Display = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal_size: terminal.TerminalSize,
    status_bar_height: u16 = 2,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const term_size = try terminal.Terminal.getSize();
        return Self{
            .allocator = allocator,
            .terminal_size = term_size,
        };
    }

    pub fn refreshTerminalSize(self: *Self) !void {
        self.terminal_size = try terminal.Terminal.getSize();
    }

    pub fn clear() void {
        terminal.clearScreen();
        terminal.moveCursor(1, 1);
    }

    pub fn render(self: Self, text_buffer: buffer.TextBuffer) void {
        const viewport_height = self.terminal_size.rows - self.status_bar_height;
        const viewport_width = self.terminal_size.cols;

        // Clear screen
        clear();

        // Render text content
        renderTextContent(text_buffer, viewport_height, viewport_width);

        // Render status bar
        self.renderStatusBar(text_buffer);

        // Position cursor
        const cursor = text_buffer.getCursor();
        const screen_row = @min(cursor.y + 1, viewport_height);
        const screen_col = @min(cursor.x + 1, viewport_width);
        terminal.moveCursor(screen_row, screen_col);
    }

    fn renderTextContent(text_buffer: buffer.TextBuffer, viewport_height: u16, viewport_width: u16) void {
        const line_count = text_buffer.getLineCount();
        const cursor_y = text_buffer.getCursor().y;

        // Calculate scrolling offset
        var scroll_offset: usize = 0;
        if (line_count > viewport_height) {
            if (cursor_y >= viewport_height) {
                scroll_offset = cursor_y - viewport_height + 1;
            }
        }

        // Render visible lines
        for (0..viewport_height) |row| {
            const line_index = row + scroll_offset;
            terminal.moveCursor(@intCast(row + 1), 1);
            terminal.clearLine();

            if (line_index < line_count) {
                if (text_buffer.getLine(line_index)) |line_content| {
                    renderLine(line_content, viewport_width);
                }
            } else {
                // Render empty line with line number
                renderLine("", viewport_width);
            }
        }
    }

    fn renderLine(line_content: []const u8, viewport_width: u16) void {
        const content_len = @min(line_content.len, viewport_width);

        // Render line content
        if (content_len > 0) {
            std.debug.print("{s}", .{line_content[0..content_len]});
        }

        // Fill remaining space with background
        const remaining = viewport_width - content_len;
        if (remaining > 0) {
            const spaces = [_]u8{' '} ** 200; // Buffer for spaces
            const spaces_to_print = @min(remaining, spaces.len);
            std.debug.print("{s}", .{spaces[0..spaces_to_print]});
        }
    }

    fn renderStatusBar(self: Self, text_buffer: buffer.TextBuffer) void {
        const status_row = self.terminal_size.rows - 1;
        terminal.moveCursor(status_row, 1);

        // Draw banana yellow status bar background
        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        terminal.setBold();

        // Build status bar content
        var status_content = std.ArrayList(u8).init(self.allocator);
        defer status_content.deinit();

        // Filename or "New Buffer"
        if (text_buffer.getFilename()) |filename| {
            status_content.writer().print(" {s}", .{filename}) catch {};
        } else {
            status_content.appendSlice(" New Buffer") catch {};
        }

        // Dirty indicator
        if (text_buffer.isDirty()) {
            status_content.appendSlice(" *") catch {};
        }

        // Cursor position
        const cursor = text_buffer.getCursor();
        const line_count = text_buffer.getLineCount();
        status_content.writer().print(" | Ln {d}/{d}, Col {d}", .{
            cursor.y + 1,
            line_count,
            cursor.x + 1
        }) catch {};

        // Pad the rest of the status bar
        const status_len = @min(status_content.items.len, self.terminal_size.cols - 2);
        const remaining_space = self.terminal_size.cols - status_len - 2;

        std.debug.print(" {s}", .{status_content.items[0..status_len]});

        // Fill remaining space
        const filler = [_]u8{' '} ** 200;
        const filler_len = @min(remaining_space, filler.len);
        if (filler_len > 0) {
            std.debug.print("{s}", .{filler[0..filler_len]});
        }

        terminal.resetColor();
    }

    pub fn renderHelpBar(self: Self) void {
        const help_row = self.terminal_size.rows;
        terminal.moveCursor(help_row, 1);

        // Banana yellow help bar
        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.BRIGHT_YELLOW_BG);
        terminal.setBold();

        const help_text = " ^X Exit  ^O Save  ^W Write As  ^F Find  ^G Go To Line  ^K Cut  ^U Paste  ^C Cancel ";
        const help_len = @min(help_text.len, self.terminal_size.cols);

        std.debug.print("{s}", .{help_text[0..help_len]});

        // Fill remaining space
        const remaining = self.terminal_size.cols - help_len;
        if (remaining > 0) {
            const filler = [_]u8{' '} ** 200;
            const filler_len = @min(remaining, filler.len);
            std.debug.print("{s}", .{filler[0..filler_len]});
        }

        terminal.resetColor();
    }

    pub fn renderMessage(self: Self, message: []const u8) void {
        const message_row = self.terminal_size.rows;
        terminal.moveCursor(message_row, 1);

        // Clear the message line
        terminal.clearLine();

        // Yellow highlighted message
        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        terminal.setBold();

        const message_len = @min(message.len, self.terminal_size.cols - 2);
        std.debug.print(" {s}", .{message[0..message_len]});

        terminal.resetColor();
    }

    pub fn renderPrompt(self: Self, prompt: []const u8, input: []const u8) void {
        const prompt_row = self.terminal_size.rows;
        terminal.moveCursor(prompt_row, 1);

        // Clear the prompt line
        terminal.clearLine();

        // Yellow prompt with user input
        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        terminal.setBold();

        const total_len = prompt.len + input.len;
        const max_len = self.terminal_size.cols - 2;
        const display_len = @min(total_len, max_len);

        std.debug.print(" {s}{s}", .{ prompt, input[0..display_len - prompt.len] });

        terminal.resetColor();
    }

    pub fn renderSearchResults(self: Self, text_buffer: buffer.TextBuffer, matches: []const buffer.TextBuffer.SearchMatch, current_match: usize) void {
        const viewport_height = self.terminal_size.rows - self.status_bar_height;
        const viewport_width = self.terminal_size.cols;
        const line_count = text_buffer.getLineCount();
        const cursor_y = text_buffer.getCursor().y;

        // Calculate scrolling offset
        var scroll_offset: usize = 0;
        if (line_count > viewport_height) {
            if (cursor_y >= viewport_height) {
                scroll_offset = cursor_y - viewport_height + 1;
            }
        }

        // Render lines with highlighting
        for (0..viewport_height) |row| {
            const line_index = row + scroll_offset;
            terminal.moveCursor(@intCast(row + 1), 1);
            terminal.clearLine();

            if (line_index < line_count) {
                if (text_buffer.getLine(line_index)) |line_content| {
                    renderLineWithSearchHighlights(line_content, viewport_width, line_index, matches, current_match);
                }
            }
        }

        // Update status bar with search info
        self.renderSearchStatusBar(matches, current_match);
    }

    fn renderLineWithSearchHighlights(line_content: []const u8, viewport_width: u16, line_index: usize, matches: []const buffer.SearchMatch, current_match: usize) void {
        var col: usize = 0;

        for (matches, 0..) |match_info, i| {
            if (match_info.line == line_index) {
                // Render content before match
                if (match_info.start > col) {
                    const segment_len = @min(match_info.start - col, viewport_width - col);
                    std.debug.print("{s}", .{line_content[col..col + segment_len]});
                    col += segment_len;
                }

                // Render highlighted match
                if (col < viewport_width and col < line_content.len) {
                    const match_len = @min(match_info.end - match_info.start, viewport_width - col);

                    if (i == current_match) {
                        // Current match - bright yellow background
                        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.BRIGHT_YELLOW_BG);
                        terminal.setBold();
                    } else {
                        // Other matches - yellow background
                        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
                    }

                    std.debug.print("{s}", .{line_content[col..col + match_len]});
                    terminal.resetColor();
                    col += match_len;
                }
            }
        }

        // Render remaining content
        if (col < viewport_width and col < line_content.len) {
            const remaining_len = @min(line_content.len - col, viewport_width - col);
            std.debug.print("{s}", .{line_content[col..col + remaining_len]});
        }

        // Fill remaining space
        const remaining = viewport_width - @min(line_content.len, viewport_width);
        if (remaining > 0) {
            const filler = [_]u8{' '} ** 200;
            const filler_len = @min(remaining, filler.len);
            std.debug.print("{s}", .{filler[0..filler_len]});
        }
    }

    fn renderSearchStatusBar(self: Self, matches: []const buffer.TextBuffer.SearchMatch, current_match: usize) void {
        const status_row = self.terminal_size.rows - 1;
        terminal.moveCursor(status_row, 1);

        terminal.setColor(terminal.BANANA_COLORS.BLACK_FG, terminal.BANANA_COLORS.YELLOW_BG);
        terminal.setBold();

        var status = std.ArrayList(u8).init(self.allocator);
        defer status.deinit();

        if (matches.len > 0) {
            status.writer().print(" Search: {d}/{d} matches", .{ current_match + 1, matches.len }) catch {};
        } else {
            status.appendSlice(" Search: No matches") catch {};
        }

        status.writer().print(" | ^F Find Next  ^R Find Previous  ^C Cancel", .{}) catch {};

        const status_len = @min(status.items.len, self.terminal_size.cols);
        std.debug.print("{s}", .{status.items[0..status_len]});

        terminal.resetColor();
    }
};