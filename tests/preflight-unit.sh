#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d /tmp/ask-tmux-preflight-unit.XXXXXX)"
FAKE_TMUX="$TEST_ROOT/tmux"
FAKE_LOG="$TEST_ROOT/tmux.log"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$*" >> "$FAKE_TMUX_LOG"' \
  'case "${1:-}" in' \
  '  -V) printf "%s\n" "tmux 3.4"; exit 0 ;;' \
  '  list-sessions)' \
  '    case "${FAKE_TMUX_MODE:-ready}" in' \
  '      ready) printf "%s\n" "fixture-session"; exit 0 ;;' \
  '      absent) printf "%s\n" "no server running on /tmp/tmux-fixture/default" >&2; exit 1 ;;' \
  '      denied) printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2; exit 1 ;;' \
  '      protocol) printf "%s\n" "protocol version mismatch (client 8, server 7)" >&2; exit 1 ;;' \
  '      failed) printf "%s\n" "unexpected tmux control failure" >&2; exit 42 ;;' \
  '    esac' \
  '    ;;' \
  '  *) printf "%s\n" "mutating tmux command was not expected: $*" >&2; exit 99 ;;' \
  'esac' \
  > "$FAKE_TMUX"
chmod +x "$FAKE_TMUX"

run_preflight() {
  local mode="$1"
  FAKE_TMUX_MODE="$mode" \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" preflight --json
}

ready_json="$(run_preflight ready)"
python3 - "$ready_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["schema"] == "ask_tmux_preflight.v1", record
assert record["status"] == "ready", record
assert record["kind"] == "tmux_control_ready", record
assert record["blocking"] is False, record
assert record["command_exit"] == 0, record
assert record["tmux"]["version"] == "tmux 3.4", record
PY

wrapper_json="$(
  FAKE_TMUX_MODE=ready \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
    "$ROOT/bin/ask-tmux-codex" preflight --json
)"
python3 - "$wrapper_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["kind"] == "tmux_control_ready", record
PY

absent_json="$(run_preflight absent)"
python3 - "$absent_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["status"] == "ready", record
assert record["kind"] == "tmux_server_absent", record
assert record["blocking"] is False, record
assert record["command_exit"] == 1, record
PY

set +e
denied_json="$(run_preflight denied)"
denied_rc=$?
set -e
[[ "$denied_rc" == "1" ]] || fail "socket denial should make preflight fail"
python3 - "$denied_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["status"] == "blocked", record
assert record["kind"] == "tmux_socket_denied", record
assert record["blocking"] is True, record
assert record["retryable"] is False, record
assert record["command_exit"] == 1, record
assert "Operation not permitted" in record["stderr"], record
assert record["caller"]["pid"] > 0, record
assert record["caller"]["cwd"], record
PY

set +e
protocol_json="$(run_preflight protocol)"
protocol_rc=$?
set -e
[[ "$protocol_rc" == "1" ]] || fail "protocol mismatch should make preflight fail"
python3 - "$protocol_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["kind"] == "tmux_protocol_mismatch", record
assert record["retryable"] is False, record
PY

set +e
failed_json="$(run_preflight failed)"
failed_rc=$?
set -e
[[ "$failed_rc" == "1" ]] || fail "unknown tmux failure should make preflight fail"
python3 - "$failed_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["kind"] == "tmux_control_failed", record
assert record["command_exit"] == 42, record
PY

set +e
missing_json="$(
  ASK_TMUX_TMUX_BIN="$TEST_ROOT/not-installed-tmux" \
    "$ROOT/bin/ask-tmux-consultant" preflight --json
)"
missing_rc=$?
set -e
[[ "$missing_rc" == "1" ]] || fail "missing tmux client should make preflight fail"
python3 - "$missing_json" <<'PY'
import json
import sys

record = json.loads(sys.argv[1])
assert record["kind"] == "tmux_client_missing", record
assert record["blocking"] is True, record
assert record["retryable"] is False, record
assert record["command_exit"] == 127, record
PY

if grep -Eq 'new-session|send-keys|kill-session|paste-buffer|set-buffer' "$FAKE_LOG"; then
  fail "preflight must not mutate tmux state"
fi

set +e
doctor_output="$(
  FAKE_TMUX_MODE=denied \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" doctor --provider codex \
    2>&1
)"
doctor_rc=$?
set -e
[[ "$doctor_rc" == "1" ]] || fail "doctor should fail when caller cannot access tmux"
grep -Fq 'FAIL tmux_control=tmux_socket_denied' <<<"$doctor_output" \
  || fail "doctor should expose the caller-context tmux denial"

set +e
pipeline_doctor_output="$(
  HOME="$TEST_ROOT/pipeline-doctor-home" \
  FAKE_TMUX_MODE=denied \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
  ASK_TMUX_CONSULTANT_RUNNER="$ROOT/bin/ask-tmux-consultant" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$TEST_ROOT/pipeline-doctor-state" \
    "$ROOT/bin/ask-tmux-codex-pipeline" doctor \
    2>&1
)"
pipeline_doctor_rc=$?
set -e
[[ "$pipeline_doctor_rc" == "1" ]] \
  || fail "pipeline doctor should fail when caller cannot access tmux"
grep -Fq 'FAIL tmux_control=tmux_socket_denied' <<<"$pipeline_doctor_output" \
  || fail "pipeline doctor should expose the base runner tmux denial"

SEND_HOME="$TEST_ROOT/send-home"
SEND_PROJECT="$TEST_ROOT/send-project"
mkdir -p "$SEND_HOME" "$SEND_PROJECT"
set +e
send_output="$(
  HOME="$SEND_HOME" \
  FAKE_TMUX_MODE=denied \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider codex \
      --stub \
      --key denied-preflight \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "The preflight must stop this send." \
      2>&1
)"
send_rc=$?
set -e

[[ "$send_rc" == "1" ]] || fail "socket denial should stop consultant send"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_socket_denied' <<<"$send_output" \
  || fail "send should emit a machine-readable tmux denial"
grep -Fq '"kind": "tmux_socket_denied"' <<<"$send_output" \
  || fail "send should retain the preflight evidence"
[[ ! -e "$SEND_HOME/.omx/state/consultants" ]] \
  || fail "send should not create consultant state after preflight denial"
[[ ! -e "$SEND_PROJECT/.omx/consultants" ]] \
  || fail "send should not create packets after preflight denial"

if grep -Eq 'new-session|send-keys|kill-session|paste-buffer|set-buffer' "$FAKE_LOG"; then
  fail "denied send must not mutate tmux state"
fi

RUNTIME_TMUX="$TEST_ROOT/runtime-tmux"
RUNTIME_TMUX_STATE="$TEST_ROOT/runtime-tmux.state"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  -V) printf "%s\n" "tmux 3.4"; exit 0 ;;' \
  '  list-sessions) printf "%s\n" "fixture-session"; exit 0 ;;' \
  '  has-session)' \
  '    if [[ -e "$FAKE_TMUX_RUNTIME_STATE" ]]; then exit 0; fi' \
  '    printf "%s\n" "can'\''t find session: fixture-session" >&2' \
  '    exit 1' \
  '    ;;' \
  '  new-session) : > "$FAKE_TMUX_RUNTIME_STATE"; exit 0 ;;' \
  '  list-panes) printf "%s\n" "%%42"; exit 0 ;;' \
  '  capture-pane) printf "%s\n" "provider is still starting"; exit 0 ;;' \
  '  *) printf "%s\n" "unexpected tmux command: $*" >&2; exit 99 ;;' \
  'esac' \
  > "$RUNTIME_TMUX"
chmod +x "$RUNTIME_TMUX"

READY_HOME="$TEST_ROOT/ready-home"
READY_PROJECT="$TEST_ROOT/ready-project"
mkdir -p "$READY_HOME" "$READY_PROJECT"
set +e
ready_output="$(
  HOME="$READY_HOME" \
  FAKE_TMUX_RUNTIME_STATE="$RUNTIME_TMUX_STATE" \
  ASK_TMUX_TMUX_BIN="$RUNTIME_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider codex \
      --stub \
      --key ready-timeout \
      --cwd-mode current \
      --cwd "$READY_PROJECT" \
      --ready-timeout 0 \
      --prompt "Classify provider readiness timeout." \
      2>&1
)"
ready_rc=$?
set -e

[[ "$ready_rc" == "1" ]] || fail "provider readiness timeout should fail consultant send"
grep -Fqx 'ASK_TMUX_OUTCOME=provider_not_ready' <<<"$ready_output" \
  || fail "readiness timeout should emit a typed outcome"
grep -Fqx 'ASK_TMUX_RETRYABLE=true' <<<"$ready_output" \
  || fail "readiness timeout should state retryability"

CLAUDE_BIN_DIR="$TEST_ROOT/claude-bin"
CLAUDE_VERSION_LOG="$TEST_ROOT/claude-version.log"
mkdir -p "$CLAUDE_BIN_DIR"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$CLAUDE_VERSION_LOG"' \
  'exit 0' \
  > "$CLAUDE_BIN_DIR/cc-claude"
chmod +x "$CLAUDE_BIN_DIR/cc-claude"

set +e
claude_denied_output="$(
  HOME="$TEST_ROOT/claude-denied-home" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CLAUDE_VERSION_LOG="$CLAUDE_VERSION_LOG" \
  FAKE_TMUX_MODE=denied \
  FAKE_TMUX_LOG="$FAKE_LOG" \
  ASK_TMUX_TMUX_BIN="$FAKE_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --key claude-preflight-order \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "Tmux denial must precede credential work." \
      2>&1
)"
claude_denied_rc=$?
set -e
[[ "$claude_denied_rc" == "1" ]] || fail "Claude send should stop at denied tmux preflight"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_socket_denied' <<<"$claude_denied_output" \
  || fail "Claude send should report the tmux denial"
[[ ! -s "$CLAUDE_VERSION_LOG" ]] \
  || fail "tmux preflight must run before Claude launcher --version work"

claude_dry_output="$(
  HOME="$TEST_ROOT/claude-dry-home" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CLAUDE_VERSION_LOG="$CLAUDE_VERSION_LOG" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --dry-run \
      --key claude-dry-run \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "Dry run must not unlock credentials." \
      2>&1
)"
grep -Fq 'DRY_RUN provider=claude' <<<"$claude_dry_output" \
  || fail "Claude dry run should still render its plan"
[[ ! -s "$CLAUDE_VERSION_LOG" ]] \
  || fail "Claude dry run must not invoke launcher --version"

CONTROL_TMUX="$TEST_ROOT/control-tmux"
CONTROL_LIVE="$TEST_ROOT/control-live"
CONTROL_COMPLETION="$TEST_ROOT/control-completion"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  -V) printf "%s\n" "tmux 3.4"; exit 0 ;;' \
  '  list-sessions) printf "%s\n" "fixture-session"; exit 0 ;;' \
  '  has-session)' \
  '    if [[ ! -e "$CONTROL_LIVE" ]]; then' \
  '      printf "%s\n" "can'\''t find session: fixture-session" >&2' \
  '      exit 1' \
  '    fi' \
  '    case "$CONTROL_MODE" in' \
  '      readiness-denied|status-denied|cleanup-denied)' \
  '        printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '        exit 1' \
  '        ;;' \
  '      readiness-empty) exit 1 ;;' \
  '      completion-protocol)' \
  '        if [[ -e "$CONTROL_COMPLETION" ]]; then' \
  '          printf "%s\n" "protocol version mismatch (client 8, server 7)" >&2' \
  '          exit 1' \
  '        fi' \
  '        ;;' \
  '    esac' \
  '    exit 0' \
  '    ;;' \
  '  new-session)' \
  '    if [[ "$CONTROL_MODE" == "create-failed" ]]; then' \
  '      printf "%s\n" "server failed to start" >&2' \
  '      exit 42' \
  '    fi' \
  '    : > "$CONTROL_LIVE"' \
  '    exit 0' \
  '    ;;' \
  '  display-message) printf "%s\n" "%%42"; exit 0 ;;' \
  '  list-panes)' \
  '    if [[ "$CONTROL_MODE" == "pane-resolution-denied" || "$CONTROL_MODE" == "replace-pane-resolution-denied" ]]; then' \
  '      printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '      exit 1' \
  '    fi' \
  '    printf "%s\n" "%%42"' \
  '    exit 0' \
  '    ;;' \
  '  capture-pane)' \
  '    if [[ "$CONTROL_MODE" == "capture-denied" || "$CONTROL_MODE" == "reconcile-capture-denied" || "$CONTROL_MODE" == "status-capture-denied" || ( "$CONTROL_MODE" == "ambiguous-delivery-denied" && -e "$CONTROL_COMPLETION" ) ]]; then' \
  '      printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '      exit 1' \
  '    fi' \
  '    printf "%s\n" "ASK_TMUX_STUB_READY"' \
  '    exit 0' \
  '    ;;' \
  '  set-buffer) exit 0 ;;' \
  '  paste-buffer)' \
  '    if [[ "$CONTROL_MODE" == "delivery-failed" ]]; then' \
  '      printf "%s\n" "paste-buffer transport failed" >&2' \
  '      exit 42' \
  '    fi' \
  '    exit 0' \
  '    ;;' \
  '  send-keys)' \
  '    if [[ "$CONTROL_MODE" == "completion-protocol" || "$CONTROL_MODE" == "ambiguous-delivery-denied" ]]; then' \
  '      : > "$CONTROL_COMPLETION"' \
  '    fi' \
  '    exit 0' \
  '    ;;' \
  '  delete-buffer) exit 0 ;;' \
  '  kill-session)' \
  '    if [[ "$CONTROL_MODE" == "replace-kill-denied" || "$CONTROL_MODE" == "release-kill-denied" ]]; then' \
  '      printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '      exit 1' \
  '    fi' \
  '    rm -f "$CONTROL_LIVE"' \
  '    exit 0' \
  '    ;;' \
  '  *) printf "%s\n" "unexpected tmux command: $*" >&2; exit 99 ;;' \
  'esac' \
  > "$CONTROL_TMUX"
chmod +x "$CONTROL_TMUX"

run_control_send() {
  local mode="$1" key="$2" case_home="$3"
  rm -f "$CONTROL_LIVE" "$CONTROL_COMPLETION"
  mkdir -p "$case_home"
  HOME="$case_home" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE="$mode" \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --key "$key" \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --ready-timeout 0 \
      --wait-timeout 0 \
      --prompt "Exercise typed tmux runtime failures."
}

assert_failed_nonbusy_state() {
  local case_home="$1" state_file
  state_file="$(find "$case_home/.omx/state/consultants" -type f -name '*.json' | sed -n '1p')"
  [[ -n "$state_file" ]] || fail "expected a persisted consultant failure state"
  python3 - "$state_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)
assert state["status"] == "failed", state
assert state["busy"] is False, state
PY
}

assert_live_state() {
  local case_home="$1" expected_busy="$2" state_file
  state_file="$(find "$case_home/.omx/state/consultants" -type f -name '*.json' | sed -n '1p')"
  [[ -n "$state_file" ]] || fail "expected a persisted consultant live state"
  python3 - "$state_file" "$expected_busy" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)
assert state["status"] == "live", state
assert state["busy"] is (sys.argv[2] == "true"), state
assert state["completed_epoch"] is None, state
PY
}

READINESS_CONTROL_HOME="$TEST_ROOT/readiness-control-home"
set +e
readiness_control_output="$(run_control_send readiness-denied readiness-control-loss "$READINESS_CONTROL_HOME" 2>&1)"
readiness_control_rc=$?
set -e
[[ "$readiness_control_rc" == "1" ]] || fail "readiness control loss should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$readiness_control_output" \
  || fail "readiness socket loss should stay a typed tmux failure"
grep -Fq '"command_exit": 1' <<<"$readiness_control_output" \
  || fail "readiness control failure should retain the tmux command status"
grep -Fq 'Operation not permitted' <<<"$readiness_control_output" \
  || fail "readiness control failure should retain tmux stderr"
assert_live_state "$READINESS_CONTROL_HOME" false

EMPTY_CONTROL_HOME="$TEST_ROOT/empty-control-home"
set +e
empty_control_output="$(run_control_send readiness-empty empty-control-loss "$EMPTY_CONTROL_HOME" 2>&1)"
empty_control_rc=$?
set -e
[[ "$empty_control_rc" == "1" ]] || fail "empty nonzero readiness probe should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_control_failed' <<<"$empty_control_output" \
  || fail "empty nonzero tmux result must not be mistaken for session absence"
assert_live_state "$EMPTY_CONTROL_HOME" false

COMPLETION_CONTROL_HOME="$TEST_ROOT/completion-control-home"
set +e
completion_control_output="$(run_control_send completion-protocol completion-control-loss "$COMPLETION_CONTROL_HOME" 2>&1)"
completion_control_rc=$?
set -e
[[ "$completion_control_rc" == "1" ]] || fail "completion control loss should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_protocol_mismatch' <<<"$completion_control_output" \
  || fail "completion protocol loss should stay a typed tmux failure"
grep -Fq 'protocol version mismatch' <<<"$completion_control_output" \
  || fail "completion control failure should retain tmux stderr"
assert_live_state "$COMPLETION_CONTROL_HOME" true

CREATE_FAILURE_HOME="$TEST_ROOT/create-failure-home"
set +e
create_failure_output="$(run_control_send create-failed create-failure "$CREATE_FAILURE_HOME" 2>&1)"
create_failure_rc=$?
set -e
[[ "$create_failure_rc" == "1" ]] || fail "tmux new-session failure should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_session_create_failed' <<<"$create_failure_output" \
  || fail "tmux new-session failure should have a precise typed outcome"
grep -Fq 'server failed to start' <<<"$create_failure_output" \
  || fail "tmux new-session failure should retain tmux stderr"
assert_failed_nonbusy_state "$CREATE_FAILURE_HOME"

PANE_RESOLUTION_DENIED_HOME="$TEST_ROOT/pane-resolution-denied-home"
set +e
pane_resolution_denied_output="$(
  run_control_send pane-resolution-denied pane-resolution-denied "$PANE_RESOLUTION_DENIED_HOME" 2>&1
)"
pane_resolution_denied_rc=$?
set -e
[[ "$pane_resolution_denied_rc" == "1" ]] \
  || fail "pane discovery control denial should stop a new send"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$pane_resolution_denied_output" \
  || fail "pane discovery should retain its typed control denial"
pane_resolution_denied_state="$(
  find "$PANE_RESOLUTION_DENIED_HOME/.omx/state/consultants" -type f -name '*.json' | sed -n '1p'
)"
[[ -n "$pane_resolution_denied_state" ]] \
  || fail "successful new-session must be recorded before pane discovery"
python3 - "$pane_resolution_denied_state" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)
assert state["status"] == "live", state
assert state["busy"] is False, state
assert state["pane_target"] == "", state
assert state["session_name"].startswith("ask-tmux-claude-"), state
assert state["last_packet"] and os.path.isfile(state["last_packet"]), state
assert state["last_response"], state
assert state["done_sentinel"].startswith("<<<ASK_TMUX_DONE:claude:"), state
assert state["completed_epoch"] is None, state
PY

DELIVERY_FAILURE_HOME="$TEST_ROOT/delivery-failure-home"
set +e
delivery_failure_output="$(run_control_send delivery-failed delivery-failure "$DELIVERY_FAILURE_HOME" 2>&1)"
delivery_failure_rc=$?
set -e
[[ "$delivery_failure_rc" == "1" ]] || fail "tmux prompt delivery failure should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_prompt_delivery_failed' <<<"$delivery_failure_output" \
  || fail "tmux prompt delivery failure should have a precise typed outcome"
grep -Fq 'paste-buffer transport failed' <<<"$delivery_failure_output" \
  || fail "tmux prompt delivery failure should retain tmux stderr"
assert_failed_nonbusy_state "$DELIVERY_FAILURE_HOME"

AMBIGUOUS_DELIVERY_HOME="$TEST_ROOT/ambiguous-delivery-home"
rm -f "$CONTROL_LIVE" "$CONTROL_COMPLETION"
set +e
ambiguous_delivery_output="$(
  HOME="$AMBIGUOUS_DELIVERY_HOME" \
  CONTROL_MODE=ambiguous-delivery-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider codex \
      --stub \
      --key ambiguous-delivery \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --ready-timeout 0 \
      --wait-timeout 0 \
      --prompt "Do not retry a prompt after Enter may have been accepted." \
      2>&1
)"
ambiguous_delivery_rc=$?
set -e
[[ "$ambiguous_delivery_rc" == "1" ]] \
  || fail "post-Enter control loss should stop the blocking send"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_prompt_delivery_unconfirmed' <<<"$ambiguous_delivery_output" \
  || fail "post-Enter control loss should have an accepted-unconfirmed outcome"
grep -Fqx 'ASK_TMUX_RETRYABLE=false' <<<"$ambiguous_delivery_output" \
  || fail "accepted-unconfirmed delivery must not invite an automatic resend"
ambiguous_delivery_state="$(
  find "$AMBIGUOUS_DELIVERY_HOME/.omx/state/consultants" -type f -name '*.json' | sed -n '1p'
)"
python3 - "$ambiguous_delivery_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)
assert state["status"] == "live", state
assert state["busy"] is True, state
assert state["completed_epoch"] is None, state
PY

create_live_control_fixture() {
  local case_home="$1" key="$2"
  rm -f "$CONTROL_LIVE" "$CONTROL_COMPLETION"
  mkdir -p "$case_home"
  HOME="$case_home" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE=fixture \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --no-wait \
      --key "$key" \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --ready-timeout 0 \
      --prompt "Create a live state fixture." \
      >/dev/null
  find "$case_home/.omx/state/consultants" -type f -name '*.json' | sed -n '1p'
}

RECONCILE_DENIED_HOME="$TEST_ROOT/reconcile-denied-home"
reconcile_denied_state="$(create_live_control_fixture "$RECONCILE_DENIED_HOME" reconcile-denied)"
cp "$reconcile_denied_state" "$reconcile_denied_state.before"
reconcile_packet_count_before="$(
  find "$SEND_PROJECT/.omx/consultants/packets" -type f | wc -l | tr -d ' '
)"
set +e
reconcile_denied_output="$(
  HOME="$RECONCILE_DENIED_HOME" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE=reconcile-capture-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --no-wait \
      --key reconcile-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "Do not reinterpret capture denial as a busy or missing session." \
      2>&1
)"
reconcile_denied_rc=$?
set -e
[[ "$reconcile_denied_rc" == "1" ]] || fail "send reconciliation capture denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$reconcile_denied_output" \
  || fail "send reconciliation should retain typed capture denial"
cmp -s "$reconcile_denied_state.before" "$reconcile_denied_state" \
  || fail "send reconciliation denial must not mutate lifecycle state"
reconcile_packet_count_after="$(
  find "$SEND_PROJECT/.omx/consultants/packets" -type f | wc -l | tr -d ' '
)"
[[ "$reconcile_packet_count_after" == "$reconcile_packet_count_before" ]] \
  || fail "send reconciliation denial must stop before writing another packet"

STATUS_DENIED_HOME="$TEST_ROOT/status-denied-home"
status_denied_state="$(create_live_control_fixture "$STATUS_DENIED_HOME" status-denied)"
cp "$status_denied_state" "$status_denied_state.before"
set +e
status_denied_output="$(
  HOME="$STATUS_DENIED_HOME" \
  CONTROL_MODE=status-capture-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" status \
      --provider claude \
      --key status-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      2>&1
)"
status_denied_rc=$?
set -e
[[ "$status_denied_rc" == "1" ]] || fail "status capture denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$status_denied_output" \
  || fail "status should retain typed capture denial"
cmp -s "$status_denied_state.before" "$status_denied_state" \
  || fail "status denial must not mutate lifecycle state"

CAPTURE_DENIED_HOME="$TEST_ROOT/capture-denied-home"
capture_denied_state="$(create_live_control_fixture "$CAPTURE_DENIED_HOME" capture-denied)"
cp "$capture_denied_state" "$capture_denied_state.before"
set +e
capture_denied_output="$(
  HOME="$CAPTURE_DENIED_HOME" \
  CONTROL_MODE=capture-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" capture \
      --provider claude \
      --key capture-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      2>&1
)"
capture_denied_rc=$?
set -e
[[ "$capture_denied_rc" == "1" ]] || fail "capture control denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$capture_denied_output" \
  || fail "capture should retain typed control denial"
cmp -s "$capture_denied_state.before" "$capture_denied_state" \
  || fail "capture denial must not mutate lifecycle state"

RELEASE_DENIED_HOME="$TEST_ROOT/release-denied-home"
release_denied_state="$(create_live_control_fixture "$RELEASE_DENIED_HOME" release-denied)"
cp "$release_denied_state" "$release_denied_state.before"
set +e
release_denied_output="$(
  HOME="$RELEASE_DENIED_HOME" \
  CONTROL_MODE=release-kill-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" release \
      --provider claude \
      --key release-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      2>&1
)"
release_denied_rc=$?
set -e
[[ "$release_denied_rc" == "1" ]] || fail "release kill denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$release_denied_output" \
  || fail "release should retain typed kill denial"
cmp -s "$release_denied_state.before" "$release_denied_state" \
  || fail "release kill denial must not mark the session released"

CLEANUP_DENIED_HOME="$TEST_ROOT/cleanup-denied-home"
cleanup_denied_state="$(create_live_control_fixture "$CLEANUP_DENIED_HOME" cleanup-denied)"
python3 - "$cleanup_denied_state" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    state = json.load(handle)
state["last_used_epoch"] = 1
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
cp "$cleanup_denied_state" "$cleanup_denied_state.before"
set +e
cleanup_denied_output="$(
  HOME="$CLEANUP_DENIED_HOME" \
  CONTROL_MODE=cleanup-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" cleanup \
      --provider claude \
      --stale-after 1s \
      2>&1
)"
cleanup_denied_rc=$?
set -e
[[ "$cleanup_denied_rc" == "1" ]] || fail "cleanup control denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$cleanup_denied_output" \
  || fail "cleanup should retain typed liveness denial"
cmp -s "$cleanup_denied_state.before" "$cleanup_denied_state" \
  || fail "cleanup denial must not mark the session released"

REPLACE_DENIED_HOME="$TEST_ROOT/replace-denied-home"
replace_denied_state="$(create_live_control_fixture "$REPLACE_DENIED_HOME" replace-denied)"
python3 - "$replace_denied_state" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    state = json.load(handle)
state["busy"] = False
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
cp "$replace_denied_state" "$replace_denied_state.before"
replace_packet_count_before="$(
  find "$SEND_PROJECT/.omx/consultants/packets" -type f | wc -l | tr -d ' '
)"
set +e
replace_denied_output="$(
  HOME="$REPLACE_DENIED_HOME" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE=replace-kill-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --no-wait \
      --fresh \
      --replace \
      --key replace-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "Do not continue after replacement kill is denied." \
      2>&1
)"
replace_denied_rc=$?
set -e
[[ "$replace_denied_rc" == "1" ]] || fail "fresh replace kill denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$replace_denied_output" \
  || fail "fresh replace should retain typed kill denial"
cmp -s "$replace_denied_state.before" "$replace_denied_state" \
  || fail "fresh replace kill denial must not mutate lifecycle state"
replace_packet_count_after="$(
  find "$SEND_PROJECT/.omx/consultants/packets" -type f | wc -l | tr -d ' '
)"
[[ "$replace_packet_count_after" == "$replace_packet_count_before" ]] \
  || fail "fresh replace kill denial must stop before writing another packet"

REPLACE_PANE_DENIED_HOME="$TEST_ROOT/replace-pane-denied-home"
replace_pane_denied_state="$(
  create_live_control_fixture "$REPLACE_PANE_DENIED_HOME" replace-pane-denied
)"
python3 - "$replace_pane_denied_state" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    state = json.load(handle)
state["busy"] = False
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
cp "$replace_pane_denied_state" "$replace_pane_denied_state.before"
set +e
replace_pane_denied_output="$(
  HOME="$REPLACE_PANE_DENIED_HOME" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE=replace-pane-resolution-denied \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --no-wait \
      --fresh \
      --replace \
      --key replace-pane-denied \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --prompt "Record the replacement generation before pane discovery." \
      2>&1
)"
replace_pane_denied_rc=$?
set -e
[[ "$replace_pane_denied_rc" == "1" ]] \
  || fail "replacement pane discovery denial should stop the send"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$replace_pane_denied_output" \
  || fail "replacement pane discovery should retain typed control denial"
python3 - "$replace_pane_denied_state.before" "$replace_pane_denied_state" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    old = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    new = json.load(handle)
assert new["status"] == "live", new
assert new["busy"] is False, new
assert new["pane_target"] == "", new
assert new["session_name"] == old["session_name"], (old, new)
assert new["last_packet"] != old["last_packet"], (old, new)
assert new["last_response"] != old["last_response"], (old, new)
assert new["done_sentinel"] != old["done_sentinel"], (old, new)
assert os.path.isfile(new["last_packet"]), new
assert new["completed_epoch"] is None, new
PY

COMPLETION_TIMEOUT_HOME="$TEST_ROOT/completion-timeout-home"
set +e
completion_timeout_output="$(run_control_send completion-timeout completion-timeout "$COMPLETION_TIMEOUT_HOME" 2>&1)"
completion_timeout_rc=$?
set -e
[[ "$completion_timeout_rc" == "1" ]] || fail "completion timeout should fail the blocking send"
grep -Fqx 'ASK_TMUX_OUTCOME=provider_completion_timeout' <<<"$completion_timeout_output" \
  || fail "total wait deadline should be named provider_completion_timeout"

ATTACH_SEND_HOME="$TEST_ROOT/attach-send-home"
rm -f "$CONTROL_LIVE" "$CONTROL_COMPLETION"
attach_send_output="$(
  HOME="$ATTACH_SEND_HOME" \
  PATH="$CLAUDE_BIN_DIR:$PATH" \
  CONTROL_MODE=attach \
  CONTROL_LIVE="$CONTROL_LIVE" \
  CONTROL_COMPLETION="$CONTROL_COMPLETION" \
  ASK_TMUX_TMUX_BIN="$CONTROL_TMUX" \
    "$ROOT/bin/ask-tmux-consultant" send \
      --provider claude \
      --stub \
      --no-wait \
      --attach \
      --key configured-attach-send \
      --cwd-mode current \
      --cwd "$SEND_PROJECT" \
      --ready-timeout 0 \
      --prompt "Display the configured attach client."
)"
grep -Fq "attach_command=$CONTROL_TMUX attach -t " <<<"$attach_send_output" \
  || fail "send --attach should resolve and display the configured tmux binary"

printf '%s\n' 'preflight unit ok'
