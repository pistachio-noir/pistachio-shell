#!/bin/sh
# Links the shell into place (src/ as Quickshell's "pistachio" config; psc, built from rust/, into ~/.local/bin),
# builds the helper programs in rust/ into ~/.local/bin and installs the Manrope font, then checks what the
# shell needs (psc doctor) and prints the pacman line for anything missing. It never installs packages itself.
# Safe to run again, also after moving the repo. It never replaces a real file or folder with a link;
# the fonts are copied over any older copies.
#
#   ./install.sh        install
#   ./install.sh dry    show what it would do; no files changed, no builds, no downloads
#
# Output: one line per step (✓ done, ! a note, ✗ an error, · would do), colour only on a terminal and never
# with NO_COLOR set, so a log stays plain text.
set -eu

mode=${1-}
usage() { echo "Usage: $0 [dry]" >&2; exit 2; }
[ "$#" -le 1 ] || usage
case "$mode" in ""|dry) ;; *) usage ;; esac

repo=$(cd "$(dirname "$0")" && pwd)
bin="$HOME/.local/bin"

# ---- presentation -------------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR-}" ] && [ "${TERM-dumb}" != dumb ]; then
    tty=1 bold=$(printf '\033[1m') dim=$(printf '\033[2m') green=$(printf '\033[32m') yellow=$(printf '\033[33m') red=$(printf '\033[31m') reset=$(printf '\033[0m')
else
    tty= bold= dim= green= yellow= red= reset=
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG-}}}" in
    *UTF-8*|*utf8*|*UTF8*|*utf-8*) good='✓' note='!' bad='✗' would='·' arrow='→' ;;
    *) good='+' note='!' bad='x' would='-' arrow='->' ;;
esac
notes=0 problems=0

# "~/…" for paths in the home folder
short() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# step <done|note|error|would> <what> <status word> <detail>
step() {
    case "$1" in
        done) mark="$green$good$reset" ;;
        note) mark="$yellow$note$reset"; notes=$((notes + 1)) ;;
        error) mark="$red$bad$reset"; problems=$((problems + 1)) ;;
        would) mark="$dim$would$reset" ;;
    esac
    [ -z "$tty" ] || printf '\r\033[K'
    line=$(printf '  %s %-9s %-11s %s' "$mark" "$2" "$3" "$4")
    if [ "$1" = error ]; then printf '%s\n' "$line" >&2; else printf '%s\n' "$line"; fi
}

# a step that takes a while: shown on a terminal until the step's own line replaces it
working() { [ -z "$tty" ] || printf '  %s %-9s %s' "$dim…$reset" "$1" "$dim$2$reset"; }

# an indented second line under a step (a command to run, a hint)
more() { printf '      %-9s %-11s %s\n' "" "" "$1"; }

heading() { printf '\n%s%s%s\n' "$bold" "$1" "$reset"; }

printf '%sPistachio Noir Shell%s installer\n' "$bold" "$reset"
printf '%srepo %s%s\n' "$dim" "$(short "$repo")" "$reset"
[ "$mode" != dry ] || printf '%sdry run: nothing is changed, built or downloaded%s\n' "$yellow" "$reset"

# ---- steps ---------------------------------------------------------------------------------------------

# link <what> <target> <link>
link() {
    if [ -L "$3" ] && [ "$(readlink "$3")" = "$2" ]; then
        step done "$1" "ok" "$(short "$3") $arrow $(short "$2")"
        return
    fi
    if [ -e "$3" ] && [ ! -L "$3" ]; then
        step error "$1" "in the way" "$(short "$3") exists and is not a link"
        more "move it away and run this again" >&2
        exit 1
    fi
    old=$(readlink "$3" || true)
    if [ "$mode" = dry ]; then
        step would "$1" "would link" "$(short "$3") $arrow $(short "$2")${old:+ (was $(short "$old"))}"
        return
    fi
    mkdir -p "$(dirname "$3")"
    ln -sfn "$2" "$3"
    step done "$1" "linked" "$(short "$3") $arrow $(short "$2")${old:+ (was $(short "$old"))}"
}

# Manrope, the UI font: Google Fonts' variable TTF, every weight (200–800) in one file. Fontsource's
# files can't be used on the desktop: they name every weight "Manrope ExtraLight", so "Manrope"
# matched nothing (found when this first used them). Not fatal: without it the shell still runs,
# and this can be run again later.
fonts() {
    dest=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/manrope
    base=https://github.com/google/fonts/raw/main/ofl/manrope
    for tool in curl fc-cache fc-scan; do
        command -v "$tool" >/dev/null || { step note font "skipped" "$tool is missing, so Manrope wasn't installed"; return 0; }
    done
    if [ "$mode" = dry ]; then
        step would font "would get" "Manrope (every weight) from Google Fonts into $(short "$dest")"
        return
    fi
    working font "downloading Manrope"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    if ! curl -fsSL -o "$tmp/Manrope.ttf" "$base/Manrope%5Bwght%5D.ttf" \
        || ! curl -fsSL -o "$tmp/OFL.txt" "$base/OFL.txt"; then
        step note font "offline" "couldn't download Manrope; run this again when online"
        return 0
    fi
    # only a real font called Manrope goes in (not, say, an error page from a captive portal)
    if ! fc-scan --format '%{family}\n' "$tmp/Manrope.ttf" 2>/dev/null | grep -q '^Manrope'; then
        step note font "not a font" "the Manrope download wasn't a font; nothing installed"
        return 0
    fi
    mkdir -p "$dest"
    cp "$tmp/Manrope.ttf" "$dest/Manrope[wght].ttf"
    cp "$tmp/OFL.txt" "$dest/OFL.txt"
    fc-cache -f "$dest" >/dev/null
    step done font "installed" "Manrope, every weight, in $(short "$dest")"
}

# The helpers that run all day beside the shell (the polkit agent and its kin), built from rust/ and
# copied, not linked, so they keep working when the repo moves or is being rebuilt. A running helper
# keeps its old file until the shell restarts (psc restart). Not fatal: without cargo the shell
# still runs, and psc doctor names what's missing.
helpers() {
    command -v cargo >/dev/null || { step note helpers "skipped" "cargo is missing, so rust/ wasn't built (see docs/requirements.md)"; return 0; }
    if [ "$mode" = dry ]; then
        step would helpers "would build" "pistachio-* helpers from rust/ into $(short "$bin")"
        step would psc "would build" "psc (Rust) as $(short "$bin/psc")"
        return
    fi
    # the helpers first, on their own, so a psc that can't build (its crates not fetched yet) never
    # keeps the polkit, devices and LocalSend helpers from being rebuilt
    working helpers "building rust/ (the first build takes a few minutes)"
    if ! cargo build --release --quiet --manifest-path "$repo/rust/Cargo.toml" -p pistachio-auth -p pistachio-devices -p pistachio-localsend; then
        step note helpers "not built" "rust/ didn't build; the helpers already installed stay"
        return 0
    fi
    mkdir -p "$bin"
    names=
    for helper in "$repo"/rust/target/release/pistachio-*; do
        [ -f "$helper" ] && [ -x "$helper" ] || continue
        # install replaces the file instead of writing into it, which a running helper would block
        install -m 755 "$helper" "$bin/"
        names="${names:+$names, }$(basename "$helper")"
    done
    step done helpers "built" "${names:-none} $arrow $(short "$bin")"
    # psc, in Rust since 19 November 2026; it replaces a link to the old script, kept as legacy/psc
    working psc "building psc"
    if cargo build --release --quiet --manifest-path "$repo/rust/Cargo.toml" -p psc && [ -x "$repo/rust/target/release/psc" ]; then
        rm -f "$bin/psc"
        install -m 755 "$repo/rust/target/release/psc" "$bin/psc"
        step done psc "built" "$(short "$bin/psc")"
        psc_built=1
    else
        step note psc "not built" "psc didn't build; the psc already installed (or legacy/psc) stays"
    fi
}

heading "Install"
link config "$repo/src" "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/pistachio"
psc_built=
helpers
# without cargo (or if the build failed) the old script still gives a working psc
# (a psc from an earlier build, a real file, stays as it is)
if [ -z "$psc_built" ] && [ "$mode" != dry ] && { [ -L "$bin/psc" ] || [ ! -e "$bin/psc" ]; }; then
    link psc "$repo/legacy/psc" "$bin/psc"
    step note psc "fallback" "the old script only starts, stops and calls the shell; Settings, Lens and more need the Rust psc"
fi
fonts

# ---- what the shell needs ------------------------------------------------------------------------------
heading "Check"
case ":$PATH:" in
    *":$bin:"*) step done path "ok" "$(short "$bin") is on your PATH" ;;
    *) step note path "not set" "$(short "$bin") is not on your PATH; add it, or run $(short "$bin/psc")" ;;
esac
# psc doctor lists what's found; only a Rust psc from 20 November 2026 on has --packages (not legacy/psc,
# not a link to it). It exits 1 while something required is missing, so its exit code isn't the test here.
if [ -x "$bin/psc" ] && [ ! -L "$bin/psc" ] && "$bin/psc" doctor --help 2>/dev/null | grep -q -- --packages; then
    required=$("$bin/psc" doctor --packages required 2>/dev/null || true)
    optional=$("$bin/psc" doctor --packages optional 2>/dev/null || true)
    if [ -n "$required" ]; then
        step error needs "missing" "the shell can't run without these:"
        more "sudo pacman -S --needed $required" >&2
    else
        step done needs "ok" "everything the shell needs is installed"
    fi
    if [ -n "$optional" ]; then
        count=$(printf '%s\n' "$optional" | wc -w)
        step note extras "$count missing" "optional; psc doctor says what each one adds"
        more "sudo pacman -S --needed $optional"
    else
        step done extras "ok" "every optional tool is installed too"
    fi
else
    command -v qs >/dev/null && step done needs "qs found" "the Rust psc isn't installed, so only Quickshell was checked" \
        || step error needs "missing" "qs (Quickshell) is not installed; see docs/requirements.md"
fi

# ---- summary -------------------------------------------------------------------------------------------
if [ "$mode" = dry ]; then
    printf '\n%sDry run complete:%s nothing was changed.\n' "$bold" "$reset"
    exit 0
fi
if [ "$problems" -gt 0 ]; then
    printf '\n%sInstalled, but not ready yet:%s install what is marked %s above, then start the shell.\n' "$bold" "$reset" "$red$bad$reset"
elif [ "$notes" -gt 0 ]; then
    printf '\n%sDone%s, with %s note%s above.\n' "$bold" "$reset" "$notes" "$([ "$notes" = 1 ] || echo s)"
else
    printf '\n%sDone.%s\n' "$bold" "$reset"
fi
printf '%sNext:%s\n' "$bold" "$reset"
printf '  %-14s %s\n' "psc start" "run the shell in the background (or psc to run it in this terminal)"
printf '  %-14s %s\n' "psc restart" "after pulling changes to rust/, so the helpers restart too"
printf '  %-14s %s\n' "psc doctor" "everything the shell can use, found or missing"
