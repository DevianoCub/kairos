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

A clean startup prints the `[KAIROS] v0.3.1 online` line and no `TypeError` /
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

1. For per-screen UI, the root type is `PanelWindow` with
   `required property var modelData` + `screen: modelData`.
2. For global UI (later), use a single `PanelWindow`/`PopupWindow` outside Variants.
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

## Real-session Niri checklist

1. Start KAIROS → banner `v0.3.1`, `COMPOSITOR NIRI`, `WKSP 01` on workspace 1.
2. Switch `WS1`…`WS4` → the `▲` caret, `WKSP` chip and matrix follow instantly
   (Niri emits `WorkspaceActivated` only for switches — no full reload).
3. Open/close a window, move one between workspaces → occupancy rails update.
4. Restart KAIROS → state reconstructs from the first `WorkspacesChanged`.
5. Restart Niri (or kill its socket) → KAIROS survives, reports
   `reconnecting`, and relinks when Niri returns.

## Milestones

- v0.1 top HUD (base identity + metrics)
- v0.2 system telemetry — CPU/NET/TMP via `/proc` deltas + Gauge/Graph
- v0.3 Niri IPC + workspace matrix
- v0.3.1 hardened Niri backend + compositor seam (current)
- v0.4+ GPU/DISK/BATTERY, command interface, control center, media,
  notifications, lock, power

Implement in order; validate each milestone before starting the next.