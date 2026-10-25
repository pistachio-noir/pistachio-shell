#!/bin/sh
# Links the shell into place (src/ as Quickshell's "pistachio" config, bin/psc into ~/.local/bin) and
# installs the Manrope font.
# Safe to run again, also after moving the repo. It never replaces a real file or folder with a link;
# the fonts are copied over any older copies.
set -eu

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

link "$repo/src" "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/pistachio"
link "$repo/bin/psc" "$HOME/.local/bin/psc"
fonts

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: ~/.local/bin is not on your PATH; add it, or run ~/.local/bin/psc" ;;
esac
command -v qs >/dev/null || echo "note: qs (Quickshell) is not installed; see Requirements in README.md"
echo "done: run psc to start the shell in this terminal, or psc start for the background"
