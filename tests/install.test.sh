#!/bin/sh
# install.sh in a throwaway home with stand-in cargo/curl (no download, no real build, nothing outside
# the temporary folder): psc is never left missing, and a psc build failure doesn't stop the helpers.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }
run() { # $1: cargo behaviour (fail-all | fail-psc)
    t=$(mktemp -d)
    mkdir -p "$t/stub" "$t/home/.local/bin"
    printf '#!/bin/sh\nexit 1\n' > "$t/stub/curl"
    if [ "$1" = fail-all ]; then printf '#!/bin/sh\nexit 1\n' > "$t/stub/cargo"
    # fail-psc: building psc (or the whole workspace, which includes it) fails; the helpers alone build
    else printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = psc ] && exit 1; done\nfor a in "$@"; do [ "$a" = -p ] && exit 0; done\nexit 1\n' > "$t/stub/cargo"; fi
    chmod +x "$t/stub/curl" "$t/stub/cargo"
    echo "$t"
}
# 1. a real psc from an earlier Rust install, then a run where nothing builds: exit 0, psc kept
t=$(run fail-all); printf 'old rust psc\n' > "$t/home/.local/bin/psc"
out=$(HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" PATH="$t/stub:$PATH" sh "$repo/install.sh" 2>&1); code=$?
check "no build: install still succeeds" '[ $code -eq 0 ]'
check "no build: the earlier psc is kept" '[ "$(cat "$t/home/.local/bin/psc")" = "old rust psc" ]'
rm -rf "$t"
# 2. a fresh home where nothing builds: the old script is linked, so there is a psc
t=$(run fail-all)
HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" PATH="$t/stub:$PATH" sh "$repo/install.sh" >/dev/null 2>&1
check "fresh home, no build: psc links the script" '[ "$(readlink "$t/home/.local/bin/psc")" = "$repo/legacy/psc" ]'
check "fresh home, no build: the linked script is there and runs" '[ -x "$t/home/.local/bin/psc" ] && [ -f "$t/home/.local/bin/psc" ]'
rm -rf "$t"
# 3. psc can't build (clap not fetched) but the helpers can: the helpers are still installed
t=$(run fail-psc)
out=$(HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" PATH="$t/stub:$PATH" sh "$repo/install.sh" 2>&1)
check "psc build fails: helpers still installed" '[ -x "$t/home/.local/bin/pistachio-auth" ]' || echo "$out"
rm -rf "$t"
exit $fail
