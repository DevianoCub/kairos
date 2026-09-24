# KAIROS — Architecture

KAIROS follows a strict layered model. Data flows downward; the UI never
reaches past its layer:

```text
DATA           /proc, compositor sockets, DBus, udev
    ↓
SERVICES       services/SystemService.qml, ... (one owner per domain)
    ↓
STATE          typed, live properties the UI binds to
    ↓
COMPONENTS     components/*.qml (HudText, HudLabel, Metric, ...)
    ↓
PANELS         panels/TopHud.qml, ... (one window per screen if needed)
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
├── panels/              windows / composite UI regions
├── animations/          motion primitives (future milestones)
└── assets/              fonts, icons, graphics, sounds (future)
```

## Services

| Service | Owns | Notes |
| --- | --- | --- |
| `SystemService` | clock, MEM, LOAD, UPTIME, CPU%, NET RX/TX, TEMP, compositor name, synthetic status | v0.2 |
| `NiriService` | Niri IPC link, workspaces, windows, focus, outputs, reconnect | v0.3, read-only |

Delta metrics (CPU%, NET rates) keep raw counters snapshot between ticks and
compute one sample per tick. Histories are bounded (`Settings.graphSamples`)
and fed to `Graph` primitives — never unbounded.

A service is a `QtObject` with:

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

## Niri IPC

Exactly one `NiriService` owns the compositor connection. It connects to the
raw `NIRI_SOCKET` UNIX socket via `Quickshell.Io.Socket` + `SplitParser`
(newline-delimited JSON), writes one `"EventStream"` request, and consumes
the event stream forever:

- `WorkspacesChanged` / `WindowsChanged` are **authoritative full replacements**;
  every update rebuilds the model, then `refreshDerived()` recomputes outputs,
  active/focused workspaces, window counts and the focused window.
- `WorkspaceActivated {id, focused}` (niri ≥ 26, id+focused only) drives an
  **optimistic focus move** on the current model; the authoritative
  `WorkspacesChanged` arrives immediately after and reconciles any skew.
- `WindowOpenedOrChanged` / `WindowClosed` / `WindowFocusChanged` upsert /
  remove / re-flag windows.
- A dropped link flips `connected` to `false`, clears nothing, and schedules a
  reconnect with exponential backoff (`niriRetryMinMs` → `niriRetryMaxMs`),
  re-reading `NIRI_SOCKET` on every attempt. While offline the matrix renders a
  restrained `niri ○ offline` state and the `WKSP` chip shows `--` — no data
  is fabricated.

Components never call IPC directly. Panels read `workspacesFor(output)`,
`displayIndexFor(output)`, `outputs`, `focusedWorkspace`, … from the service.
The service is read-only: it never issues commands to Niri.

## Performance stance

- finite polls at coarse intervals (seconds, not frames),
- no unbounded arrays (bounded histories only),
- native `SystemClock` instead of spawning `date`,
- one short-lived `/proc` read per tick, guarded against overlap.