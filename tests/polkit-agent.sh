#!/bin/bash
# Self-check of the polkit agent (src/services/polkit-agent.py): requests come out as JSON lines with
# the user, the app that asked and the vendor, and dismissing or withdrawing one answers polkit. Only
# polkitd may call the real agent, so this runs it with --session (on the session bus, where it never
# starts PAM) and plays polkit with gdbus. Never asks for a password, so it costs no pam_faillock
# strike; can run while the shell runs.
# HELPER="<command>" tests another build of the agent (default: the one the shell runs).
set -euo pipefail
HELPER=${HELPER:-$HOME/.local/bin/pistachio-auth}
TMP=$(mktemp -d)
trap 'kill "$PID" "$SLEEPER" 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkfifo "$TMP/in"
$HELPER --session < "$TMP/in" > "$TMP/out" 2> "$TMP/err" &
PID=$!
exec 3> "$TMP/in"
# the app asking: a name longer than the 15 characters the kernel keeps in comm
ln -s "$(command -v sleep)" "$TMP/pistachio-test-requester"
"$TMP/pistachio-test-requester" 30 3>&- & # without the agent's stdin, which it would keep open
SLEEPER=$!

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
# begin <cookie> <identities> [details]: asks like polkitd would, in the background; the reply goes to $TMP/reply
begin() {
    gdbus call --session --dest "$NAME" --object-path /pistachio/PolkitAgent \
        --method org.freedesktop.PolicyKit1.AuthenticationAgent.BeginAuthentication \
        org.freedesktop.policykit.exec "Authentication is needed to run \`/usr/bin/true' as the super user" "" \
        "${3:-@a{ss\} {\}}" "$1" "$2" > "$TMP/reply" 2>&1 &
    ASKING=$!
}
# answer <json>: the shell's answer
answer() { echo "$1" >&3; }
# check_reply <text> <label>: the reply polkitd got contains the text
check_reply() {
    wait "$ASKING" || true
    grep -qF "$1" "$TMP/reply" || { echo "FAIL: $2 (got: $(cat "$TMP/reply"))"; exit 1; }
    echo "ok: $2"
}

ME="[('unix-user', {'uid': <uint32 $(id -u)>})]"

check_line 1 "m['event'] == 'ready' and m['name'].startswith(':')" "agent ready"
NAME=$(line 1 | python3 -I -c "import json, sys; print(json.load(sys.stdin)['name'])")

begin c1 "[('unix-user', {'uid': <uint32 0>}), ('unix-user', {'uid': <uint32 $(id -u)>})]" "{'polkit.subject-pid': '$SLEEPER', 'polkit.caller-pid': '$$'}"
check_line 2 "m['event'] == 'request' and m['cookie'] == 'c1' and m['action'] == 'org.freedesktop.policykit.exec' and m['message'].startswith('Authentication is needed')" "request passed on"
check_line 2 "m['user'] == '$(id -un)'" "authenticates as this user when polkit allows it"
check_line 2 "m['requester'] == 'pistachio-test-requester (pid $SLEEPER)'" "names the app that asked, in full"
check_line 2 "m['vendor'] == 'The polkit project'" "vendor looked up from polkit's actions"
answer '{"cookie": "c1", "response": "not a password"}'
check_line 3 "m == {'event': 'failed', 'cookie': 'c1', 'error': 'No PAM with --session'}" "a response reaches PAM's place (none in --session)"
answer '{"cookie": "c1", "cancel": true}'
check_reply "org.freedesktop.PolicyKit1.Error.Cancelled" "dismissing answers polkit"

begin c2 "$ME"
check_line 4 "m['cookie'] == 'c2' and m['requester'] == '' and m['vendor'] == 'The polkit project'" "no pid: no requester"
gdbus call --session --dest "$NAME" --object-path /pistachio/PolkitAgent \
    --method org.freedesktop.PolicyKit1.AuthenticationAgent.CancelAuthentication c2 > /dev/null
check_reply "org.freedesktop.PolicyKit1.Error.Cancelled" "polkit withdrawing it ends the request"
check_line 5 "m == {'event': 'cancel', 'cookie': 'c2'}" "withdrawal passed on to the shell"

begin c3 "[('unix-user', {'uid': <uint32 0>})]"
check_line 6 "m['cookie'] == 'c3' and m['user'] == 'root'" "another user when polkit names only that one"
answer 'not json'
answer '{"cookie": "nope", "cancel": true}'
answer '{"cookie": "nope", "response": "hunter2-must-not-be-logged"}'
answer '{"cookie": "c3"}'
answer '{"cookie": "c3", "cancel": true}'
check_reply "org.freedesktop.PolicyKit1.Error.Cancelled" "dismissed, after ignoring a garbled and an unknown answer"
grep -q "ignored answer" "$TMP/err" || { echo "FAIL: bad answers not logged"; exit 1; }
! grep -q "hunter2" "$TMP/err" "$TMP/out" || { echo "FAIL: a password reached the log"; exit 1; }
echo "ok: an answer nobody waits for is logged without its password"
[ "$(wc -l < "$TMP/out")" -eq 6 ] || { echo "FAIL: an answer without a response did something"; exit 1; }
echo "ok: an answer without a response starts nothing"

begin c4 "[('unix-group', {'gid': <uint32 998>})]"
check_reply "No user to authenticate as" "no user named: refused, nothing asked"
[ "$(wc -l < "$TMP/out")" -eq 6 ] || { echo "FAIL: the refused request reached the shell"; exit 1; }

exec 3>&-
for _ in $(seq 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
! kill -0 "$PID" 2>/dev/null || { echo "FAIL: agent still running after stdin closed"; exit 1; }
echo "ok: agent exits when the shell goes"

# polkitd going away and coming back: a second agent watches a stand-in name on the session bus
own_name() { # holds the stand-in name until killed
    python3 -I -c "
from gi.repository import Gio, GLib
Gio.bus_own_name(Gio.BusType.SESSION, 'org.pistachio.TestPolkit', Gio.BusNameOwnerFlags.NONE, None, None, None)
GLib.MainLoop().run()" &
    OWNER=$!
}
: > "$TMP/out"
mkfifo "$TMP/in2"
$HELPER --session --watch org.pistachio.TestPolkit < "$TMP/in2" >> "$TMP/out" 2>> "$TMP/err" &
PID=$!
exec 3> "$TMP/in2"
NAME=$(line 1 | python3 -I -c "import json, sys; print(json.load(sys.stdin)['name'])")
own_name
check_line 2 "m == {'event': 'ready'}" "polkit appearing: registered"
begin c5 "$ME"
check_line 3 "m['cookie'] == 'c5'" "a request while polkit runs"
kill "$OWNER"
check_line 4 "m == {'event': 'lost'}" "polkit going away is told to the shell"
check_reply "The agent went away" "and the open request is ended"
own_name
check_line 5 "m == {'event': 'ready'}" "polkit coming back: registered again"
kill "$OWNER"
exec 3>&-

echo "all passed"
