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
PANELS         panels/TopHud.qml, panels/WorkspacePanel.qml, ...
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

Panels that are per-screen (Top HUD, Workspace Matrix) are instantiated inside
`Variants { model: Quickshell.screens }`. Global overlays (launcher, control
center, notification center) will be single instances — never duplicated per
monitor.

## Compositor & desktop state

Exactly **one** `CompositorService` is instantiated in `shell.qml`, backed by
`NiriBackend`. Panels never talk to a compositor directly — they bind to the
common contract:

```text
KAIROS UI (TopHud, WorkspacePanel)
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
`MANGO`, and the workspace UI shows `◦ no backend`.

### Adding another compositor family

Implement the `CompositorService` contract in a new backend
(e.g. `HyprlandBackend.qml`) and swap one line in `shell.qml`:

```qml
property CompositorService compositor: NiriBackend {}
```

No UI changes are required. This is a design requirement — only the Niri
backend exists today.

## Performance stance

- finite polls at coarse intervals (seconds, not frames),
- no unbounded arrays (bounded histories only),
- native `SystemClock` instead of spawning `date`,
- one short-lived `/proc` read per tick, guarded against overlap.