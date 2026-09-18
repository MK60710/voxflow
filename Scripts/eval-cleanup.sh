#!/bin/bash
# Step 6, blueprint task 5: ON-DEMAND cleanup-quality eval — 15 real
# messy-transcript -> expected-clean pairs run against the real Groq API
# using Mihir's real Keychain-stored key. NOT part of Scripts/test.sh's
# build gate (that suite is offline-only, mocked-transport, per the
# blueprint's own instruction that live-LLM tests are nondeterministic and
# burn rate limits). Run manually, whenever you want to re-check cleanup
# quality after touching CleanupPromptTemplate.swift or the Groq model
# choice:
#
#   Scripts/eval-cleanup.sh
#
# This just runs the real Swift target (VoxFlowCleanupEval) so the eval
# always exercises the exact production prompt/engine code, never a
# hand-copied duplicate that could drift out of sync.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Fetch the key via the CLI `security` tool (already trusted on this
# machine, returns instantly) rather than letting the Swift binary call
# SecItemCopyMatching itself — a brand-new/not-yet-approved binary doing
# that triggers a one-time interactive Keychain-authorization dialog
# (routed through SecurityAgent) that a headless/unattended run has no way
# to click through and will hang on indefinitely. Passed via environment
# variable only: never echoed, never written to a file, unset immediately
# after the run.
GROQ_API_KEY="$(security find-generic-password -a "groq-api-key" -s "com.mihirk.voxflow" -w 2>/dev/null || true)"
if [ -z "$GROQ_API_KEY" ]; then
    echo "No Groq key found via 'security find-generic-password' (service com.mihirk.voxflow, account groq-api-key)." >&2
    exit 1
fi
export GROQ_API_KEY
swift run VoxFlowCleanupEval
unset GROQ_API_KEY
