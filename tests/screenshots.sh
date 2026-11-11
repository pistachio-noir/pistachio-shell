#!/bin/sh
# Briefly opens the picker; saves only temporary crops, with no clipboard, OCR, colour or recording actions.
set -eu
SCREENSHOT_TEST_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
python3 -B "$SCREENSHOT_TEST_ROOT/tests/screenshots.test.py"
