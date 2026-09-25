# KAIROS — Development

## Run the development version

From a shell **inside** your Wayland session:

```bash
qs -c kairos -v
```

`-v` prints INFO logs. Watch for `[KAIROS]` lifecycle lines and any QML warnings.
Use `qs -c kairos -d` to daemonize, or `-n` to prevent duplicate instances.

Quickshell reloads the config when `shell.qml` (or a watched file) changes —
just edit and let it hot-reload.

## Check for QML errors

Run with verbose logging and inspect stderr:

```bash
qs -c kairos -vv
```

A clean startup prints the `[KAIROS] v0.4 online` line and no `TypeError` /
`is not defined` / binding-loop warnings. If the link to Niri is down you will
see a single `[KAIROS] niri: link lost (...), retrying` warning per drop
(paired with a `quickshell.io.socket` warn), then silent backoff retries. An
empty `NIRI_SOCKET` produces **no** warnings — the backend stays in
`unsupported` and probes at idle cadence.

## Add a component

1. Create `components/Foo.qml`.
2. Base it on an existing primitive (`HudText`, `Rectangle`, `Item`, …).
3. Pull every color/size from `Theme`; never hardcode hex.
4. Import with `import "../config"` and `import "../components"`.
5. Use it from a panel — an unused component is dead weight.

Components are presentational: they must not poll services or run commands.

## Add a service

1. Create `services/FooService.qml` as an `Item` (or `QtObject` when it hosts
   no child objects). Services that own non-visual children — a `Socket` +
   `SplitParser` + `Timer`, like `NiriBackend` — must root as `Item`
   (QtObject has no default property for children).
2. Expose only live `property` state.
3. Own your own `Timer`/`Process`; choose coarse intervals
   (`Settings.fastInterval` / `slowInterval`).
4. Degrade gracefully — when data is missing, set `N/A` / `OFF`, never throw.
5. Instanciate it once in `shell.qml` and inject it into panels.

## Add a compositor backend

1. Read the common contract in `services/compositor/CompositorService.qml`.
2. Add `services/compositor/<Family>Backend.qml` rooted as `CompositorService`
   (import `"."` to see the sibling base).
3. Drive `name`, `connected`, `connectionState` and the common state
   (`workspaces`, `windows`, …) from that compositor's own IPC; reuse the base
   helpers — never reimplement them.
4. Swap the instantiation in `shell.qml`:
   `property CompositorService compositor: <Family>Backend {}`.
5. Keep the UI untouched.

## Add a panel

1. The Top HUD and Workspace Matrix are per-screen: root type is `PanelWindow`
   with `required property var modelData` + `screen: modelData` inside
   `Variants`.
2. The contextual layer is **single-global**: one `BottomRail`, one
   `FocusCapsule`, one `FocusPulse`. Panels bind `screen: pulse.targetScreen`
   to follow the focused output — never duplicate them per screen.
3. Inject services via properties (e.g. `systemService: root.systemService`).
4. Compose from components; no raw `Text`/`Rectangle` color literals.

## Modify the theme

Edit `config/Theme.qml` only. Tokens:

| Token | Meaning |
| --- | --- |
| `Theme.background/surface/line/text/muted/subtle` | surfaces & typography |
| `Theme.accent / warning / critical / ok` | state colors |
| `Theme.fontMono / fontCondensed` | font stacks |
| `Theme.size* / track*` | typography scale |
| `Theme.borderWidth / radius / spacing` | geometry |
| `Theme.animationFast/Normal/Slow`, `Theme.reducedMotion` | motion |

Runtime behavior lives in `config/Settings.qml` (HUD height, refresh, formats).

## Debugging

- **Values stuck at `--` / `N/A`** — check the service's `Process` command
  manually in a terminal; ensure the poll timer is running.
- **Binding loops** — Quickshell/Qt log `Binding loop detected`; check for a
  binding that writes to a property it reads (e.g. `text` deriving from `text`).
- **Window not appearing** — verify the compositor supports layer-shell and
  that `Quickshell.screens` contains your outputs.
- **Bottom surfaces stacking mid-screen** — Quickshell sets `exclusionMode:
  Auto` by default, which reserves `implicitHeight + reverse margin` at the
  anchored edge. Two bottom-anchored panels then stack instead of placing
  where you expect. Give the edge-owner an explicit
  `exclusiveZone: <its height>` and give floaters above it `exclusiveZone: 0`
  (their margins are then measured from the edge-owner's top).
- **Opaque white stripe when hidden** — `PanelWindow.color` defaults to
  **white** (Quickshell docs). A panel whose children fade to `opacity: 0`
  shows a white slab; set `color: "transparent"` on the window and let the
  interior paint when visible.
- **Stale test instances** — orphaned Quickshell instances keep their layer
  surfaces alive and silently push/cover the new ones. Always check
  `niri msg -j layers` for unexpected `quickshell` surfaces (there should be
  exactly one per panel) and kill with `pkill -9 -f '[q]uickshell -p'` (the
  `[q]` bracket prevents `pkill` from matching your own command line — never
  put the plain process name in the same command).
- **Noisy logs** — services should only emit on state failures, not per tick.

## Test the Niri link without Niri

`NiriBackend` is a pure IPC client, so you can (and should) exercise it against
a fake compositor before touching a real session:

1. Serve the EventStream protocol on a fake socket (niri-ipc ≥ 26.4 schema):
   accept the connection, read the `"EventStream"` request line, stream
   newline-delimited JSON — `WorkspacesChanged`, `WindowsChanged`, then
   `WorkspaceActivated {id, focused}` moves (with 1-based `idx`).
2. Run with `NIRI_SOCKET=/tmp/fake.sock qs -c kairos -v`.
3. Confirm: `[KAIROS] niri: linked`, focus changes flow into
   `connected` + the workspace model, closing the socket triggers
   `link lost ... retrying` (states `reconnecting`/`error`), and restarting
   the socket yields a clean relink with fresh full state.

On a real Niri session use `niri msg action focus-workspace <n>` to switch
workspaces, `niri msg action focus-window --id <n>` to change focus, and
`niri msg action move-window-to-workspace <n>` to exercise occupancy —
restore the session (workspace 1, original window) afterwards.

## Test the v0.4 contextual layer

Verify the two v0.4 instruments (`BottomRail`, `FocusCapsule`) without
touching them visually:

1. **Idle clean** — with KAIROS running, the only bottom artifact is a
   transparent 12 px strip; no permanent active-window panel, no chip.
2. **Live switches** — `focus-workspace <n>` / `focus-window --id <n>` should
   produce a capsule (window variant, or `WORKSPACE` variant on an empty
   workspace) that auto-fades after ~2.5 s, and a forced rail reveal that
   auto-dismisses after ~3 s of inactivity. Move the pointer away from the
   bottom edge between actions so the forced timers actually fire.
3. **Hover** — move the pointer to the bottom edge: the rail reveals
   (height 12 → 36), and collapses after `railHoverGraceMs` once the pointer
   leaves. There is no global pointer API on Wayland, so this is a manual
   check (`xdotool mousemove` works if installed).
4. **Title-only change** — with the focus capsule not visible, retitle the
   focused window (e.g. retitle a terminal). No capsule/rail replay should
   occur; the text in an already-revealed rail updates in place.
5. **Disconnect/reconnect** — killing the fake socket (harness above) hides
   both instruments; relinking repopulates the rail and fires a single pulse.
6. **No-window state** — switching to an empty workspace collapses the window
   block in the revealed rail (clock + `WS 04` remain) and pulses the
   workspace-only capsule.

## Real-session Niri checklist

1. Start KAIROS → banner `v0.4`, `COMPOSITOR NIRI`; no permanent workspace UI
   and no top-left matrix (v0.5) — the desktop is clean until interaction.
   Bottom edge shows only the 12 px strip.
2. Switch `WS1`…`WS4` → (Niri emits `WorkspaceActivated` only for switches —
   no full reload); the focus capsule pulses and auto-fades; the rail reveals
   (window identity + `WS nn`) and auto-dismisses.
3. Open/close a window, move one between workspaces → the revealed rail's
   identity row updates; workspace-only switches render the bare `WS nn`.
4. Restart KAIROS → state reconstructs from the first `WorkspacesChanged`;
   the restored window name appears once in the capsule.
5. Restart Niri (or kill its socket) → KAIROS survives, reports
   `reconnecting`, both instruments hide, and relinks when Niri returns.

## Milestones

- v0.1 top HUD (base identity + metrics)
- v0.2 system telemetry — CPU/NET/TMP via `/proc` deltas + Gauge/Graph
- v0.3 Niri IPC + workspace matrix
- v0.3.1 hardened Niri backend + compositor seam
- v0.4 contextual active-window UX — bottom rail + focus capsule
  (current)
- v0.5 top-left workspace matrix removed; rail = single workspace indicator
- v0.5+ GPU/DISK/BATTERY telemetry, command interface, control center,
  right-side contextual drawer, media, notifications, lock, power

Implement in order; validate each milestone before starting the next.