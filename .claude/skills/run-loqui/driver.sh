#!/bin/bash
# Drive the Loqui menu bar app from a terminal. See SKILL.md next to this file.
#
#   driver.sh build              install/verify the model, build + sign Loqui.app
#   driver.sh launch             quit any running copy, launch, find its menu bar icon
#   driver.sh status             pid, memory, CPU, menu bar icon position
#   driver.sh logs [minutes]     unified log for the app's subsystem (default 5)
#   driver.sh ss [name]          full screenshot, the icon itself, and a menu bar crop
#   driver.sh menu               click the icon (needs Accessibility for the terminal)
#   driver.sh transcribe         real-model transcription smoke test on tests/fixtures/jfk.wav
#   driver.sh test               full unit test suite
#   driver.sh quit               AppKit terminate, SIGTERM fallback
#
# Output (screenshots, state) goes to $LOQUI_DRIVER_OUT, default $TMPDIR/loqui-driver.
set -euo pipefail

SKILL_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(CDPATH= cd -- "$SKILL_DIR/../../.." && pwd -P)"
TMP_ROOT="${TMPDIR:-/tmp}"
OUT="${LOQUI_DRIVER_OUT:-${TMP_ROOT%/}/loqui-driver}"
mkdir -p "$OUT"
APP="$ROOT/Loqui.app"
EXECUTABLE="$APP/Contents/MacOS/Loqui"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$ROOT/Loqui/Info.plist")"
ITEM_FILE="$OUT/statusitem-id"
LOG=/usr/bin/log   # zsh has a `log` builtin; always use the binary.

die() { echo "error: $*" >&2; exit 1; }

app_pid() { pgrep -f "^$EXECUTABLE" | head -1 || true; }

menubar_items() { swift "$SKILL_DIR/menubar-items.swift"; }

item_row() {
    local id; id="$(cat "$ITEM_FILE" 2>/dev/null)" || return 1
    menubar_items | awk -F'\t' -v id="$id" '$1 == id'
}

# Prints "identity<TAB>teamID" for the first Apple Development identity,
# preferring $LOQUI_DEVELOPMENT_TEAM. The team is the certificate's OU, which
# is NOT the ID in parentheses in the identity name.
signing_identity() {
    local name subject team first=""
    while IFS= read -r name; do
        subject="$(security find-certificate -c "$name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)" || continue
        team="$(sed -nE 's/.*OU ?= ?([A-Z0-9]+).*/\1/p' <<<"$subject")"
        [[ -n "$team" ]] || continue
        [[ -z "$first" ]] && first="$name"$'\t'"$team"
        if [[ -n "${LOQUI_DEVELOPMENT_TEAM:-}" && "$team" == "$LOQUI_DEVELOPMENT_TEAM" ]]; then
            printf '%s\t%s\n' "$name" "$team"; return
        fi
    done < <(security find-identity -v -p codesigning | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p')
    [[ -n "$first" ]] && printf '%s\n' "$first"
}

cmd_build() {
    cd "$ROOT"
    if ! ./scripts/dependency-tool.sh verify-model >/dev/null 2>&1; then
        echo "==> Installing pinned Parakeet model (~1.2 GB download)..."
        ./scripts/dependency-tool.sh install-model
    fi
    local signing
    signing="$(signing_identity)"
    if [[ -n "$signing" ]]; then
        echo "==> Signing with ${signing%%$'\t'*} (team ${signing##*$'\t'})"
        LOQUI_SIGNING_MODE=apple-development \
        LOQUI_SIGNING_IDENTITY="${signing%%$'\t'*}" \
        LOQUI_EXPECTED_TEAM_ID="${signing##*$'\t'}" \
            ./bundle.sh
    else
        echo "==> No Apple Development identity; ad-hoc signing (TCC grants reset every build)"
        ./bundle.sh
    fi
}

cmd_quit() {
    local pid; pid="$(app_pid)"
    [[ -n "$pid" ]] || { echo "not running"; return 0; }
    # Same mechanism as scripts/macos-app-lifecycle.ts: no Apple Events, so no
    # Automation consent prompt.
    osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.forEach(a => a.terminate); ''" >/dev/null
    for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || { echo "quit pid $pid"; rm -f "$ITEM_FILE"; return 0; }; sleep 0.1; done
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    echo "quit pid $pid (SIGTERM fallback)"
    rm -f "$ITEM_FILE"
}

cmd_launch() {
    [[ -x "$EXECUTABLE" ]] || die "no $APP; run: $0 build"
    cmd_quit >/dev/null
    local before pid row new_id
    before="$(menubar_items | cut -f1 | sort)"
    local since; since="$(date '+%Y-%m-%d %H:%M:%S')"
    open -n -a "$APP"
    for _ in $(seq 100); do pid="$(app_pid)"; [[ -n "$pid" ]] && break; sleep 0.1; done
    [[ -n "$pid" ]] || die "Loqui did not start; check: $0 logs"
    echo "pid $pid"
    for _ in $(seq 30); do
        new_id="$(comm -13 <(echo "$before") <(menubar_items | cut -f1 | sort) | head -1)"
        [[ -n "$new_id" ]] && break
        sleep 0.5
    done
    if [[ -n "$new_id" ]]; then
        echo "$new_id" > "$ITEM_FILE"
        row="$(item_row)"
        if [[ "$(cut -f2 <<<"$row")" == 1 ]]; then
            echo "menu bar icon: window $new_id at x=$(cut -f3 <<<"$row") width=$(cut -f5 <<<"$row")"
        else
            echo "menu bar icon: window $new_id exists but is OFF-SCREEN (menu bar full / hidden behind the notch)"
        fi
    else
        echo "warning: no new menu bar item appeared within 15s"
    fi
    # Model load is ~1s on relaunch but ~40s on the first launch after a build,
    # while Core ML recompiles its cache for the new bundle.
    local logs="" waited=0
    echo "waiting for model (up to ${LOQUI_MODEL_WAIT:-90}s)..."
    while (( waited < ${LOQUI_MODEL_WAIT:-90} )); do
        sleep 2; waited=$(( waited + 2 ))
        logs="$("$LOG" show --start "$since" --style compact --predicate "subsystem == \"$BUNDLE_ID\"" 2>/dev/null || true)"
        grep -q 'Dependency preflight' <<<"$logs" && break
    done
    if grep -q "recording monitor registered" <<<"$logs"; then
        echo "hotkey: $(grep -o "monitor registered; key: [A-Za-z]*" <<<"$logs" | tail -1 | sed "s/.*key: //") monitor registered"
    else
        echo "hotkey: monitor NOT registered (see: $0 logs)"
    fi
    if grep -q 'Dependency preflight ready' <<<"$logs"; then
        echo "model: $(grep -o 'Dependency preflight ready; [^;]*' <<<"$logs" | tail -1 | sed 's/.*; //') ready"
    else
        echo "model: NOT ready (see: $0 logs)"
    fi
}

cmd_status() {
    local pid; pid="$(app_pid)"
    [[ -n "$pid" ]] || { echo "not running"; return 1; }
    ps -o pid=,rss=,%cpu= -p "$pid" | awk '{printf "pid %s  rss %.0f MB  cpu %s%%\n", $1, $2/1024, $3}'
    local row; row="$(item_row || true)"
    if [[ -n "$row" ]]; then
        echo "menu bar icon: window $(cut -f1 <<<"$row") onscreen=$(cut -f2 <<<"$row") x=$(cut -f3 <<<"$row") width=$(cut -f5 <<<"$row")"
    else
        echo "menu bar icon: unknown (launch with this driver to track it)"
    fi
}

cmd_logs() {
    "$LOG" show --last "${1:-5}m" --style compact --predicate "subsystem == \"$BUNDLE_ID\"" | grep -v '^Timestamp'
}

cmd_ss() {
    local name="${1:-loqui}" full icon crop row id onscreen x y w h
    full="$OUT/$name-full.png"; icon="$OUT/$name-icon.png"; crop="$OUT/$name-menubar.png"
    screencapture -x "$full"
    echo "$full"
    row="$(item_row || true)"
    [[ -n "$row" ]] || { echo "(icon not tracked; run: $0 launch)"; return 0; }
    IFS=$'\t' read -r id onscreen x y w h _ <<<"$row"
    # Capturing by window ID renders the icon even when macOS hides it behind
    # the notch, so this always shows the app's current state symbol.
    screencapture -x -o -l "$id" "$icon"
    echo "$icon"
    if [[ "$onscreen" != 1 ]]; then
        echo "(icon is hidden behind the notch; no menu bar crop)"
        return 0
    fi
    # Pad 120pt on each side so neighbouring icons give context; an open menu
    # hangs below the icon, so capture 400pt down.
    x=$(( x > 120 ? x - 120 : 0 ))
    screencapture -x -R "$x,$y,$(( w + 240 )),400" "$crop"
    echo "$crop"
}

cmd_menu() {
    local row onscreen x y w h err
    row="$(item_row || true)"
    [[ -n "$row" ]] || die "icon not tracked; run: $0 launch"
    IFS=$'\t' read -r _ onscreen x y w h _ <<<"$row"
    [[ "$onscreen" == 1 ]] || die "icon is hidden behind the notch; make room in the menu bar first (see SKILL.md)"
    if ! err="$(osascript -e "tell application \"System Events\" to click at {$(( x + w / 2 )), $(( y + h / 2 ))}" 2>&1)"; then
        echo "$err" >&2
        die "clicking needs Accessibility for this terminal app (System Settings > Privacy & Security > Accessibility)"
    fi
    sleep 1
    cmd_ss menu-open
}

cmd_transcribe() {
    cd "$ROOT"
    ./scripts/dependency-tool.sh verify-model >/dev/null || die "model missing; run: $0 build"
    local out status=0
    out="$(LOQUI_PARAKEET_SMOKE_TEST=1 LOQUI_TEST_AUDIO="$ROOT/tests/fixtures/jfk.wav" \
        swift test --package-path Loqui --filter ParakeetIntegrationTests 2>&1)" || status=$?
    grep -E "^Test Case '.*' (passed|failed)" <<<"$out" || true
    grep -E ' error: ' <<<"$out" || true
    grep -o 'Parakeet short draft latency: [0-9.]* seconds' <<<"$out" || true
    return "$status"
}

cmd_test() {
    cd "$ROOT"
    local out status=0
    out="$(swift test --package-path Loqui 2>&1)" || status=$?
    grep -E ' error: |\) failed \(' <<<"$out" || true
    grep -E 'Executed [0-9]+ tests' <<<"$out" | tail -1
    return "$status"
}

case "${1:-}" in
    build) cmd_build ;;
    launch) cmd_launch ;;
    status) cmd_status ;;
    logs) shift; cmd_logs "$@" ;;
    ss) shift; cmd_ss "$@" ;;
    menu) cmd_menu ;;
    transcribe) cmd_transcribe ;;
    test) cmd_test ;;
    quit) cmd_quit ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
