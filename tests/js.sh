#!/bin/sh
# The launcher's matcher and calculator and the calendar's month grid: tests/*.test.js, with node if
# it's installed, else in Quickshell's own JS engine (tests/qsjs), the one the shell runs them in.
cd "$(dirname "$0")" || exit 1
status=0
for test in *.test.js; do
    if command -v node > /dev/null; then
        node "$test" || status=1
    else
        result=$(QML_XHR_ALLOW_FILE_READ=1 TEST="$PWD/$test" timeout 20 qs -p "$PWD/qsjs" 2>&1 | grep -o -E "(PASS|FAIL) .*")
        echo "${result:-FAIL $test: no result}" | sed 's/^PASS //'
        case "$result" in PASS*) ;; *) status=1 ;; esac
    fi
done
exit $status
