#!/bin/bash
# Build, bundle, sign, and launch VoxFlow.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$REPO_ROOT/Scripts/bundle.sh" "${1:-debug}"

# Relaunch cleanly if already running.
pkill -x VoxFlow 2>/dev/null || true
sleep 0.3
open "$REPO_ROOT/.build/VoxFlow.app"
echo "VoxFlow launched — look for the waveform icon in the menu bar."
