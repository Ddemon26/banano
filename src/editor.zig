const std = @import("std");
const terminal = @import("terminal.zig");
const buffer = @import("buffer.zig");
const display = @import("display.zig");
const input = @import("input.zig");

pub const Editor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    term: terminal.Terminal,
    display: display.Display,
    input_handler: input.InputHandler,
    text_buffer: buffer.TextBuffer,
    clipboard: std.ArrayList(u8),
    search_matches: std.ArrayList(buffer.SearchMatch),
    current_search_match: usize,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var term = try terminal.Terminal.init();
        try term.enableRawMode();

        const clipboard = std.ArrayList(u8).init(allocator);
        const search_matches = std.ArrayList(buffer.SearchMatch).init(allocator);

        return Self{
            .allocator = allocator,
            .term = term,
            .display = try display.Display.init(allocator),
            .input_handler = input.InputHandler.init(allocator),
            .text_buffer = buffer.TextBuffer.init(allocator),
            .clipboard = clipboard,
            .search_matches = search_matches,
            .current_search_match = 0,
            .running = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.term.deinit();
        self.text_buffer.deinit();
        self.clipboard.deinit();
        self.search_matches.deinit();
        self.input_handler.deinit();
    }

    pub fn loadFile(self: *Self, filename: []const u8) !void {
        self.text_buffer.loadFromFile(filename) catch |err| {
            try self.showMessage("Error loading file: {s}", .{@errorName(err)});
            return;
        };
    }

    pub fn run(self: *Self) !void {
        terminal.hideCursor();

        while (self.running) {
            // Refresh display
            self.display.refreshTerminalSize() catch {};

            // Render based on current mode
            switch (self.input_handler.getMode()) {
                .normal => {
                    self.display.render(self.text_buffer);
                    self.display.renderHelpBar();
                },
                .search => {
                    self.display.renderSearchResults(
                        self.text_buffer,
                        self.search_matches.items,
                        self.current_search_match,
                    );
                    self.display.renderPrompt("Search: ", self.input_handler.getSearchText());
                },
                .prompt => {
                    self.display.render(self.text_buffer);
                    self.display.renderPrompt("Command: ", self.input_handler.getPromptText());
                },
                .command => {
                    self.display.render(self.text_buffer);
                    self.display.renderPrompt("File: ", self.input_handler.getPromptText());
                },
            }

            // Read and process input
            const key = try terminal.Terminal.readKey();
            const action = self.input_handler.processKey(key);

            try self.handleAction(action);
        }

        terminal.showCursor();
        terminal.clearScreen();
        terminal.moveCursor(1, 1);
    }

    fn handleAction(self: *Self, action: input.EditorAction) !void {
        switch (action) {
            .quit => try self.handleQuit(),
            .save => try self.handleSave(),
            .save_as => try self.handleSaveAs(),
            .open => try self.handleOpen(),
            .find => try self.handleFind(),
            .find_next => try self.handleFindNext(),
            .find_previous => try self.handleFindPrevious(),
            .goto_line => try self.handleGotoLine(),
            .help => try self.handleHelp(),
            .cut_line => try self.handleCutLine(),
            .copy_line => try self.handleCopyLine(),
            .paste => try self.handlePaste(),
            .undo => try self.handleUndo(),
            .redo => try self.handleRedo(),

            // Movement
            .move_up => self.text_buffer.moveCursor(0, -1),
            .move_down => self.text_buffer.moveCursor(0, 1),
            .move_left => self.text_buffer.moveCursor(-1, 0),
            .move_right => self.text_buffer.moveCursor(1, 0),
            .move_word_left => try self.handleMoveWordLeft(),
            .move_word_right => try self.handleMoveWordRight(),
            .move_line_start => self.text_buffer.moveCursor(-@as(i32, @intCast(self.text_buffer.getCursor().x)), 0),
            .move_line_end => {
                const line_len = if (self.text_buffer.getLine(self.text_buffer.getCursor().y)) |line|
                    line.len
                else
                    0;
                self.text_buffer.moveCursor(@intCast(line_len - self.text_buffer.getCursor().x), 0);
            },
            .move_page_up => try self.handlePageUp(),
            .move_page_down => try self.handlePageDown(),
            .move_file_start => self.text_buffer.setCursor(0, 0),
            .move_file_end => {
                const last_line = self.text_buffer.getLineCount() - 1;
                const last_line_len = if (self.text_buffer.getLine(last_line)) |line|
                    line.len
                else
                    0;
                self.text_buffer.setCursor(last_line_len, last_line);
            },

            // Text editing
            .insert_char => |ch| try self.text_buffer.insertChar(ch),
            .insert_newline => try self.text_buffer.insertNewline(),
            .backspace => self.text_buffer.deleteChar(),
            .delete => self.text_buffer.deleteCharForward(),
            .cut_word_start => try self.handleCutWordStart(),
            .cut_word_end => try self.handleCutWordEnd(),

            // Search mode
            .search_input => |ch| {
                if (ch == 0) {
                    // Buffer updated, perform search
                    try self.performSearch();
                }
            },
            .search_submit => try self.handleSearchSubmit(),
            .search_cancel => {
                self.input_handler.setMode(.normal);
                self.search_matches.clearAndFree();
            },

            // Command/prompt mode
            .prompt_input => |ch| {
                if (ch == 0) {
                    // Buffer updated, nothing special to do
                }
            },
            .prompt_submit => try self.handlePromptSubmit(),
            .prompt_cancel => {
                self.input_handler.setMode(.normal);
            },

            .cancel => {
                self.input_handler.setMode(.normal);
                self.search_matches.clearAndFree();
            },

            .none => {},
        }
    }

    fn handleQuit(self: *Self) !void {
        if (self.text_buffer.isDirty()) {
            self.input_handler.setMode(.prompt);
            try self.showMessage("File has unsaved changes. Save anyway? (y/n)", .{});
        } else {
            self.running = false;
        }
    }

    fn handleSave(self: *Self) !void {
        if (self.text_buffer.getFilename() != null) {
            self.text_buffer.saveToFile() catch |err| {
                try self.showMessage("Error saving file: {s}", .{@errorName(err)});
                return;
            };
            try self.showMessage("File saved successfully", .{});
        } else {
            self.input_handler.setMode(.command);
        }
    }

    fn handleSaveAs(self: *Self) !void {
        self.input_handler.setMode(.command);
    }

    fn handleOpen(self: *Self) !void {
        self.input_handler.setMode(.command);
    }

    fn handleFind(self: *Self) !void {
        self.input_handler.setMode(.search);
        self.current_search_match = 0;
        self.search_matches.clearAndFree();
    }

    fn handleFindNext(self: *Self) !void {
        if (self.search_matches.items.len > 0) {
            self.current_search_match = (self.current_search_match + 1) % self.search_matches.items.len;
            const match = self.search_matches.items[self.current_search_match];
            self.text_buffer.setCursor(match.start, match.line);
        }
    }

    fn handleFindPrevious(self: *Self) !void {
        if (self.search_matches.items.len > 0) {
            if (self.current_search_match == 0) {
                self.current_search_match = self.search_matches.items.len - 1;
            } else {
                self.current_search_match -= 1;
            }
            const match = self.search_matches.items[self.current_search_match];
            self.text_buffer.setCursor(match.start, match.line);
        }
    }

    fn handleGotoLine(self: *Self) !void {
        self.input_handler.setMode(.prompt);
    }

    fn handleHelp(self: *Self) !void {
        // Display help screen (simplified)
        const help_text =
            \\Banano Editor Help
            \\
            \\Movement:
            \\  Arrow Keys     - Move cursor
            \\  Ctrl+A         - Beginning of line
            \\  Ctrl+E         - End of line
            \\  Ctrl+V         - Page down
            \\  Ctrl+Y         - Page up
            \\
            \\Editing:
            \\  Ctrl+K         - Cut line
            \\  Ctrl+U         - Paste
            \\  Ctrl+X         - Exit
            \\  Ctrl+O         - Save
            \\  Ctrl+W         - Save as
            \\
            \\Search:
            \\  Ctrl+F         - Find
            \\  Ctrl+N         - Find next
            \\  Ctrl+R         - Find previous
            \\
            \\Press any key to continue...
        ;

        self.display.clear();
        terminal.moveCursor(1, 1);
        std.debug.print("{s}\n", .{help_text});

        _ = try terminal.Terminal.readKey(); // Wait for any key
    }

    fn handleCutLine(self: *Self) !void {
        const cursor = self.text_buffer.getCursor();
        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                self.clipboard.clearAndFree();
                try self.clipboard.appendSlice(line);
                try self.clipboard.append('\n');
            }
            self.text_buffer.deleteLine(cursor.y);
            if (cursor.y >= self.text_buffer.getLineCount() and cursor.y > 0) {
                self.text_buffer.setCursor(0, cursor.y - 1);
            }
        }
    }

    fn handleCopyLine(self: *Self) !void {
        const cursor = self.text_buffer.getCursor();
        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                self.clipboard.clearAndFree();
                try self.clipboard.appendSlice(line);
                try self.clipboard.append('\n');
            }
        }
    }

    fn handlePaste(self: *Self) !void {
        for (self.clipboard.items) |ch| {
            if (ch == '\n') {
                try self.text_buffer.insertNewline();
            } else {
                try self.text_buffer.insertChar(ch);
            }
        }
    }

    fn handleUndo(self: *Self) !void {
        // Simplified undo - just clear dirty flag
        self.text_buffer.setDirty(false);
        try self.showMessage("Undo: Not fully implemented", .{});
    }

    fn handleRedo(self: *Self) !void {
        try self.showMessage("Redo: Not fully implemented", .{});
    }

    fn handleMoveWordLeft(self: *Self) !void {
        const cursor = self.text_buffer.getCursor();
        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                if (cursor.x > 0) {
                    // Find previous word boundary
                    var new_x = cursor.x;
                    while (new_x > 0 and std.ascii.isWhitespace(line[new_x - 1])) {
                        new_x -= 1;
                    }
                    while (new_x > 0 and !std.ascii.isWhitespace(line[new_x - 1])) {
                        new_x -= 1;
                    }
                    self.text_buffer.setCursor(new_x, cursor.y);
                } else if (cursor.y > 0) {
                    // Move to end of previous line
                    const prev_line_len = if (self.text_buffer.getLine(cursor.y - 1)) |prev_line|
                        prev_line.len
                    else
                        0;
                    self.text_buffer.setCursor(prev_line_len, cursor.y - 1);
                }
            }
        }
    }

    fn handleMoveWordRight(self: *Self) !void {
        const cursor = self.text_buffer.getCursor();
        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                if (cursor.x < line.len) {
                    // Find next word boundary
                    var new_x = cursor.x;
                    while (new_x < line.len and !std.ascii.isWhitespace(line[new_x])) {
                        new_x += 1;
                    }
                    while (new_x < line.len and std.ascii.isWhitespace(line[new_x])) {
                        new_x += 1;
                    }
                    self.text_buffer.setCursor(new_x, cursor.y);
                } else if (cursor.y + 1 < self.text_buffer.getLineCount()) {
                    // Move to beginning of next line
                    self.text_buffer.setCursor(0, cursor.y + 1);
                }
            }
        }
    }

    fn handlePageUp(self: *Self) !void {
        const page_size = self.display.terminal_size.rows - 3; // Subtract status bars
        self.text_buffer.moveCursor(0, -@as(i32, @intCast(page_size)));
    }

    fn handlePageDown(self: *Self) !void {
        const page_size = self.display.terminal_size.rows - 3; // Subtract status bars
        self.text_buffer.moveCursor(0, @intCast(page_size));
    }

    fn handleCutWordStart(self: *Self) !void {
        // Delete from cursor to beginning of word
        const cursor = self.text_buffer.getCursor();
        var target_x = cursor.x;

        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                while (target_x > 0 and !std.ascii.isWhitespace(line[target_x - 1])) {
                    target_x -= 1;
                }
            }
        }

        // Delete characters from cursor to target_x
        while (self.text_buffer.getCursor().x > target_x) {
            self.text_buffer.deleteChar();
        }
    }

    fn handleCutWordEnd(self: *Self) !void {
        // Delete from cursor to end of word
        const cursor = self.text_buffer.getCursor();
        var target_x = cursor.x;

        if (cursor.y < self.text_buffer.getLineCount()) {
            if (self.text_buffer.getLine(cursor.y)) |line| {
                while (target_x < line.len and !std.ascii.isWhitespace(line[target_x])) {
                    target_x += 1;
                }
            }
        }

        // Delete characters from cursor to target_x
        while (self.text_buffer.getCursor().x < target_x) {
            self.text_buffer.deleteCharForward();
        }
    }

    fn performSearch(self: *Self) !void {
        const search_text = self.input_handler.getSearchText();
        if (search_text.len == 0) {
            self.search_matches.clearAndFree();
            return;
        }

        self.search_matches.clearAndFree();
        const line_count = self.text_buffer.getLineCount();

        for (0..line_count) |line_idx| {
            if (self.text_buffer.getLine(line_idx)) |line| {
                var pos: usize = 0;
                while (true) {
                    const match_idx = std.mem.indexOf(u8, line[pos..], search_text);
                    if (match_idx) |idx| {
                        const start = pos + idx;
                        const end = start + search_text.len;

                        try self.search_matches.append(.{
                            .line = line_idx,
                            .start = start,
                            .end = end,
                        });

                        pos = end;
                    } else {
                        break;
                    }
                }
            }
        }

        if (self.search_matches.items.len > 0) {
            self.current_search_match = 0;
            const first_match = self.search_matches.items[0];
            self.text_buffer.setCursor(first_match.start, first_match.line);
        }
    }

    fn handleSearchSubmit(self: *Self) !void {
        if (self.search_matches.items.len > 0) {
            self.input_handler.setMode(.normal);
        } else {
            try self.showMessage("No matches found", .{});
        }
    }

    fn handlePromptSubmit(self: *Self) !void {
        const prompt_text = self.input_handler.getPromptText();

        // Handle different prompt types based on context
        if (self.text_buffer.isDirty() and std.mem.eql(u8, prompt_text, "y")) {
            self.running = false;
        } else if (std.mem.startsWith(u8, prompt_text, "Goto line ")) {
            const line_str = prompt_text["Goto line ".len..];
            const line_num = std.fmt.parseInt(usize, line_str, 10) catch 0;
            if (line_num > 0 and line_num <= self.text_buffer.getLineCount()) {
                self.text_buffer.setCursor(0, line_num - 1);
            }
        }

        self.input_handler.setMode(.normal);
    }

    fn showMessage(self: Self, comptime format: []const u8, args: anytype) !void {
        var message_buf: [256]u8 = undefined;
        const message = try std.fmt.bufPrint(&message_buf, format, args);
        self.display.renderMessage(message);

        // Brief pause to show message
        std.time.sleep(500 * std.time.ns_per_ms);
    }
};