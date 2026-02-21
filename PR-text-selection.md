# TerminalView: add text selection with copy-to-clipboard

Partially addresses https://github.com/magiblot/tvterm/issues/5 (Copy/Paste support).

## Summary

Implements the **Text selection** item from the README feature checklist. Users can now click-drag to select text in terminal views and copy it to the system clipboard via the menu.

This covers the **copy** half of #5. Clipboard copy uses platform-native tools (`pbcopy`/`xclip`/`xsel`) rather than OSC 52, which avoids Turbo Vision screen management conflicts. Bracketed paste (the other half of #5) is not included and should be a separate PR.

## What changed and why

**Problem**: tvterm had no way to select or copy text from the terminal output.

**Solution**: Added mouse-driven text selection with highlighted rendering and clipboard copy, following the existing architecture patterns (event routing via `TVTermConstants`, rendering via `writeLine`, state access via `lockState`).

### Changes by file (8 files, +269 -11)

| File | Change |
|------|--------|
| `include/tvterm/termemu.h` | Add `mouseEnabled` field to `TerminalState` |
| `include/tvterm/termview.h` | Add `Selection` struct, selection methods, `copySelection()` |
| `include/tvterm/consts.h` | Add `cmCopySelection` to `TVTermConstants`, update `focusedCmds()` span |
| `source/tvterm-core/vtermemu.cc` | Expose `localState.mouseEnabled` in `updateState()` |
| `source/tvterm-core/termview.cc` | Selection mouse handling, highlight rendering via `reverseAttribute()` + `writeLine`, copy with `lockState` + platform clipboard |
| `source/tvterm/cmds.h` | Add `cmCopySelection` command ID |
| `source/tvterm/wnd.cc` | Wire `cmCopySelection` into `appConsts` initializer |
| `source/tvterm/app.cc` | Add "Copy Selection" menu item |

## Design decisions

- **Selection state lives in `TerminalView`** (main thread only) — no threading changes needed.
- **`mouseEnabled` exposed via `TerminalState`** so the view knows when to intercept mouse for selection vs forwarding to the emulator (e.g. vim, htop).
- **Left-button drag only** when terminal app has not captured mouse; wheel/middle/right always forwarded.
- **Deterministic highlight rendering**: copies cells from `TerminalSurface`, applies `::reverseAttribute()`, writes via `writeLine`. Never mutates the owner buffer in-place.
- **Full redraw forced** (`ownerBufferChanged = true`) when selection changes to prevent stale highlight artifacts from damage-reuse optimisation.
- **Copy command routed through `TerminalView::handleEvent`** via `consts.cmCopySelection`, avoiding private member access issues (`view` is private in `BasicTerminalWindow`).
- **Menu-only trigger** for MVP — no keybinding to avoid Ctrl+C/SIGINT conflict.
- **Wide character handling**: selection boundaries adjusted to avoid splitting double-width glyphs; trail cells skipped during text extraction.
- **Platform clipboard**: pipes to `pbcopy`/`xclip`/`xsel` on Unix. Windows `SetClipboardData` is stubbed as TODO.
- **Defensive bounds checking**: all surface access clamped against `surface.size` and `view.size`, per-cell bounds check in highlight loop, `count <= 0` guard after wide-char adjustments. Audited for resize+selection safety — no UB found.

## Platforms tested

- [x] macOS (Apple Clang) — manual testing, all core tests pass
- [x] Linux GCC (Docker ubuntu:22.04) — clean build, no new warnings
- [ ] Linux Clang
- [ ] Windows MSVC

## How to test

1. Build: `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build`
2. Run `./build/tvterm`, open a shell, produce some text output
3. Click-drag with left mouse button → text highlights with inverted colors
4. Release mouse → highlight persists
5. Press any key → highlight clears, key is sent to terminal
6. Open menu (Ctrl+B) → "Copy Selection" item → copies selected text to clipboard
7. Verify with `pbpaste` (macOS) or `xclip -o` (Linux)
8. Run a mouse-aware app (`vim`, `htop`) → verify mouse still works for the app
9. Test wide characters: `echo 你好世界` → select across → no split glyphs
10. Resize window during/after selection → no crash or artifacts

## Follow-up work (not in this PR)

- Bracketed paste support (remainder of #5)
- OSC 52 as alternative clipboard mechanism
- Shift+drag selection when terminal app has mouse captured
- Keybinding for copy (requires input-grab mode consideration)
- Windows clipboard implementation
- Double-click word selection
- Trailing whitespace trimming on copy
- Integration with scrollback (when implemented)

## Checklist

- [x] Builds warning-clean under `-Wall` (no new warnings)
- [x] No dependency or submodule changes
- [x] No CMake changes
- [x] Follows existing code style (4-space indent, Allman braces, camelCase/PascalCase)
- [x] Component-prefixed commit subject
- [ ] Screenshots / terminal captures attached
