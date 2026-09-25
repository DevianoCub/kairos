# KAIROS

A fictional-system desktop shell for **NixOS** + Wayland compositors, built on
**Quickshell / QtQuick / QML**. KAIROS presents your desktop as the control
interface of a fictional machine: dense, technical, asymmetrical, and state-aware.

The visual language is inspired by Evangelion-style technical interfaces,
Ghost in the Shell / cyberpunk system HUDs, spacecraft cockpits and industrial
instrumentation — but KAIROS has its **own identity**, its own terminology and
its own architecture. Nothing is copied from existing projects.

Showcase
--------------------
<img width="1920" height="1165" alt="image" src="https://github.com/user-attachments/assets/72094884-e87e-4585-9191-b1069fceedf2" />


-----------------------


Initial targets:

- Compositor: **Niri**, **MangoWM** (any layer-shell capable Wayland compositor)
- Display protocol: **Wayland**
- UI: **Quickshell 0.3.x / QtQuick / QML**

## Requirements

- Quickshell 0.3.1 (available in Nixpkgs)
- A Wayland compositor that supports the layer-shell protocol
  (Niri, MangoWM, wlroots-based compositors, …)
- Standard coreutils available in `$PATH` (`sh`, `awk`, `/proc` readable)
- **Niri IPC (optional, v0.3+):** Niri ≥ 26 with `NIRI_SOCKET` exported in the
  session environment. Without it KAIROS still runs; the workspace state
  consumers (the contextual active-window layer) simply report an honest
  offline state.

## Install / Run

Place this repository at:

```text
~/.config/quickshell/kairos/
```

Then run from inside your Wayland session:

```bash
qs -c kairos
# or
quickshell -c kairos
```

Launch it from your compositor's startup. Example for Niri:

```kdl
spawn-at-startup "qs" "-c" "kairos"
```

## Configuration

Two singleton modules centralize the shell:

- `config/Theme.qml` — palette, fonts, typography scale, geometry, motion.
  Every color and size flows from here.
- `config/Settings.qml` — runtime behavior: HUD height, refresh rate,
  clock/date format, exclusive zone.

Set `exclusiveZone` in `Settings.qml` to `> 0` to make the HUD reserve screen
space (pushes windows down); the default of `0` keeps KAIROS a pure overlay.

## Compositor support

| Backend | Status |
| --- | --- |
| **Niri** | **SUPPORTED** — read-only IPC via the raw `NIRI_SOCKET` EventStream (workspaces, windows, focus, occupancy, reconnect) |
| Hyprland / Sway / River / labwc / … | **PLANNED** — architected for, not implemented |
| MangoWM | **NOT IMPLEMENTED (no desktop-state backend)** — detected as the running compositor by `SystemService`, but KAIROS exposes no workspace state and never pretends otherwise |

Portability is an architectural seam, not a feature yet: the UI consumes the
common `CompositorService` contract (`services/compositor/`); the Niri
implementation (`NiriBackend.qml`) fills it. Implementing another compositor
means writing one backend, not touching the UI.

## Current state

- **v0.5** — **top-left workspace matrix removed**: the per-screen
  `panels/WorkspacePanel.qml` strip is deleted. The bottom rail is now the
  single workspace indicator (identity + WS id + clock), so the desktop isn't
  duplicated top-left/bottom. The TopHUD stays.
- **v0.4** — **contextual active-window UX** (single global surface, not
  per-output):
  - **Bottom contextual rail** (`panels/BottomRail.qml`) — one full-width
    strip; invisible by default (a 12 px transparent hover strip only);
    revealed by hovering the bottom edge, by a focused-window / workspace
    change (forced reveal, auto-dismissed after `railRevealMs`), or stays
    open while the pointer is on it. Shows window identity, the display
    **workspace id**, and the clock. Disconnect reverts it to the bare strip.
    A single bottom anchor + `exclusiveZone: heightNow` keeps it pinned to the
    true bottom edge through hide/reveal cycles.
  - **Focus capsule** (`panels/FocusCapsule.qml`) — a small floating sheet
    near the bottom center that answers a focused-window or workspace change
    for `focusCapsuleMs` (~2.5 s), then fades out. Workspace-only switches on
    empty workspaces render a `WORKSPACE 04` variant. It is non-focusable and
    tiny, so its brief input footprint is negligible.
  - **`components/FocusPulse.qml`** — the single global controller: a
    fingerprint of the focused output (`focused window id | display
    workspace`), `pulse++` only on a *logical* target change. **Title-only
    edits update in place without replaying the entrance animation.**
    Disconnect zeros the fingerprint and hides both instruments; reconnect
    repopulates with a single pulse.
  - Both instruments bind their `screen` to the focused workspace's output, so
    the single capsule/rail follows the user instead of being duplicated per
    monitor. The permanent TopHUD **WKSP chip is removed** — workspace
    association is now conveyed contextually by the rail/capsule, keeping the
    idle desktop clean.
  - Still consumes only the common `CompositorService` contract; no
    Niri-specific dependency in any visual component. The `WindowIdentity`
    row (monogram tile, appId, elided title) is shared by rail and capsule and
    is reusable for the future right-side contextual drawer.
- **v0.3.1** — **hardened Niri integration + compositor seam**:
  - `services/compositor/CompositorService.qml` — the **common desktop-state
    contract** the UI binds to: `connected`, `connectionState`,
    `workspaces` (index, name?, output, active/focused/urgent/occupied),
    `activeWorkspaces`, `focusedWorkspace`, `activeWorkspace`, `windows`
    (appId, title, workspaceId, output, focused), `focusedWindow`, `outputs`,
    plus compositor-agnostic helpers (`workspacesFor`, `displayColumnFor`,
    `displayIndexFor`, `workspaceLabel`).
  - `services/compositor/NiriBackend.qml` — the **Niri implementation** of
    that contract: raw `NIRI_SOCKET` EventStream, authoritative full-state
    rebuilds, optimistic focus moves, window patch events, and a lifecycle of
    `disconnected / connecting / connected / reconnecting / error /
    unsupported` with exponential-backoff reconnect. Never issues commands.
  - `panels/WorkspacePanel.qml` — per-screen matrix under the HUD: thin
    per-column status rails (active = accent, occupied = strong, urgent =
    warning, idle = quiet), `▲` caret + `ACTIVE` tag, and restrained offline
    readouts (`◦ no backend` when no compositor is supported, `○ offline` /
    `○ link` during outages) — no fabricated data. **Removed in v0.5** (see
    Current state); the bottom rail is now the single workspace indicator.
  - The TopHUD **WKSP** chip (added in v0.3) read the compositor-native index
    correctly — Niri is 1-based — and showed `--` while the link was down.
    (As of v0.4 the chip is removed: the downlink state is honest, but the
    desktop stays quiet; workspace association now lives in the contextual
    rail/capsule.) The retry cadence is `niriRetryMinMs` / `niriRetryMaxMs` /
    `niriRetryIdleMs`.
- **v0.3** — Niri IPC + workspace matrix (superseded by the v0.3.1 backend).
- **v0.2** — Top HUD overlay on every screen: identity, status, compositor
  link, MEM / LOAD / UPTIME / CLOCK plus **system telemetry**:
  - **CPU** — segmented gauge + busy % from `/proc/stat` deltas.
  - **NET** — RX/TX rate (auto-detected interface) from `/proc/net/dev`
    deltas, with a self-scaling history sparkline.
  - **TMP** — max on-die temperature from Linux thermal zones.
  - Derived status (`ONLINE` / `CAUTION` / `CRITICAL`) from real thresholds.
- Planned: GPU/DISK/BATTERY telemetry, command interface, control center,
  right-side contextual drawer, media, notifications, lock, power UI.
