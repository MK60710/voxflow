#!/bin/bash
# Run the Swift Testing suite under Command-Line-Tools-only setups.
# CLT ships Testing.framework outside the default search paths, so plain
# `swift test` fails with "no such module 'Testing'" — these flags fix it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

cd "$REPO_ROOT"
exec swift test \
    -Xswiftc -F"$FWK" \
    -Xlinker -F"$FWK" \
    -Xlinker -rpath -Xlinker "$FWK" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
