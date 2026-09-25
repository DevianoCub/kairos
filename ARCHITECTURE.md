# KAIROS — Architecture

KAIROS follows a strict layered model. Data flows downward; the UI never
reaches past its layer:

```text
DATA           /proc, compositor sockets, DBus, udev
    ↓
SERVICES       services/SystemService.qml,
               services/compositor/*.qml (one desktop-state owner)
    ↓
STATE          common desktop-state contract (CompositorService)
    ↓
COMPONENTS     components/*.qml (HudText, HudLabel, Metric, ...)
    ↓
PANELS         panels/TopHud.qml, ...
    ↓
SHELL          shell.qml (composition root)
```

## Rule

The UI must never execute commands or parse raw data. A panel reads
`SystemService.memoryPercent`; it does not run `free` or read `/proc`.

```qml
// GOOD
Metric { label: "MEM"; value: SystemService.memoryPercent }

// BAD
Text { text: /* run awk, parse output, format here */ }
```

## Directory layout

```text
kairos/
├── shell.qml            composition root; instantiates services + panels
├── config/              Theme.qml, Settings.qml (QML singletons via qmldir)
├── components/          reusable visual primitives, theme-driven
├── services/            stateful system data providers (no visual logic)
│   └── compositor/      CompositorService.qml (contract) + backends
├── panels/              windows / composite UI regions
├── animations/          motion primitives (future milestones)
└── assets/              fonts, icons, graphics, sounds (future)
```

## Services

| Service | Owns | Notes |
| --- | --- | --- |
| `SystemService` | clock, MEM, LOAD, UPTIME, CPU%, NET RX/TX, TEMP, compositor name, synthetic status | v0.2 |
| `CompositorService` (base) | the common desktop-state contract | v0.3.1, UI binds only here |
| `NiriBackend` | Niri IPC link, workspaces, windows, focus, outputs, reconnect | v0.3.1, read-only |
| `AppLauncherService` | desktop-entry discovery, model, search scoring, launch execution | v0.5, no visuals |
| `CommandService` | the command bus: one-shot intents (`contextualEvent`, `appLaunched`, `publishContextual`) | v0.5, event bus |

Delta metrics (CPU%, NET rates) keep raw counters snapshot between ticks and
compute one sample per tick. Histories are bounded (`Settings.graphSamples`)
and fed to `Graph` primitives — never unbounded.

A service is an `Item` (or `QtObject` when it hosts no child objects) with:

- live `property` state the UI binds to,
- its own timers / process handles (isolated, bounded),
- graceful degradation (`N/A` instead of crashing).

Later services (staged): `NetworkService`, `AudioService`, `MediaService`,
`NotificationService`.

## State

The synthetic KAIROS **system state** (`NORMAL / BUSY / WARNING / CRITICAL /
…`) is derived from real conditions in services, never fabricated. UI reacts
to state transitions, services react to raw data.

## Panels & screens

The Top HUD is instantiated inside
`Variants { model: Quickshell.screens }` — one instance per physical monitor.
(The per-screen workspace matrix from v0.3 was removed in the v0.4 correction;
the bottom rail is now the single workspace indicator.)

The **contextual active-window surface is deliberately NOT per-screen**: exactly
one `BottomRail` exists in the whole shell, driven by a single `FocusPulse`. It
binds `screen: pulse.targetScreen`, so the single surface follows the output
that owns the focused workspace instead of being duplicated. Global overlays
(launcher, control center, notification center) are single instances — never
duplicated per monitor. The launcher is **ephemeral**: it is a third layer-shell
surface only while a command is being typed, and it is fully unmapped once
closed (`exclusiveZone: 0` overlay, so no window geometry ever changes).

## Compositor & desktop state

Exactly **one** `CompositorService` is instantiated in `shell.qml`, backed by
`NiriBackend`. Panels never talk to a compositor directly — they bind to the
common contract:

```text
KAIROS UI (TopHud, BottomRail)
    │  binds to
CompositorService (common desktop state)
    │  implements
NiriBackend (Niri IPC, read-only)
    │
Niri 26 (NIRI_SOCKET EventStream)
```

### Common desktop-state model

```text
CompositorService
├── name              "" | "Niri"           backend identity
├── connected         bool                  link live
├── connectionState   disconnected|connecting|connected|
│                     reconnecting|error|unsupported
├── workspaces        [{ id, index, name?, output,
│                        isActive, isFocused, isUrgent, occupied }]
├── activeWorkspaces  active workspaces (per output)
├── focusedWorkspace  focused workspace, or null
├── activeWorkspace   focused, else first active, else null
├── windows           [{ id, appId, title, workspaceId,
│                        output, isFocused }]
├── focusedWindow     focused window, or null
├── outputs           distinct workspace outputs
└── helpers           workspacesFor, displayColumnFor,
                      displayIndexFor, workspaceLabel
```

`index` is the compositor-native numeric index (Niri: 1-based `idx`).
Compositors that name workspaces (Sway…) set `name` instead and the UI renders
  
it verbatim. `occupied` is derived from windows — never guessed.

### Niri backend

Connects to the raw `NIRI_SOCKET` UNIX socket via `Quickshell.Io.Socket` +
`SplitParser` (newline-delimited JSON), writes one `"EventStream"` request,
then consumes the stream forever:

- `WorkspacesChanged` / `WindowsChanged` are **authoritative full
  replacements**; every update rebuilds the model, then derived state
  (outputs, active/focused workspaces, occupancy, focused window) recomputes.
- `WorkspaceActivated {id, focused}` — the *only* event Niri 26 emits on a
  workspace switch — refocuses the workspace in-place (clearing the previous
  focus). It is the primary update path, not a hint.
- `WindowOpenedOrChanged`, `WindowClosed`, `WindowFocusChanged` maintain the
  window model incrementally.
- A dropped link flips `connected` to `false` and enters
  `reconnecting` / `error`, retrying with exponential backoff
  (`niriRetryMinMs` → `niriRetryMaxMs`). An empty `NIRI_SOCKET` means the
  compositor has no Niri backend: state is `unsupported`, re-probed at an
  idle cadence (`niriRetryIdleMs`). No state is fabricated while down.

### System detection vs. desktop backend

`SystemService.compositorName` reports whichever Wayland compositor is
running (e.g. `MANGO` under MangoWM). `CompositorService` reports whether
KAIROS has a **supported backend** for it. These are different axes: under
MangoWM, KAIROS keeps running (telemetry intact), the compositor readout says
`MANGO`, and the workspace instruments show an honest offline state.

### Adding another compositor family

Implement the `CompositorService` contract in a new backend
(e.g. `HyprlandBackend.qml`) and swap one line in `shell.qml`:

```qml
property CompositorService compositor: NiriBackend {}
```

No UI changes are required. This is a design requirement — only the Niri
backend exists today.

## Contextual active-window surface (v0.4)

The active-window UI is **not a panel** that sits on screen — it is exactly
**one** thin instrument on the bottom edge that appears in response to state
changes. Nothing else floats over the wallpaper:

```text
CompositorService (focusedWindow, focusedWorkspace,
                   activeWorkspace, workspaces, windows, ...)
    │  one global FocusPulse (components/FocusPulse.qml)
    │  fingerprint = "<window id>|<display workspace>"
    ├── PULSE (logical target changed)   → rail forced-reveals (≈3 s)
    └── title-only (same target)         → mutate text in place, no replay
    │
    ▼
BottomRail (panels/BottomRail.qml)
  single full-width strip on the bottom edge
  12 px hidden ↔ 36 px revealed, hover / forced reveal
  window: [K] kitty   ~/projects/kairos   WS 03
  empty:  WORKSPACE 03
```

Design rules:

- **Idle clean.** With the link alive and nothing happening, the only
  bottom-edge artifact is a transparent 12 px hover strip. No permanent
  active-window region a user must route around.
- **Contextual, not persistent.** The rail answers a state *change*, then gets
  out of the way. `FocusPulse.pulse` increments only when the **target**
  changes; retitles mutate in place without replaying the entrance animation.
  Disconnect zeros the fingerprint and hides the rail; a relink to the **same**
  target is silent (no redundant reveal) — only a genuinely new target pulses.
- **Compositor-agnostic.** `FocusPulse`, `WindowIdentity` and `BottomRail`
  bind only to `CompositorService`. The monogram tile (first letter of
  `appId`) is the identity glyph; there is **no icon-theme lookup** — KAIROS
  reads `appId` + `title`, nothing else.
- **One surface, follow-the-focus.** A single `FocusPulse` keys off the
  focused workspace owner output (`targetScreen`), and the rail binds its
  `screen` to it. It is never duplicated per output and never stacks.
- **Edge ownership.** The HUD (top) is the desktop panel: it reserves its top
  exclusion zone (`Settings.exclusiveZone`). The rail is the opposite — a
  pure overlay with `exclusiveZone: 0` (quickshell's setter forces
  exclusion-mode `Normal`), so it reserves **zero** work-area and application
  window geometry never changes when it appears. A single bottom anchor keeps
  it at the physical bottom edge through every hide/reveal cycle.
- **Deterministic auto-hide.** Exactly one rule decides visibility —
  `revealed = fForced || fPointer || fGrace` — across four states
  (`HIDDEN / FORCED_REVEAL / HOVER_REVEAL / HIDE_PENDING`). `fForced` is set
  only by a logical focus/workspace change and cleared only by the one reveal
  timer (3 s, unless the pointer sits inside); pointer enter/leave drive
  `fPointer`/`fGrace` and the single grace timer. No two timers ever fight:
  each clears exactly one flag and one `reevaluate()` owns the transitions.
  Every transition / timer start-stop is logged (`[Rail] ...`, kept until
  proven).
- **Input.** In Quickshell 0.3.1 `PanelWindow` has no `passThrough`, so the
  revealed rail uses a `MouseArea` (its hidden state is only a 12 px strip,
  `railHoverReveal` toggles hover). Focus-stealing is a known interaction
  trade-off; `passThrough` should be adopted as soon as a Quickshell release
  exposes it.
- **Hierarchy for the future drawer.** `WindowIdentity` (monogram + appId +
  elided title) is the shared identity row; a future right-side contextual
  drawer reuses `FocusPulse`/`WindowIdentity` unchanged and only does its own
  reveal/pin geometry.

## Command center / app launcher (v0.5)

The command center is a **foundation for the whole command layer**. v0.5 ships
the app launcher only; volume, brightness, notifications, media and power attach
later by publishing intents on the same command bus.

```text
Quickshell.DesktopEntries (XDG desktop-entry index, live-monitored)
    │  applications.values + applicationsChanged (coalesced)
    ▼
AppLauncherService (services/commands/AppLauncherService.qml)
    ├── snapshot model (id, name, genericName, comment, icon, keywords,
    │                  categories, tokens, entry) — deterministic sort
    ├── search: prefix/substring/subsequence scoring over lowercased
    │   name/generic/id/keywords/categories/comment; score + name/id ties
    └── launch(entry) → DesktopEntry.execute()  (parsed argv, shell-free,
                                                 field codes stripped)
    │
    ▼
Launcher (components/launcher/)                    view + navigation only
  PanelWindow — ephemeral, exclusiveZone: 0, aboveWindows, focusable
  CLOSED→OPENING→OPEN→CLOSING→CLOSED; fade + late focus hand-off
  Sized to the instrument column; bottom-anchor only → the compositor
  centers the unanchored axis; margins.bottom = (screenH - h)/2 + shiftY
  LauncherSearch (TextInput, > prompt, nav signals; never owns state)
  LauncherResult (result NODE on the spine: 1px/3px marker on the spine
                  column, name right of it, uppercase category tag;
                  hover select on MOVEMENT, click activates)
    │
    ├── publishes → CommandService.publishContextual("LAUNCHED <Name>")
    │                 → BottomRail reveals its rail + label for ~3 s
    └── triggered by → IpcHandler{ target "kairos" } (toggleLauncher /
                       launcherQuery / launcherMove / launcherRun /
                       launcherState / launcherGeom)
```

Rule of separation: the service owns data, model, search and execution; the UI
owns the state machine, selection and painting. The launcher never reads a
`.desktop` file, spawns a process or knows a compositor name. All four IPC
functions drive the **exact** code paths the keyboard uses.

### Surface geometry (Nexus placement)

The launcher is a **sized** window, not a stretched layer: `anchors.bottom`
only (no left/right), plus an explicit `width: Settings.launcherMaxWidth` and a
`margins.bottom` derived from `(screenH - height)/2 + launcherCenterShiftY`.
Under Niri both side-anchors stretch the surface full-width, which pinned the
instrument off-center; bottom-anchor-only makes the compositor center the
unanchored axis. `_screenW/_screenH` read `screen.width/height` directly — the
QML-reported `devicePixelRatio` is unreliable at the layer scale and must not
be divided by. The spine column sits at `_spineX ≈ nexus.width/2`; the window
elevation is exactly `launcherCenterShiftY` logical px above screen center.

### The Nexus view

```text
            COMMAND 03                      ← caption + live zero-padded count
              > fire▮                       ← NUCLEUS (prompt), column centered
            ────────────                      (underline hugs the typed width)
    ●                 Firefox        WEB    ← nodes on the shared 1 px spine
    ●  Files                            …
    ●  Kitty                 TERMINAL
        │
        │   spine (Theme.faint) full height; selected segment
        │   (nucleus → selected node) draws Theme.accent = "energized"
   ↑↓ SELECT · ↵ RUN · ESC CLOSE
```

- 1 px spine: x `_spineX`, y 0 → `nucleusRow.y`, Theme.faint. The energized
  `pathSegment` (Theme.accent) spans `rowCenterY(selected) → nucleusRow.y` and
  re-animates on every selection move.
- Result gaps: `_resultCount > 4` → compact (`launcherNodeGapCompact`), else
  loose (`launcherNodeGapLoose`). Rows: 1 → single node on a short energized
  stem; 0 → `NO MATCH` line, spine hidden.
- Entrance: spine, then nodes, one per 40 ms (`_stagger`); only on OPEN, never
  replayed by typing.

### Selection input contract

Hover selection is driven by **`onPositionChanged`**, never `onEntered` — a
freshly instantiated delegate under a stationary cursor fires a synthetic enter
and would otherwise re-select itself. A `_hoverGuardUntil` (800 ms) window is
armed on every open/results-change, and `_keyboardMode` is set by the first
`moveSelection`/`activateSelection` — after which hover re-entries never
overwrite the keyboard selection. Query/results changes reset index 0 and clear
keyboard mode (unchanged).

### Search semantics (deterministic)

- Empty query → whole catalog, alphabetical (name, then id).
- Field codes in `Exec` were already stripped at desktop-entry parse time;
  `execute()` runs the parsed argv detached with no shell — no injection, no
  `%` leakage. `Terminal=true` runs raw (no TTY) in v0.5.
- Scoring tiers: name prefix/substring (strongest) → genericName → id →
  subsequence fuzz on the name → keyword/category/comment soft signals; ties
  break by name, then id (`localeCompare`).

### Lifecycle safety

Opening sets the query to `""` and the selection to index 0; edits reset the
selection; model changes clamp it in range. Closing releases the keyboard; the
compositor re-focuses the previous window — KAIROS makes no focus calls.

## Performance stance

- finite polls at coarse intervals (seconds, not frames),
- no unbounded arrays (bounded histories only),
- native `SystemClock` instead of spawning `date`,
- one short-lived `/proc` read per tick, guarded against overlap.