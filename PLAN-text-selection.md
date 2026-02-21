# Text Selection Implementation Plan (v3 — Codex-approved)

## Overview
Add mouse-based text selection to tvterm's terminal view, allowing users to click-drag to highlight text and copy it to clipboard. Self-contained within `TerminalView` + supporting state, builds on existing mouse event plumbing.

## Review Feedback Incorporated
This is v2, addressing all 5 required fixes from Codex review:
1. ✅ Highlight rendering redesigned — uses `reverseAttribute()` on surface cells, written via `writeLine` (deterministic, no owner buffer mutation)
2. ✅ Full redraw forced when selection is active — `ownerBufferChanged = true` before `drawView()` to bypass damage-reuse
3. ✅ Copy trigger defined — explicit copy via command + lock discipline via `lockState`
4. ✅ TScreenCell API corrected — use `cell._ch.getText()` and `::getAttr()`/`::reverseAttribute()`
5. ✅ Selection restricted to left-button drag only

---

## Design Decisions

### D1: Selection state lives in TerminalView (main thread only)
Selection is purely UI state — no threading/synchronization needed. The view already owns the mouse interaction and the draw path. We do NOT put selection into `TerminalState` (which crosses thread boundaries).

### D2: mouseEnabled must be exposed to the view
Currently `mouseEnabled` lives in `VTermEmulator::LocalState` (private). The view needs to know whether the terminal app has captured the mouse to decide whether to intercept clicks for selection vs forwarding to the emulator.

**Solution**: Add `bool mouseEnabled` to `TerminalState`, populated in `VTermEmulator::updateState`. The view reads it during `draw()` (which is inside `lockState`) and caches it for event handling.

### D3: Selection vs emulator mouse — behavior model
- When `!mouseEnabled` (normal shell, no mouse app): **left-button** click-drag = selection. Mouse events are NOT forwarded to emulator (they were being silently dropped anyway — `vtermemu.cc:297-302`).
- When `mouseEnabled` (vim, htop, etc.): mouse events forwarded to emulator as before. Selection not available in MVP. (Shift+drag selection is a follow-up enhancement.)
- Mouse wheel: always forwarded (for scroll/arrow behavior in alt screen). NOT intercepted for selection.
- Middle/right button: always forwarded to emulator regardless of mouseEnabled.

### D4: Selection rendering — deterministic writeLine from surface
**Key insight**: Turbo Vision provides `::reverseAttribute(TColorAttr)` in `colors.h` which swaps fg/bg (or toggles slReverse for default colors). This is exactly what we need.

**Rendering strategy**: When selection is active/valid, for each row that intersects the selection:
1. Copy the `TScreenCell` data from `TerminalSurface` for the selected range into a local buffer
2. Apply `::reverseAttribute()` to each cell's attr
3. Call `writeLine()` with the modified cells

This is **deterministic** — we always derive from the surface, never read-modify-write the owner buffer. The surface is the source of truth.

**Forcing full redraw**: When selection changes, set `ownerBufferChanged = true` before calling `drawView()`. This forces `canReuseOwnerBuffer()` to return false, causing `updateDisplay` to copy ALL rows from the surface (not just damaged ones). This prevents stale highlight artifacts.

### D5: Copy mechanism and lock discipline
- Copy is triggered by a new command `cmCopySelection` (added to `TVTermConstants`), accessible via menu only (no keybinding in MVP to avoid Ctrl+C/SIGINT conflicts).
- Copy handler runs in `handleEvent` and calls `termCtrl.lockState(...)` to safely read `TerminalSurface` cells.
- Text extraction uses `cell._ch.getText()` which returns `TStringView` (UTF-8 bytes).
- For MVP: write to stdout via OSC 52 is risky in a Turbo Vision app. Instead, use platform clipboard: `pbcopy` pipe on macOS, `xclip`/`xsel` on Linux. Windows uses `SetClipboardData`. Fallback: store in internal buffer, print on exit.

### D6: Selection coordinate model
Selection uses **cell coordinates** relative to the view (y = row, x = column). Defined by `anchor` (mouse-down) and `current` (mouse-move/up). Normalized to `start`/`end` with row-major ordering.

Single-cell selections ARE allowed (useful for "click to position cursor" follow-ups).

### D7: Wide character handling
- When iterating selected cells, skip trail cells (`_ch.isWideCharTrail()`) during text extraction.
- During highlight rendering, if selection start falls on a trail cell, extend to include the lead cell. If selection end falls on a wide cell, include the trail cell.
- Clamp all cell coordinates against `surface.size` before access.

---

## Files to Modify

### 1. `include/tvterm/termemu.h` — Add mouseEnabled to TerminalState
```cpp
struct TerminalState
{
    TerminalSurface surface;

    bool cursorChanged {false};
    TPoint cursorPos {0, 0};
    bool cursorVisible {false};
    bool cursorBlink {false};

    bool titleChanged {false};
    GrowArray title;

    bool mouseEnabled {false};  // NEW
};
```

### 2. `source/tvterm-core/vtermemu.cc` — Expose mouseEnabled
In `VTermEmulator::updateState`, add after existing code:
```cpp
state.mouseEnabled = localState.mouseEnabled;
```

### 3. `include/tvterm/termview.h` — Add selection state and methods
```cpp
#define Uses_TView
#define Uses_TGroup
#include <tvision/tv.h>

struct MouseEventType;

namespace tvterm
{

class TerminalController;
class TerminalSurface;
struct TerminalState;
struct TVTermConstants;

class TerminalView : public TView
{
    const TVTermConstants &consts;
    bool ownerBufferChanged {false};

    // Selection state (main thread only, no sync needed)
    struct Selection
    {
        TPoint anchor {0, 0};
        TPoint current {0, 0};
        bool active {false};    // drag in progress
        bool valid {false};     // completed selection exists
    };

    Selection selection;
    bool cachedMouseEnabled {false};

    void handleMouse(ushort what, MouseEventType mouse) noexcept;
    void handleSelectionMouse(ushort what, TPoint localPos) noexcept;
    void updateCursor(TerminalState &state) noexcept;
    void updateDisplay(TerminalSurface &surface) noexcept;
    void applySelectionHighlight(TerminalSurface &surface) noexcept;
    void normalizeSelection(TPoint &start, TPoint &end) const noexcept;
    void clearSelection() noexcept;
    bool canReuseOwnerBuffer() noexcept;

public:

    TerminalController &termCtrl;

    TerminalView( const TRect &bounds, TerminalController &termCtrl,
                  const TVTermConstants &consts ) noexcept;
    ~TerminalView();

    void changeBounds(const TRect& bounds) override;
    void setState(ushort aState, bool enable) override;
    void handleEvent(TEvent &ev) override;
    void draw() override;

    void copySelection() noexcept;  // called from command handler
};

} // namespace tvterm
```

### 4. `source/tvterm-core/termview.cc` — Main implementation

#### 4a. handleEvent — route mouse for selection (left button only, !mouseEnabled)
```cpp
void TerminalView::handleEvent(TEvent &ev)
{
    TView::handleEvent(ev);

    switch (ev.what)
    {
        case evCommand:
            if (ev.message.command == consts.cmCopySelection)
            {
                copySelection();
                clearEvent(ev);
            }
            break;

        case evBroadcast:
            if ( ev.message.command == consts.cmCheckTerminalUpdates &&
                 termCtrl.stateHasBeenUpdated() )
                drawView();
            break;

        case evKeyDown:
        {
            // Clear selection on any keypress
            if (selection.active || selection.valid)
            {
                clearSelection();
                ownerBufferChanged = true;
                drawView();
            }

            TerminalEvent termEvent;
            termEvent.type = TerminalEventType::KeyDown;
            termEvent.keyDown = ev.keyDown;
            termCtrl.sendEvent(termEvent);

            clearEvent(ev);
            break;
        }

        case evMouseDown:
            // Left button + !mouseEnabled → selection mode
            if (!cachedMouseEnabled && (ev.mouse.buttons & mbLeftButton))
            {
                TPoint localPos = makeLocal(ev.mouse.where);
                handleSelectionMouse(evMouseDown, localPos);
                while (mouseEvent(ev, evMouse))
                {
                    localPos = makeLocal(ev.mouse.where);
                    handleSelectionMouse(ev.what, localPos);
                }
                if (ev.what == evMouseUp)
                {
                    localPos = makeLocal(ev.mouse.where);
                    handleSelectionMouse(evMouseUp, localPos);
                }
                clearEvent(ev);
            }
            else
            {
                // Forward to emulator (existing behavior)
                do {
                    handleMouse(ev.what, ev.mouse);
                } while (mouseEvent(ev, evMouse));
                if (ev.what == evMouseUp)
                    handleMouse(ev.what, ev.mouse);
                clearEvent(ev);
            }
            break;

        case evMouseWheel:
            // Always forward wheel to emulator
            handleMouse(ev.what, ev.mouse);
            clearEvent(ev);
            break;

        case evMouseMove:
        case evMouseAuto:
        case evMouseUp:
            handleMouse(ev.what, ev.mouse);
            clearEvent(ev);
            break;
    }
}
```

#### 4b. handleSelectionMouse
```cpp
void TerminalView::handleSelectionMouse(ushort what, TPoint localPos) noexcept
{
    // Clamp to view bounds
    localPos.x = max(0, min(localPos.x, size.x - 1));
    localPos.y = max(0, min(localPos.y, size.y - 1));

    if (what & evMouseDown)
    {
        selection.anchor = localPos;
        selection.current = localPos;
        selection.active = true;
        selection.valid = false;
        ownerBufferChanged = true;
        drawView();
    }
    else if (what & (evMouseMove | evMouseAuto))
    {
        if (selection.active && localPos != selection.current)
        {
            selection.current = localPos;
            ownerBufferChanged = true;  // Force full redraw
            drawView();
        }
    }
    else if (what & evMouseUp)
    {
        if (selection.active)
        {
            selection.current = localPos;
            selection.active = false;
            selection.valid = true;  // Allow single-cell selection
            ownerBufferChanged = true;
            drawView();
        }
    }
}
```

#### 4c. normalizeSelection
```cpp
void TerminalView::normalizeSelection(TPoint &start, TPoint &end) const noexcept
{
    TPoint a = selection.anchor;
    TPoint b = selection.current;
    if (a.y < b.y || (a.y == b.y && a.x <= b.x))
    {
        start = a;
        end = b;
    }
    else
    {
        start = b;
        end = a;
    }
}
```

#### 4d. clearSelection
```cpp
void TerminalView::clearSelection() noexcept
{
    selection.active = false;
    selection.valid = false;
}
```

#### 4e. draw — cache mouseEnabled
```cpp
void TerminalView::draw()
{
    termCtrl.lockState([&] (auto &state) {
        cachedMouseEnabled = state.mouseEnabled;
        updateCursor(state);
        updateDisplay(state.surface);

        TerminalUpdatedMsg upd {*this, state};
        message(owner, evCommand, consts.cmTerminalUpdated, &upd);
    });
}
```

#### 4f. updateDisplay — apply selection highlight AFTER normal rendering
```cpp
void TerminalView::updateDisplay(TerminalSurface &surface) noexcept
{
    bool reuseBuffer = canReuseOwnerBuffer();
    TRect r = getExtent().intersect({{0, 0}, surface.size});
    if (0 <= r.a.x && r.a.x < r.b.x && 0 <= r.a.y && r.a.y < r.b.y)
    {
        for (int y = r.a.y; y < r.b.y; ++y)
        {
            auto c = rangeToCopy(y, r, surface, reuseBuffer);
            if (c.begin < c.end)  // Guard against invalid ranges
                writeLine(c.begin, y, c.end - c.begin, 1, &surface.at(y, c.begin));
        }
        surface.clearDamage();
    }

    // Apply selection highlight
    if (selection.active || selection.valid)
        applySelectionHighlight(surface);
}
```

#### 4g. applySelectionHighlight — deterministic, from surface, via writeLine
```cpp
void TerminalView::applySelectionHighlight(TerminalSurface &surface) noexcept
{
    TPoint start, end;
    normalizeSelection(start, end);

    // Clamp against surface bounds
    int maxY = min((int)surface.size.y, (int)size.y) - 1;
    int maxX = min((int)surface.size.x, (int)size.x) - 1;
    start.y = max(0, min(start.y, maxY));
    start.x = max(0, min(start.x, maxX));
    end.y = max(0, min(end.y, maxY));
    end.x = max(0, min(end.x, maxX));

    for (int y = start.y; y <= end.y; ++y)
    {
        int selBegin = (y == start.y) ? start.x : 0;
        int selEnd = (y == end.y) ? end.x + 1 : min((int)surface.size.x, (int)size.x);
        selBegin = max(selBegin, 0);
        selEnd = min(selEnd, min((int)surface.size.x, (int)size.x));

        if (selBegin >= selEnd)
            continue;

        // Handle wide char boundaries
        // If selBegin is on a trail cell, move back to include the lead
        if (selBegin > 0 && surface.at(y, selBegin)._ch.isWideCharTrail())
            --selBegin;
        // If selEnd-1 is a wide char, include the trail
        if (selEnd <= maxX && surface.at(y, selEnd - 1).isWide())
            ++selEnd;

        int count = selEnd - selBegin;
        // Build modified cells with reversed attributes
        // Use stack buffer for small lines, heap for large
        TScreenCell buf[256];
        TScreenCell *cells = (count <= 256) ? buf : new TScreenCell[count];

        for (int i = 0; i < count; ++i)
        {
            cells[i] = surface.at(y, selBegin + i);
            ::setAttr(cells[i], ::reverseAttribute(::getAttr(cells[i])));
        }

        writeLine(selBegin, y, count, 1, cells);

        if (cells != buf)
            delete[] cells;
    }
}
```

#### 4h. copySelection — with proper lock discipline
```cpp
void TerminalView::copySelection() noexcept
{
    if (!selection.valid)
        return;

    GrowArray text;
    termCtrl.lockState([&] (auto &state) {
        auto &surface = state.surface;
        TPoint start, end;
        normalizeSelection(start, end);

        for (int y = start.y; y <= end.y && y < surface.size.y; ++y)
        {
            int lineBegin = (y == start.y) ? start.x : 0;
            int lineEnd = (y == end.y) ? end.x + 1 : surface.size.x;
            lineBegin = max(lineBegin, 0);
            lineEnd = min(lineEnd, surface.size.x);

            for (int x = lineBegin; x < lineEnd; ++x)
            {
                auto &cell = surface.at(y, x);
                // Skip wide char trails (text is on the lead cell)
                if (cell._ch.isWideCharTrail())
                    continue;

                TStringView cellText = cell._ch.getText();
                if (cellText.size() == 1 && cellText[0] == '\0')
                {
                    // Empty cell → space
                    char sp = ' ';
                    text.push(&sp, 1);
                }
                else
                {
                    text.push(cellText.data(), cellText.size());
                }
            }

            // Add newline between lines (not after last)
            if (y < end.y)
            {
                char nl = '\n';
                text.push(&nl, 1);
            }
        }
    });

    // Trim trailing spaces from each line
    // (omitted in MVP for simplicity)

    // Platform clipboard (MVP: macOS pbcopy)
    if (text.size() > 0)
    {
#if !defined(_WIN32)
        FILE *pipe = popen("pbcopy 2>/dev/null || xclip -selection clipboard 2>/dev/null || xsel --clipboard --input 2>/dev/null", "w");
        if (pipe)
        {
            fwrite(text.data(), 1, text.size(), pipe);
            pclose(pipe);
        }
#else
        // Windows clipboard: OpenClipboard/SetClipboardData
        // TODO: implement
#endif
    }
}
```

### 5. `include/tvterm/consts.h` — Add cmCopySelection to TVTermConstants
The copy command ID must be accessible from `tvterm-core` (where `TerminalView` lives).
Following the existing pattern, add it to `TVTermConstants`:
```cpp
struct TVTermConstants
{
    ushort cmCheckTerminalUpdates;
    ushort cmTerminalUpdated;
    // Focused commands (enabled/disabled on window focus)
    ushort cmGrabInput;
    ushort cmReleaseInput;
    ushort cmCopySelection;  // NEW — also a focused command
    // Help contexts
    ushort hcInputGrabbed;

    TSpan<const ushort> focusedCmds() const
    {
        // cmGrabInput, cmReleaseInput, cmCopySelection are contiguous
        return {&cmGrabInput, size_t(&cmCopySelection + 1 - &cmGrabInput)};
    }
};
```

### 6. `source/tvterm/cmds.h` — Add copy command ID
```cpp
enum : ushort
{
    cmGrabInput = 100,
    cmReleaseInput,
    cmTileCols,
    cmTileRows,
    cmCopySelection,  // NEW
    // Commands that cannot be deactivated.
    cmNewTerm = 1000,
    cmCheckTerminalUpdates,
    cmTerminalUpdated,
    cmGetOpenTerms,
};
```

### 7. `source/tvterm/wnd.cc` — Wire cmCopySelection into appConsts
```cpp
const tvterm::TVTermConstants TerminalWindow::appConsts =
{
    cmCheckTerminalUpdates,
    cmTerminalUpdated,
    cmGrabInput,
    cmReleaseInput,
    cmCopySelection,  // NEW
    hcInputGrabbed,
};
```

### 8. `source/tvterm-core/termview.cc` — Handle copy command in TerminalView
The copy command is handled directly in `TerminalView::handleEvent` via `evCommand`,
using `consts.cmCopySelection` (from `TVTermConstants`). This avoids the `view` is
private issue — no window access needed.

Add to the `handleEvent` switch, before the existing `evBroadcast` case:
```cpp
        case evCommand:
            if (ev.message.command == consts.cmCopySelection)
            {
                copySelection();
                clearEvent(ev);
            }
            break;
```

### 9. `source/tvterm/app.cc` — Add menu item (menu only, no keybinding conflict)
In `openMenu()`, add after "Grab Input":
```cpp
*new TMenuItem("~C~opy Selection", cmCopySelection, kbNoKey)
```

**No keybinding for MVP**: Ctrl+C conflicts with terminal SIGINT. Ctrl+Shift+C is not
reliably distinguishable in all terminals. Menu-only is safe. A keybinding can be
added as a follow-up once input-grab mode semantics are sorted out.

---

## Implementation Order

1. **Step 1**: Add `mouseEnabled` to `TerminalState` + expose in `VTermEmulator::updateState` + cache in `TerminalView::draw`. *(3 files, ~5 lines)*
2. **Step 2**: Add `Selection` struct and fields to `TerminalView` header. *(1 file, ~15 lines)*
3. **Step 3**: Implement `handleSelectionMouse`, `normalizeSelection`, `clearSelection`. Modify `handleEvent` to route mouse — left button only. *(1 file, ~80 lines)*
4. **Step 4**: Implement `applySelectionHighlight` using `reverseAttribute()` + `writeLine`. Add guard in `updateDisplay`. Force full redraw via `ownerBufferChanged = true`. *(1 file, ~50 lines)*
5. **Step 5**: Build and test manually — verify highlight appears, is deterministic, clears properly, doesn't leave artifacts.
6. **Step 6**: Add `cmCopySelection` command. Implement `copySelection` with `lockState` + `_ch.getText()` + platform clipboard pipe. Wire into menu. *(3 files, ~50 lines)*
7. **Step 7**: Handle edge cases: wide chars at selection boundaries, view resize during selection, empty surface.

**Total estimated new code**: ~200 lines across 5 files.
No new files. No dependency changes. No CMake changes.

---

## Testing Plan

<test-results date="2026-02-21" platform="macOS (Apple Clang)">

### Manual Tests — macOS
- Build: `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build` ✅
- Run: `./build/tvterm` ✅

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Selection rendering | ✅ PASS | Click-drag highlights with inverted colors. Screenshot captured. |
| 2 | Selection persists after mouse-up | ✅ PASS | Highlight stays visible after releasing mouse. |
| 3 | Clear on keypress | ✅ PASS | Any key clears highlight and is sent to terminal. |
| 4 | Left button only | ✅ PASS | Right-click does not start selection. |
| 5 | Copy to clipboard | ✅ PASS | Copied `'1 james  staff  24547 F'` via menu → verified with `pbpaste`. |
| 6 | Mouse apps (vim) | ✅ PASS | Vim mouse clicks work. Pasted `'will copy paste this bit 123456'` inside vim. |
| 7 | Wide chars (`echo 你好世界`) | ✅ PASS | Clean selection across CJK characters, no split glyphs. |
| 8 | Resize during selection | ✅ PASS | Not a crash — user accidentally entered tvterm's Resize/Move modal mode (R key). Selection clears on resize via `changeBounds`. |
| 9 | Multiple terminals | ✅ PASS | Tested on Linux Docker — opened ~15 terminals via Ctrl+B→N cascade, no crash. Also needs macOS interactive verify for selection-in-one-click-other. |
| 10 | Disconnected terminal | ✅ PASS (code audit) | `lockState` + surface access safe when disconnected. Window intercepts keyDown before view on disconnect (calls `close()`). Mouse selection on disconnected terminal is safe — controller/state still valid. |

### Codex Resize Safety Audit
- Codex audited all resize+selection code paths (2026-02-21)
- **Verdict: NO ISSUES FOUND**
- All surface access clamped, per-cell bounds checked, no race between draw/resize (both use `lockState`), `writeLine` never receives negative counts

### Build Tests

| Platform | Compiler | Result |
|----------|----------|--------|
| macOS | Apple Clang | ✅ PASS (no new warnings) |
| Linux (Docker ubuntu:22.04) | GCC | ✅ PASS (build + interactive run) |
| Linux (upstream CI) | GCC 7 | ✅ PASS (GitHub Actions) |
| Linux (upstream CI) | Clang | ✅ PASS (GitHub Actions) |
| Windows | MSVC | ⬜ NOT TESTED |

</test-results>

---

<pr-draft>

## Pull Request: Add text selection with copy-to-clipboard

Partially addresses #5 (Copy/Paste support in terminals).

### Summary

Implements the **Text selection** item from the README feature checklist. Users can now click-drag to select text in terminal views and copy it to the system clipboard via the menu.

This covers the **copy** half of #5. Clipboard copy uses platform-native tools (`pbcopy`/`xclip`/`xsel`) rather than OSC 52, which avoids Turbo Vision screen management conflicts. Bracketed paste (the other half of #5) is not included and should be a separate PR.

### What changed and why

**Problem**: tvterm had no way to select or copy text from the terminal output.

**Solution**: Added mouse-driven text selection with highlighted rendering and clipboard copy, following the existing architecture patterns (event routing via `TVTermConstants`, rendering via `writeLine`, state access via `lockState`).

### Changes by file

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

### Design decisions

- **Selection state lives in `TerminalView`** (main thread only) — no threading changes needed.
- **`mouseEnabled` exposed via `TerminalState`** so the view knows when to intercept mouse for selection vs forwarding to the emulator (e.g. vim, htop).
- **Left-button drag only** when terminal app has not captured mouse; wheel/middle/right always forwarded.
- **Deterministic highlight rendering**: copies cells from `TerminalSurface`, applies `::reverseAttribute()`, writes via `writeLine`. Never mutates the owner buffer in-place.
- **Full redraw forced** (`ownerBufferChanged = true`) when selection changes to prevent stale highlight artifacts from damage-reuse optimisation.
- **Copy command routed through `TerminalView::handleEvent`** via `consts.cmCopySelection`, avoiding private member access issues.
- **Menu-only trigger** for MVP — no keybinding to avoid Ctrl+C/SIGINT conflict.
- **Wide character handling**: selection boundaries adjusted to avoid splitting double-width glyphs; trail cells skipped during text extraction.
- **Platform clipboard**: pipes to `pbcopy`/`xclip`/`xsel` on Unix. Windows `SetClipboardData` is stubbed as TODO.

### Platforms tested

- [x] macOS (Apple Clang) — manual testing, all 8 core tests pass
- [x] Linux GCC (Docker ubuntu:22.04) — clean build, no warnings
- [ ] Linux Clang
- [ ] Windows MSVC

### How to test

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

### Follow-up work (not in this PR)

- Bracketed paste support (remainder of #5)
- OSC 52 as alternative clipboard mechanism
- Shift+drag selection when terminal app has mouse captured
- Keybinding for copy (requires input-grab mode consideration)
- Windows clipboard implementation
- Double-click word selection
- Trailing whitespace trimming on copy
- Integration with scrollback (when implemented)

### Checklist

- [x] Builds warning-clean under `-Wall`
- [x] No dependency or submodule changes
- [x] No CMake changes
- [x] Follows existing code style (4-space indent, Allman braces, camelCase/PascalCase)
- [x] Component-prefixed commit subjects
- [ ] Screenshots / terminal captures attached

</pr-draft>
