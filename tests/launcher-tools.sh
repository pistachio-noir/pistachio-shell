#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 -B tests/launcher-tools.test.py
python3 -B tests/launcher-preview.test.py
python3 -B tests/launcher-tools-ui.test.py
