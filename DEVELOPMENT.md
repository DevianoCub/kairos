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

A clean startup prints the `[KAIROS] v0.5 online` line and no `TypeError` /
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

1. The Top HUD is per-screen: root type is `PanelWindow`
   with `required property var modelData` + `screen: modelData` inside
   `Variants`.
2. The contextual layer is **single-global**: one `BottomRail`, one
   `FocusPulse`. Panels bind `screen: pulse.targetScreen`
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
  where you expect. Make the rail a pure overlay with
  `exclusiveZone: 0` (the setter forces exclusion-mode `Normal`, i.e. zero
  reservation) so it never competes for the edge and never moves application
  windows; the top HUD is the one surface that reserves (via
  `Settings.exclusiveZone`).
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

Verify the single v0.4 surface (`BottomRail`) without touching it visually:

Each reveal/hide must appear in the log as a state transition
(`[Rail] HIDDEN -> FORCED_REVEAL reason=focus-change`, `-> HIDDEN
reason=timer`, `HOVER_REVEAL -> HIDE_PENDING`, …).

1. **Idle clean** — with KAIROS running, the only bottom artifact is a
   transparent 12 px strip; no permanent active-window panel, no floating
   capsule, no chip. Nothing else is on screen over the wallpaper.
2. **Zero work-area** — before revealing, record a focused window's geometry
   (`niri msg -j windows`); after a forced reveal it must be byte-identical.
   The rail is an overlay (`exclusiveZone: 0`); windows never move.
3. **Forced reveal auto-hide** — `focus-workspace <n>` / `focus-window --id
   <n>` force-reveals the rail (window variant, or `WORKSPACE` on an empty
   workspace). WITHOUT touching the mouse, it must hide after ~3 s. Repeat
   several times.
4. **Hover keeps it visible** — force-reveal, then move the pointer into the
   rail before 3 s: it stays visible (state leaves `FORCED_REVEAL` only when
   the timer fires). Move the pointer away: `HOVER_REVEAL -> HIDE_PENDING`,
   then `-> HIDDEN` after `railHoverGraceMs`.
5. **No replay on non-change** — a title-only edit (retitle the focused
   window) must NOT pulse: no `[Rail]` reveal, the reveal timer is not
   restarted, text in an already-revealed rail updates in place.
6. **Reconnect without change** — restart the backend socket; if the focused
   target is unchanged there is no reveal. A genuinely new target pulses once.
7. **Determinism under stress** — repeatedly switch `ws1→ws2→ws3→ws1` and
   repeatedly `focus-window` between two windows; the rail must reveal and
   dismiss identically every cycle. Any log line where two timers fight over
   visibility is a bug.

## Test the v0.5 app launcher

The launcher is fully exercisable without sending a keystroke: the IpcHandler
target `kairos` exposes `toggleLauncher`, `launcherQuery(text)`,
`launcherMove(dir)` and `launcherRun()` that invoke the exact keyboard code
paths. All canonical driver commands:

```bash
qs ipc -c kairos call kairos toggleLauncher
qs ipc -c kairos call kairos launcherQuery kit
qs ipc -c kairos call kairos launcherMove -1
qs ipc -c kairos call kairos launcherRun
```

1. **Clean start** — restart (`bash /tmp/relaunch.sh`); log shows
   `[KAIROS] v0.5 online`, `niri: linked`, exactly one
   `[Launcher] desktop index: N apps` and no warnings. `niri msg -j layers`
   reports exactly **2** `quickshell` surfaces at rest.
2. **Ephemerality** — `toggleLauncher` opens a **3rd** surface; toggling or
   launching returns to **2**. Rapid double-toggle is a no-op (guard).
3. **Live discovery, no rescan** — `desktop index` appears in the log only on
   startup or a real file change (never per keystroke). While running, write a
   `.desktop` into `~/.local/share/applications/`: the index line reappears
   with the new count and `launcherQuery <new name>` + `launcherRun` launches
   it; remove the file and the count drops back.
4. **Launch flows** — `launcherQuery kit` + `launcherRun` → log
   `[Launcher] launched kitty (kitty)`, a kitty process/window appears, the
   launcher closes itself (`close reason=launch`) and `CommandService`
   triggers the rail (`▶ LAUNCHED kitty`, reveals ~3 s then auto-hides).
5. **Selection** — `launcherMove(-1)` on a non-empty query wraps to the last
   result; a following `launcherRun` launches exactly that app.
6. **Deterministic search** — the ported scorer in
   `python3 /tmp/kairos_sim.py` (prefix/subsequence/soft-signal/tie/empty
   battery, 13 assertions, from the real scoring) must pass; confirm with real
   queries that `fire` → Firefox, `kit` → kitty, empty → first app
   alphabetically, and garbage → `NO MATCH`.
7. **Geometry invariant** — screenshot before and while the launcher is open;
   with the HUD (top) and rail (bottom) bands and the centered palette masked
   out, the application region is pixel-identical (mean diff ≈ 0). The
   launcher is an `exclusiveZone: 0` overlay; no window moves or resizes.
8. **Clean close paths** — `close reason=ipc` (toggle), `close reason=launch`
   (activation), `close reason=escape` (Escape key — code-inspected, since no
   key-injection tool exists on this machine; wtype/ydotool are absent).
   Because `focusable: true` briefly moves keyboard focus to the shell, the
   rail force-reveals with `reason=workspace-change` while typing — expected
   and acceptable.

## Real-session Niri checklist

1. Start KAIROS → banner `v0.5`, `COMPOSITOR NIRI`; no permanent workspace UI,
   no top-left matrix, no floating capsule — the desktop is clean until
   interaction. Bottom edge shows only the 12 px strip.
2. Switch `WS1`…`WS4` → (Niri emits `WorkspaceActivated` only for switches —
   no full reload); the rail reveals (window identity + `WS nn`, or
   `WORKSPACE nn` on empty workspaces) and auto-dismisses.
3. Open/close a window, move one between workspaces → the revealed rail's
   identity row updates.
4. Restart KAIROS → state reconstructs from the first `WorkspacesChanged`;
   the restored window name appears once in the rail.
5. Restart Niri (or kill its socket) → KAIROS survives, reports
   `reconnecting`, the rail hides, and relinks when Niri returns.
6. Bind `Super+Space` (or similar) to
   `qs ipc -c kairos call kairos toggleLauncher`; type a name, Enter to run,
   Escape to dismiss — launch returns keyboard focus to the previous window.

## Milestones

- v0.1 top HUD (base identity + metrics)
- v0.2 system telemetry — CPU/NET/TMP via `/proc` deltas + Gauge/Graph
- v0.3 Niri IPC + workspace matrix
- v0.3.1 hardened Niri backend + compositor seam
- v0.4 contextual active-window UX — one bottom rail; capsule + matrix
  removed (design correction), rail = the single workspace indicator
- v0.5 command center part 1 — app launcher foundation: live XDG discovery,
  deterministic search, safe launch, ephemeral surface, command bus +
  rail feedback, IPC trigger (current)
- v0.5+ command families (volume, brightness, notifications, media),
  control center, GPU/DISK/BATTERY telemetry, right-side contextual drawer,
  lock, power

Implement in order; validate each milestone before starting the next.