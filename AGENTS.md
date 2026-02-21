# Repository Guidelines

## Project Structure & Module Organization
`tvterm` is a CMake-based C++ project with two primary targets:

- `source/tvterm-core/`: core terminal library implementation (`tvterm-core` target).
- `source/tvterm/`: application entry/UI code (`tvterm` executable target).
- `include/tvterm/`: public headers for core types and interfaces.
- `include/pch.h`: precompiled header used when `TVTERM_OPTIMIZE_BUILD=ON`.
- `deps/`: dependency wiring and submodules (`tvision`, `vterm`).
- `.github/workflows/cmake.yml`: CI build matrix (Linux GCC and Clang).

## Architecture Deep Dive

### Two-Target Build
- `tvterm-core` contains terminal orchestration, PTY abstraction, emulator glue, and Turbo Vision-backed terminal rendering primitives.
- `tvterm` is the app/UI shell that wires menus, desktop/window management, and creates terminal windows using `tvterm-core`.
- Most behavior changes should be made in `tvterm-core`; `tvterm` is typically where commands, window/menu plumbing, and app-level UX hooks are added.

### Key Abstractions
- `TerminalEmulator` (`include/tvterm/termemu.h`): abstract backend interface (`handleEvent`, `updateState`) designed so emulators are swappable.
- `VTermEmulator` (`source/tvterm-core/vtermemu.cc`): current libvterm-backed implementation.
- `Writer`: output abstraction used by emulator code to send bytes back to the PTY client.
- `TerminalSurface`: `TDrawSurface` wrapper with row-level damage tracking to avoid full-surface redraws.
- `TerminalController` (`source/tvterm-core/termctrl.cc`): orchestrator owning PTY, emulator instance, event loop state, and synchronization.
- `TerminalView` (`source/tvterm-core/termview.cc`): `TView` that forwards input events and draws damaged terminal rows to the TView buffer.
- `BasicTerminalWindow` (`source/tvterm-core/termwnd.cc`): `TWindow` wrapper around `TerminalView` and terminal title/update integration.

### Threading Model
`TerminalController` starts two detached threads (both owned indirectly via `selfOwningPtr`):

- `WriterLoop`:
  - Waits on condition variable/timeouts.
  - Processes queued events from the main thread.
  - Calls `updateState` on timeout boundaries.
  - Writes pending emulator output to PTY.
- `ReaderLoop`:
  - Performs blocking reads from PTY.
  - Emits `ClientDataRead` events into emulator processing.
  - Updates timeouts, may process queued events/state updates, and wakes WriterLoop.

Concurrency details:
- Emulator + event-loop shared state are guarded by a single mutex (`TerminalEventLoop::mutex`).
- Main thread event submission uses `eventQueue` (`Mutex<std::queue<TerminalEvent>>`) with separate locking from emulator mutex; this is effectively lock-light from UI perspective (not truly lock-free).
- Main/UI thread interacts by `sendEvent(...)`, receives wakeups via `TEventQueue::wakeUp()`, and redraws when `cmCheckTerminalUpdates` is broadcast.

### Data Flow (End-to-End)
1. PTY reader gets bytes from child process.
2. `ReaderLoop` creates `TerminalEventType::ClientDataRead`.
3. `VTermEmulator::handleEvent` consumes event.
4. `vterm_input_write(...)` feeds libvterm parser/state machine.
5. libvterm callbacks (`damage`, `movecursor`, `settermprop`, etc.) update emulator-local state and row damage metadata.
6. On timeout/update window, `VTermEmulator::updateState` copies local state into shared `TerminalState`.
7. `drawDamagedArea` writes changed cells to `TerminalState::surface` (`TerminalSurface`) and accumulates row damage.
8. `TerminalView::draw` -> `updateDisplay` copies only damaged row segments into Turbo Vision view buffer via `writeLine(...)`.

### Platform Support
- Unix PTY path: `forkpty()` + shell exec (`$SHELL`) in child.
- Windows PTY path: ConPTY (`CreatePseudoConsole`) with extended startup attributes (`STARTUPINFOEX` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`) and `CreateProcessA`.

### Scrollback Foundation (LineStack)
- `VTermEmulator` includes `LineStack` with `maxSize = 10000`.
- libvterm `sb_pushline`/`sb_popline` callbacks already store/retrieve scrollback lines there.
- This is foundational plumbing for scrollback, but scrollback is not yet exposed in user-visible viewport behavior.

### Agent-Oriented Change Map
- Input/event routing: `source/tvterm-core/termview.cc`, `source/tvterm-core/termctrl.cc`.
- Emulator behavior and cell/state updates: `source/tvterm-core/vtermemu.cc`.
- Shared model/state definitions: `include/tvterm/termemu.h`.
- PTY + child-process lifecycle/platform code: `source/tvterm-core/pty.cc`.
- Window title/frame integration: `source/tvterm-core/termwnd.cc`, `include/tvterm/termwnd.h`.

## TODO Triage (Upstream README)

Ranked by practical implementation priority (value/effort), while noting raw technical difficulty:

1. `Text Selection` (Medium difficulty, high user value)
- Why high priority: very visible UX improvement, self-contained, no hard backend changes.
- Existing support: `TerminalView` already receives mouse events (`evMouseDown/Move/Up`); surface cells are `TScreenCell` with full attributes.
- Needed work:
  - Track drag start/end cell positions in `TerminalView`.
  - Add selection state in `TerminalState` (or equivalent state owned by controller/view with clear ownership).
  - Render highlight (reverse/inverted attrs) during `updateDisplay`.
  - Add copy-to-clipboard path on selection completion.

2. `Send Signal to Child Process` (Easy, lowest effort quick win)
- Unix path is straightforward: `kill(clientPid, signal)`; `PtyDescriptor` already has `clientPid`.
- Windows needs control-event equivalent (`GenerateConsoleCtrlEvent` or backend-appropriate alternative).
- Mostly wiring: expose API on `TerminalController`/PTY layer + add menu item/key binding.

3. `Scrollback` (Medium difficulty)
- Existing support: `VTermEmulator::LineStack` already captures lines via `sb_pushline`/`sb_popline` (`max 10000`).
- Needed work:
  - Viewport offset tracking in `TerminalView`/state.
  - Scroll input handling (Shift+PgUp/PgDn and/or mouse wheel when not in alt screen).
  - Render scrolled-back lines from `LineStack` onto surface/view.
  - Coordinate with controller/state updates and alt-screen behavior.

4. `Find Text` (Medium difficulty)
- Needs content access from current surface and scrollback.
- UI likely via Turbo Vision dialog/input (`TDialog`, `TInputLine`).
- Needs match highlighting and navigation semantics.
- Becomes much stronger once scrollback is implemented.

5. `Other terminal emulator implementations` (Medium difficulty)
- Architecture is ready (`TerminalEmulator` + `TerminalEmulatorFactory`).
- Main work is implementing compatible backend and parity behavior.

6. `Better dependency management` (Low product value, build-system oriented)
- Current approach is functional: git submodules plus optional system-library flags.
- Improvements are mostly packaging/reproducibility and contributor UX.

7. `Text reflow on resize` (Hard)
- libvterm does not provide full logical-line reflow behavior.
- Current behavior uses `vterm_set_size()` (truncate/pad style semantics).
- Proper reflow requires substantial line-model tracking and rewrap logic.

### Recommended First Task
`Text Selection` is the best first implementation target:
- Self-contained in `TerminalView` + shared terminal state.
- Reuses existing mouse event plumbing.
- Highly visible and easy for humans to validate.
- Independent of other TODO dependencies.

Suggested implementation pattern:
- Store normalized selection anchors (start/end cell positions).
- Apply inversion during `updateDisplay` on cells in selection range.
- Commit copy on mouse-up or explicit copy command.

### Easiest Quick Win
`Send Signal to Child Process` is the fastest low-risk improvement and can likely be implemented with minimal code changes.

## Build, Test, and Development Commands
Initialize dependencies first:

```sh
git submodule update --init --recursive
```

## Local Setup For Humans
Use this section when onboarding locally without changing upstream docs.

- Prerequisites (macOS): Xcode Command Line Tools, CMake, and Perl.
- Clone with submodules, or initialize them after cloning:

```sh
git clone --recursive <repo-url>
# or, inside an existing clone:
git submodule update --init --recursive
```

- Configure and build on macOS:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j"$(sysctl -n hw.ncpu)"
```

- Run locally:

```sh
./build/tvterm
```

- If `./build/tvterm` is missing, locate the binary:

```sh
find build -type f -name tvterm
```

Configure and build locally:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(nproc)
```

Run the app:

```sh
./build/tvterm
```

Use system libraries instead of submodules (optional):

```sh
cmake -S . -B build -DTVTERM_USE_SYSTEM_LIBVTERM=ON -DTVTERM_USE_SYSTEM_TVISION=ON
```

## Coding Style & Naming Conventions
- Language level: C++14.
- Follow existing style in `source/` and `include/`: 4-space indentation, Allman-style braces, and compact includes.
- File naming uses lowercase with `.cc`/`.h` (example: `termview.cc`, `termctrl.h`).
- Types use PascalCase (`TerminalView`), functions/methods use camelCase (`handleEvent`), and command constants use `cm*` (`cmCheckTerminalUpdates`).
- Keep builds warning-clean under `-Wall`.

## Testing Guidelines
There is currently no dedicated unit-test target in CMake. Validation is done through:

1. Clean configure + build on your platform.
2. Manual smoke testing in `tvterm` (open terminal, keyboard input, resize, menu actions).
3. CI compatibility expectations from `.github/workflows/cmake.yml` (GCC/Clang Linux builds).

When touching terminal behavior, prioritize manual scenarios covering:
- Rapid output (damage tracking under load).
- Resize behavior while output is active.
- Keyboard + mouse interactions (especially focus transitions and wheel/drag paths).
- Disconnect lifecycle (child exit and window close).

## Commit & Pull Request Guidelines
- Use short, imperative commit subjects; optional component prefix is common (example: `VTermEmulator: enable text reflow`).
- Keep each commit focused on one change.
- PRs should include:
  - What changed and why.
  - Any dependency/submodule updates.
  - Platforms/compilers tested.
  - Screenshots or terminal captures for visible UI/behavior changes.
  - Linked issue/reference when applicable.
