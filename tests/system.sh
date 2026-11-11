#!/bin/sh
# No live devices, credentials or model requests. QML settings use isolated hardware stand-ins.
set -eu
cd "$(dirname "$0")/.."
python3 -B tests/system.test.py
python3 -B tests/mic-check.test.py
python3 -B tests/settings.test.py
