#!/usr/bin/env bash
# Builds Loqui, installs it into /Applications, and relaunches it if it was
# running. The install is atomic: the previous copy is restored if anything
# fails after it was moved aside.
#
#   ./scripts/deploy.sh
#
# Optional:
#   LOQUI_INSTALL_DIR=/path   install somewhere other than /Applications
#   LOQUI_SKIP_BUILD=1        install the existing ./Loqui.app without rebuilding
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$ROOT/Loqui/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"; }
APP_NAME="$(plist CFBundleName)"
EXECUTABLE_NAME="$(plist CFBundleExecutable)"
BUNDLE_ID="$(plist CFBundleIdentifier)"
SOURCE_APP="$ROOT/$APP_NAME.app"
INSTALL_DIR="${LOQUI_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

fail() { echo "error: $*" >&2; exit 1; }
[[ "$(uname)" == Darwin ]] || fail "Loqui builds and installs on macOS only"

if identity="$("$SCRIPT_DIR/signing-identity.sh")"; then
    export LOQUI_SIGNING_MODE=apple-development
    export LOQUI_SIGNING_IDENTITY="${identity%%$'\t'*}"
    export LOQUI_EXPECTED_TEAM_ID="${identity##*$'\t'}"
    echo "==> Signing with $LOQUI_SIGNING_IDENTITY (team $LOQUI_EXPECTED_TEAM_ID)"
else
    export LOQUI_SIGNING_MODE=adhoc
    echo "warning: no Apple Development identity found; signing ad-hoc." >&2
    echo "         macOS will ask again for Microphone and Accessibility after each install." >&2
fi

if [[ "${LOQUI_SKIP_BUILD:-0}" != 1 ]]; then
    echo "==> Building $APP_NAME..."
    "$ROOT/bundle.sh"
fi
[[ -x "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" ]] || fail "$SOURCE_APP is missing; build it first"

# NSRunningApplication.terminate needs no Apple Events, so it never triggers an
# Automation consent prompt.
running_pids() { pgrep -f "/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME\$" || true; }
stop_running_app() {
    osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID').js.forEach(a => a.terminate); ''" >/dev/null
    for _ in $(seq 50); do
        [[ -z "$(running_pids)" ]] && return 0
        sleep 0.1
    done
    running_pids | xargs kill -TERM 2>/dev/null || true
}

was_running=0
if [[ -n "$(running_pids)" ]]; then
    was_running=1
    echo "==> Quitting the running $APP_NAME..."
    stop_running_app
fi

mkdir -p "$INSTALL_DIR"
staging="$(mktemp -d "$INSTALL_DIR/.loqui-install-XXXXXX" 2>/dev/null)" || \
    fail "$INSTALL_DIR is not writable by this account. Install from an administrator account, or copy $APP_NAME.app there by hand."
previous="$staging/previous-$APP_NAME.app"
restore_previous() {
    if [[ -d "$previous" && ! -e "$INSTALLED_APP" ]]; then
        mv -- "$previous" "$INSTALLED_APP"
    fi
    rm -rf -- "$staging"
}
trap restore_previous EXIT

echo "==> Staging $INSTALLED_APP..."
/usr/bin/ditto "$SOURCE_APP" "$staging/$APP_NAME.app"
LOQUI_EXPECTED_SIGNATURE="$LOQUI_SIGNING_MODE" "$SCRIPT_DIR/verify-bundle.sh" "$staging/$APP_NAME.app"
if [[ -e "$INSTALLED_APP" ]]; then
    mv -- "$INSTALLED_APP" "$previous"
fi
mv -- "$staging/$APP_NAME.app" "$INSTALLED_APP"
rm -rf -- "$previous"
[[ -x "$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME" ]] || fail "installed executable is missing"

if [[ "$was_running" == 1 ]]; then
    echo "==> Relaunching $APP_NAME..."
    open -a "$INSTALLED_APP"
fi
echo "==> Installed $INSTALLED_APP"
