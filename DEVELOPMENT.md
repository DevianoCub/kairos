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

A clean startup prints the `[KAIROS] v0.3 online` line and no `TypeError` /
`is not defined` / binding-loop warnings. If the link to Niri is down you will
see a single `[KAIROS] niri: link lost (...), retrying` warning per drop
(paired with a `quickshell.io.socket` warn), then silent backoff retries.

## Add a component

1. Create `components/Foo.qml`.
2. Base it on an existing primitive (`HudText`, `Rectangle`, `Item`, …).
3. Pull every color/size from `Theme`; never hardcode hex.
4. Import with `import "../config"` and `import "../components"`.
5. Use it from a panel — an unused component is dead weight.

Components are presentational: they must not poll services or run commands.

## Add a service

1. Create `services/FooService.qml` as a `QtObject` (`QtQml`) — or an `Item`
   when the service hosts child objects (e.g. `NiriService` owns a `Socket`
   + `SplitParser` + `Timer`).
2. Expose only live `property` state.
3. Own your own `Timer`/`Process`; choose coarse intervals
   (`Settings.fastInterval` / `slowInterval`).
4. Degrade gracefully — when data is missing, set `N/A` / `OFF`, never throw.
5. Instanciate it once in `shell.qml` and inject it into panels.

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

`NiriService` is a pure IPC client, so you can (and should) exercise it against
a fake compositor before touching a real session:

1. Serve the EventStream protocol on a fake socket (niri-ipc ≥ 26.4 schema):
   accept the connection, read the `"EventStream"` request line, stream
   newline-delimited JSON — `ConfigLoaded`, `WorkspacesChanged`, `WindowsChanged`,
   then `WorkspaceActivated {id, focused}` moves, etc.
2. Run with `NIRI_SOCKET=/tmp/fake.sock qs -c kairos -v`.
3. Confirm: `[KAIROS] niri: linked`, matrix cells track focus (`▲` caret),
   closing the socket triggers `link lost ... retrying`, and restarting the
   socket yields a clean relink with fresh full state.

On a real Niri session the workflow is identical but keys off `WS1`/`WS2`…
focus moves and confirms the output names in the panel match `Screen.name`.

## Milestones

- v0.1 top HUD (base identity + metrics)
- v0.2 system telemetry — CPU/NET/TMP via `/proc` deltas + Gauge/Graph
- v0.3 Niri IPC + workspace matrix (current)
- v0.4+ GPU/DISK/BATTERY, command interface, control center, media,
  notifications, lock, power

Implement in order; validate each milestone before starting the next.