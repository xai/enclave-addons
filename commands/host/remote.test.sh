#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
remote=$script_dir/remote
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_file() {
    expected=$1
    file=$2
    actual=$(cat "$file")
    [ "$actual" = "$expected" ] || fail "$file: expected '$expected', got '$actual'"
}

assert_status() {
    expected_status=$1
    shift
    if "$@"; then
        actual_status=0
    else
        actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] ||
        fail "expected status $expected_status, got $actual_status from $*"
}

repo=$tmp/repo
home=$tmp/home
fakebin=$tmp/bin
capture=$tmp/capture
mkdir -p "$repo" "$home" "$fakebin" "$capture"
git -C "$repo" init -q -b 'Feature/Quoting.case'
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" remote add origin https://example.invalid/acme/repo.git
printf 'tracked\n' > "$repo/tracked"
git -C "$repo" add tracked
git -C "$repo" commit -qm initial

cat > "$fakebin/enclave" <<'EOF'
#!/bin/sh
if [ "${1:-}" = version ] && [ "${2:-}" = --json ]; then
    printf '%s\n' '{"version":"test","commit":"local-commit","date":"today"}'
    exit 0
fi

: "${CAPTURE:?}"
rm -f "$CAPTURE"/arg.*
i=0
for arg in "$@"; do
    printf '%s' "$arg" > "$CAPTURE/arg.$i"
    i=$((i + 1))
done
printf '%s' "$i" > "$CAPTURE/argc"
printf '%s' "${ENCLAVE_YOLO-unset}" > "$CAPTURE/yolo"
printf '%s' "${FOO-unset}" > "$CAPTURE/foo"
printf '%s' "${ENCLAVE_BIN-unset}" > "$CAPTURE/bin"
printf '%s' "${ENCLAVE_PROJECT_ROOT-unset}" > "$CAPTURE/project-root"
printf '%s' "${ENCLAVE_CONFIG_DIR-unset}" > "$CAPTURE/config-dir"
printf '%s' "${ENCLAVE_REMOTE_HOST-unset}" > "$CAPTURE/remote-host"
exit "${ENCLAVE_TEST_EXIT:-0}"
EOF
chmod +x "$fakebin/enclave"

release_dir=$tmp/release
mkdir -p "$release_dir"
cp "$fakebin/enclave" "$release_dir/enclave-linux-amd64"
cp "$fakebin/enclave" "$release_dir/enclave-linux-arm64"
release_checksum=$(sha256sum "$release_dir/enclave-linux-amd64")
release_checksum=${release_checksum%% *}

cat > "$fakebin/curl" <<'EOF'
#!/bin/sh
set -eu
for url in "$@"; do :; done
case "$url" in
    */checksums.txt)
        printf '%s  %s\n' \
            "$RELEASE_CHECKSUM" enclave-linux-amd64 \
            "$RELEASE_CHECKSUM" enclave-linux-arm64
        ;;
    */enclave-linux-amd64|*/enclave-linux-arm64)
        cat "$RELEASE_DIR/${url##*/}"
        ;;
    *) exit 22 ;;
esac
EOF
chmod +x "$fakebin/curl"

cat > "$fakebin/ssh" <<'EOF'
#!/bin/sh
set -eu

while [ $# -gt 0 ]; do
    case "$1" in
        -o)
            case "$2" in
                ControlPath=*)
                    if [ -n "${CAPTURE:-}" ]; then
                        printf '%s\n' "${2#ControlPath=}" >> "$CAPTURE/control-paths"
                    fi
                    ;;
            esac
            shift 2
            ;;
        -S|-O|-i|-F|-J|-l|-p) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || exit 2
host=$1
shift

if [ "${SSH_MODE:-capture}" = execute ]; then
    [ $# -gt 0 ] || exit 0
    cd "$HOME"
    exec sh -c "$*"
fi
if [ "${SSH_MODE:-capture}" = bootstrap ] || [ "${SSH_MODE:-capture}" = bootstrap-arm64 ]; then
    [ $# -gt 0 ] || exit 0
    if [ "$SSH_MODE" = bootstrap-arm64 ]; then
        case "$*" in
            *'uname -s; uname -m'*) printf '%s\n' Linux aarch64; exit 0 ;;
        esac
    fi
    cd "$HOME"
    PATH="/usr/bin:/bin:$HOME/.local/bin" exec sh -c "$*"
fi

: "${CAPTURE:?}"
printf '%s' "$host" > "$CAPTURE/ssh-host"
printf '%s' "$#" > "$CAPTURE/ssh-argc"
i=0
for arg in "$@"; do
    printf '%s' "$arg" > "$CAPTURE/ssh-arg.$i"
    i=$((i + 1))
done
EOF
chmod +x "$fakebin/ssh"

# Help is wholly local, even without project or host configuration.
env -i PATH="$PATH" "$remote" -h > "$tmp/help"
grep -q '^Usage: enclave remote' "$tmp/help" || fail 'help did not print usage'

git -C "$repo" config enclave.remote.host configured-host
env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 "$remote" --sync=none version --json \
    > "$tmp/configured-host-command"
grep -q "'configured-host'" "$tmp/configured-host-command" ||
    fail 'git-configured host was not selected'

env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 "$remote" build-host.example \
    > "$tmp/host-only-command"
grep -q "'build-host.example'" "$tmp/host-only-command" ||
    fail 'sole positional argument was not selected as the host'

# Dry-run output is executable shell syntax. Replay it through a fake ssh, then
# replay the captured remote command through a fake enclave. This independently
# checks every quoting layer, including a trailing newline in one argument.
newline_arg='line one
line two
'
env -i \
    PATH="$PATH" \
    HOME="$home" \
    ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_CONFIG_DIR="$tmp/local-config" \
    ENCLAVE_BIN="$fakebin/enclave" \
    ENCLAVE_REMOTE_DRY_RUN=1 \
    ENCLAVE_REMOTE_HOST=ignored \
    ENCLAVE_YOLO=0 \
    FOO=bar \
    "$remote" pi --sync=none --tool claude -- \
    'space value' "single'quote" "\$dollar" "\`backticks\`" "$newline_arg" \
    > "$tmp/dry-command"

env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" \
    sh -c "$(cat "$tmp/dry-command")"
assert_file pi "$capture/ssh-host"
assert_file 1 "$capture/ssh-argc"

project_hash=$(printf '%s' https://example.invalid/acme/repo.git |
    git -C "$repo" hash-object --stdin)
branch_hash=$(printf '%s' 'Feature/Quoting.case' |
    git -C "$repo" hash-object --stdin)
workspace_root=$home/.local/share/enclave/remote-workspaces
remote_checkout=$workspace_root/repo-$project_hash/feature-quoting-case-$branch_hash
mkdir -p "$remote_checkout"
remote_command=$(cat "$capture/ssh-arg.0")
env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" \
    sh -c "$remote_command"

assert_file 8 "$capture/argc"
assert_file --tool "$capture/arg.0"
assert_file claude "$capture/arg.1"
assert_file -- "$capture/arg.2"
assert_file 'space value' "$capture/arg.3"
assert_file "single'quote" "$capture/arg.4"
assert_file "\$dollar" "$capture/arg.5"
assert_file "\`backticks\`" "$capture/arg.6"
printf '%s' "$newline_arg" > "$tmp/expected-newline-arg"
cmp -s "$capture/arg.7" "$tmp/expected-newline-arg" ||
    fail 'newline argument did not round-trip'
assert_file 0 "$capture/yolo"
assert_file unset "$capture/foo"
assert_file unset "$capture/bin"
assert_file unset "$capture/project-root"
assert_file unset "$capture/config-dir"
assert_file unset "$capture/remote-host"

# Enclave options are inspected only before the forwarded --.
env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 ENCLAVE_REMOTE_HOST=pi \
    "$remote" --sync=none -p 3000 -- -p hello \
    > "$tmp/port-command" 2> "$tmp/port-stderr"
grep -q 'ssh -L 3000:127.0.0.1:3000 pi' "$tmp/port-stderr" ||
    fail 'published port did not print a tunnel hint'

env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 ENCLAVE_REMOTE_HOST=pi \
    "$remote" --sync=none -- -p hello \
    > "$tmp/tool-port-command" 2> "$tmp/tool-port-stderr"
[ ! -s "$tmp/tool-port-stderr" ] || fail 'tool -p incorrectly printed a tunnel hint'

assert_status 2 env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 ENCLAVE_REMOTE_HOST=pi \
    "$remote" --sync=none --bridge-port 3000
assert_status 2 env -i PATH="$PATH" HOME="$home" ENCLAVE_PROJECT_ROOT="$repo" \
    ENCLAVE_REMOTE_DRY_RUN=1 ENCLAVE_REMOTE_HOST=pi \
    "$remote" --sync=none --tool theia

# A dirty session-starting checkout fails before the first SSH process.
printf 'dirty\n' >> "$repo/tracked"
rm -f "$capture/ssh-host"
assert_status 2 env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" \
    "$remote" pi --tool claude -- -p hello
[ ! -e "$capture/ssh-host" ] || fail 'dirty checkout contacted SSH'
git -C "$repo" checkout -q -- tracked

# The default root is never adopted when it already contains unmarked data.
rm -rf "$workspace_root"
mkdir -p "$workspace_root"
printf 'keep\n' > "$workspace_root/user-data"
assert_status 73 env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=execute \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" \
    "$remote" pi --tool claude --background --name t -- -p hello
[ -f "$workspace_root/user-data" ] || fail 'unmarked workspace root was modified'

# A complete sync can be exercised locally: fake ssh executes its remote
# command, including git-receive-pack for the push.
rm -rf "$workspace_root"
rm -f "$capture/control-paths"
if ! env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=execute \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" ENCLAVE_YOLO=0 \
    "$remote" pi --tool claude --background --name t -- -p hello \
    > "$tmp/sync-stdout" 2> "$tmp/sync-stderr"; then
    cat "$tmp/sync-stderr" >&2
    fail 'clean checkout did not sync and run'
fi
[ -f "$workspace_root/.enclave-remote-root" ] ||
    fail 'sync did not mark the managed workspace root'
[ -d "$remote_checkout/.git" ] || fail 'sync did not initialize the remote checkout'
[ "$(git -C "$remote_checkout" branch --show-current)" = 'Feature/Quoting.case' ] ||
    fail 'sync did not check out the local branch remotely'
[ "$(git -C "$remote_checkout" rev-parse HEAD)" = "$(git -C "$repo" rev-parse HEAD)" ] ||
    fail 'sync did not push local HEAD'
assert_file 0 "$capture/yolo"
[ "$(sort -u "$capture/control-paths" | wc -l | tr -d ' ')" = 1 ] ||
    fail 'SSH and Git did not share one ControlPath'

# Remote exit status is the command's status, and pull updates only FETCH_HEAD.
assert_status 7 env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=execute \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" ENCLAVE_TEST_EXIT=7 \
    "$remote" pi --sync=none ps --json

git -C "$remote_checkout" config user.email remote@example.com
git -C "$remote_checkout" config user.name Remote
printf 'remote commit\n' > "$remote_checkout/remote-work"
git -C "$remote_checkout" add remote-work
git -C "$remote_checkout" commit -qm 'remote work'
remote_head=$(git -C "$remote_checkout" rev-parse HEAD)
env -i PATH="$fakebin:$PATH" HOME="$home" SSH_MODE=execute \
    ENCLAVE_PROJECT_ROOT="$repo" "$remote" pull pi > "$tmp/pull-stdout"
[ "$(git -C "$repo" rev-parse FETCH_HEAD)" = "$remote_head" ] ||
    fail 'pull did not update FETCH_HEAD to the remote branch'
[ "$(git -C "$repo" rev-parse HEAD)" != "$remote_head" ] ||
    fail 'pull unexpectedly changed the local branch'
grep -q 'Fetched Feature/Quoting.case into FETCH_HEAD' "$tmp/pull-stdout" ||
    fail 'pull did not report FETCH_HEAD'

# A missing remote binary is selected by OS/architecture, checksum-verified,
# installed atomically, and then used even when ~/.local/bin is not on PATH.
rm -f "$home/.local/bin/enclave"
env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=bootstrap \
    RELEASE_DIR="$release_dir" RELEASE_CHECKSUM="$release_checksum" \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" \
    "$remote" pi --sync=none version --json \
    > "$tmp/bootstrap-stdout" 2> "$tmp/bootstrap-stderr"
[ -x "$home/.local/bin/enclave" ] || fail 'bootstrap did not install the remote binary'
grep -q 'Installing enclave-linux-amd64' "$tmp/bootstrap-stderr" ||
    fail 'bootstrap did not select the Linux amd64 release asset'
grep -q '"commit":"local-commit"' "$tmp/bootstrap-stdout" ||
    fail 'bootstrap did not run the installed binary'

rm -f "$home/.local/bin/enclave"
env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=bootstrap-arm64 \
    RELEASE_DIR="$release_dir" RELEASE_CHECKSUM="$release_checksum" \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" \
    "$remote" pi --sync=none version --json \
    > "$tmp/bootstrap-arm64-stdout" 2> "$tmp/bootstrap-arm64-stderr"
grep -q 'Installing enclave-linux-arm64' "$tmp/bootstrap-arm64-stderr" ||
    fail 'bootstrap did not select the Linux arm64 release asset'

rm -f "$home/.local/bin/enclave"
bad_checksum=0000000000000000000000000000000000000000000000000000000000000000
assert_status 1 env -i PATH="$fakebin:$PATH" HOME="$home" CAPTURE="$capture" SSH_MODE=bootstrap \
    RELEASE_DIR="$release_dir" RELEASE_CHECKSUM="$bad_checksum" \
    ENCLAVE_PROJECT_ROOT="$repo" ENCLAVE_BIN="$fakebin/enclave" \
    "$remote" pi --sync=none version --json
[ ! -e "$home/.local/bin/enclave" ] ||
    fail 'checksum failure left an installed remote binary'

printf '%s\n' 'remote tests passed'
