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
  session environment. Without it KAIROS still runs; the workspace matrix and
  the `WKSP` chip simply report an honest offline state.

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
    `○ link` during outages) — no fabricated data.
  - The TopHUD **WKSP** chip now reads the compositor-native index correctly
    (Niri is 1-based), `--` while the link is down. `Settings.showWorkspacePanel`
    toggles the panel; retry cadence is `niriRetryMinMs` / `niriRetryMaxMs` /
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
  media, notifications, lock, power UI.
