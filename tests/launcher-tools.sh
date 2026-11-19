#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
(cd rust && cargo test -q -p psc tools::)  # launcher-tools.py's cases, now psc launcher-tools
python3 -B tests/launcher-preview.test.py
python3 -B tests/launcher-tools-ui.test.py
