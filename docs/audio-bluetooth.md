# Audio and Bluetooth in the Pistachio Noir Shell

Quickshell 0.3.2 already wraps both PipeWire and BlueZ, so the shell needs no `pactl` or `bluetoothctl` output parsing. The one gap is BlueZ's pairing agent, which the shell brings itself as a small helper (see "Pairing agent"). The property names below were checked against the 0.3.2 type pages.

## Short answer

Two singletons, `services/Audio.qml` and `services/Bluetooth.qml`, own all the state. Every part of the UI reads from them, so no two parts can disagree.

| Service | Built on | Used by |
| --- | --- | --- |
| `Audio.qml` | `Quickshell.Services.Pipewire` | Bar status chip, quick settings, OSD, launcher System mode |
| `Bluetooth.qml` | `Quickshell.Bluetooth` (BlueZ over DBus), and `pistachio-devices bluetooth` (from `rust/`) for pairing codes | Bar status chip, quick settings, launcher Bluetooth mode and pairing questions |
| Brightness | `ddcutil` through `Process` (DDC/CI to the monitor) | Quick settings, OSD, launcher System mode |

## Audio: Quickshell.Services.Pipewire

`Audio.qml` binds the default sink and source with a `PwObjectTracker`, because volume and mute read as invalid on unbound nodes. It exposes `volume`, `muted`, `setVolume()` (clamped) and the list of output devices.

| Need | What to use | Note |
| --- | --- | --- |
| Default output and input | `Pipewire.defaultAudioSink`, `defaultAudioSource` | Read-only, and can be `null` briefly when the default changes, so guard for it |
| Switch output device | `Pipewire.preferredDefaultAudioSink` | A hint to PipeWire, so the UI shows what `defaultAudioSink` actually reports |
| Volume, mute, per-channel volume | `node.audio.volume`, `.muted`, `.volumes` | Writable, but only valid when the node is bound with `PwObjectTracker { objects: [...] }` |
| Device list and per-app mixer | `Pipewire.nodes` filtered by `isSink` and `isStream` | `Pipewire.ready` turns true once the first sync with PipeWire is done |
| Switch input device | `Pipewire.preferredDefaultAudioSource` | As for outputs. WirePlumber won't make an input the default while every jack on it reads "not available" (checked: the motherboard's mic and line-in with nothing plugged in); it keeps the configured choice and uses another input. Quickshell doesn't expose jacks, so `Audio` runs `pactl -f json list sources` (ports and their `availability`) at startup and after `pactl subscribe` reports a card or source event, and the launcher greys such inputs out |

## Bluetooth: Quickshell.Bluetooth

`Bluetooth.qml` wraps `Bluetooth.defaultAdapter` and exposes a sorted device list (connected first, then paired, then nearby), the `powered` state and the actions. Use `defaultAdapter.devices` for the full list, because the docs describe `Bluetooth.devices` as connected devices only.

| Object | Properties | Functions |
| --- | --- | --- |
| `BluetoothAdapter` | `enabled` (power switch), `discovering` (scan), `devices`, `state`, `discoverable`, `pairable`, `name` | None documented |
| `BluetoothDevice` | `name`, `deviceName`, `icon`, `address`, `paired`, `bonded`, `connected`, `trusted`, `blocked`, `state`, `pairing`, `battery`, `batteryAvailable` | `connect()`, `disconnect()`, `pair()`, `cancelPair()`, `forget()` |

Scanning only runs while the launcher's Bluetooth view is open (built in phase 6). It stops on close or after 60 s, so the radio is not left scanning. Nearby devices whose name is just their address (anonymous BLE beacons) are hidden.

### Pairing agent

Quickshell 0.3.2 has no pairing agent (checked: no agent, PIN or passkey type in `Quickshell.Bluetooth`, and nothing on `BluetoothDevice` beyond `pair()` and `cancelPair()`). Without one, BlueZ can't ask for or show a code, so keyboards and phones would not pair. The shell brings its own:

- **`pistachio-devices bluetooth`** (`rust/devices/src/bluetooth.rs`; Python until 12 November 2026, same protocol) registers an `org.bluez.Agent1` object with `AgentManager1.RegisterAgent` (capability `KeyboardDisplay`, so BlueZ can use every method) and makes it the default with `RequestDefaultAgent`. It is a helper process, because QML has no way to serve a D-Bus object. It watches `org.bluez` and registers again when bluetoothd restarts, answers only calls from bluetoothd, and exits when its stdin closes, so it never outlives the shell.
- **`Bluetooth.qml`** runs it while an adapter exists and talks JSON lines with it: questions come out on stdout, answers go back on stdin (the protocol is at the top of the script). It holds the question waiting for an answer as `request`, and `answer(accept, value)` replies. Accepting a pairing also trusts the device, as `pair()` does. Questions that arrive while the screen is locked are declined at once, and locking declines one that waits.
- **The launcher** shows the question in place of the results, as it does a power question, and opens in the Bluetooth view for it. Cancel is chosen first. Closing the launcher declines.

| BlueZ asks | When | The launcher shows |
| --- | --- | --- |
| `RequestConfirmation` | most phones and newer devices: both sides show a 6-digit code | "Pair with …?", the code, Cancel / Pair |
| `RequestAuthorization` | a device starts a pairing that needs no code | "Pair with …?", Decline / Pair |
| `AuthorizeService` | a paired but untrusted device asks to use a service | "Let … use audio?" (the service from its UUID), Decline / Allow |
| `RequestPinCode`, `RequestPasskey` | the device shows a code, or an old one has a fixed PIN | typed into the search field (a PIN takes 1 to 16 letters and digits, a passkey up to 6 digits), Enter sends it |
| `DisplayPinCode`, `DisplayPasskey` | keyboards: type the shown code on the keyboard | the code, with a pistachio cursor under the next key once the keyboard reports keys typed; it goes when the device has paired or BlueZ sends `Cancel` |

BlueZ asks one question at a time, and a request that is not answered fails after BlueZ's own timeout, which sends `Cancel`. The bus policy (`/usr/share/dbus-1/system.d/bluetooth.conf`) lets only root call `Agent1` methods, so `tests/bluetooth-agent.sh` runs the agent with `--session` on the session bus and asks it every kind of question with `gdbus`. The last agent to ask to be the default wins, and when it goes, BlueZ falls back to the one before, so the shell takes over from another agent (KDE's, for example) while it runs.

## Brightness and OSD

Brightness is the one thing Quickshell has no module for. This desktop has no `/sys/class/backlight`, so `brightnessctl` has nothing to drive; `services/Brightness.qml` talks to the monitor over DDC/CI with `ddcutil` instead (checked in phase 4: `ddcutil getvcp 10 --brief` prints `VCP 10 C <current> <max>`, no root needed, about 0.2 s per call). It runs one `ddcutil` at a time and sends only the latest value of a slider drag. Changes made with the monitor's own buttons show up the next time quick settings opens.

- **Volume keys:** the Hyprland keybinds call `wpctl` directly. The OSD reacts to the PipeWire change, so it doesn't need to know who caused it.
- **OSD hygiene:** skip the startup and sink-changed moments so the OSD doesn't flash when the default device changes. The volume change arrives before the device change, so the OSD checks a tick later (tested in phase 7 by switching outputs). A switch shows the new device instead (built after phase 8): its name, a headphones or speaker icon (from `device.form-factor` or `device.icon-name`; a Bluetooth output has neither, only its device does, which Quickshell doesn't expose, so BlueZ's `icon` for the device at `api.bluez5.address` decides) and its volume. The default output is briefly null in between, so a switch is a change of node name, and the first output after startup isn't one.
- **Microphone OSD** (owner's request, after phase 8): the OSD names the apps in `Audio.recorders` when one starts recording, and says when the last has stopped. A change counts once it has held for a second (browsers and voice apps open the mic briefly to look at devices; tested with a 0.4 s `pw-cat` capture, which showed nothing), and the apps recording at startup aren't news. It ignores Do not disturb, fullscreen and quick settings being open: it's a privacy cue.
- **Brightness keys:** the keybinds call `qs -c pistachio ipc call brightness up` (or `down`), 5 % a step, so the shell changes the value and shows the OSD itself. The stock Hyprland config binds them to `brightnessctl`, which does nothing here.

Night light has no Quickshell module either. It uses `hyprsunset` (checked against the Hyprland wiki in phase 4): `services/NightLight.qml` runs `hyprsunset --temperature <K>` itself while night light is on, changes the warmth with `hyprctl hyprsunset temperature <K>`, and stops the process to turn it off. So it needs no autostart line; do not also autostart hyprsunset, or the shell's copy exits and the tile turns off. The quick settings design has a Night light tile plus a warmth slider (2500 K to 6500 K) that appears while it is on.

## What to install on Arch

| Area | Packages | Also needed |
| --- | --- | --- |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse` | `pipewire-pulse` keeps apps that still use PulseAudio working |
| Bluetooth | `bluez`, `bluez-utils`; the pairing agent is built by `install.sh` | `bluetooth.service` enabled and running |
| Brightness | `ddcutil` | the `i2c-dev` kernel module loaded; the monitor's DDC/CI setting on |
| Night light | `hyprsunset` | None: the shell starts it |

## Not confirmed yet

These three were open when the plan was written; all are settled now.

- [x] **PIN prompts:** Quickshell has no pairing agent, so the shell runs its own (see "Pairing agent" above). Built after phase 8. The protocol, the launcher's questions, and the lock and close behaviour were checked against a copy of the shell whose agent ran on the session bus. Pairing with a real device that shows or asks for a code is still to be tried.
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
- [Process](https://quickshell.org/docs/v0.3.2/types/Quickshell.Io/Process) (opened on 2026-10-26, for the pairing agent)

BlueZ's D-Bus API, opened on 2026-10-26:

- [org.bluez.Agent1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst)
- [org.bluez.AgentManager1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.AgentManager.rst)
