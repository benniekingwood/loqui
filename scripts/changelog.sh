#!/bin/bash
# Keeps CHANGELOG.md and VERSION in step. Every change merged into main gets a
# new version and a changelog section describing it.
#
#   changelog.sh check               newest section matches VERSION and is filled in
#   changelog.sh check-bump <ref>    VERSION is newer than at <ref> (pull requests)
#   changelog.sh bump <major|minor|patch>
#                                    raise VERSION and open a dated section for it
#   changelog.sh notes [version]     print one section's notes (default: VERSION)
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${LOQUI_CHANGELOG_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)}"
CHANGELOG="$ROOT/CHANGELOG.md"
VERSION_FILE="$ROOT/VERSION"
SEMVER='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
HEADING="^## \\[($SEMVER)\\] - ([0-9]{4}-[0-9]{2}-[0-9]{2})\$"

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

read_version() {
    LOQUI_VERSION_FILE="$1" "$SCRIPT_DIR/read-version.sh"
}

# Succeeds when $1 is strictly newer than $2.
version_is_newer() {
    local newer older index
    IFS=. read -r -a newer <<< "$1"
    IFS=. read -r -a older <<< "$2"
    for index in 0 1 2; do
        (( newer[index] > older[index] )) && return 0
        (( newer[index] < older[index] )) && return 1
    done
    return 1
}

# Prints "version date" for every release heading, newest first.
release_headings() {
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ $HEADING ]]; then
            printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[5]}"
        elif [[ "$line" == '## '* ]]; then
            fail "CHANGELOG.md heading is not '## [x.y.z] - YYYY-MM-DD': $line"
        fi
    done < "$CHANGELOG"
}

section_notes() {
    awk -v heading="## [$1] - " '
        index($0, heading) == 1 { found = 1; next }
        found && /^## / { exit }
        found && /^\[[^]]+\]: / { exit }
        found { print }
    ' "$CHANGELOG" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

check() {
    [[ -f "$CHANGELOG" ]] || fail "CHANGELOG.md is missing"
    local version headings newest newest_date previous notes
    version="$(read_version "$VERSION_FILE")"
    headings="$(release_headings)"
    [[ -n "$headings" ]] || fail "CHANGELOG.md has no release sections"

    read -r newest newest_date <<< "$(sed -n '1p' <<< "$headings")"
    [[ "$newest" == "$version" ]] || \
        fail "VERSION is $version but the newest CHANGELOG.md section is $newest; add a section for $version"
    [[ "$newest_date" != '0000-00-00' ]] || fail "CHANGELOG.md section $newest has no date"

    previous=''
    while read -r version _; do
        if [[ -n "$previous" ]]; then
            version_is_newer "$previous" "$version" || \
                fail "CHANGELOG.md sections must be newest first and unique: $version follows $previous"
        fi
        previous="$version"
    done <<< "$headings"

    notes="$(section_notes "$newest")"
    grep -Eq '^- [^[:space:]]' <<< "$notes" || \
        fail "CHANGELOG.md section $newest lists no changes"
    if grep -Eq '^-[[:space:]]*$' <<< "$notes"; then
        fail "CHANGELOG.md section $newest has an empty bullet; describe the change"
    fi
    echo "CHANGELOG.md documents $newest"
}

check_bump() {
    local base="$1" base_version version
    git -C "$ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null || fail "unknown base revision: $base"
    check >/dev/null
    version="$(read_version "$VERSION_FILE")"
    if ! git -C "$ROOT" cat-file -e "$base:VERSION" 2>/dev/null; then
        echo "$base has no VERSION; $version is the first version"
        return
    fi
    base_version="$(git -C "$ROOT" show "$base:VERSION" | tr -d '[:space:]')"
    [[ "$base_version" =~ ^$SEMVER$ ]] || fail "$base has an invalid VERSION: $base_version"
    version_is_newer "$version" "$base_version" || \
        fail "VERSION must be raised above $base_version for this change; run scripts/changelog.sh bump patch|minor|major"
    echo "VERSION raised from $base_version to $version"
}

bump() {
    local part="$1" version major minor patch next today section
    version="$(read_version "$VERSION_FILE")"
    IFS=. read -r major minor patch <<< "$version"
    case "$part" in
        major) next="$((major + 1)).0.0" ;;
        minor) next="$major.$((minor + 1)).0" ;;
        patch) next="$major.$minor.$((patch + 1))" ;;
        *) usage ;;
    esac
    today="${LOQUI_CHANGELOG_DATE:-$(date +%F)}"
    # awk expands the \n escapes; BSD awk rejects literal newlines in -v values.
    section="## [$next] - $today\\n\\n### Changed\\n\\n- \\n"
    # Insert the new section above the newest release, keeping the preamble.
    awk -v section="$section" '
        !done && /^## \[/ { print section; done = 1 }
        { print }
        END { if (!done) { print ""; print section } }
    ' "$CHANGELOG" > "$CHANGELOG.tmp"
    mv "$CHANGELOG.tmp" "$CHANGELOG"
    printf '%s\n' "$next" > "$VERSION_FILE"
    echo "VERSION is now $next. Describe the change under '## [$next]' in CHANGELOG.md."
}

notes() {
    local version="${1:-$(read_version "$VERSION_FILE")}" text
    text="$(section_notes "$version")"
    [[ -n "$text" ]] || fail "CHANGELOG.md has no notes for $version"
    printf '%s\n' "$text"
}

case "${1:-}" in
    check) [[ $# -eq 1 ]] || usage; check ;;
    check-bump) [[ $# -eq 2 ]] || usage; check_bump "$2" ;;
    bump) [[ $# -eq 2 ]] || usage; [[ -f "$CHANGELOG" ]] || fail "CHANGELOG.md is missing"; bump "$2" ;;
    notes) [[ $# -le 2 ]] || usage; notes "${2:-}" ;;
    *) usage ;;
esac
