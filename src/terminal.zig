const std = @import("std");

pub const TerminalSize = struct {
    rows: u16,
    cols: u16,
};

pub const Key = union(enum) {
    // Arrow keys
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,

    // Control keys
    ctrl_a, ctrl_b, ctrl_c, ctrl_d, ctrl_e, ctrl_f, ctrl_g,
    ctrl_h, ctrl_i, ctrl_j, ctrl_k, ctrl_l, ctrl_m, ctrl_n,
    ctrl_o, ctrl_p, ctrl_q, ctrl_r, ctrl_s, ctrl_t, ctrl_u,
    ctrl_v, ctrl_w, ctrl_x, ctrl_y, ctrl_z,

    // Special keys
    escape, enter, backspace, delete, tab,
    home, end, page_up, page_down,

    // Regular characters
    char: u8,

    pub fn fromByte(byte: u8) Key {
        if (byte == '\r' or byte == '\n') {
            return .enter;
        }
        if (byte == '\t') {
            return .tab;
        }
        if (byte == 127) {
            return .backspace;
        }
        if (byte >= 1 and byte <= 26) {
            // Ctrl+A to Ctrl+Z
            return .{ .char = byte + 'a' - 1 };
        }
        return .{ .char = byte };
    }
};

pub const Terminal = struct {
    const Self = @This();

    raw_mode_enabled: bool,

    pub fn init() !Self {
        return Self{ .raw_mode_enabled = false };
    }

    pub fn deinit(self: Self) void {
        if (self.raw_mode_enabled) {
            clearScreen();
            showCursor();
        }
    }

    pub fn enableRawMode(self: *Self) !void {
        self.raw_mode_enabled = true;
        // Simplified for cross-platform compatibility
        // In a real implementation, we'd handle Windows console mode here
    }

    pub fn getSize() !TerminalSize {
        // Return a default size for now
        return TerminalSize{
            .rows = 24,
            .cols = 80,
        };
    }

    pub fn readKey() !Key {
        var buf: [3]u8 = undefined;
        var stdin = std.fs.File.stdin();
        const n = try stdin.read(buf[0..]);

        if (n == 0) return error.EndOfFile;

        // Handle escape sequences
        if (buf[0] == '\x1b') {
            if (n >= 3 and buf[1] == '[') {
                return switch (buf[2]) {
                    'A' => .arrow_up,
                    'B' => .arrow_down,
                    'C' => .arrow_right,
                    'D' => .arrow_left,
                    'H' => .home,
                    'F' => .end,
                    else => Key.fromByte(buf[0]),
                };
            }
            if (n >= 2 and buf[1] == 'O') {
                return switch (buf[2]) {
                    'H' => .home,
                    'F' => .end,
                    else => Key.fromByte(buf[0]),
                };
            }
            return .escape;
        }

        return Key.fromByte(buf[0]);
    }

    // ANSI escape sequences for terminal control
    pub fn clearScreen() void {
        std.debug.print("\x1b[2J", .{});
    }

    pub fn moveCursor(row: u16, col: u16) void {
        std.debug.print("\x1b[{};{}H", .{ row, col });
    }

    pub fn hideCursor() void {
        std.debug.print("\x1b[?25l", .{});
    }

    pub fn showCursor() void {
        std.debug.print("\x1b[?25h", .{});
    }

    pub fn clearLine() void {
        std.debug.print("\x1b[K", .{});
    }

    pub fn setColor(fg: u8, bg: u8) void {
        std.debug.print("\x1b[{};{}m", .{ fg, bg });
    }

    pub fn resetColor() void {
        std.debug.print("\x1b[0m", .{});
    }

    pub fn setBold() void {
        std.debug.print("\x1b[1m", .{});
    }

    pub fn setReverse() void {
        std.debug.print("\x1b[7m", .{});
    }

    pub fn moveCursorUp(n: u16) void {
        std.debug.print("\x1b[{}A", .{n});
    }

    pub fn moveCursorDown(n: u16) void {
        std.debug.print("\x1b[{}B", .{n});
    }

    pub fn moveCursorRight(n: u16) void {
        std.debug.print("\x1b[{}C", .{n});
    }

    pub fn moveCursorLeft(n: u16) void {
        std.debug.print("\x1b[{}D", .{n});
    }
};

// Banana yellow color constants
pub const BANANA_COLORS = struct {
    pub const YELLOW_BG: u8 = 43; // Yellow background
    pub const YELLOW_FG: u8 = 33; // Yellow foreground
    pub const BRIGHT_YELLOW_BG: u8 = 103; // Bright yellow background
    pub const BRIGHT_YELLOW_FG: u8 = 93; // Bright yellow foreground
    pub const BLACK_FG: u8 = 30; // Black foreground
    pub const WHITE_FG: u8 = 37; // White foreground
    pub const BLUE_FG: u8 = 34; // Blue foreground
    pub const RED_FG: u8 = 31; // Red foreground
    pub const GREEN_FG: u8 = 32; // Green foreground
};
