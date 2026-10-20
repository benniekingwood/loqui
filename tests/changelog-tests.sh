#!/usr/bin/env bash
# Checks how scripts/changelog.sh keeps CHANGELOG.md and VERSION in step.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$PWD/scripts/changelog.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
run() { LOQUI_CHANGELOG_ROOT="$work" LOQUI_CHANGELOG_DATE=2030-01-02 "$script" "$@" 2>&1; }
expect_ok() { local d="$1"; shift; if out="$(run "$@")"; then pass "$d"; else flunk "$d: $out"; fi; }
expect_fail() {
    local d="$1" message="$2"; shift 2
    if out="$(run "$@")"; then flunk "$d: unexpectedly succeeded"
    elif [[ "$out" == *"$message"* ]]; then pass "$d"
    else flunk "$d: expected '$message', got '$out'"; fi
}
write() {
    printf '%s\n' "$1" > "$work/VERSION"
    printf '%s\n' "# Changelog" "" "Preamble." "" "${@:2}" > "$work/CHANGELOG.md"
}

write 1.1.0 "## [1.1.0] - 2030-01-01" "" "### Added" "" "- New thing." "" "## [1.0.0] - 2029-12-31" "" "- First."
expect_ok "a filled-in newest section matching VERSION passes" check
[[ "$(run notes)" == $'### Added\n\n- New thing.' ]] && pass "notes print only the current section" || flunk "notes: $(run notes)"
[[ "$(run notes 1.0.0)" == "- First." ]] && pass "notes print an older section" || flunk "older notes: $(run notes 1.0.0)"
expect_fail "notes for a missing version fail" "no notes for 9.9.9" notes 9.9.9

write 1.2.0 "## [1.1.0] - 2030-01-01" "" "- New thing."
expect_fail "VERSION without a section fails" "add a section for 1.2.0" check
write 1.1.0 "## [1.1.0] - 2030-01-01" "" "### Added" "" "- "
expect_fail "an empty bullet fails" "lists no changes" check
write 1.1.0 "## [1.1.0] - 2030-01-01" "" "- Real." "- "
expect_fail "a leftover empty bullet fails" "empty bullet" check
write 1.1.0 "## [1.1.0] - 2030-01-01" "" "- A." "" "## [1.2.0] - 2029-01-01" "" "- B."
expect_fail "sections out of order fail" "newest first" check
write 1.1.0 "## [1.1.0] - 2030-01-01" "" "- A." "" "## [1.1.0] - 2029-01-01" "" "- B."
expect_fail "duplicate sections fail" "newest first" check
write 1.1.0 "## [Unreleased]" "" "- A."
expect_fail "a heading without a version and date fails" "is not '## [x.y.z] - YYYY-MM-DD'" check

for case in "patch 1.1.1" "minor 1.2.0" "major 2.0.0"; do
    read -r part expected <<< "$case"
    write 1.1.0 "## [1.1.0] - 2030-01-01" "" "- A."
    run bump "$part" >/dev/null
    if [[ "$(cat "$work/VERSION")" == "$expected" ]] && grep -qx "## \[$expected\] - 2030-01-02" "$work/CHANGELOG.md" \
        && [[ "$(sed -n '5p' "$work/CHANGELOG.md")" == "## [$expected] - 2030-01-02" ]]; then
        pass "bump $part raises VERSION to $expected and opens a section above the last"
    else flunk "bump $part: $(cat "$work/VERSION")"; fi
done
expect_fail "a bumped section must be filled in" "lists no changes" check
sed -i '' 's/^- $/- Described./' "$work/CHANGELOG.md"
expect_ok "a filled-in bumped section passes" check
expect_fail "bump rejects unknown parts" "changelog.sh check" bump tiny

git -C "$work" init --quiet
write 1.1.0 "## [1.1.0] - 2030-01-01" "" "- A."
git -C "$work" add . && git -C "$work" -c user.name=Fixture -c user.email=fixture@localhost commit --quiet -m base
expect_fail "an unchanged VERSION fails the pull request check" "must be raised above 1.1.0" check-bump HEAD
run bump patch >/dev/null && sed -i '' 's/^- $/- Fix./' "$work/CHANGELOG.md"
expect_ok "a raised VERSION passes the pull request check" check-bump HEAD
write 1.0.9 "## [1.0.9] - 2030-01-01" "" "- A."
expect_fail "a lowered VERSION fails the pull request check" "must be raised above 1.1.0" check-bump HEAD
expect_fail "an unknown base fails" "unknown base revision" check-bump no-such-ref
exit "$failures"
