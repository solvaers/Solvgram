#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="/tmp/solvgram-audit-100023"
mkdir -p "$STAGE"
swiftc -swift-version 5 -O -module-cache-path /tmp/solvgram-audit-swift-cache \
  "$ROOT/Solvgram/SGSimpleSettings/Sources/SolvgramSettings.swift" \
  "$ROOT/Solvgram/SGSimpleSettings/Sources/SolvgramArchiveStorage.swift" \
  "$ROOT/Solvgram/SGSimpleSettings/Sources/SolvgramArchiveHistory.swift" \
  "$ROOT/Tests/SolvgramAudit/archive.swift" -o "$STAGE/archive-audit"
"$STAGE/archive-audit"
SUITE="app.solvgram.audit.process.$RANDOM.$RANDOM"
"$STAGE/archive-audit" write "$SUITE"
"$STAGE/archive-audit" read "$SUITE"
