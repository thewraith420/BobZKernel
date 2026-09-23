#!/bin/bash
# Guard for the nightfall-kernel branch: it must stay a SUPERSET of the Slate's
# picker kernel. Every CONFIG_X=y in the frozen picker-kernel config must still
# be =y in configs/config-7.2-nightfall. A symbol that drops to =m or is switched
# off is invisible to the module-less initramfs, i.e. exactly how the Slate's
# touch stack (LPSS/pinctrl/cros_ec) silently broke before.
#
# Crossing kernel versions (7.1 baseline vs a 7.2 candidate) also renames and
# removes symbols. So a missing symbol is classified against the kernel tree:
#   - no longer defined in any Kconfig  -> "removed upstream" (listed, not fatal)
#   - defined as a `transitional` stub  -> migrated to a new symbol (listed, not fatal)
#   - still defined but not =y          -> REAL LOSS (fatal)
#
# Usage: ./scripts/check-nightfall-superset.sh [candidate] [baseline-ref] [kernel-tree]
# Exit 0 = superset holds, 1 = something the Slate needs was lost, 2 = usage/setup.
set -e
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAND="${1:-$BASE_DIR/configs/config-7.2-nightfall}"
REF="${2:-picker-kernel}"
TREE="${3:-$BASE_DIR/builds/linux-7.2}"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git -C "$BASE_DIR" show "$REF:configs/config-7.1-picker" > "$TMP/base" 2>/dev/null || {
    echo "cannot read configs/config-7.1-picker from git ref '$REF'" >&2; exit 2; }
[ -d "$TREE" ] || { echo "kernel tree not found: $TREE (needed to tell removed-upstream from lost)" >&2; exit 2; }

grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "$TMP/base" | sort > "$TMP/want"
grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "$CAND"      | sort > "$TMP/have"
comm -23 "$TMP/want" "$TMP/have" | sed 's/=y$//' > "$TMP/missing"
gained=$(comm -13 "$TMP/want" "$TMP/have" | wc -l)

# every symbol the tree still defines
grep -rhoE '^(menu)?config [A-Za-z0-9_]+' --include='Kconfig*' "$TREE" | awk '{print "CONFIG_" $2}' | sort -u > "$TMP/defined"

# symbols the tree keeps only as `transitional` migration stubs
find "$TREE" -name 'Kconfig*' -type f -print0 | xargs -0 awk '/^(menu)?config /{sym=$2} /^[ \t]+transitional/{print "CONFIG_" sym}' | sort -u > "$TMP/transitional"

echo "baseline ($REF): $(wc -l < "$TMP/want") symbols =y   candidate: $(wc -l < "$TMP/have") =y   newly =y: $gained"
gone=(); moved=(); lost=()
while read -r sym; do
    [ -n "$sym" ] || continue
    if   grep -qx "$sym" "$TMP/transitional"; then moved+=("$sym")
    elif grep -qx "$sym" "$TMP/defined";      then lost+=("$sym")
    else gone+=("$sym"); fi
done < "$TMP/missing"

if [ ${#moved[@]} -gt 0 ]; then
    echo "migrated to a successor symbol (${#moved[@]}, transitional stub in this kernel - confirm the successor is on):"
    printf '  %s\n' "${moved[@]}"
fi
if [ ${#gone[@]} -gt 0 ]; then
    echo "removed/renamed upstream in this kernel (${#gone[@]}, not fatal - eyeball for Slate relevance):"
    printf '  %s\n' "${gone[@]}"
fi
if [ ${#lost[@]} -gt 0 ]; then
    echo "REAL LOSS - still exists in this kernel, was =y for the Slate, and no longer is:"
    for sym in "${lost[@]}"; do
        printf '  %-40s now: %s\n' "$sym" "$(grep -E "^(# )?$sym[= ]" "$CAND" || echo 'not in config')"
    done
    exit 1
fi
echo "OK: everything the Slate's picker kernel builds in is still built in."
