#!/usr/bin/env bash
# Prints "identity<TAB>teamID" for the Apple Development identity to sign local
# builds with, or nothing (exit 1) when the keychain has none.
#
# The team is the certificate's OU, which is NOT the ID in parentheses in the
# identity name. When the keychain holds several teams, set
# LOQUI_DEVELOPMENT_TEAM to choose one; otherwise the first identity wins.
#
# LOQUI_SIGNING_IDENTITIES (newline-separated "identity<TAB>OU" rows) replaces
# the keychain lookup, for tests.
set -euo pipefail

candidates() {
    if [[ -n "${LOQUI_SIGNING_IDENTITIES:-}" ]]; then
        printf '%s\n' "$LOQUI_SIGNING_IDENTITIES"
        return
    fi
    local name subject team
    while IFS= read -r name; do
        subject="$(security find-certificate -c "$name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)" || continue
        team="$(sed -nE 's/.*OU ?= ?([A-Z0-9]+).*/\1/p' <<<"$subject")"
        [[ -n "$team" ]] && printf '%s\t%s\n' "$name" "$team"
    done < <(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p')
}

first=""
while IFS=$'\t' read -r name team; do
    [[ -n "$name" && -n "$team" ]] || continue
    [[ -z "$first" ]] && first="$name"$'\t'"$team"
    if [[ -n "${LOQUI_DEVELOPMENT_TEAM:-}" && "$team" == "$LOQUI_DEVELOPMENT_TEAM" ]]; then
        printf '%s\t%s\n' "$name" "$team"
        exit 0
    fi
done < <(candidates)

[[ -n "$first" ]] || exit 1
printf '%s\n' "$first"
