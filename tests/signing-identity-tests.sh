#!/usr/bin/env bash
# Checks how scripts/signing-identity.sh picks a local signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."
script=./scripts/signing-identity.sh
failures=0
expect() {
    local description="$1" expected="$2" actual
    actual="$(env "${@:3}" "$script" 2>/dev/null || echo "<none>")"
    if [[ "$actual" == "$expected" ]]; then echo "ok - $description"; else
        echo "not ok - $description: expected '$expected', got '$actual'"; failures=$((failures + 1)); fi
}
two=$'Apple Development: A (PERSON1)\tTEAMAAAAAA\nApple Development: B (PERSON2)\tTEAMBBBBBB'
expect "first identity wins by default" $'Apple Development: A (PERSON1)\tTEAMAAAAAA' LOQUI_SIGNING_IDENTITIES="$two"
expect "LOQUI_DEVELOPMENT_TEAM selects its team" $'Apple Development: B (PERSON2)\tTEAMBBBBBB' LOQUI_SIGNING_IDENTITIES="$two" LOQUI_DEVELOPMENT_TEAM=TEAMBBBBBB
expect "an unknown preferred team falls back to the first" $'Apple Development: A (PERSON1)\tTEAMAAAAAA' LOQUI_SIGNING_IDENTITIES="$two" LOQUI_DEVELOPMENT_TEAM=NOPE
expect "rows without a team are skipped" $'Apple Development: B (PERSON2)\tTEAMBBBBBB' LOQUI_SIGNING_IDENTITIES=$'Apple Development: A (PERSON1)\t\nApple Development: B (PERSON2)\tTEAMBBBBBB'
expect "no identity prints nothing and fails" "<none>" LOQUI_SIGNING_IDENTITIES=$'\t'
exit "$failures"
