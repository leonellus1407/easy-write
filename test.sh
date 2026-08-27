#!/bin/bash
# Runs the unit tests.
#
# With full Xcode installed, `swift test` works on its own. With only the Command Line Tools,
# swift-testing ships as a framework that SwiftPM leaves off the search path, so `swift test`
# fails with "no such module 'Testing'". This puts it back.
set -euo pipefail
cd "$(dirname "$0")"

DEVELOPER="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER/Library/Developer/Frameworks"
LIBS="$DEVELOPER/Library/Developer/usr/lib"

if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    echo "▶ Testing (swift-testing from the Command Line Tools)…"
    exec swift test \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$LIBS" \
        "$@"
fi

echo "▶ Testing…"
exec swift test "$@"
