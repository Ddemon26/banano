//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

/// Banano Editor - A terminal-based text editor with banana yellow theming
pub const editor = @import("editor.zig");
pub const terminal = @import("terminal.zig");
pub const buffer = @import("buffer.zig");
pub const display = @import("display.zig");
pub const input = @import("input.zig");

/// Version information
pub const VERSION = "0.1.0";

/// Welcome message
pub const WELCOME_MESSAGE = "Welcome to Banano Editor - The Yellow Text Editor!";

pub fn printWelcome() !void {
    const stdout = std.fs.File.stdout().writer();
    try stdout.print("{s}\n", .{WELCOME_MESSAGE});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
