#!/bin/sh
# No live devices, credentials or model requests. QML settings use isolated hardware stand-ins.
set -eu
cd "$(dirname "$0")/.."
(cd rust && cargo test -q -p psc system::)  # system-tools.py's cases, now psc system
python3 -B tests/mic-check.test.py
python3 -B tests/settings.test.py
