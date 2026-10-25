# Audio and Bluetooth in the Pistachio Noir Shell

Quickshell 0.3.2 already wraps both PipeWire and BlueZ, so the shell needs no separate integrations and no `pactl` or `bluetoothctl` output parsing. The property names below were checked against the 0.3.2 type pages.

## Short answer

Two singletons, `services/Audio.qml` and `services/Bluetooth.qml`, own all the state. Every part of the UI reads from them, so no two parts can disagree.

| Service | Built on | Used by |
| --- | --- | --- |
| `Audio.qml` | `Quickshell.Services.Pipewire` | Bar status chip, quick settings, OSD, launcher System mode |
| `Bluetooth.qml` | `Quickshell.Bluetooth` (BlueZ over DBus) | Bar status chip, quick settings, launcher Bluetooth mode |
| Brightness | `ddcutil` through `Process` (DDC/CI to the monitor) | Quick settings, OSD, launcher System mode |

## Audio: Quickshell.Services.Pipewire

`Audio.qml` binds the default sink and source with a `PwObjectTracker`, because volume and mute read as invalid on unbound nodes. It exposes `volume`, `muted`, `setVolume()` (clamped) and the list of output devices.

| Need | What to use | Note |
| --- | --- | --- |
| Default output and input | `Pipewire.defaultAudioSink`, `defaultAudioSource` | Read-only, and can be `null` briefly when the default changes, so guard for it |
| Switch output device | `Pipewire.preferredDefaultAudioSink` | A hint to PipeWire, so the UI shows what `defaultAudioSink` actually reports |
| Volume, mute, per-channel volume | `node.audio.volume`, `.muted`, `.volumes` | Writable, but only valid when the node is bound with `PwObjectTracker { objects: [...] }` |
| Device list and per-app mixer | `Pipewire.nodes` filtered by `isSink` and `isStream` | `Pipewire.ready` turns true once the first sync with PipeWire is done |

## Bluetooth: Quickshell.Bluetooth

`Bluetooth.qml` wraps `Bluetooth.defaultAdapter` and exposes a sorted device list (connected first, then paired, then nearby), the `powered` state and the actions. Use `defaultAdapter.devices` for the full list, because the docs describe `Bluetooth.devices` as connected devices only.

| Object | Properties | Functions |
| --- | --- | --- |
| `BluetoothAdapter` | `enabled` (power switch), `discovering` (scan), `devices`, `state`, `discoverable`, `pairable`, `name` | None documented |
| `BluetoothDevice` | `name`, `deviceName`, `icon`, `address`, `paired`, `bonded`, `connected`, `trusted`, `blocked`, `state`, `pairing`, `battery`, `batteryAvailable` | `connect()`, `disconnect()`, `pair()`, `cancelPair()`, `forget()` |

Scanning only runs while the launcher's Bluetooth view is open (built in phase 6). It stops on close or after 60 s, so the radio is not left scanning. Nearby devices whose name is just their address (anonymous BLE beacons) are hidden.

## Brightness and OSD

Brightness is the one thing Quickshell has no module for. This desktop has no `/sys/class/backlight`, so `brightnessctl` has nothing to drive; `services/Brightness.qml` talks to the monitor over DDC/CI with `ddcutil` instead (checked in phase 4: `ddcutil getvcp 10 --brief` prints `VCP 10 C <current> <max>`, no root needed, about 0.2 s per call). It runs one `ddcutil` at a time and sends only the latest value of a slider drag. Changes made with the monitor's own buttons show up the next time quick settings opens.

- **Volume keys:** the Hyprland keybinds call `wpctl` directly. The OSD reacts to the PipeWire change, so it doesn't need to know who caused it.
- **OSD hygiene:** skip the startup and sink-changed moments so the OSD doesn't flash when the default device changes. The volume change arrives before the device change, so the OSD checks a tick later (tested in phase 7 by switching outputs).
- **Brightness keys:** the keybinds call `qs -c pistachio ipc call brightness up` (or `down`), 5 % a step, so the shell changes the value and shows the OSD itself. The stock Hyprland config binds them to `brightnessctl`, which does nothing here.

Night light has no Quickshell module either. It uses `hyprsunset` (checked against the Hyprland wiki in phase 4): `services/NightLight.qml` runs `hyprsunset --temperature <K>` itself while night light is on, changes the warmth with `hyprctl hyprsunset temperature <K>`, and stops the process to turn it off. So it needs no autostart line; do not also autostart hyprsunset, or the shell's copy exits and the tile turns off. The quick settings design has a Night light tile plus a warmth slider (2500 K to 6500 K) that appears while it is on.

## What to install on Arch

| Area | Packages | Also needed |
| --- | --- | --- |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse` | `pipewire-pulse` keeps apps that still use PulseAudio working |
| Bluetooth | `bluez`, `bluez-utils` | `bluetooth.service` enabled and running |
| Brightness | `ddcutil` | the `i2c-dev` kernel module loaded; the monitor's DDC/CI setting on |
| Night light | `hyprsunset` | None: the shell starts it |

## Not confirmed yet

Three items are still open, and each gets checked when its build phase starts.

- [ ] **PIN prompts:** the docs I read show no pairing agent. Headphones and mice that pair without a code should work. A keyboard that shows a passkey might need a `bluetoothctl` fallback.
- [x] **Per-app volumes:** checked after phase 8 with a `pw-cat` stream: an app's playback (`media.class` `Stream/Output/Audio`) reads `isStream: true` and `isSink: true`, the opposite of what the `isSink` description suggests. `Audio.streams` uses that; the launcher's System view lists them under Apps.
- [x] **Brightness IPC:** checked in phase 1. An `IpcHandler` (`Quickshell.Io`) with a `target` exposes functions with typed arguments; the keybind runs `qs ipc call <target> <function> <args>`.

## Sources

Quickshell 0.3.2 type pages, opened on 2026-10-25:

- [Pipewire](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.Pipewire/Pipewire)
- [PwNodeAudio](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.Pipewire/PwNodeAudio)
- [PwObjectTracker](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.Pipewire/PwObjectTracker)
- [Bluetooth](https://quickshell.org/docs/v0.3.2/types/Quickshell.Bluetooth/Bluetooth)
- [BluetoothAdapter](https://quickshell.org/docs/v0.3.2/types/Quickshell.Bluetooth/BluetoothAdapter)
- [BluetoothDevice](https://quickshell.org/docs/v0.3.2/types/Quickshell.Bluetooth/BluetoothDevice)
