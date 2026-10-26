#!/bin/bash
# Self-check that the quick settings services change real system state: volume and per-app volume (PipeWire),
# Bluetooth power and the pairing agent (BlueZ), monitor brightness (DDC/CI) and night light (hyprsunset, if installed).
# Everything is put back on exit. Ethernet is only read: toggling it would cut the network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)/harness"

ipc() { qs -p "$ROOT" ipc call services "$@"; }
# check <python condition over s (service state)> <label>
check() {
    ipc state | python3 -I -c "import json, sys; s = json.load(sys.stdin); assert $1, s" \
        || { echo "FAIL: $2"; exit 1; }
    echo "ok: $2"
}
# expect <label> <command...>: the command must succeed
expect() {
    local label=$1; shift
    "$@" > /dev/null || { echo "FAIL: $label"; exit 1; }
    echo "ok: $label"
}

VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
MUTED=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo 1 || echo 0)
BT_POWERED=$(bluetoothctl show | grep -q 'Powered: yes' && echo on || echo off)
BRIGHTNESS=$(ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}' || true)
SINK=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | awk -F'"' '/node.name =/ { print $2; exit }')
restore() {
    ipc setSink "$SINK" > /dev/null 2>&1 || true
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$VOLUME"
    wpctl set-mute @DEFAULT_AUDIO_SINK@ "$MUTED"
    bluetoothctl power "$BT_POWERED" > /dev/null
    if [ -n "$BRIGHTNESS" ]; then ddcutil setvcp 10 "$BRIGHTNESS" --noverify; fi
    if [ -n "${STREAM_PID:-}" ]; then kill "$STREAM_PID" 2>/dev/null || true; fi
    kill "$SHELL_PID" 2>/dev/null || true
}

qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
trap restore EXIT
sleep 3

ETHERNET=$(nmcli -t -f TYPE,STATE device | grep -qx 'ethernet:connected' && echo True || echo False)
check "s['ethernet'] == $ETHERNET and (s['speed'] > 0) == $ETHERNET" "Ethernet state matches NetworkManager"
check "abs(s['uptime'] - float(open('/proc/uptime').read().split()[0])) < 90" "uptime matches /proc/uptime"

ipc setVolume 0.42; sleep 0.5
expect "volume set to 0.42" sh -c "wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -qx 'Volume: 0.42'"
check "abs(s['volume'] - 0.42) < 0.01 and not s['muted']" "service reports 0.42, unmuted"

check "s['agent']" "pairing agent registered with BlueZ"
ipc setBluetooth false; sleep 2
expect "Bluetooth powered off" sh -c "bluetoothctl show | grep -q 'Powered: no'"
ipc setBluetooth true; sleep 2
expect "Bluetooth powered on" sh -c "bluetoothctl show | grep -q 'Powered: yes'"
check "s['agent']" "pairing agent still registered"

if [ -n "$BRIGHTNESS" ]; then
    ipc setBrightness 0.6; sleep 2
    expect "monitor brightness set to 60" sh -c "ddcutil getvcp 10 --brief | grep -q '^VCP 10 C 60 '"
else
    echo "skip: no DDC/CI monitor"
fi

ipc setDnd true
check "s['dnd']" "do not disturb on"
ipc setDnd false

if ipc state | grep -q '"nightLightAvailable":true'; then
    ipc setNightLight true; sleep 1
    expect "hyprsunset running" pgrep -x hyprsunset
    ipc setTemperature 3000; sleep 1
    check "s['nightLight'] and s['temperature'] == 3000" "warmth 3000 K"
    expect "hyprsunset applied 3000 K" sh -c "[ \"\$(hyprctl hyprsunset temperature)\" = 3000 ]"
    ipc setNightLight false; sleep 1
    expect "hyprsunset stopped" sh -c "! pgrep -x hyprsunset"

    # the schedule: a window around now switches it on, one that leaves now out switches it off
    NOW=$(( $(date +%-H) * 60 + $(date +%-M) ))
    ipc setNightSchedule true $(( NOW - 30 )) $(( NOW + 30 )); sleep 1
    check "s['nightLight'] and s['inSchedule']" "a schedule around now turns night light on"
    expect "hyprsunset running for the schedule" pgrep -x hyprsunset
    ipc setNightSchedule true $(( NOW + 60 )) $(( NOW + 120 )); sleep 1
    check "not s['nightLight'] and not s['inSchedule']" "a schedule away from now turns it off"
    ipc setNightSchedule false 1200 420; sleep 0.5
else
    echo "skip: hyprsunset not installed"
fi

# Output device: switch to another one and back (audio moves for about a second).
OTHER=$(python3 -I -c "import json, sys; print(next((s for s in json.loads(sys.argv[1]) if s != sys.argv[2]), ''))" "$(ipc sinks)" "$SINK")
if [ -n "$OTHER" ]; then
    ipc setSink "$OTHER"; sleep 1
    expect "default output switched" sh -c "wpctl inspect @DEFAULT_AUDIO_SINK@ | grep -q 'node.name = \"$OTHER\"'"
    ipc setSink "$SINK"; sleep 1
    expect "default output switched back" sh -c "wpctl inspect @DEFAULT_AUDIO_SINK@ | grep -q 'node.name = \"$SINK\"'"
else
    echo "skip: only one output device"
fi

# A Terminal=true app opens in a terminal window (which is then closed again).
APP=$(ipc terminalApp)
if [ -n "$APP" ]; then
    addresses() { hyprctl clients -j | python3 -I -c "import json, sys; print(' '.join(c['address'] for c in json.load(sys.stdin)))"; }
    BEFORE=$(addresses)
    ipc launch "$APP"; sleep 2
    NEW=$(python3 -I -c "import sys; b = set(sys.argv[1].split()); print(next((a for a in sys.argv[2].split() if a not in b), ''))" "$BEFORE" "$(addresses)")
    [ -n "$NEW" ] || { echo "FAIL: $APP opened no window"; exit 1; }
    echo "ok: $APP opened in a terminal window"
    qs -p "$ROOT" ipc call compositor close "${NEW#0x}"
else
    echo "skip: no Terminal=true app installed"
fi

# Per-app volume: a silent test stream (pw-cat playing zeros) gets its own volume and mute.
cat /dev/zero | pw-cat -p -a --format s16 --rate 48000 --channels 2 -P '{ application.name = "pistachio-test" }' - 2>/dev/null &
STREAM_PID=$!
sleep 1.5
check "'pistachio-test' in s['streams']" "test stream listed as an app"
STREAM_ID=$(pw-dump | python3 -I -c "import json, sys; print(next(o['id'] for o in json.load(sys.stdin) if o.get('info', {}).get('props', {}).get('application.name') == 'pistachio-test'))")
ipc setStreamVolume pistachio-test 0.3; sleep 0.5
expect "app volume set to 0.30" sh -c "wpctl get-volume $STREAM_ID | grep -qx 'Volume: 0.30'"
ipc toggleStreamMute pistachio-test; sleep 0.5
expect "app muted" sh -c "wpctl get-volume $STREAM_ID | grep -q MUTED"
expect "default output untouched" sh -c "wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -qx 'Volume: 0.42'"

# Settings survive a restart (the test shell keeps its own state file, not the real shell's).
ipc setDnd true; sleep 0.8 # saved 300 ms after a change
kill "$SHELL_PID"; wait "$SHELL_PID" 2>/dev/null || true
qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
sleep 3
check "s['dnd']" "do not disturb kept across a restart"
ipc setDnd false; sleep 0.8

echo "all passed"
