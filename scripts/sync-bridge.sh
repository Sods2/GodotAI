#!/usr/bin/env bash
#
# Sync the bundled godot_mcp_bridge editor addon from the pinned godot-mcp submodule.
#
# godot-mcp (third_party/godot-mcp) is the single source of truth. GodotAI ships a
# COPY of just its editor bridge at addons/godot_mcp_bridge/ so users get it in one
# install (GodotAI auto-enables it). Never hand-edit addons/godot_mcp_bridge/ —
# change godot-mcp, bump the submodule, and re-run this script.
#
# Usage:
#   git -C third_party/godot-mcp fetch --tags
#   git -C third_party/godot-mcp checkout <tag>   # pin to a released bridge version
#   ./scripts/sync-bridge.sh
#   # then parse-check (see TESTING.md), commit the submodule bump + synced files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/third_party/godot-mcp/plugin/addons/godot_mcp_bridge"
DEST="$REPO_ROOT/addons/godot_mcp_bridge"

if [ ! -f "$SRC/plugin.cfg" ]; then
	echo "ERROR: bridge not found at $SRC" >&2
	echo "Initialize the submodule first: git submodule update --init" >&2
	exit 1
fi

echo "Syncing godot_mcp_bridge:"
echo "  from: $SRC"
echo "  to:   $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"

VERSION="$(grep -E '^version=' "$DEST/plugin.cfg" | head -1 | cut -d'"' -f2)"
SRC_REV="$(git -C "$REPO_ROOT/third_party/godot-mcp" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Done. Bundled bridge version $VERSION (godot-mcp @ $SRC_REV)."
echo "Next: parse-check, then commit third_party/godot-mcp and addons/godot_mcp_bridge."
