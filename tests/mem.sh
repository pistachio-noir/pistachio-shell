#!/bin/sh
# Memory of the shell and its helper processes, in MiB, from /proc.
#   sh tests/mem.sh [label]         one line for the running shell
#   sh tests/mem.sh scenario        open and close the usual windows over IPC, a line after each
#   sh tests/mem.sh reloads <n> <shell.qml>   n live reloads of a scratch copy, a line after each
# QS_ARGS picks the instance (default "-c pistachio"; e.g. QS_ARGS="-p /path/to/copy").
# rss/peak/anon/file/shmem: the qs process (VmRSS, VmHWM, RssAnon, RssFile, RssShmem);
# helpers: resident memory of the processes it started and keeps (not the apps launched from it);
# total: rss + helpers.
set -eu

args=${QS_ARGS:--c pistachio}

pid() {
    # shellcheck disable=SC2086
    qs list $args 2>/dev/null | sed -n 's/^ *Process ID: //p' | head -n 1
}

# every descendant of $1
descendants() {
    for task in /proc/"$1"/task/*; do
        [ -r "$task/children" ] || continue
        for child in $(cat "$task/children"); do
            echo "$child"
            descendants "$child"
        done
    done
}

line() {
    p=$(pid)
    [ -n "$p" ] || { echo "mem: no shell running for: $args" >&2; exit 1; }
    helpers=0
    session=$(ps -o sid= -p "$p" | tr -d ' ')
    for child in $(descendants "$p"); do
        # an app started from the launcher runs in a session of its own: not a helper
        [ "$(ps -o sid= -p "$child" 2>/dev/null | tr -d ' ')" = "$session" ] || continue
        kb=$(sed -n 's/^VmRSS:[ \t]*\([0-9]*\).*/\1/p' "/proc/$child/status" 2>/dev/null || true)
        helpers=$((helpers + ${kb:-0}))
    done
    awk -v label="$1" -v helpers="$helpers" '
        /^VmRSS:/ { rss = $2 } /^VmHWM:/ { peak = $2 } /^RssAnon:/ { anon = $2 }
        /^RssFile:/ { file = $2 } /^RssShmem:/ { shmem = $2 }
        END { printf "%-16s rss=%d peak=%d anon=%d file=%d shmem=%d helpers=%d total=%d\n", label,
              rss / 1024, peak / 1024, anon / 1024, file / 1024, shmem / 1024, helpers / 1024, (rss + helpers) / 1024 }' "/proc/$p/status"
}

call() {
    # shellcheck disable=SC2086
    qs $args ipc call "$@" >/dev/null
}

# stage <label> <seconds open> <open call> -- <close call>
stage() {
    label=$1 wait=$2
    shift 2
    open= close= side=open
    for word; do
        if [ "$word" = "--" ]; then side=close; continue; fi
        if [ "$side" = open ]; then open="$open $word"; else close="$close $word"; fi
    done
    # shellcheck disable=SC2086
    call $open
    sleep "$wait"
    # shellcheck disable=SC2086
    call $close
    sleep 2
    line "$label"
}

case "${1:-}" in
    scenario)
        line fresh
        stage overview 2 overview open -- overview close
        call settings section appearance; sleep 1.5
        for page in sound display system; do call settings section "$page"; sleep 1.5; done
        call settings close; sleep 2; line settings
        stage launcher 2 launcher open apps -- launcher toggle
        stage quicksettings 2 quicksettings toggle -- quicksettings toggle
        stage notifications 2 notifications toggle -- notifications toggle
        stage wallpaper 2 wallpaper toggle -- wallpaper toggle
        stage power 2 power toggle -- power toggle
        stage screenshot 2 screenshot menu -- screenshot cancel
        sleep 30
        line idle-30s
        ;;
    reloads)
        n=$2 file=$3
        line before
        i=1
        while [ "$i" -le "$n" ]; do
            # written in place, so the watch on the file survives
            printf '// reload %s\n' "$i" >> "$file"
            sleep 3
            line "reload-$i"
            i=$((i + 1))
        done
        ;;
    *) line "${1:-now}" ;;
esac
