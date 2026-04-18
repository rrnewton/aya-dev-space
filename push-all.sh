#!/bin/bash
set -e
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# On Meta devservers, GIT_CONFIG_* env vars rewrite SSH→HTTPS URLs,
# which breaks push (no HTTPS credentials). Unset them to use SSH.
git_push() {
    env -u GIT_CONFIG_COUNT \
        -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 \
        -u GIT_CONFIG_KEY_1 -u GIT_CONFIG_VALUE_1 \
        -u GIT_CONFIG_KEY_2 -u GIT_CONFIG_VALUE_2 \
        git push "$@"
}

echo "=== Pushing all repos ==="

# Push scx submodule first (parent references it)
echo ""
SCX_BRANCH=$(cd scx && git branch --show-current)
echo "--- scx → fork ($SCX_BRANCH) ---"
(cd scx && git_push fork "$SCX_BRANCH")

# Push aya submodule
echo ""
AYA_BRANCH=$(cd aya && git branch --show-current)
echo "--- aya → fork ($AYA_BRANCH) ---"
(cd aya && git_push fork "$AYA_BRANCH")

# Push parent repo last
echo ""
PARENT_BRANCH=$(git branch --show-current)
echo "--- parent → origin ($PARENT_BRANCH) ---"
git_push origin "$PARENT_BRANCH"

echo ""
echo "=== All repos pushed ==="
