#!/bin/sh
# Dev tests (Settings → Experimental → Dev features, launcher "Dev tests"; or by hand): the suites that are
# safe on a running desktop, one line each, then a summary. Exit status: the number of failed suites.
#   sh tests/run.sh            isolated suites; nothing opens on screen
#   sh tests/run.sh --native   also the suites that open real windows for a moment
# Never runs the live-system suites (services.sh, compositor.sh, notifications.sh, mem.sh, ipc-surface.sh):
# they use the running shell or change real devices. Each suite's full output is in the logs folder.
set -u
root=$(CDPATH= cd -P -- "$(dirname -- "$0")/.." && pwd) || exit 100
cd "$root" || exit 100
native=0
case "${1:-}" in
    --native) native=1 ;;
    "") ;;
    *) echo "usage: sh tests/run.sh [--native]" >&2; exit 100 ;;
esac
# started from the shell, PATH is the session's, which may lack these (cargo from rustup, ~/.local/bin)
for dir in "$HOME/.cargo/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in *":$dir:"*) ;; *) [ -d "$dir" ] && PATH="$PATH:$dir" ;; esac
done
export PATH
logs=${XDG_CACHE_HOME:-$HOME/.cache}/pistachio-shell/dev-tests
rm -rf "$logs" && mkdir -p "$logs" || exit 100
passed=0 failed=0 skipped=0 failures=""
began=$(date +%s)
gi=0
python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' 2>/dev/null && gi=1

line() { printf '%s %-24s %s\n' "$1" "$2" "$3"; }

# run NAME COMMAND...: one suite, 10 minutes at most
run() {
    name=$1; shift
    start=$(date +%s)
    timeout 600 "$@" >"$logs/$name.log" 2>&1
    code=$?
    took="$(( $(date +%s) - start ))s"
    if [ "$code" -eq 0 ]; then
        passed=$((passed + 1)); line "✓" "$name" "$took"
    else
        failed=$((failed + 1)); failures="$failures $name"
        [ "$code" -eq 124 ] && took="$took, timed out" || took="$took, exit $code"
        line "✗" "$name" "$took"
        # the end of its output, without colour codes
        tail -n 12 "$logs/$name.log" | sed 's/\x1b\[[0-9;]*m//g; s/^/      /'
    fi
}

skip() { skipped=$((skipped + 1)); line "·" "$1" "skipped: $2"; }

# true when FILE uses PyGObject (anywhere: inside a function, or Python inside a .sh) and it's missing
no_gi() { [ "$gi" -eq 0 ] && grep -qE '(from|import) gi(\.| |$)' "$1"; }
needs_gi="needs PyGObject (Gentoo: dev-python/pygobject, Arch: python-gobject)"

# py NAME [dbus]: tests/NAME.test.py, on a private session bus with dbus
py() {
    file="tests/$1.test.py"
    if no_gi "$file"; then
        skip "$1" "$needs_gi"
    elif [ "${2:-}" = dbus ]; then
        run "$1" dbus-run-session -- python3 -B "$file"
    else
        run "$1" python3 -B "$file"
    fi
}

# suite NAME [dbus]: tests/NAME.sh the same way
suite() {
    file="tests/$1.sh"
    if no_gi "$file"; then
        skip "$1" "$needs_gi"
    elif [ "${2:-}" = dbus ]; then
        run "$1" dbus-run-session -- sh "$file"
    else
        run "$1" sh "$file"
    fi
}

echo "Dev tests in $root$( [ "$native" -eq 1 ] && echo ', with windows')"
echo

# Rust first, with the release psc that chat, lens and restart run (rust/target/release/psc), so they
# test this tree's code; nothing is installed
run rust sh -c 'cd rust && cargo build --release -p psc --offline && cargo test --workspace --offline'
# Shell health and the Settings suite (it checks that no owner file changed: nothing else edits meanwhile)
suite system
suite js
suite layout
suite lens
run install sh tests/install.test.sh
for name in prefs app-theming app-themes neovim-theme game-mode clipboard phone-timer capture-helper mic-check restart chat \
    first-run first-run-backend clocks clocks-popup cat-interaction events dev-features; do
    py "$name"
done
py clocks-action dbus
# the bus agents against stand-ins, on a private session bus
suite polkit-agent dbus
suite bluetooth-agent dbus
suite drives dbus
suite localsend

if [ "$native" -eq 1 ]; then
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip native "needs a Wayland session"
    else
        echo
        echo "With windows:"
        for name in bar tui-launcher tui-panels launcher-tools lens-native recording screenshots; do
            suite "$name"
        done
        for name in ambient-clock desktop-widgets session-pill overview-wallpaper launcher-preview; do
            py "$name"
        done
    fi
fi

echo
total="$(( $(date +%s) - began ))s"
summary="$passed passed, $failed failed, $skipped skipped in $total"
[ "$failed" -gt 0 ] && summary="$summary (failed:$failures)"
echo "Dev tests: $summary"
echo "Logs: $logs"
[ "$failed" -gt 100 ] && exit 100
exit "$failed"
