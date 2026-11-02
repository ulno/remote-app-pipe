#!/usr/bin/env bash
# Literal ~ values are passed through to remote-app-pipe on purpose.
# shellcheck disable=SC2088
# Integration tests for remote-app-pipe.
#
# These tests use fake ssh/scp/waypipe commands. They do not touch the network,
# your real SSH configuration, or your real desktop entries.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/remote-app-pipe"

if [[ ! -x "$APP" ]]; then
    echo "Error: $APP is not executable." >&2
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/remote-app-pipe-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
LOCAL_HOME="$WORK/local-home"
REMOTE_HOME="$WORK/remote-home"
TARGET="test-target"
SERVER_HOST="test-server-$$.invalid"

PASS=0
FAIL=0

mkdir -p "$BIN"

ok() {
    PASS=$((PASS + 1))
    printf 'ok %d - %s\n' "$PASS" "$1"
}

not_ok() {
    FAIL=$((FAIL + 1))
    printf 'not ok - %s\n' "$1" >&2
}

begin_test() {
    printf '\n# %s\n' "$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        not_ok "$desc (expected '$expected', got '$actual')"
    fi
}

assert_file() {
    local file="$1"
    local desc="$2"
    if [[ -f "$file" ]]; then
        ok "$desc"
    else
        not_ok "$desc (missing file: $file)"
    fi
}

assert_exec() {
    local file="$1"
    local desc="$2"
    if [[ -x "$file" ]]; then
        ok "$desc"
    else
        not_ok "$desc (not executable: $file)"
    fi
}

assert_no_file() {
    local path="$1"
    local desc="$2"
    if [[ ! -e "$path" ]]; then
        ok "$desc"
    else
        not_ok "$desc (unexpected path: $path)"
    fi
}

assert_contains() {
    local file="$1"
    local needle="$2"
    local desc="$3"
    if grep -Fq -- "$needle" "$file" 2>/dev/null; then
        ok "$desc"
    else
        not_ok "$desc (missing '$needle' in $file)"
    fi
}

assert_not_contains() {
    local file="$1"
    local needle="$2"
    local desc="$3"
    if grep -Fq -- "$needle" "$file" 2>/dev/null; then
        not_ok "$desc (unexpected '$needle' in $file)"
    else
        ok "$desc"
    fi
}

assert_no_line() {
    local file="$1"
    local line="$2"
    local desc="$3"
    if grep -Fxq -- "$line" "$file" 2>/dev/null; then
        not_ok "$desc (unexpected line '$line' in $file)"
    else
        ok "$desc"
    fi
}

assert_size() {
    local file="$1"
    local expected="$2"
    local desc="$3"
    local actual
    actual="$(wc -c < "$file" 2>/dev/null || echo 0)"
    assert_eq "$expected" "$actual" "$desc"
}

# ---------------------------------------------------------
# Fake remote tooling
# ---------------------------------------------------------
cat > "$BIN/ssh" <<'EOF'
#!/bin/sh
target=$1
shift
case "$*" in
    *'printf %s "$HOME"'*)
        printf '%s' "$FAKE_REMOTE_HOME"
        ;;
    "sh -s -- "*)
        HOME="$FAKE_REMOTE_HOME" sh -s -- "$4" "${5:-}"
        ;;
    "mkdir -p "*|"chmod +x "*)
        HOME="$FAKE_REMOTE_HOME" sh -c "$*"
        ;;
    *)
        echo "fake ssh: unhandled remote command: $*" >&2
        exit 1
        ;;
esac
EOF

cat > "$BIN/scp" <<'EOF'
#!/bin/sh
[ "$1" = "-q" ] && shift
[ "$1" = "--" ] && shift
src=$1
dest=$2
case "$src" in
    *:*) src=${src#*:} ;;
esac
case "$dest" in
    *:*) dest=${dest#*:} ;;
esac
mkdir -p "$(dirname "$dest")"
cp "$src" "$dest"
EOF

cat > "$BIN/waypipe" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_WAYPIPE_LOG"
if [ -n "${FAKE_WAYPIPE_OUTPUT:-}" ] && [ -f "$FAKE_WAYPIPE_OUTPUT" ]; then
    cat "$FAKE_WAYPIPE_OUTPUT" >&2
fi
if [ -n "${FAKE_WAYPIPE_STATUS:-}" ]; then
    exit "$FAKE_WAYPIPE_STATUS"
fi
EOF

cat > "$BIN/zenity" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_ZENITY_LOG"
exit 0
EOF

chmod +x "$BIN/ssh" "$BIN/scp" "$BIN/waypipe" "$BIN/zenity"

# ---------------------------------------------------------
# Test environment helpers
# ---------------------------------------------------------
reset_env() {
    rm -rf "$LOCAL_HOME" "$REMOTE_HOME"
    rm -f "$WORK/waypipe.args" "$WORK/out" "$WORK/fakeapp.args"
    mkdir -p \
        "$LOCAL_HOME/.local/share/applications" \
        "$REMOTE_HOME/.local/bin" \
        "$REMOTE_HOME/.local/share/applications"
}

run_app() {
    env -u SSH_CONNECTION \
        HOME="$LOCAL_HOME" \
        XDG_DATA_HOME="$LOCAL_HOME/.local/share" \
        FAKE_REMOTE_HOME="$REMOTE_HOME" \
        FAKE_WAYPIPE_LOG="$WORK/waypipe.args" \
        FAKE_WAYPIPE_OUTPUT="${FAKE_WAYPIPE_OUTPUT:-}" \
        FAKE_WAYPIPE_STATUS="${FAKE_WAYPIPE_STATUS:-0}" \
        FAKE_ZENITY_LOG="$WORK/zenity.args" \
        REMOTE_APP_PIPE_HANDOVER_TIMEOUT="${REMOTE_APP_PIPE_HANDOVER_TIMEOUT:-10}" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-test}" \
        PATH="$BIN:/usr/local/bin:/usr/bin:/bin" \
        "$APP" "$@"
}

install_remote_binary() {
    cp "$APP" "$REMOTE_HOME/.local/bin/remote-app-pipe"
    chmod +x "$REMOTE_HOME/.local/bin/remote-app-pipe"
}

make_remote_betterbird() {
    mkdir -p \
        "$REMOTE_HOME/.local/share/icons/hicolor/16x16/apps" \
        "$REMOTE_HOME/.local/share/icons/hicolor/256x256/apps"
    cat > "$REMOTE_HOME/.local/share/applications/eu.betterbird.Betterbird.desktop" <<'EOF'
[Desktop Entry]
Name=Betterbird
Exec=betterbird %u
Icon=betterbird
Type=Application
EOF
    printf 'small' > "$REMOTE_HOME/.local/share/icons/hicolor/16x16/apps/betterbird.png"
    dd if=/dev/zero of="$REMOTE_HOME/.local/share/icons/hicolor/256x256/apps/betterbird.png" \
        bs=1 count=300 2>/dev/null
}

# ---------------------------------------------------------
# Tests
# ---------------------------------------------------------
test_help() {
    begin_test "help output"
    run_app --help > "$WORK/out" 2>&1
    assert_eq 1 "$?" "help exits with usage status"
    assert_contains "$WORK/out" 'Usage:' "help shows usage"
    assert_contains "$WORK/out" '--refresh-icon' "help documents icon refresh"
    assert_contains "$WORK/out" '--debug' "help documents debug mode"
    assert_contains "$WORK/out" '--no-handover' "help documents handover opt-out"
}

test_validation() {
    begin_test "validation errors"
    run_app --install-desktop -a betterbird > "$WORK/out" 2>&1
    assert_eq 1 "$?" "missing -t is rejected"
    assert_contains "$WORK/out" 'Missing required parameter: -t' "missing -t error is clear"

    run_app -t "$TARGET" > "$WORK/out" 2>&1
    assert_eq 1 "$?" "missing app is rejected"
    assert_contains "$WORK/out" 'No application specified' "missing app error is clear"
}

test_host_derivation() {
    begin_test "server hostname is derived from the target"
    reset_env
    make_remote_betterbird
    install_remote_binary

    local target="remote-host.mydomain.mesh"
    run_app --install-desktop --no-fetch-icon \
        -t "$target" -a betterbird -i betterbird > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install without -H exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${target}.desktop"
    assert_file "$desktop" "desktop file created without -H"
    assert_contains "$desktop" '-H "remote-host"' "Exec records the derived hostname"
    assert_not_contains "$desktop" '-H "remote-host.mydomain.mesh"' "Exec does not use the full target as -H"

    run_app -t "$target" betterbird > "$WORK/out" 2>&1
    assert_eq 0 "$?" "launch without -H exits successfully"

    local derived
    derived="$(grep -A1 -Fx -- '-H' "$WORK/waypipe.args" | tail -n 1)"
    assert_eq "remote-host" "$derived" "launch derives -H from the target"
}

test_desktop_install_and_icon_fetch() {
    begin_test "desktop install and remote icon fetch"
    reset_env
    make_remote_betterbird

    run_app --install-desktop \
        -t "$TARGET" -H "$SERVER_HOST" \
        -a betterbird -n 'Betterbird (Home)' -i bettrbird \
        -c 'Mail and calendar' --categories 'Network;Email;' \
        > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    assert_file "$desktop" "desktop file created"
    assert_contains "$desktop" 'Name=Betterbird (Home)' "desktop name written"
    assert_contains "$desktop" 'Categories=Network;Email;' "desktop categories written"
    assert_contains "$desktop" 'StartupWMClass=eu.betterbird.Betterbird' "desktop taskbar class matches the remote app-id"
    assert_contains "$desktop" "\"$APP\"" "Exec uses the absolute local script path"
    assert_contains "$desktop" " -t \"${TARGET}\"" "Exec contains the target"
    assert_contains "$WORK/out" 'Fetched icon:' "install reports the fetched icon"

    local icon
    icon="$(sed -n 's/^Icon=//p' "$desktop" | head -n 1)"
    assert_file "$icon" "fetched icon exists locally"
    if [[ -f "$icon" ]]; then
        assert_size "$icon" 300 "largest remote icon was selected"
    fi
}

test_no_fetch_icon() {
    begin_test "desktop install with --no-fetch-icon"
    reset_env
    make_remote_betterbird

    run_app --install-desktop --no-fetch-icon \
        -t "$TARGET" -H "$SERVER_HOST" \
        betterbird -i bettrbird > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    assert_contains "$desktop" 'Icon=bettrbird' "explicit icon is kept"
    assert_contains "$desktop" 'StartupWMClass=eu.betterbird.Betterbird' "taskbar class is still resolved"
    assert_no_file "$LOCAL_HOME/.local/share/icons/remote-app-pipe" "no icon was copied"
}

test_refresh_icon() {
    begin_test "refresh icon from an existing desktop entry"
    reset_env
    make_remote_betterbird

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    cat > "$desktop" <<EOF
[Desktop Entry]
Name=Betterbird
Exec=remote-app-pipe -t ${TARGET} -H ${SERVER_HOST} betterbird %U
Icon=bettrbird
Type=Application
EOF

    run_app --refresh-icon "$desktop" > "$WORK/out" 2>&1
    assert_eq 0 "$?" "refresh exits successfully"
    assert_contains "$WORK/out" "Updated icon" "refresh reports success"
    assert_contains "$desktop" "Exec=remote-app-pipe -t ${TARGET}" "Exec line is preserved"

    local icon
    icon="$(sed -n 's/^Icon=//p' "$desktop" | head -n 1)"
    assert_file "$icon" "refreshed icon exists locally"
    assert_contains "$desktop" 'StartupWMClass=eu.betterbird.Betterbird' "refresh also repairs the taskbar class"

    run_app --refresh-icon "$WORK/does-not-exist.desktop" > "$WORK/out" 2>&1
    assert_eq 1 "$?" "refresh rejects a missing desktop file"
}

test_launch_resolves_absolute_remote_path() {
    begin_test "launch resolves the absolute remote executable"
    reset_env
    install_remote_binary

    run_app --debug -t "$TARGET" -H "$SERVER_HOST" betterbird --foo 'bar baz' > "$WORK/out" 2>&1
    assert_eq 0 "$?" "launch exits successfully"

    local log="$WORK/waypipe.args"
    assert_file "$log" "waypipe was invoked"
    assert_contains "$log" "$REMOTE_HOME/.local/bin/remote-app-pipe" "absolute remote path passed to waypipe"
    assert_contains "$log" '--server' "server mode flag passed"
    assert_contains "$log" 'bar baz' "argument with spaces is preserved"
    assert_no_line "$log" 'remote-app-pipe' "bare remote-app-pipe name is not used"
    assert_contains "$WORK/out" 'client mode: resolved remote executable' "debug shows the resolved remote executable"

    local debug_count
    debug_count="$(grep -Fxc -- '--debug' "$log")"
    assert_eq 2 "$debug_count" "debug flag is passed to waypipe and the remote script"
}

test_launch_missing_remote_binary() {
    begin_test "launch fails clearly without a remote binary"
    reset_env

    run_app -t "$TARGET" -H "$SERVER_HOST" betterbird > "$WORK/out" 2>&1
    assert_eq 1 "$?" "launch fails"
    assert_contains "$WORK/out" 'not executable' "error explains the missing binary"
    assert_contains "$WORK/out" 'Deploy it first' "error suggests --deploy"
}

test_deploy_expands_remote_home() {
    begin_test "deploy expands ~ against the remote home"
    reset_env

    run_app --deploy -t "$TARGET" > "$WORK/out" 2>&1
    assert_eq 0 "$?" "deploy exits successfully"
    assert_exec "$REMOTE_HOME/.local/bin/remote-app-pipe" "deployed binary is executable"
    assert_no_file "$REMOTE_HOME/~" "no literal tilde directory was created"

    local cmp_status=0
    cmp -s "$APP" "$REMOTE_HOME/.local/bin/remote-app-pipe" || cmp_status=$?
    assert_eq 0 "$cmp_status" "deployed file matches the local script"

    reset_env
    run_app --deploy -t "$TARGET" --bin-dir '~/custom-bin' > "$WORK/out" 2>&1
    assert_eq 0 "$?" "deploy with custom bin dir exits successfully"
    assert_exec "$REMOTE_HOME/custom-bin/remote-app-pipe" "custom remote bin dir is used"
    assert_no_file "$REMOTE_HOME/~" "custom bin dir does not create a literal tilde directory"
}

test_custom_bin_dir_in_desktop_exec() {
    begin_test "custom remote bin dir is stored in the launcher"
    reset_env

    run_app --install-desktop --no-fetch-icon \
        -t "$TARGET" -H "$SERVER_HOST" \
        betterbird -i betterbird --bin-dir '~/custom-bin' \
        > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    assert_contains "$desktop" '--bin-dir "~/custom-bin"' "Exec contains --bin-dir"
}

test_startup_wm_class_override() {
    begin_test "StartupWMClass override"
    reset_env

    run_app --install-desktop --no-fetch-icon \
        -t "$TARGET" -H "$SERVER_HOST" \
        betterbird -i betterbird --startup-wm-class 'org.example.Betterbird' \
        > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install with override exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    assert_contains "$desktop" 'StartupWMClass=org.example.Betterbird' "override is written to the launcher"
}

test_server_command_resolution() {
    begin_test "server command resolution"
    reset_env

    cat > "$BIN/zeditor" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$WORK/zeditor.args"
EOF
    chmod +x "$BIN/zeditor"

    # Simulate an app whose desktop-entry name differs from its binary.
    mkdir -p "$LOCAL_HOME/.local/share/applications"
    cat > "$LOCAL_HOME/.local/share/applications/dev.zed.Zed.desktop" <<'EOF'
[Desktop Entry]
Name=Zed
Exec=zeditor %U
TryExec=zeditor
Type=Application
EOF

    run_app --server --no-handover --debug zeditor 'arg one' > "$WORK/out" 2>&1
    assert_eq 0 "$?" "zeditor is found and runs"
    assert_file "$WORK/zeditor.args" "zeditor was executed"
    assert_contains "$WORK/zeditor.args" 'arg one' "zeditor argument passed"
    assert_contains "$WORK/out" 'app exited with status 0' "debug reports zeditor exit status"

    run_app --server --no-handover --debug zed 'arg two' > "$WORK/out" 2>&1
    assert_eq 0 "$?" "zed falls back to zeditor"
    assert_contains "$WORK/zeditor.args" 'arg two' "fallback zeditor received the argument"
}

test_server_missing_app() {
    begin_test "missing remote application"
    reset_env

    run_app --server --no-handover missing-app-xyz > "$WORK/out" 2>&1
    assert_eq 127 "$?" "missing app returns command-not-found status"
    assert_contains "$WORK/out" 'application not found' "missing app error is clear"
}

test_debug_and_generic_handover() {
    begin_test "debug output and generic handover"
    reset_env

    # Start a safely named long-running process that the generic handover
    # should find. Its WAYLAND_DISPLAY differs from the test client's.
    mkdir -p "$WORK/handover-proc"
    cp /bin/sleep "$WORK/handover-proc/rap-test-app"
    chmod +x "$WORK/handover-proc/rap-test-app"
    env WAYLAND_DISPLAY="wayland-victim-$$" "$WORK/handover-proc/rap-test-app" 60 &
    local victim=$!

    # This is what the script launches after the handover.
    cat > "$BIN/rap-test-app" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$WORK/rap-test-app.args"
EOF
    chmod +x "$BIN/rap-test-app"

    run_app --server --debug rap-test-app > "$WORK/out" 2>&1
    assert_eq 0 "$?" "server mode with --debug exits successfully"
    assert_file "$WORK/rap-test-app.args" "app was executed after handover"
    assert_contains "$WORK/out" 'handover: candidate pid' "handover found the running process"
    assert_contains "$WORK/out" 'handover: sending SIGTERM' "handover sent SIGTERM"
    assert_contains "$WORK/out" 'handover: pid' "handover reported pid details"
    assert_contains "$WORK/out" 'stopped' "handover reported the process stopped"
    assert_contains "$WORK/out" 'app exited with status 0' "debug reports the app exit status"

    local victim_state
    victim_state=$(ps -o stat= -p "$victim" 2>/dev/null | tr -d ' ' || true)
    if [[ -z "$victim_state" || "$victim_state" == Z* ]]; then
        ok "handover stopped the existing process"
    else
        not_ok "handover stopped the existing process"
    fi
    wait "$victim" 2>/dev/null || true
}

test_no_handover() {
    begin_test "--no-handover is preserved in launchers and remote commands"
    reset_env
    install_remote_binary

    run_app --install-desktop --no-fetch-icon --no-handover \
        -t "$TARGET" -H "$SERVER_HOST" \
        -a betterbird -i betterbird > "$WORK/out" 2>&1
    assert_eq 0 "$?" "install with --no-handover exits successfully"

    local desktop="$LOCAL_HOME/.local/share/applications/remote-betterbird-${TARGET}.desktop"
    assert_contains "$desktop" '--no-handover' "launcher records --no-handover"

    run_app --no-handover -t "$TARGET" -H "$SERVER_HOST" betterbird > "$WORK/out" 2>&1
    assert_eq 0 "$?" "launch with --no-handover exits successfully"
    assert_contains "$WORK/waypipe.args" '--no-handover' "remote command receives --no-handover"
}

test_handover_failure_remote() {
    begin_test "remote handover failure is reported"
    reset_env

    # The app must resolve, but the running process ignores SIGTERM and has a
    # unique argv[0] that the generic handover can match.
    cat > "$BIN/rap-stubborn-app" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$BIN/rap-stubborn-app"

    ( trap '' TERM; export WAYLAND_DISPLAY="wayland-stubborn-$$-test"; exec -a rap-stubborn-app sleep 60 ) &
    local victim=$!
    sleep 0.2

    REMOTE_APP_PIPE_HANDOVER_TIMEOUT=1 \
        run_app --server rap-stubborn-app > "$WORK/out" 2>&1
    assert_eq 75 "$?" "remote returns EX_TEMPFAIL on handover failure"
    assert_contains "$WORK/out" 'could not stop these' "failure lists the remaining processes"
    assert_contains "$WORK/out" 'REMOTE_APP_PIPE_HANDOVER_FAILED' "failure marker is emitted"

    kill -KILL "$victim" 2>/dev/null || true
    wait "$victim" 2>/dev/null || true
}

test_handover_failure_dialog() {
    begin_test "handover failure shows a client dialog"
    reset_env
    install_remote_binary

    printf 'REMOTE_APP_PIPE_HANDOVER_FAILED\n' > "$WORK/waypipe-output"
    FAKE_WAYPIPE_OUTPUT="$WORK/waypipe-output" FAKE_WAYPIPE_STATUS=75 \
        run_app -t "$TARGET" -H "$SERVER_HOST" betterbird > "$WORK/out" 2>&1
    assert_eq 75 "$?" "client returns the waypipe status"
    assert_file "$WORK/zenity.args" "dialog tool was invoked"
    assert_contains "$WORK/zenity.args" 'Could not stop' "dialog explains the handover failure"
}

test_server_mode() {
    begin_test "server mode runs the app locally"
    reset_env

    cat > "$BIN/fakeapp" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$WORK/fakeapp.args"
EOF
    chmod +x "$BIN/fakeapp"

    run_app --server fakeapp 'arg one' 'arg two' > "$WORK/out" 2>&1
    assert_eq 0 "$?" "server mode exits successfully"
    assert_file "$WORK/fakeapp.args" "app was executed"
    assert_contains "$WORK/fakeapp.args" 'arg one' "first app argument passed"
    assert_contains "$WORK/fakeapp.args" 'arg two' "second app argument passed"
}

# ---------------------------------------------------------
# Run
# ---------------------------------------------------------
test_help
test_validation
test_host_derivation
test_desktop_install_and_icon_fetch
test_no_fetch_icon
test_refresh_icon
test_launch_resolves_absolute_remote_path
test_launch_missing_remote_binary
test_deploy_expands_remote_home
test_custom_bin_dir_in_desktop_exec
test_startup_wm_class_override
test_no_handover
test_server_command_resolution
test_server_missing_app
test_debug_and_generic_handover
test_handover_failure_remote
test_handover_failure_dialog
test_server_mode

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
