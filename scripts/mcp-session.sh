#!/usr/bin/env bash
# Runs a scripted MCP session against `reminders --mcp` over stdio and prints each JSON-RPC response on its own
# line (in completion order, so match them by "id").
#
# Usage: scripts/mcp-session.sh [binary] [tool arguments-json]...
#   scripts/mcp-session.sh                                     # initialize + tools/list
#   scripts/mcp-session.sh .build/release/reminders reminders_lists '{}'
#   scripts/mcp-session.sh "" reminders_add '{"list":"Inbox","title":"Milk","due":"tomorrow"}'
#
# The binary defaults to the debug build. Tool calls get ids 3, 4, ...
set -euo pipefail

cd "$(dirname "$0")/.."
binary="${1:-}"
[[ -n "$binary" ]] || binary="$(swift build --show-bin-path)/reminders"
shift || true

{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-session.sh","version":"1.0"}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  id=3
  while [[ $# -ge 2 ]]; do
    printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$id" "$1" "$2"
    id=$((id + 1))
    shift 2
  done
} | "$binary" --mcp
