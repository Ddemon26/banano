const std = @import("std");

/// Represents a line of text in the editor
pub const Line = struct {
    const Self = @This();

    chars: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .chars = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.chars.deinit();
    }

    pub fn insertChar(self: *Self, pos: usize, ch: u8) !void {
        try self.chars.insert(pos, ch);
    }

    pub fn deleteChar(self: *Self, pos: usize) void {
        if (pos < self.chars.items.len) {
            _ = self.chars.orderedRemove(pos);
        }
    }

    pub fn appendString(self: *Self, str: []const u8) !void {
        try self.chars.appendSlice(str);
    }

    pub fn slice(self: Self) []const u8 {
        return self.chars.items;
    }

    pub fn len(self: Self) usize {
        return self.chars.items.len;
    }

    pub fn clear(self: *Self) void {
        self.chars.clearAndFree();
    }
};

/// Gap buffer for efficient text editing
pub const GapBuffer = struct {
    const Self = @This();

    buffer: std.ArrayList(u8),
    gap_start: usize,
    gap_end: usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        var buffer = std.ArrayList(u8).init(allocator);
        buffer.resize(1024) catch unreachable;

        return Self{
            .buffer = buffer,
            .gap_start = 0,
            .gap_end = 1024,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    fn ensureGap(self: *Self, min_gap: usize) !void {
        const current_gap = self.gap_end - self.gap_start;
        if (current_gap >= min_gap) return;

        // Double the buffer size
        const new_size = self.buffer.items.len * 2;
        try self.buffer.resize(new_size);

        // Move gap to the end if needed
        if (self.gap_end < new_size) {
            const move_amount = new_size - self.buffer.items.len;
            std.mem.copy(
                u8,
                self.buffer.items[self.gap_start + move_amount ..],
                self.buffer.items[self.gap_start .. self.gap_end],
            );
            self.gap_start += move_amount;
            self.gap_end += move_amount;
        }
    }

    pub fn moveGap(self: *Self, pos: usize) void {
        if (pos < self.gap_start) {
            // Move gap left
            const move_len = self.gap_start - pos;
            std.mem.copy(
                u8,
                self.buffer.items[pos + (self.gap_end - self.gap_start) ..],
                self.buffer.items[pos .. self.gap_start],
            );
            self.gap_start = pos;
            self.gap_end -= move_len;
        } else if (pos > self.gap_start) {
            // Move gap right
            const move_len = pos - self.gap_start;
            std.mem.copy(
                u8,
                self.buffer.items[self.gap_end .. self.gap_end + move_len],
                self.buffer.items[self.gap_start .. pos],
            );
            self.gap_start = pos;
            self.gap_end += move_len;
        }
    }

    pub fn insertChar(self: *Self, ch: u8) !void {
        try self.ensureGap(1);
        self.buffer.items[self.gap_start] = ch;
        self.gap_start += 1;
    }

    pub fn insertString(self: *Self, str: []const u8) !void {
        try self.ensureGap(str.len);
        std.mem.copy(u8, self.buffer.items[self.gap_start ..], str);
        self.gap_start += str.len;
    }

    pub fn deleteChar(self: *Self) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
        }
    }

    pub fn deleteCharForward(self: *Self) void {
        if (self.gap_end < self.buffer.items.len) {
            self.gap_end += 1;
        }
    }

    pub fn getString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const len = self.buffer.items.len - (self.gap_end - self.gap_start);
        var result = try allocator.alloc(u8, len);

        // Copy text before gap
        std.mem.copy(u8, result, self.buffer.items[0..self.gap_start]);

        // Copy text after gap
        std.mem.copy(
            u8,
            result[self.gap_start..],
            self.buffer.items[self.gap_end..],
        );

        return result;
    }
};

/// Search match representation
pub const SearchMatch = struct {
    line: usize,
    start: usize,
    end: usize,
};

/// Main text buffer that manages lines
pub const TextBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),
    cursor_x: usize,
    cursor_y: usize,
    filename: ?[]const u8,
    dirty: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .cursor_x = 0,
            .cursor_y = 0,
            .filename = null,
            .dirty = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
        if (self.filename) |filename| {
            self.allocator.free(filename);
        }
    }

    pub fn insertLine(self: *Self, pos: usize) !void {
        const new_line = Line.init(self.allocator);
        try self.lines.insert(pos, new_line);
        self.dirty = true;
    }

    pub fn deleteLine(self: *Self, pos: usize) void {
        if (pos < self.lines.items.len) {
            self.lines.items[pos].deinit();
            _ = self.lines.orderedRemove(pos);
            self.dirty = true;
        }
    }

    pub fn insertChar(self: *Self, ch: u8) !void {
        if (self.lines.items.len == 0) {
            try self.insertLine(0);
        }

        const line = &self.lines.items[self.cursor_y];
        try line.insertChar(self.cursor_x, ch);
        self.cursor_x += 1;
        self.dirty = true;
    }

    pub fn insertString(self: *Self, str: []const u8) !void {
        if (self.lines.items.len == 0) {
            try self.insertLine(0);
        }

        const line = &self.lines.items[self.cursor_y];
        try line.appendSlice(str);
        self.cursor_x += str.len;
        self.dirty = true;
    }

    pub fn deleteChar(self: *Self) void {
        if (self.lines.items.len == 0) return;

        if (self.cursor_x > 0) {
            const line = &self.lines.items[self.cursor_y];
            line.deleteChar(self.cursor_x - 1);
            self.cursor_x -= 1;
            self.dirty = true;
        } else if (self.cursor_y > 0) {
            // Merge with previous line
            const prev_line = &self.lines.items[self.cursor_y - 1];
            const current_line = &self.lines.items[self.cursor_y];

            self.cursor_x = prev_line.len();
            try prev_line.appendSlice(current_line.slice());

            self.deleteLine(self.cursor_y);
            self.cursor_y -= 1;
            self.dirty = true;
        }
    }

    pub fn deleteCharForward(self: *Self) void {
        if (self.lines.items.len == 0) return;

        const line = &self.lines.items[self.cursor_y];
        if (self.cursor_x < line.len()) {
            line.deleteChar(self.cursor_x);
            self.dirty = true;
        } else if (self.cursor_y + 1 < self.lines.items.len) {
            // Merge with next line
            const next_line = &self.lines.items[self.cursor_y + 1];
            try line.appendSlice(next_line.slice());
            self.deleteLine(self.cursor_y + 1);
            self.dirty = true;
        }
    }

    pub fn insertNewline(self: *Self) !void {
        if (self.lines.items.len == 0) {
            try self.insertLine(0);
        }

        const current_line = &self.lines.items[self.cursor_y];
        const new_content = current_line.slice()[self.cursor_x..];

        // Split the current line
        current_line.chars.shrinkRetainingCapacity(self.cursor_x);

        // Insert new line with remaining content
        try self.insertLine(self.cursor_y + 1);
        const new_line = &self.lines.items[self.cursor_y + 1];
        try new_line.appendSlice(new_content);

        self.cursor_x = 0;
        self.cursor_y += 1;
        self.dirty = true;
    }

    pub fn moveCursor(self: *Self, dx: i32, dy: i32) void {
        if (dy < 0 and self.cursor_y > 0) {
            self.cursor_y -= @intCast(-dy);
        } else if (dy > 0 and self.cursor_y < self.lines.items.len - 1) {
            self.cursor_y += @intCast(dy);
        }

        const current_line = if (self.lines.items.len > 0) self.lines.items[self.cursor_y].len() else 0;
        if (dx < 0 and self.cursor_x > 0) {
            self.cursor_x -= @intCast(-dx);
        } else if (dx > 0 and self.cursor_x < current_line) {
            self.cursor_x += @intCast(dx);
        }

        // Ensure cursor stays within line bounds
        if (self.cursor_x > current_line) {
            self.cursor_x = current_line;
        }
    }

    pub fn setCursor(self: *Self, x: usize, y: usize) void {
        if (y < self.lines.items.len) {
            self.cursor_y = y;
            const line_len = self.lines.items[y].len();
            self.cursor_x = @min(x, line_len);
        }
    }

    pub fn getCursor(self: Self) struct { x: usize, y: usize } {
        return .{ .x = self.cursor_x, .y = self.cursor_y };
    }

    pub fn getLine(self: Self, index: usize) ?[]const u8 {
        if (index < self.lines.items.len) {
            return self.lines.items[index].slice();
        }
        return null;
    }

    pub fn getLineCount(self: Self) usize {
        return self.lines.items.len;
    }

    pub fn isDirty(self: Self) bool {
        return self.dirty;
    }

    pub fn setDirty(self: *Self, dirty: bool) void {
        self.dirty = dirty;
    }

    pub fn getFilename(self: Self) ?[]const u8 {
        return self.filename;
    }

    pub fn setFilename(self: *Self, filename: []const u8) !void {
        if (self.filename) |old_name| {
            self.allocator.free(old_name);
        }
        self.filename = try self.allocator.dupe(u8, filename);
    }

    pub fn loadFromFile(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        // Clear existing content
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearAndFree();

        // Set filename
        try self.setFilename(filename);

        // Read file content
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit
        defer self.allocator.free(content);

        // Split into lines
        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        while (lines.next()) |line_str| {
            try self.insertLine(self.lines.items.len);
            const new_line = &self.lines.items[self.lines.items.len - 1];
            try new_line.appendSlice(line_str);
        }

        // Handle empty file
        if (self.lines.items.len == 0) {
            try self.insertLine(0);
        }

        self.cursor_x = 0;
        self.cursor_y = 0;
        self.dirty = false;
    }

    pub fn saveToFile(self: Self) !void {
        if (self.filename) |filename| {
            const file = try std.fs.cwd().createFile(filename, .{});
            defer file.close();

            var buffered_writer = std.io.bufferedWriter(file.writer());
            const writer = buffered_writer.writer();

            for (self.lines.items, 0..) |line, i| {
                try writer.writeAll(line.slice());
                if (i < self.lines.items.len - 1) {
                    try writer.writeByte('\n');
                }
            }

            try buffered_writer.flush();
        }
    }
};