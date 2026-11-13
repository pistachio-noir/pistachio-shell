#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 -B tests/tui-launcher.test.py
