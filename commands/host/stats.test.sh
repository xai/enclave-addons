#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
stats=$script_dir/stats
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# assert_line <pattern> <file> -- some line of the report matches the
# extended regular expression.
assert_line() {
    grep -Eq -- "$1" "$2" || {
        cat "$2" >&2
        fail "no line matches /$1/"
    }
}

assert_no_line() {
    if grep -Eq -- "$1" "$2"; then
        cat "$2" >&2
        fail "unexpected line matches /$1/"
    fi
}

assert_status() {
    expected_status=$1
    shift
    if "$@" >/dev/null 2>&1; then
        actual_status=0
    else
        actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] ||
        fail "expected status $expected_status, got $actual_status from $*"
}

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg-config"
export XDG_STATE_HOME="$tmp/xdg-state"
export XDG_CACHE_HOME="$tmp/xdg-cache"
export ENCLAVE_CONFIG_DIR="$tmp/config"
export TZ=UTC
export COLUMNS=100
unset NO_COLOR ENCLAVE_BIN
mkdir -p "$HOME" "$ENCLAVE_CONFIG_DIR/skills/one" "$ENCLAVE_CONFIG_DIR/commands/host"

if [ "$(uname)" = Darwin ]; then
    state="$HOME/Library/Application Support/org.eclipse.enclave/state"
else
    state="$XDG_STATE_HOME/enclave"
fi

# A fake enclave for the running-sessions tile.
cat > "$tmp/enclave" <<'EOF'
#!/bin/sh
[ "$1 $2" = "ps --json" ] || exit 1
printf '%s\n' '[{"tool":"claude","status":"running","projectDir":"/work/alpha"},
{"tool":"pi","status":"exited","projectDir":"/work/alpha"}]'
EOF
chmod +x "$tmp/enclave"
cp "$tmp/enclave" "$ENCLAVE_CONFIG_DIR/commands/host/fake"

python3 - "$state" <<'EOF'
import json, os, sqlite3, sys

state = sys.argv[1]

def write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for line in lines:
            f.write(line if isinstance(line, str) else json.dumps(line))
            f.write("\n")

def project(phash, path):
    write(os.path.join(state, "projects", phash, "project.json"), [{"path": path}])
    return os.path.join(state, "projects", phash)

def claude(uuid, ts, kind="user", mid=None, out=0, usage=None):
    d = {"type": kind, "uuid": uuid, "timestamp": ts}
    if kind == "assistant":
        u = usage or {"input_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
        d["message"] = {"id": mid, "model": "claude-test", "usage": dict(u, output_tokens=out)}
    return d

alpha = project("aaaaaaaaaaaa", "/work/alpha")
store = os.path.join(alpha, "claude", "config-store", "default", "projects", "-work-alpha")
# 10:00-10:10 and, after an idle gap, 12:00-12:05: 15 minutes of activity.
# msg_1 is logged twice with a growing output count; the larger one counts.
usage1 = {"input_tokens": 10, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 20}
write(os.path.join(store, "s1.jsonl"), [
    {"type": "mode"},
    claude("u1", "2026-01-05T10:00:00.000Z"),
    claude("u2", "2026-01-05T10:01:00.000Z", "assistant", "msg_1", 5, usage1),
    claude("u3", "2026-01-05T10:01:00.500Z", "assistant", "msg_1", 7, usage1),
    "not json",
    claude("u4", "2026-01-05T10:10:00.000Z", "assistant", "msg_2", 3, {"input_tokens": 1}),
    claude("u5", "2026-01-05T12:00:00.000Z"),
    claude("u6", "2026-01-05T12:05:00.000Z", "assistant", "msg_3", 1, {"input_tokens": 2}),
    {"type": "assistant", "uuid": "u7", "timestamp": "2026-01-05T12:05:00.000Z",
     "message": {"id": "msg_x", "model": "<synthetic>", "usage": {"output_tokens": 999}}},
])
# A subagent replays msg_1 (counted once) and adds 50 output tokens.
write(os.path.join(store, "s1", "subagents", "agent-a.jsonl"), [
    claude("u2", "2026-01-05T10:01:00.000Z", "assistant", "msg_1", 7, usage1),
    claude("v1", "2026-01-05T10:03:00.000Z", "assistant", "msg_4", 50),
])
os.makedirs(os.path.join(alpha, "claude", "config-store", "named"))
write(os.path.join(alpha, "claude", "memory", "note.md"), ["remember"])
write(os.path.join(alpha, "claude", "memory", ".git", "HEAD"), ["ref"])
write(os.path.join(alpha, "claude", "history", "bash_history"), ["ls", "pwd", "exit"])
write(os.path.join(alpha, "claude", "env", "env"), ["SECRET=never-read"])

write(os.path.join(alpha, "pi", "config-store", "default", "agent", "sessions", "--work-alpha--", "p.jsonl"), [
    {"type": "session", "id": "pi-1", "timestamp": "2026-01-06T20:00:00.000Z"},
    {"type": "message", "id": "e1", "timestamp": "2026-01-06T20:00:00.000Z", "message": {"role": "user"}},
    {"type": "message", "id": "e2", "timestamp": "2026-01-06T20:00:30.000Z",
     "message": {"role": "assistant", "model": "pi-model",
                 "usage": {"input": 5, "output": 5, "cacheRead": 0, "cacheWrite": 0}}},
])

beta = project("bbbbbbbbbbbb", "/work/beta")
sessions = os.path.join(beta, "codex", "config-store", "default", "sessions", "2026", "01", "05")
# Running totals: deltas of 200+800+50 and 100+400+30 tokens.
write(os.path.join(sessions, "rollout-a.jsonl"), [
    {"timestamp": "2026-01-05T09:00:00.000Z", "type": "session_meta", "payload": {"id": "S", "session_id": "S"}},
    {"timestamp": "2026-01-05T09:00:01.000Z", "type": "turn_context", "payload": {"model": "gpt-test"}},
    {"timestamp": "2026-01-05T09:00:10.000Z", "type": "event_msg", "payload": {"type": "token_count", "info": {
        "total_token_usage": {"input_tokens": 1000, "cached_input_tokens": 800, "output_tokens": 50}}}},
    {"timestamp": "2026-01-05T09:05:00.000Z", "type": "event_msg", "payload": {"type": "token_count", "info": {
        "total_token_usage": {"input_tokens": 1500, "cached_input_tokens": 1200, "output_tokens": 80}},
        "rate_limits": {"primary": {"used_percent": 42.0, "window_minutes": 300}}}},
])
# A subagent thread of S: its own meta first, then its parent's.
write(os.path.join(sessions, "rollout-b.jsonl"), [
    {"timestamp": "2026-01-05T09:01:00.000Z", "type": "session_meta", "payload": {"id": "T", "session_id": "S"}},
    {"timestamp": "2026-01-05T09:01:00.000Z", "type": "session_meta", "payload": {"id": "S", "session_id": "S"}},
    {"timestamp": "2026-01-05T09:02:00.000Z", "type": "event_msg", "payload": {"type": "token_count", "info": {
        "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 0, "output_tokens": 10}}}},
])
write(os.path.join(beta, "codex", "logs", "network.log"), [
    {"ts": "2026-01-05T09:00:00.000000001Z", "type": "session", "verdict": "info", "rule": "start"},
    {"ts": "2026-01-05T09:00:02Z", "type": "tcp", "domain": "api.example.com", "port": 443, "verdict": "pass", "rule": "mitm-dispatch"},
    {"ts": "2026-01-05T09:00:02Z", "type": "http", "domain": "api.example.com", "status": 200,
     "req_bytes": 10, "resp_bytes": 20, "verdict": "pass", "rule": "allowlist"},
    "{truncated",
    {"ts": "2026-01-05T09:00:03Z", "type": "dns", "domain": "bad.example", "verdict": "deny", "rule": "nxdomain"},
])
write(os.path.join(beta, "codex", "gateway-config", "meta.json"), [{"mode": "restricted", "tool": "codex"}])

# OpenCode: a child session folds into its root; the rows live only in the WAL.
db = os.path.join(beta, "opencode", "config-store", "default", "opencode.db")
os.makedirs(os.path.dirname(db))
conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA wal_autocheckpoint=0")
conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT)")
conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
conn.commit()
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
start = 1767772800000  # 2026-01-07T08:00:00Z
conn.executemany("INSERT INTO session VALUES (?, ?)", [("root", None), ("child", "root")])
conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?)", [
    ("m1", "root", start, json.dumps({"role": "user", "time": {"created": start}})),
    ("m2", "child", start + 1000, json.dumps({"role": "assistant", "modelID": "oc-model",
        "time": {"created": start + 1000, "completed": start + 60000},
        "tokens": {"input": 7, "output": 3, "reasoning": 2, "cache": {"read": 1, "write": 0}}})),
])
conn.commit()
sys.stdout.flush()
os._exit(0)  # leave the WAL uncheckpointed, as a running OpenCode would
EOF

python3 - "$state" <<'EOF'
import json, os, sys
state = sys.argv[1]
def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))
beta = os.path.join(state, "projects", "bbbbbbbbbbbb")
write(os.path.join(beta, "mistral-vibe", "config-store", "default", "logs", "session", "session_1", "meta.json"), {
    "session_id": "v1", "start_time": "2026-01-08T10:00:00+00:00", "end_time": "2026-01-08T10:10:00+00:00",
    "config": {"active_model": "mistral-test"},
    "stats": {"session_prompt_tokens": 100, "session_cached_tokens": 60, "session_completion_tokens": 10}})
write(os.path.join(beta, "antigravity", "config-store", "default", "antigravity-cli", "conversations", "c1.db"), "")
gamma = os.path.join(state, "projects", "cccccccccccc")
write(os.path.join(gamma, "project.json"), {"path": "/work/gamma"})
write(os.path.join(gamma, "amp", "logs", "network.log"),
      '{"ts":"2026-01-09T09:00:00Z","type":"session","verdict":"info","rule":"start"}\n'
      '{"ts":"2026-01-09T10:00:00Z","type":"session","verdict":"info","rule":"start"}\n')
EOF

[ -s "$state/projects/bbbbbbbbbbbb/opencode/config-store/default/opencode.db-wal" ] ||
    fail 'fixture: the OpenCode WAL should hold the messages'

# A link planted in a store must not lead the scan out of the state root.
transcripts="$state/projects/aaaaaaaaaaaa/claude/config-store/default/projects/-work-alpha"
printf '%s\n' '{"type":"assistant","uuid":"x1","timestamp":"2026-01-05T10:02:00Z","message":{"id":"msg_out","model":"claude-test","usage":{"output_tokens":1000000}}}' \
    > "$tmp/outside.jsonl"
ln -s "$tmp/outside.jsonl" "$transcripts/planted.jsonl"

# An unreadable transcript costs itself, not the report. Root reads anything.
unreadable=0
if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' '{"type":"user","uuid":"y1","timestamp":"2026-01-05T10:00:00Z"}' > "$transcripts/locked.jsonl"
    chmod 000 "$transcripts/locked.jsonl"
    unreadable=1
fi

snapshot() {
    python3 - "$state" <<'EOF'
import hashlib, os, sys
for root, dirs, files in sorted(os.walk(sys.argv[1])):
    dirs.sort()
    for name in sorted(files) + dirs:
        p = os.path.join(root, name)
        st = os.lstat(p)
        digest = ""
        if os.path.isfile(p):
            try:
                with open(p, "rb") as f:
                    digest = hashlib.sha256(f.read()).hexdigest()
            except PermissionError:
                digest = "unreadable"
        print(p, st.st_mode, st.st_size, st.st_mtime_ns, digest)
EOF
}

snapshot > "$tmp/before"
ENCLAVE_BIN="$tmp/enclave" "$stats" --color never > "$tmp/report"
snapshot > "$tmp/after"
cmp -s "$tmp/before" "$tmp/after" || {
    diff "$tmp/before" "$tmp/after" >&2 || true
    fail 'the state tree changed during the scan'
}
report=$tmp/report

# Tiles: six sessions (amp's gateway-only starts are not sessions), one running.
assert_line '^  SESSIONS +SESSION TIME .* RUNNING NOW$' "$report"
assert_line '^  6 +' "$report"
assert_line '^  2 projects +sessions summed ' "$report"
assert_line ' 1 *$' "$report"
assert_line 'claude×1$' "$report"

# Tools: active time with the idle gap removed, deduplicated tokens.
assert_line '^  ● claude +1 +15m +15m +194 ' "$report"
assert_line '^  ● codex +1 +5m +5m +1\.7k ' "$report"
assert_line '^  ● mistral-vibe +1 +10m +10m +110 ' "$report"
assert_line '^  ● opencode +1 +1m +1m +13 ' "$report"
assert_line '^  ● pi +1 +30s +30s +10 ' "$report"
assert_line '^  ● amp† +2 +– +– +– ' "$report"
assert_line '^  ● antigravity‡ +1 +– +– +– ' "$report"
assert_line 'codex rate limits as of .*: 5h window 42% used' "$report"

# Tokens: 194 + 1690 + 110 + 13 + 10, split by kind.
assert_line '^━━ Tokens  2\.0k total' "$report"
assert_line 'input 465 +■ cache read 1\.4k +■ cache write 20 +■ output 171$' "$report"
assert_no_line '<synthetic>' "$report"

assert_line '^  /work/alpha +●● +2 ' "$report"
assert_line '^  Agent memory +1 file in 1 project \(claude 1\)$' "$report"
assert_line '^  Shell +3 commands in enclave shell history$' "$report"
assert_line '^  Parallel stores +1 config store besides default' "$report"
assert_line '^  Subagents +Claude 1 · Codex 1 subagent transcripts' "$report"
assert_line '^  Setup +1 host command · 1 shared skill$' "$report"

assert_line '^  3 gateway session starts · 1 gateway \(restricted ×1\)$' "$report"
assert_line '^  1 HTTP request \(↑ 10B ↓ 20B\) · 1 TCP connection · 1 DNS denial$' "$report"
assert_line 'api\.example\.com .* 1 +bad\.example .* 1 nxdomain$' "$report"
assert_no_line 'SECRET|never-read' "$report"
assert_no_line '1\.0M' "$report"
if [ "$unreadable" -eq 1 ]; then
    assert_line '^  1 file could not be read and was left out \(Permission denied\):$' "$report"
    assert_line '^    projects/aaaaaaaaaaaa/claude/.*/locked\.jsonl$' "$report"
fi

# The root itself may be a symlink, as when ~/.local/state lives elsewhere.
ln -s "$state" "$tmp/state-link"
"$stats" --color never --state-dir "$tmp/state-link" > "$tmp/linked"
assert_line '^  ● claude +1 +15m +15m +194 ' "$tmp/linked"

# --since keeps only what happened from then on.
"$stats" --color never --state-dir "$state" --since 2026-01-06 > "$tmp/since"
assert_no_line '^  ● claude ' "$tmp/since"
assert_no_line '^  ● codex ' "$tmp/since"
assert_line '^  ● pi +1 ' "$tmp/since"
assert_line '^  ● amp† +2 ' "$tmp/since"
assert_no_line 'RUNNING NOW' "$tmp/since"

"$stats" --color never --state-dir "$state" --tool codex,pi > "$tmp/tools"
assert_line '^  ● codex ' "$tmp/tools"
assert_no_line '^  ● claude ' "$tmp/tools"

"$stats" --color never --state-dir "$state" --project /work/alpha > "$tmp/project"
assert_line '^  ● claude ' "$tmp/project"
assert_no_line '^  ● codex ' "$tmp/project"

"$stats" --color never --state-dir "$state" --disk > "$tmp/disk"
assert_line '^━━ Disk ' "$tmp/disk"

"$stats" --color always --state-dir "$state" > "$tmp/color"
grep -q "$(printf '\033')\[" "$tmp/color" || fail '--color always printed no colour'
NO_COLOR=1 "$stats" --state-dir "$state" > "$tmp/nocolor"
if grep -q "$(printf '\033')\[" "$tmp/nocolor"; then fail 'colour on a pipe'; fi
# Characters, not bytes: the bars are multi-byte, which mawk's length() counts.
for width in 64 80 120; do
    COLUMNS=$width "$stats" --color never --state-dir "$state" --disk |
        python3 -c 'import sys; w = int(sys.argv[1]); sys.exit(any(len(l) > w for l in sys.stdin.read().splitlines()))' "$width" ||
        fail "a line is wider than $width columns"
done

# A Pi fork copies its parent's entries with their ids and timestamps; the
# shared history counts once. An OpenCode WAL linked to a valid WAL outside
# the store must not be read: its 1M tokens would show.
fork_state="$tmp/fork-state"
python3 - "$fork_state" "$tmp/outside" <<'EOF'
import json, os, shutil, sqlite3, sys
state, outside = sys.argv[1:]
proj = os.path.join(state, "projects", "dddddddddddd")
def write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("".join(json.dumps(line) + "\n" for line in lines))
write(os.path.join(proj, "project.json"), [{"path": "/work/delta"}])
sessions = os.path.join(proj, "pi", "config-store", "default", "agent", "sessions", "--work-delta--")
shared = [
    {"type": "message", "id": "e1", "timestamp": "2026-01-06T20:00:00.000Z", "message": {"role": "user"}},
    {"type": "message", "id": "e2", "timestamp": "2026-01-06T20:00:30.000Z",
     "message": {"role": "assistant", "model": "pi-model",
                 "usage": {"input": 5, "output": 5, "cacheRead": 0, "cacheWrite": 0}}},
]
write(os.path.join(sessions, "parent.jsonl"),
      [{"type": "session", "id": "pi-1", "timestamp": "2026-01-06T20:00:00.000Z"}] + shared)
write(os.path.join(sessions, "fork.jsonl"),
      [{"type": "session", "id": "pi-2", "timestamp": "2026-01-06T20:05:00.000Z"}] + shared + [
       {"type": "message", "id": "e3", "timestamp": "2026-01-06T20:06:00.000Z",
        "message": {"role": "assistant", "model": "pi-model",
                    "usage": {"input": 0, "output": 3, "cacheRead": 0, "cacheWrite": 0}}}])

os.makedirs(outside)
db = os.path.join(outside, "opencode.db")
conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA wal_autocheckpoint=0")
conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT)")
conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
conn.commit()
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
store = os.path.join(proj, "opencode", "config-store", "default")
os.makedirs(store)
shutil.copyfile(db, os.path.join(store, "opencode.db"))
start = 1767772800000
conn.execute("INSERT INTO session VALUES ('s', NULL)")
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?)", ("m1", "s", start, json.dumps({
    "role": "assistant", "modelID": "oc-model", "time": {"created": start, "completed": start + 1000},
    "tokens": {"input": 1000000, "output": 0, "cache": {"read": 0, "write": 0}}})))
conn.commit()
os.symlink(db + "-wal", os.path.join(store, "opencode.db-wal"))
sys.stdout.flush()
os._exit(0)
EOF
[ -s "$tmp/outside/opencode.db-wal" ] || fail 'fixture: the outside WAL should hold the message'
"$stats" --color never --state-dir "$fork_state" > "$tmp/fork"
assert_line '^  ● pi +2 .* 13 ' "$tmp/fork"
assert_no_line '1\.0M|oc-model' "$tmp/fork"

"$stats" -h > "$tmp/help"
assert_line '^Usage: enclave stats \[options\]$' "$tmp/help"
assert_status 2 "$stats" --since yesterday
assert_status 2 "$stats" --top 0
assert_status 1 "$stats" --state-dir "$tmp/missing"
mkdir "$tmp/empty"
"$stats" --color never --state-dir "$tmp/empty" > "$tmp/none"
assert_line '^No Enclave sessions found under ' "$tmp/none"

printf '%s\n' 'stats tests passed'
