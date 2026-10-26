#!/bin/bash
# Self-check of the pairing agent (src/services/bluetooth-agent.py): every kind of BlueZ question comes
# out as a JSON line, and the answers written back reach the caller. The system bus lets only root call
# an agent, so this runs it with --session (on the session bus, without BlueZ) and asks it with gdbus.
# Touches no Bluetooth state; can run while the shell runs.
set -euo pipefail
AGENT="$(cd "$(dirname "$0")/.." && pwd)/src/services/bluetooth-agent.py"
DEVICE=/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF
TMP=$(mktemp -d)
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkfifo "$TMP/in"
python3 -I "$AGENT" --session < "$TMP/in" > "$TMP/out" 2> "$TMP/err" &
PID=$!
exec 3> "$TMP/in"

# line <n>: the agent's n-th line of output, waiting up to 2 s for it
line() {
    for _ in $(seq 20); do
        [ "$(wc -l < "$TMP/out")" -ge "$1" ] && { sed -n "$1p" "$TMP/out"; return; }
        sleep 0.1
    done
    echo "FAIL: no line $1 from the agent"; cat "$TMP/err"; exit 1
}
# check_line <n> <python condition over m (the line)> <label>
check_line() {
    line "$1" | python3 -I -c "import json, sys; m = json.load(sys.stdin); assert $2, m" \
        || { echo "FAIL: $3"; exit 1; }
    echo "ok: $3"
}
# ask <method> [args…]: calls the agent like BlueZ would, in the background; the reply goes to $TMP/reply
ask() {
    gdbus call --session --dest "$NAME" --object-path /pistachio/agent --method "org.bluez.Agent1.$1" "${@:2}" > "$TMP/reply" 2>&1 &
    ASKING=$!
}
# answer <json>: the shell's answer
answer() { echo "$1" >&3; }
# check_reply <text> <label>: the reply BlueZ got contains the text
check_reply() {
    wait "$ASKING" || true
    grep -qF "$1" "$TMP/reply" || { echo "FAIL: $2 (got: $(cat "$TMP/reply"))"; exit 1; }
    echo "ok: $2"
}

check_line 1 "m['event'] == 'ready' and m['name'].startswith(':')" "agent ready"
NAME=$(line 1 | python3 -I -c "import json, sys; print(json.load(sys.stdin)['name'])")

ask RequestConfirmation "$DEVICE" 4242
check_line 2 "m == {'event': 'request', 'kind': 'confirm', 'device': '$DEVICE', 'code': '004242', 'id': 1}" "confirmation asked, code zero-padded"
answer '{"id": 1, "accept": true}'
check_reply "()" "confirmation accepted"

ask RequestPasskey "$DEVICE"
check_line 3 "m['kind'] == 'passkey' and m['id'] == 2" "passkey asked"
answer '{"id": 2, "accept": true, "value": "012345"}'
check_reply "(uint32 12345,)" "passkey sent as a number"

ask RequestPasskey "$DEVICE"
line 4 > /dev/null
answer '{"id": 3, "accept": true, "value": "1234567"}'
check_reply "org.bluez.Error.Rejected" "passkey over 999999 refused"

ask RequestPinCode "$DEVICE"
check_line 5 "m['kind'] == 'pin' and m['id'] == 4" "PIN asked"
answer '{"id": 4, "accept": true, "value": "0000"}'
check_reply "('0000',)" "PIN sent as text"

ask RequestPinCode "$DEVICE"
line 6 > /dev/null
answer '{"id": 5, "accept": false}'
check_reply "org.bluez.Error.Rejected" "declined PIN rejected"

ask RequestAuthorization "$DEVICE"
check_line 7 "m['kind'] == 'authorize' and m['id'] == 6" "incoming pairing asked"
gdbus call --session --dest "$NAME" --object-path /pistachio/agent --method org.bluez.Agent1.Cancel > /dev/null
check_reply "org.bluez.Error.Canceled" "BlueZ's Cancel withdraws the question"
check_line 8 "m == {'event': 'cancel'}" "Cancel passed on to the shell"

ask DisplayPasskey "$DEVICE" 7 2
check_reply "()" "code display answered at once"
check_line 9 "m['kind'] == 'display-passkey' and m['code'] == '000007' and m['entered'] == 2 and m['id'] == 0" "code display passed on with the keys typed"

ask AuthorizeService "$DEVICE" 0000110b-0000-1000-8000-00805f9b34fb
check_line 10 "m['kind'] == 'service' and m['uuid'].startswith('0000110b') and m['id'] == 7" "service use asked"
answer 'not json'
answer '{"id": 99, "accept": true}'
answer '{"id": 7, "accept": true}'
check_reply "()" "service allowed, after ignoring a garbled and an unknown answer"
grep -q "ignored answer" "$TMP/err" || { echo "FAIL: bad answers not logged"; exit 1; }

exec 3>&-
for _ in $(seq 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
! kill -0 "$PID" 2>/dev/null || { echo "FAIL: agent still running after stdin closed"; exit 1; }
echo "ok: agent exits when the shell goes"

echo "all passed"
