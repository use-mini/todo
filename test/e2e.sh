#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?usage: e2e.sh <path-to-todo-binary>}"
DB=$(mktemp)
trap 'rm -f "$DB"' EXIT

export TODO_FILE="$DB"

"$BIN" install linux

output=$("$BIN")

if echo "$output" | grep -q "install linux"; then
    echo "PASS"
else
    echo "FAIL: expected 'install linux' in output, got:"
    echo "$output"
    exit 1
fi
