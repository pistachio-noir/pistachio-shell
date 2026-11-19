#!/bin/sh
# A stand-in for `qs`, for psc's tests: logs every call (one argument per line, then "<end of call>"), keeps
# "shells" as pid files in $FAKE_STATE, and starts a fake shell that ignores SIGTERM and has a child.
printf "%s\n" "$@" "<end of call>" >> "$FAKE_LOG"
case "$*" in
    "-c pistachio list")
        for f in "$FAKE_STATE"/*.pid; do
            [ -f "$f" ] || continue
            pid=$(cat "$f")
            if kill -0 "$pid" 2>/dev/null; then printf 'Instance fake%s:\n  Process ID: %s\n  Shell ID: x\n' "$pid" "$pid"; fi
        done ;;
    "-c pistachio kill") [ -n "$FAKE_KILL_WORKS" ] && for f in "$FAKE_STATE"/*.pid; do kill -KILL "$(cat "$f")" 2>/dev/null; done; true ;;
    "-c pistachio -n -d")
        sh -c 'trap "" TERM; sleep 300 & while :; do sleep 0.2; done' >/dev/null 2>&1 &
        echo $! > "$FAKE_STATE/$!.pid" ;;
    "-c pistachio ipc show") printf 'target launcher\n  function toggle(): void\ntarget bar\n  function peek(): void\n' ;;
esac
exit 0
