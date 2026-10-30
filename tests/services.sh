#!/bin/bash
# Self-check that the quick settings services change real system state: volume, per-app volume and the
# microphone (PipeWire), with the apps recording, the System monitor's readings,
# Bluetooth power and the pairing agent (BlueZ; power is left alone while a device is connected), monitor
# brightness (DDC/CI), Do not disturb's schedule and night light (hyprsunset, if installed), and the
# System monitor's warnings. Everything is put back on exit. Ethernet is only read: toggling it would
# cut the network. The test shell's notify-send is a stand-in that writes to a file, so it never sends
# a real notification.
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
MIC_VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{print $2}')
MIC_MUTED=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo 1 || echo 0)
BT_POWERED=$(bluetoothctl show | grep -q 'Powered: yes' && echo on || echo off)
BRIGHTNESS=$(ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}' || true)
SINK=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | awk -F'"' '/node.name =/ { print $2; exit }')
SOURCE=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ | awk -F'"' '/node.name =/ { print $2; exit }')
# a node's id by its name, or nothing once it's gone
node_id() {
    pw-dump | python3 -I -c "import json, sys; print(next((o['id'] for o in json.load(sys.stdin) if o.get('info', {}).get('props', {}).get('node.name') == sys.argv[1]), ''))" "$1"
}
restore() {
    ipc setSink "$SINK" > /dev/null 2>&1 || true
    # the devices the test started on, not whichever is the default by now (it changed once when
    # Bluetooth power dropped the headphones that were the default)
    local id
    id=$(node_id "$SINK")
    if [ -n "$id" ]; then wpctl set-volume "$id" "$VOLUME"; wpctl set-mute "$id" "$MUTED"; fi
    id=$(node_id "$SOURCE")
    if [ -n "$id" ]; then wpctl set-volume "$id" "$MIC_VOLUME"; wpctl set-mute "$id" "$MIC_MUTED"; fi
    if [ -n "${RECORD_PID:-}" ]; then kill "$RECORD_PID" 2>/dev/null || true; fi
    if [ -n "${READER_PID:-}" ]; then kill "$READER_PID" 2>/dev/null || true; fi
    if [ -n "${CAST_PID:-}" ]; then kill "$CAST_PID" 2>/dev/null || true; fi
    bluetoothctl power "$BT_POWERED" > /dev/null
    if [ -n "$BRIGHTNESS" ]; then ddcutil setvcp 10 "$BRIGHTNESS" --noverify; fi
    if [ -n "${STREAM_PID:-}" ]; then kill "$STREAM_PID" 2>/dev/null || true; fi
    kill "$SHELL_PID" 2>/dev/null || true
    rm -rf "$STUBS"
}

# the stand-in notify-send: one line per notification, in $STUBS/notified
STUBS=$(mktemp -d)
printf '#!/bin/sh\necho "$*" >> "%s/notified"\n' "$STUBS" > "$STUBS/notify-send"
chmod +x "$STUBS/notify-send"
touch "$STUBS/notified"
export PATH="$STUBS:$PATH"

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
if bluetoothctl devices Connected | grep -q .; then
    # powering off drops connected devices, and headphones don't come back by themselves
    echo "skip: Bluetooth power, a device is connected ($(bluetoothctl devices Connected | cut -d' ' -f3- | paste -sd,))"
else
    ipc setBluetooth false; sleep 2
    expect "Bluetooth powered off" sh -c "bluetoothctl show | grep -q 'Powered: no'"
    ipc setBluetooth true; sleep 2
    expect "Bluetooth powered on" sh -c "bluetoothctl show | grep -q 'Powered: yes'"
    check "s['agent']" "pairing agent still registered"
fi

if [ -n "$BRIGHTNESS" ]; then
    ipc setBrightness 0.6; sleep 2
    expect "monitor brightness set to 60" sh -c "ddcutil getvcp 10 --brief | grep -q '^VCP 10 C 60 '"
else
    echo "skip: no DDC/CI monitor"
fi

ipc setDnd true
check "s['dnd']" "do not disturb on"
ipc setDnd false

# Do not disturb's schedule: a window around now switches it on, one that leaves now out switches it
# off, and night light's times do the same once it follows them (night light itself stays off).
NOW=$(( $(date +%-H) * 60 + $(date +%-M) ))
ipc setDndTimes $(( NOW - 30 )) $(( NOW + 30 )); ipc setDndSchedule true; sleep 0.5
check "s['dnd'] and s['inDndSchedule']" "a Do not disturb schedule around now turns it on"
ipc setDndTimes $(( NOW + 60 )) $(( NOW + 120 )); sleep 0.5
check "not s['dnd'] and not s['inDndSchedule']" "one away from now turns it off"
ipc setNightSchedule false $(( NOW - 30 )) $(( NOW + 30 )); ipc setDndFollowsNight true; sleep 0.5
check "s['dnd'] and s['inDndSchedule']" "night light's times around now turn it on once it follows them"
ipc setDndFollowsNight false; ipc setDndSchedule false; ipc setNightSchedule false 1200 420; ipc setDnd false; sleep 0.5
check "not s['dnd'] and not s['dndScheduled']" "schedule off again"

if pgrep -x hyprsunset > /dev/null; then
    # one hyprsunset at a time: the test shell's can't start next to the running shell's
    echo "skip: night light is on in the running shell"
elif ipc state | grep -q '"nightLightAvailable":true'; then
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

# The microphone: its level and mute reach PipeWire.
ipc setMicVolume 0.37; sleep 0.5
expect "mic level set to 0.37" sh -c "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -qx 'Volume: 0.37'"
check "abs(s['micVolume'] - 0.37) < 0.01 and not s['micMuted']" "service reports the mic at 0.37, unmuted"
ipc toggleMicMute; sleep 0.5
expect "mic muted" sh -c "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED"
check "s['micMuted']" "service reports the mic muted"
check "len(s['sources']) > 0" "microphones listed as inputs"
# Inputs with nothing plugged in: every jack "not available", as pactl reports them.
UNPLUGGED=$(pactl -f json list sources | python3 -I -c "import json, sys; print(sorted(s['name'] for s in json.load(sys.stdin) if s['ports'] and all(p['availability'] == 'not available' for p in s['ports'])))")
check "sorted(s['unplugged']) == $UNPLUGGED" "inputs with nothing plugged in found ($UNPLUGGED)"

# An app recording (pw-cat capturing to /dev/null, nothing kept) shows as one.
pw-cat -r -a --format s16 --rate 48000 --channels 1 -P '{ application.name = "pistachio-rec-test" }' - > /dev/null 2>&1 &
RECORD_PID=$!
sleep 1.5
check "'pistachio-rec-test' in s['recorders']" "recording app listed"
kill "$RECORD_PID"; RECORD_PID=; sleep 0.8
check "'pistachio-rec-test' not in s['recorders']" "gone once it stops"

# A screen shared through the portal: a stand-in for xdg-desktop-portal-hyprland's video source (a
# GStreamer test pattern, named like its node) and an app reading it. WirePlumber won't link the two
# by itself ("target not found"), so pw-link does.
if gst-inspect-1.0 pipewiresink > /dev/null 2>&1; then
    gst-launch-1.0 -q videotestsrc is-live=true ! video/x-raw,width=320,height=180,framerate=10/1 \
        ! pipewiresink mode=provide stream-properties="props,media.class=Video/Source,node.name=xdg-desktop-portal-hyprland" > /dev/null 2>&1 &
    CAST_PID=$!
    gst-launch-1.0 -q pipewiresrc autoconnect=false \
        stream-properties="props,application.name=pistachio-share-test,node.name=pistachio-share-test" ! fakesink > /dev/null 2>&1 &
    READER_PID=$!
    sleep 1.2
    pw-link "$(pw-link -o | grep -m1 '^xdg-desktop-portal-hyprland:')" "$(pw-link -i | grep -m1 pistachio-share-test)"
    sleep 0.8
    check "'pistachio-share-test' in s['screen']" "app sharing the screen listed"
    kill "$READER_PID"; READER_PID=; sleep 0.8
    check "s['screen'] == []" "gone once it stops reading"
    kill "$CAST_PID"; CAST_PID=
else
    echo "skip: screen sharing (no GStreamer PipeWire plugin)"
fi

# The System monitor's readings, taken while watched.
ipc setStatsWatching true; sleep 2.5
check "0 <= s['cpu'] <= 1 and 0 < s['memUsed'] < s['memTotal']" "CPU load and memory read"
GPU=$(command -v nvidia-smi > /dev/null && echo True || echo False)
check "s['gpuFound'] == $GPU" "GPU read exactly when nvidia-smi is there"
# / and /home, once each: a /home on the root filesystem (btrfs subvolumes) shows as one disk
DISKS=$(df -P / /home | awk 'NR > 1 { print $1 }' | sort -u | wc -l)
check "len(s['disks']) == $DISKS and s['disks'][0]['mount'] == '/' and all(0 < d['free'] <= d['size'] for d in s['disks'])" "free disk space read for / and /home"
ipc setStatsWatching false

# Its warnings, from made-up readings: a disk under 10 % free warns once, and a CPU at 85 °C or more
# once it has been for a minute (the heat's start is moved back a minute rather than waited for).
notified() { grep -c "$1" "$STUBS/notified" || true; }
ipc parseStats "disk /dev/test 1048576 52428 /"; sleep 0.5
[ "$(notified 'almost full')" = 1 ] || { echo "FAIL: low disk warns"; exit 1; }
ipc parseStats "disk /dev/test 1048576 52428 /"; sleep 0.5
[ "$(notified 'almost full')" = 1 ] || { echo "FAIL: low disk warns only once"; exit 1; }
echo "ok: a disk under 10 % free warns, once"
ipc parseStats "temp 90000"; sleep 0.3
[ "$(notified 'running hot')" = 0 ] || { echo "FAIL: CPU heat waits a minute"; exit 1; }
ipc backdateHeat cpu 61000; ipc parseStats "temp 90000"; sleep 0.5
[ "$(notified 'CPU running hot')" = 1 ] || { echo "FAIL: CPU hot for a minute warns"; exit 1; }
echo "ok: a CPU hot for a minute warns"
ipc parseStats "temp 50000"

# Settings survive a restart (the test shell keeps its own state file, not the real shell's).
ipc setDnd true; sleep 0.8 # saved 300 ms after a change
kill "$SHELL_PID"; wait "$SHELL_PID" 2>/dev/null || true
qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
sleep 3
check "s['dnd']" "do not disturb kept across a restart"
ipc setDnd false; sleep 0.8

echo "all passed"
