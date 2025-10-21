# Banano Editor

Banano is a terminal text editor with bright banana‑themed UI accents, built in Zig for a fast startup and small footprint. It targets Zig 0.15 and focuses on keyboard-driven editing, search, and file management without pulling in external dependencies.

## Features

- **Cross-platform terminal UI** with raw-mode handling for responsive key input.
- **Line-based editing** including cut/copy/paste of lines and word trimming helpers.
- **Incremental search** with highlighted matches and next/previous navigation.
- **Command prompt** for quick save-as, open, and goto-line operations.
- **Status and message bars** that react to buffer state, cursor position, and search results.
- **Self-contained build** powered by `zig build`—no third-party libraries required.

## Requirements

- Zig 0.15.1 or newer (the project relies on the latest stdlib APIs).
- A terminal that supports ANSI escape codes (Windows Terminal, macOS Terminal, most Linux TTYs).

## Getting Started

```bash
# Clone the repository
git clone https://github.com/<your-account>/banano.git
cd banano

# Build the editor
zig build

# Run the editor (optionally pass a file path)
zig build run -- path/to/file.txt

# Execute the test suite
zig build test
```

On Windows, ensure no running instance of `zig-out/bin/banano.exe` blocks subsequent builds—close the editor or end the process before rebuilding.

## Keyboard Shortcuts

| Shortcut           | Action                         |
| ------------------ | ------------------------------ |
| `Ctrl+Q` / `Ctrl+X`| Quit (prompts if buffer dirty) |
| `Ctrl+S` / `Ctrl+O`| Save current file              |
| `Ctrl+W`           | Save As (prompts for filename) |
| `Ctrl+G`           | Goto line (via prompt)         |
| `Ctrl+F` / `Ctrl+N`| Find / Find next match         |
| `Ctrl+R`           | Find previous match            |
| `Ctrl+K` / `Ctrl+Y`| Cut current line / Copy line   |
| `Ctrl+P`           | Paste clipboard content        |
| `Ctrl+U` / `Ctrl+Z`| Undo                           |
| Arrow keys         | Move cursor                    |
| `Ctrl+A` / `Ctrl+E`| Move to start / end of line    |
| `Ctrl+V`           | Page down                      |
| `Ctrl+C` / `Esc`   | Cancel prompt or search        |
| `Ctrl+M` / `Enter` | Insert newline or accept prompt|

During searches, type to update the query. `Ctrl+S`/`Ctrl+M` accepts the current match; `Ctrl+C` cancels and returns to normal mode.

## Project Layout

```
build.zig         # Build script configuring executable and tests
src/
  main.zig        # Entry point wiring allocator, args, and editor loop
  editor.zig      # Core editor state machine and action handlers
  buffer.zig      # Text buffer, lines, search results, persistence helpers
  display.zig     # Rendering of text, status bar, and prompts
  input.zig       # Keyboard processing and mode transitions
  terminal.zig    # Terminal abstraction for raw mode and ANSI utilities
```

## Development

- Format and lint: Zig currently formats on save via your editor; there is no dedicated `zig fmt` step.
- Testing: `zig build test` runs the bundled unit tests and fuzz example from `main.zig`.
- Debugging: add `std.debug.print` statements or run via `zig build run -Drelease-safe=false` for better insight.

## Contributing

Issues and pull requests are welcome. Please:

1. Build and test locally (`zig build`, `zig build test`).
2. Describe the motivation for the change and any behavioural differences.
3. Keep additions consistent with the existing code style (mostly standard Zig formatting).

## License

This project currently has no explicit license. If you intend to use it in another project, please open an issue so the maintainers can clarify licensing terms.
