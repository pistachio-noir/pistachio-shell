#!/bin/sh
# Real QML/process state, with a fake encoder and notification command. Never records owner content.
set -eu
RECORDING_TEST_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
python3 -B "$RECORDING_TEST_ROOT/tests/recording.test.py"
