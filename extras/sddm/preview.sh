#!/bin/sh
# Opens the SDDM theme in a window, without SDDM. The password "test" logs in; anything else fails.
# `preview.sh shot out.png [wrong|menu]` saves a picture instead (used for pistachio-noir/preview.png).
dir=$(cd "$(dirname "$0")" && pwd)
qml=$(command -v qml6 || command -v qml || echo /usr/lib/qt6/bin/qml)
exec "$qml" "$dir/preview/Preview.qml" -- "$@"
