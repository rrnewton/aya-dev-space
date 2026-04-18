#!/bin/bash
set -e
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

echo "=== Pushing all repos ==="

# Push scx submodule first (parent references it)
echo ""
SCX_BRANCH=$(cd scx && git branch --show-current)
echo "--- scx → fork ($SCX_BRANCH) ---"
(cd scx && with-proxy git push fork "$SCX_BRANCH")

# Push aya submodule
echo ""
AYA_BRANCH=$(cd aya && git branch --show-current)
echo "--- aya → fork ($AYA_BRANCH) ---"
(cd aya && with-proxy git push fork "$AYA_BRANCH")

# Push parent repo last
echo ""
PARENT_BRANCH=$(git branch --show-current)
echo "--- parent → origin ($PARENT_BRANCH) ---"
with-proxy git push origin "$PARENT_BRANCH"

echo ""
echo "=== All repos pushed ==="
