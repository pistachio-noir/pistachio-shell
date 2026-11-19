#!/bin/sh
# Links the shell into place (src/ as Quickshell's "pistachio" config; psc, built from rust/, into ~/.local/bin),
# builds the helper programs in rust/ into ~/.local/bin and installs the Manrope font.
# Safe to run again, also after moving the repo. It never replaces a real file or folder with a link;
# the fonts are copied over any older copies.
set -eu

mode=${1-}
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [dry]" >&2
    exit 2
fi
case "$mode" in
    ""|dry) ;;
    *)
        echo "Usage: $0 [dry]" >&2
        exit 2
        ;;
esac

if [ "$mode" = dry ]; then
    echo "dry run: no files will be changed; builds and downloads are skipped"
fi

repo=$(cd "$(dirname "$0")" && pwd)

# link <target> <link>
link() {
    if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
        echo "ok      $2 -> $1"
        return
    fi
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        echo "error: $2 exists and is not a link; move it away and run this again" >&2
        exit 1
    fi
    old=$(readlink "$2" || true)
    if [ "$mode" = dry ]; then
        echo "would link  $2 -> $1${old:+ (was $old)}"
        return
    fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
    echo "linked  $2 -> $1${old:+ (was $old)}"
}

# Manrope, the UI font: Google Fonts' variable TTF, every weight (200–800) in one file. Fontsource's
# files can't be used on the desktop: they name every weight "Manrope ExtraLight", so "Manrope"
# matched nothing (found when this first used them). Not fatal: without it the shell still runs,
# and this can be run again later.
fonts() {
    dest=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/manrope
    base=https://github.com/google/fonts/raw/main/ofl/manrope
    for tool in curl fc-cache fc-scan; do
        command -v "$tool" >/dev/null || { echo "note: $tool is missing, so Manrope wasn't installed"; return 0; }
    done
    if [ "$mode" = dry ]; then
        echo "would download and validate Manrope from $base"
        echo "would copy Manrope[wght].ttf and OFL.txt into $dest"
        echo "would refresh the font cache for $dest"
        return
    fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    if ! curl -fsSL -o "$tmp/Manrope.ttf" "$base/Manrope%5Bwght%5D.ttf" \
        || ! curl -fsSL -o "$tmp/OFL.txt" "$base/OFL.txt"; then
        echo "note: couldn't download Manrope; run this again when online"
        return 0
    fi
    # only a real font called Manrope goes in (not, say, an error page from a captive portal)
    if ! fc-scan --format '%{family}\n' "$tmp/Manrope.ttf" 2>/dev/null | grep -q '^Manrope'; then
        echo "note: the Manrope download wasn't a font; nothing installed"
        return 0
    fi
    mkdir -p "$dest"
    cp "$tmp/Manrope.ttf" "$dest/Manrope[wght].ttf"
    cp "$tmp/OFL.txt" "$dest/OFL.txt"
    fc-cache -f "$dest" >/dev/null
    echo "fonts   Manrope, every weight, in $dest"
}

# The helpers that run all day beside the shell (the polkit agent and its kin), built from rust/ and
# copied, not linked, so they keep working when the repo moves or is being rebuilt. A running helper
# keeps its old file until the shell restarts (psc restart). Not fatal: without cargo the shell
# still runs, and its log names what's missing.
helpers() {
    command -v cargo >/dev/null || { echo "note: cargo is missing, so the helpers in rust/ weren't built; see Requirements in README.md"; return 0; }
    if [ "$mode" = dry ]; then
        echo "would build release helpers from $repo/rust/Cargo.toml"
        echo "would install executable pistachio-* helpers into $HOME/.local/bin (mode 755)"
        echo "would install psc (Rust) as $HOME/.local/bin/psc, replacing the link to legacy/psc"
        return
    fi
    # the helpers first, on their own, so a psc that can't build (its crates not fetched yet) never
    # keeps the polkit, devices and LocalSend helpers from being rebuilt
    if ! cargo build --release --quiet --manifest-path "$repo/rust/Cargo.toml" -p pistachio-auth -p pistachio-devices -p pistachio-localsend; then
        echo "note: the helpers in rust/ didn't build; the ones already installed stay"
        return 0
    fi
    mkdir -p "$HOME/.local/bin"
    for helper in "$repo"/rust/target/release/pistachio-*; do
        [ -f "$helper" ] && [ -x "$helper" ] || continue
        # install replaces the file instead of writing into it, which a running helper would block
        install -m 755 "$helper" "$HOME/.local/bin/"
        echo "built   $HOME/.local/bin/$(basename "$helper")"
    done
    # psc, in Rust since 19 November 2026; it replaces a link to the old script, kept as legacy/psc
    if cargo build --release --quiet --manifest-path "$repo/rust/Cargo.toml" -p psc && [ -x "$repo/rust/target/release/psc" ]; then
        rm -f "$HOME/.local/bin/psc"
        install -m 755 "$repo/rust/target/release/psc" "$HOME/.local/bin/psc"
        echo "built   $HOME/.local/bin/psc"
        psc_built=1
    else
        echo "note: psc didn't build; the psc already installed (or the legacy/psc script) stays"
    fi
}

link "$repo/src" "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/pistachio"
psc_built=
helpers
# without cargo (or if the build failed) the old script still gives a working psc
# (a psc from an earlier build, a real file, stays as it is)
if [ -z "$psc_built" ] && [ "$mode" != dry ] && { [ -L "$HOME/.local/bin/psc" ] || [ ! -e "$HOME/.local/bin/psc" ]; }; then
    link "$repo/legacy/psc" "$HOME/.local/bin/psc"
fi
fonts

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: ~/.local/bin is not on your PATH; add it, or run ~/.local/bin/psc" ;;
esac
command -v qs >/dev/null || echo "note: qs (Quickshell) is not installed; see Requirements in README.md"
if [ "$mode" = dry ]; then
    echo "dry run complete: no changes made"
else
    echo "done: run psc to start the shell in this terminal, or psc start for the background"
fi
