# KAIROS

A fictional-system desktop shell for **NixOS** + Wayland compositors, built on
**Quickshell / QtQuick / QML**. KAIROS presents your desktop as the control
interface of a fictional machine: dense, technical, asymmetrical, and state-aware.

The visual language is inspired by Evangelion-style technical interfaces,
Ghost in the Shell / cyberpunk system HUDs, spacecraft cockpits and industrial
instrumentation — but KAIROS has its **own identity**, its own terminology and
its own architecture. Nothing is copied from existing projects.

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
  the `WKSP` chip simply stay offline.

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

## Current state

- **v0.3** — **Niri IPC + workspace matrix**:
  - `services/NiriService.qml` — read-only bridge to the Niri compositor.
    Speaks the raw `NIRI_SOCKET` EventStream directly, exposes structured
    workspace/window state, does optimistic focus moves, and reconnects with
    exponential backoff. Never issues commands to Niri.
  - `panels/WorkspacePanel.qml` — per-screen matrix hanging under the HUD:
    cells (focused / active / occupied / urgent), a sliding `▲` caret and
    accent rail, and a restrained `niri ○ offline` state when Niri is absent —
    no fabricated data.
  - The TopHUD gains a **WKSP** chip showing the current workspace index per
    screen (`--` while offline). `Settings.showWorkspacePanel` toggles the
    panel; retry cadence is `Settings.niriRetryMinMs` / `niriRetryMaxMs`.
- **v0.2** — Top HUD overlay on every screen: identity, status, compositor
  link, MEM / LOAD / UPTIME / CLOCK plus **system telemetry**:
  - **CPU** — segmented gauge + busy % from `/proc/stat` deltas.
  - **NET** — RX/TX rate (auto-detected interface) from `/proc/net/dev`
    deltas, with a self-scaling history sparkline.
  - **TMP** — max on-die temperature from Linux thermal zones.
  - Derived status (`ONLINE` / `CAUTION` / `CRITICAL`) from real thresholds.
- Planned: GPU/DISK/BATTERY telemetry, command interface, control center,
  media, notifications, lock, power UI.