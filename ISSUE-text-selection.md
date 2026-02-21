# Issue: Text selection implementation (ready for review)

**Title:** Text selection implementation — ready for review/PR

**Body:**

Hi @magiblot 👋

Love this project — a terminal emulator inside Turbo Vision is a brilliant idea.

I've implemented the **Text selection** feature from the README checklist and would like to contribute it back. Before opening a PR, wanted to check if you're open to this and if the approach looks reasonable.

## What it does

- Click-drag with left mouse button to select text (highlighted with reversed colors)
- Copy selected text to system clipboard via menu ("Copy Selection")
- Selection clears on any keypress
- Mouse-aware apps (vim, htop, etc.) still receive mouse events normally — selection only activates when the terminal app hasn't captured the mouse

## Implementation approach

- Selection state lives in `TerminalView` (main thread only, no threading changes)
- Exposed `mouseEnabled` from `VTermEmulator` via `TerminalState` so the view knows when to intercept mouse vs forward to emulator
- Highlight rendering uses `reverseAttribute()` on cells from `TerminalSurface`, written via `writeLine` — deterministic, no owner buffer mutation
- Copy uses platform-native clipboard tools (`pbcopy`/`xclip`/`xsel` via pipe)
- Added `cmCopySelection` to `TVTermConstants` following the existing command pattern
- Wide character boundaries handled (no split glyphs)
- ~260 lines across 8 files, no new dependencies, no CMake changes

## Tested on

- macOS (Apple Clang) — full manual testing
- Linux GCC (Docker ubuntu:22.04) — build + interactive run

## What it doesn't do (follow-up work)

- Bracketed paste (the other half of #5)
- Shift+drag when terminal app has mouse captured
- Windows clipboard (`SetClipboardData` stubbed as TODO)
- Double-click word selection

The branch is at https://github.com/j-greig/tvterm/tree/feature/text-selection if you'd like to take a look. Happy to open a PR, adjust the approach, or discuss anything.

Partially addresses #5.
