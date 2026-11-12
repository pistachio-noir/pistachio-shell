#!/bin/sh
# Guards the shell's IPC surface: every target and function in tests/ipc-surface.txt must still be
# there, with the same signature (the owner's keybinds call them). New functions pass, and are listed.
#   sh tests/ipc-surface.sh            compare the running shell with the snapshot
#   sh tests/ipc-surface.sh --save     rewrite the snapshot from the running shell
# QS_ARGS picks the instance (default "-c pistachio"; e.g. QS_ARGS="-p /path/to/copy").
set -eu
cd "$(dirname "$0")"
snapshot=ipc-surface.txt

# "target x" / "  function f(a: string): void" lines → sorted "x.f(a: string): void" lines
surface() {
    # shellcheck disable=SC2086
    qs ${QS_ARGS:--c pistachio} ipc show | awk '
        $1 == "target" { target = $2; next }
        $1 == "function" { sub(/^ *function /, ""); print target "." $0 }' | sort
}

now=$(surface)
[ -n "$now" ] || { echo "ipc-surface: the shell gave no IPC listing (is it running?)" >&2; exit 1; }

if [ "${1:-}" = "--save" ]; then
    printf '%s\n' "$now" > "$snapshot"
    echo "saved $(wc -l < "$snapshot") functions"
    exit 0
fi

missing=$(printf '%s\n' "$now" | comm -23 "$snapshot" -)
added=$(printf '%s\n' "$now" | comm -13 "$snapshot" -)
[ -z "$added" ] || printf 'new (fine):\n%s\n' "$added"
if [ -n "$missing" ]; then
    printf 'MISSING or changed:\n%s\n' "$missing" >&2
    exit 1
fi
echo "ok: all $(wc -l < "$snapshot") IPC functions are there"
