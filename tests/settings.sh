#!/bin/sh
# Real QML controls with isolated stand-ins: never touches desktop audio, Bluetooth or saved settings.
set -eu
cd "$(dirname "$0")/.."
python3 -B tests/settings.test.py
