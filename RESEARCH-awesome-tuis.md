# Awesome TUIs Research — Relevance to tvterm

> **Prompt:** "grok https://github.com/rothgar/awesome-tuis for C++ TUI apps or things that might be nice additions"
> **Source:** https://github.com/rothgar/awesome-tuis
> **Date:** 2026-02-21
> **Total entries surveyed:** ~500+ apps across 13 categories

---

## Executive Summary

The awesome-tuis list has ~500 TUI apps. tvterm is already listed in the Productivity section. The most relevant findings fall into three buckets:

1. **C++ TUI Libraries** — competitors/alternatives to Turbo Vision
2. **Turbo Vision Ecosystem** — apps built on the same framework as tvterm
3. **Apps that showcase tvterm** — things that look great running *inside* tvterm

---

## Tier 1: Directly Relevant — Turbo Vision Ecosystem

These use the same `tvision` framework as tvterm, built by magiblot or the community.

| Project | Stars | Language | Why it matters |
|---------|-------|----------|---------------|
| [tvision](https://github.com/magiblot/tvision) | 2,761 | C++ | tvterm's foundation — the modern Turbo Vision port itself |
| [turbo](https://github.com/magiblot/turbo) | 625 | C++ | **magiblot's text editor** — Scintilla + Turbo Vision. Sister project to tvterm. Could embed inside tvterm windows. |
| [turbo-mle](https://github.com/magiblot/turbo-mle) | 11 | C | Another magiblot editor experiment — Turbo Vision TUI for the mle editor |
| [chr](https://github.com/chr-editor/chr) | 48 | C++ | Terminal editor inspired by Turbo Pascal editor, uses Turbo Vision. Proof others build on tvision. |
| [tparted](https://github.com/Kagamma/tparted) | 75 | Pascal | Disk partition editor built on Free/Turbo Vision — shows the framework works for system tools |
| [Vindauga](https://github.com/gabbpuy/vindauga) | 14 | Python | Python port of Turbo Vision — cross-pollination potential |
| [Jexer](https://gitlab.com/AutumnMeowMeow/jexer) | — | Java | Java windowing system "reminiscent of Borland's Turbo Vision" — spiritual sibling |

**Key insight:** magiblot has a clear vision — tvision is the platform, turbo is the editor, tvterm is the terminal. These three form a suite. Contributing to tvterm means contributing to this ecosystem.

---

## Tier 2: C++ TUI Libraries — Competitors & Inspirations

These are the other C++ TUI frameworks. Worth studying for feature ideas.

| Library | Stars | Description | Relevance to tvterm |
|---------|-------|-------------|-------------------|
| [FTXUI](https://github.com/ArthurSonzogni/FTXUI) | 9,683 | Functional C++ TUI — React-like declarative API | ⭐ Most popular C++ TUI lib. Has great component model, animations, flexbox layout. Could inspire tvterm widget improvements. |
| [imtui](https://github.com/ggerganov/imtui) | 3,520 | ImGui for terminals — by ggerganov (llama.cpp author) | Immediate-mode TUI. Different paradigm from Turbo Vision's retained mode. Has mouse+256 color support. |
| [FINAL CUT](https://github.com/gansm/finalcut) | 1,146 | C++14 widget toolkit — closest competitor to tvision | Most similar to Turbo Vision. Has text selection, clipboard, drag-and-drop already. **Study their selection implementation.** |
| [Tui Widgets](https://github.com/tuiwidgets/tuiwidgets) | 23 | High-level C++ widget toolkit | Small but has Qt-like signals/slots. Different approach. |
| [GGUI](https://github.com/Gabidal/GGUI) | 6 | C++17 structured TUI | Very small, not mature |
| [rang](https://github.com/agauniyal/rang) | — | Header-only terminal colors | Utility lib, not a framework |
| [notcurses](https://github.com/dankamongmen/notcurses) | — | C/Python blingful graphics lib | Lower-level than tvision, supports sixel/kitty graphics |

**Key insight:** FINAL CUT is the closest competitor — it already has clipboard support. FTXUI is the most popular but uses a completely different paradigm. Turbo Vision's advantage is its classic windowing model.

---

## Tier 3: Apps That Showcase tvterm

These are TUI apps that look great running *inside* tvterm — good for demos, screenshots, and testing.

### 🏆 Top Picks for tvterm Demos

| App | Stars | Description | Why great in tvterm |
|-----|-------|-------------|-------------------|
| [htop](https://github.com/htop-dev/htop) | 7,843 | Interactive process viewer | ✅ Already tested — mouse-aware, shows mouseEnabled working |
| [btop++](https://github.com/aristocratos/btop) | 30,435 | Beautiful resource monitor | Gorgeous TUI with themes, would make stunning tvterm screenshot |
| [lazygit](https://github.com/jesseduffield/lazygit) | 72,778 | Git TUI | Most starred TUI app. Mouse-aware. Perfect multi-window tvterm demo. |
| [cgdb](https://github.com/cgdb/cgdb) | 1,816 | Console GDB frontend | C++ debugger in a terminal — very meta for debugging tvterm itself |
| [cmus](https://cmus.github.io/) | — | Console music player | Shows tvterm can run media apps |
| [sc-im](https://github.com/andmarti1424/sc-im) | — | Terminal spreadsheet | Borland-era nostalgia — spreadsheet inside a Turbo Vision app |
| [termshark](https://github.com/gcla/termshark) | 9,814 | Terminal Wireshark | Complex TUI with mouse, good stress test |
| [nnn](https://github.com/jarun/nnn) | — | Fast file manager | Lightweight, good for tvterm file browsing |

### 🎮 Fun Demos

| App | Stars | Description |
|-----|-------|-------------|
| [DOOM-ASCII](https://github.com/wojciech-graj/doom-ascii) | — | DOOM in ASCII art |
| [tinytetris](https://github.com/taylorconor/tinytetris) | — | 80x23 terminal tetris |
| [cbonsai](https://gitlab.com/jallbrit/cbonsai) | — | Bonsai tree generator |
| [mapscii](https://github.com/rastapasta/mapscii) | — | World map in braille/ASCII |
| [pipes screensaver](https://github.com/inunix3/rxpipes) | — | Classic pipes screensaver |

---

## Tier 4: Feature Inspiration for tvterm

Ideas stolen from studying the awesome-tuis list:

### From Terminal Multiplexers (tmux, zellij, dvtm)
| Feature | Source | Difficulty | Value |
|---------|--------|-----------|-------|
| **Session save/restore** | tmux, zellij | High | Save terminal layout across restarts |
| **Tiling layouts** | dvtm, zellij | Medium | tvterm already has tile cols/rows — could add more layouts |
| **Named sessions** | tmux | Low | Let users name terminal windows |
| **Broadcast input** | tmux | Medium | Type in all terminals simultaneously |

### From Editors (turbo, micro, helix)
| Feature | Source | Difficulty | Value |
|---------|--------|-----------|-------|
| **Scrollback buffer** | Already in tvterm TODO | Medium | Critical missing feature |
| **Search in scrollback** | tmux copy-mode | Medium | Find text in terminal history |
| **Bracketed paste** | Standard | Low | Our planned follow-up PR |

### From FINAL CUT (competitor study)
| Feature | Source | Difficulty | Value |
|---------|--------|-----------|-------|
| **Drag-and-drop** | finalcut | High | Drag text between terminals |
| **Built-in clipboard widget** | finalcut | Medium | Clipboard history viewer |
| **Theming system** | finalcut | Medium | User-customizable colors |

### From This Awesome List Generally
| Feature | Source | Difficulty | Value |
|---------|--------|-----------|-------|
| **URL detection + open** | Many terminal emulators | Medium | Click URLs to open browser |
| **Image rendering** | notcurses, chafa, sixel | High | Show images in terminal (sixel/kitty) |
| **Split pane mode** | zellij, tmux | Medium | Horizontal/vertical splits within one window |

---

## Tier 5: Potential Contributions Beyond tvterm

If you want to contribute to other C++ TUI projects after this PR:

| Project | Stars | Opportunity |
|---------|-------|-------------|
| **turbo** (magiblot) | 625 | Same maintainer — could add features, already know the codebase |
| **FTXUI** | 9,683 | Very active, lots of open issues, large community |
| **FINAL CUT** | 1,146 | Similar to tvision, could cross-pollinate ideas |
| **btop++** | 30,435 | C++ resource monitor, very popular, active development |
| **far2l** | 2,121 | Linux port of FAR Manager — another Borland-era nostalgia project |

---

## Notable Omissions from awesome-tuis

Things that *should* be on the list but aren't:

- **Alacritty** / **kitty** / **WezTerm** — terminal emulators (not TUIs per se, but related)
- **notcurses** is listed under Python but is primarily a C library
- tvterm is listed but could use a better description — "A terminal emulator that runs in your terminal" undersells it

---

## Recommendations for tvterm's Next Steps

Based on this research, prioritized:

1. **Scrollback buffer** — The #1 missing feature. Every terminal multiplexer has it.
2. **Bracketed paste** — Already planned, finishes the copy/paste story (issue #5).
3. **URL detection** — Low-hanging fruit, high user value.
4. **Split panes** — Would differentiate tvterm from basic terminal-in-terminal.
5. **Screenshot gallery** — Run btop, lazygit, htop inside tvterm and screenshot for README. Instant star boost.

---

*Generated from surveying https://github.com/rothgar/awesome-tuis (~500 entries) with focus on C++ TUI apps and relevance to the tvterm project.*
