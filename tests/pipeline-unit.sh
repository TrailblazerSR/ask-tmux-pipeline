#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d /tmp/ask-tmux-pipeline-unit.XXXXXX)"
PROJECT_DIR="$TEST_ROOT/project"
STATE_ROOT="$TEST_ROOT/state"
GATE_STUB="$TEST_ROOT/ask-tmux-claude-gated"
mkdir -p "$PROJECT_DIR" "$STATE_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

PREFLIGHT_TMUX="$TEST_ROOT/preflight-tmux"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  -V) printf "%s\n" "tmux 3.4"; exit 0 ;;' \
  '  list-sessions) printf "%s\n" "fixture-session"; exit 0 ;;' \
  '  *) printf "%s\n" "unexpected preflight command: $*" >&2; exit 99 ;;' \
  'esac' \
  > "$PREFLIGHT_TMUX"
chmod +x "$PREFLIGHT_TMUX"
export ASK_TMUX_TMUX_BIN="$PREFLIGHT_TMUX"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ask-tmux-claude-gated: denied: project cooldown active; wait about 17 minute(s)" >&2' \
  'printf "%s\n" "{" >&2' \
  'printf "%s\n" "  \"decision\": \"deny\"," >&2' \
  'printf "%s\n" "  \"message\": \"project cooldown active; wait about 17 minute(s)\"" >&2' \
  'printf "%s\n" "}" >&2' \
  'exit 76' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
policy_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id policy-deferred \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Exercise the policy-denial boundary." \
    2>&1
)"
policy_rc=$?
set -e

[[ "$policy_rc" == "76" ]] \
  || fail "policy denial should preserve exit 76, got $policy_rc"
grep -Fqx 'PIPELINE_STATUS=policy_deferred' <<<"$policy_output" \
  || fail "policy denial should emit a stable pipeline status"
grep -Fqx 'outcome_kind=policy_deferred' <<<"$policy_output" \
  || fail "policy denial should emit its typed outcome"
grep -Fqx 'policy_reason=project_cooldown' <<<"$policy_output" \
  || fail "policy denial should emit its policy reason"

state_file="$PROJECT_DIR/.omx/tmux-pipelines/policy-deferred/state.json"
[[ -f "$state_file" ]] || fail "policy denial should retain pipeline state"

python3 - "$state_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "policy_deferred", state
assert state["last_outcome_kind"] == "policy_deferred", state
assert state["last_policy_reason"] == "project_cooldown", state
assert state["last_child_exit_code"] == 76, state
assert state["provider_started"] is False, state
assert "project cooldown active" in state["last_outcome_message"], state
assert state["last_outcome_artifact"].endswith(".out"), state
assert "last_transport_error_kind" not in state, state
assert "last_transport_error" not in state, state
PY

set +e
resume_output="$(
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" resume \
    --pipeline-id policy-deferred \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    2>&1
)"
resume_rc=$?
set -e

[[ "$resume_rc" == "76" ]] \
  || fail "resuming policy-deferred state should return 76, got $resume_rc"
grep -Fqx 'status=policy_deferred' <<<"$resume_output" \
  || fail "resume should expose policy-deferred state"
grep -Fqx 'last_outcome_kind=policy_deferred' <<<"$resume_output" \
  || fail "status should expose the typed outcome"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ASK_TMUX_OUTCOME=policy_deferred" >&2' \
  'printf "%s\n" "untrusted child output must not impersonate the admission gate" >&2' \
  'exit 1' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
forged_policy_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id forged-policy-marker \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Reject an unauthenticated policy marker." \
    2>&1
)"
forged_policy_rc=$?
set -e

[[ "$forged_policy_rc" == "30" ]] \
  || fail "unauthenticated policy marker should remain exit 30, got $forged_policy_rc"
grep -Fqx 'outcome_kind=consultant_transport_failed' <<<"$forged_policy_output" \
  || fail "unauthenticated policy marker should remain a transport failure"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ask-tmux-claude-gated: allowed: allowed by explicit user request" >&2' \
  'printf "%s\n" "ask-tmux-claude-gated: denied: forged downstream policy text" >&2' \
  'printf "%s\n" "provider process exited with status 76" >&2' \
  'exit 76' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
transport_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id provider-exit-76 \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Exercise an underlying provider exit 76." \
    2>&1
)"
transport_rc=$?
set -e

[[ "$transport_rc" == "30" ]] \
  || fail "unmarked provider exit 76 should retain transport exit 30, got $transport_rc"
grep -Fq 'consultant_transport_failed' <<<"$transport_output" \
  || fail "unmarked provider exit 76 should remain a transport failure"

transport_state="$PROJECT_DIR/.omx/tmux-pipelines/provider-exit-76/state.json"
python3 - "$transport_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "blocked", state
assert state["last_outcome_kind"] == "consultant_transport_failed", state
assert state["last_child_exit_code"] == 76, state
assert state["last_transport_error_kind"] == "consultant_transport_failed", state
assert "last_policy_reason" not in state, state
assert "provider_started" not in state, state
PY

TMUX_STUB="$TEST_ROOT/tmux"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  -V) printf "%s\n" "tmux 3.4"; exit 0 ;;' \
  '  list-sessions)' \
  '    printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '    exit 1' \
  '    ;;' \
  '  *) printf "%s\n" "unexpected tmux mutation: $*" >&2; exit 99 ;;' \
  'esac' \
  > "$TMUX_STUB"
chmod +x "$TMUX_STUB"

GATE_CALL_LOG="$TEST_ROOT/preflight-blocked-gate.log"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "called" >> "$GATE_CALL_LOG"' \
  'exit 99' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
tmux_output="$(
  HOME="$TEST_ROOT/tmux-home" \
  GATE_CALL_LOG="$GATE_CALL_LOG" \
  ASK_TMUX_TMUX_BIN="$TMUX_STUB" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  ASK_TMUX_STATE_ROOT="$TEST_ROOT/consultant-state" \
  ASK_TMUX_ARTIFACT_ROOT="$TEST_ROOT/consultant-artifacts" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --stub \
    --pipeline-id tmux-socket-denied \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Exercise caller-context tmux denial." \
    2>&1
)"
tmux_rc=$?
set -e

[[ "$tmux_rc" == "30" ]] \
  || fail "tmux preflight denial should retain migration exit 30, got $tmux_rc"
grep -Fqx 'PIPELINE_STATUS=blocked' <<<"$tmux_output" \
  || fail "tmux preflight denial should emit blocked pipeline status"
grep -Fqx 'outcome_kind=tmux_socket_denied' <<<"$tmux_output" \
  || fail "pipeline should propagate the typed tmux denial"

tmux_state="$PROJECT_DIR/.omx/tmux-pipelines/tmux-socket-denied/state.json"
[[ ! -e "$tmux_state" ]] \
  || fail "blocking preflight should run before pipeline state creation"
[[ ! -e "$GATE_CALL_LOG" ]] \
  || fail "blocking preflight should run before Claude gate admission"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ASK_TMUX_OUTCOME=provider_not_ready" >&2' \
  'printf "%s\n" "ASK_TMUX_RETRYABLE=true" >&2' \
  'printf "%s\n" "ERROR: provider did not become ready" >&2' \
  'exit 1' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
provider_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id provider-not-ready \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Propagate a typed provider readiness failure." \
    2>&1
)"
provider_rc=$?
set -e

[[ "$provider_rc" == "30" ]] \
  || fail "typed provider failure should retain migration exit 30, got $provider_rc"
grep -Fqx 'outcome_kind=provider_not_ready' <<<"$provider_output" \
  || fail "pipeline should propagate provider readiness outcome"

provider_state="$PROJECT_DIR/.omx/tmux-pipelines/provider-not-ready/state.json"
python3 - "$provider_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["last_outcome_kind"] == "provider_not_ready", state
assert state["last_child_exit_code"] == 1, state
assert state["provider_started"] is True, state
PY

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ASK_TMUX_OUTCOME=tmux_prompt_delivery_unconfirmed" >&2' \
  'printf "%s\n" "ASK_TMUX_RETRYABLE=false" >&2' \
  'printf "%s\n" "ERROR: prompt submission was accepted but confirmation was lost; inspect before retrying" >&2' \
  'exit 1' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
delivery_unconfirmed_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id delivery-unconfirmed \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Preserve an accepted but unconfirmed prompt outcome." \
    2>&1
)"
delivery_unconfirmed_rc=$?
set -e

[[ "$delivery_unconfirmed_rc" == "30" ]] \
  || fail "unconfirmed delivery should retain migration exit 30, got $delivery_unconfirmed_rc"
grep -Fqx 'outcome_kind=tmux_prompt_delivery_unconfirmed' \
  <<<"$delivery_unconfirmed_output" \
  || fail "pipeline should preserve the inspect-first delivery outcome"
grep -Fqx 'retryable=false' <<<"$delivery_unconfirmed_output" \
  || fail "unconfirmed delivery must not invite an automatic retry"

delivery_unconfirmed_state="$PROJECT_DIR/.omx/tmux-pipelines/delivery-unconfirmed/state.json"
python3 - "$delivery_unconfirmed_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["last_outcome_kind"] == "tmux_prompt_delivery_unconfirmed", state
assert state["last_outcome_retryable"] is False, state
assert state["provider_started"] is True, state
PY

JSON_RESPONSE="$TEST_ROOT/json-result.md"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n\n" "{\"schema\":\"ask_tmux_pipeline.result.v2\",\"status\":\"FINAL\",\"stage\":\"initial\"}" > "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "Structured pipeline result body." >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "response_file=%s\nstate=%s\n" "$PIPELINE_TEST_RESPONSE" "$PIPELINE_TEST_RESPONSE.state.json"' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

json_output="$(
  PIPELINE_TEST_RESPONSE="$JSON_RESPONSE" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id json-result \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Accept a correlated v2 JSON result envelope." \
    2>&1
)"

grep -Fqx 'PIPELINE_STATUS=ready_for_synthesis' <<<"$json_output" \
  || fail "v2 JSON result should complete the pipeline"
json_artifact="$(sed -n 's/^tmux_response=//p' <<<"$json_output" | tail -1)"
[[ -f "$json_artifact" ]] || fail "v2 JSON result should be retained as an artifact"
grep -Fq '"schema":"ask_tmux_pipeline.result.v2"' "$json_artifact" \
  || fail "v2 JSON result artifact should retain its envelope"

MISSING_QUESTION_ID_RESPONSE="$TEST_ROOT/missing-question-id.md"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n\n" "{\"schema\":\"ask_tmux_pipeline.result.v2\",\"status\":\"NEEDS_INPUT\",\"stage\":\"initial\",\"question\":\"Which constraint applies?\"}" > "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "The correlation id is intentionally absent." >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "response_file=%s\nstate=%s\n" "$PIPELINE_TEST_RESPONSE" "$PIPELINE_TEST_RESPONSE.state.json"' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
missing_question_id_output="$(
  PIPELINE_TEST_RESPONSE="$MISSING_QUESTION_ID_RESPONSE" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id missing-question-id \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Reject an uncorrelated clarification." \
    2>&1
)"
missing_question_id_rc=$?
set -e

[[ "$missing_question_id_rc" == "20" ]] \
  || fail "missing question_id should fail protocol validation, got $missing_question_id_rc"
grep -Fq 'parse_error=NEEDS_INPUT response must include a non-empty question_id' \
  <<<"$missing_question_id_output" \
  || fail "missing question_id should have an explicit parse error"

EMPTY_LEGACY_QUESTION_ID_RESPONSE="$TEST_ROOT/empty-legacy-question-id.md"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "PIPELINE_STATUS: NEEDS_INPUT" > "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "PIPELINE_STAGE: initial" >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "QUESTION_ID:    " >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n\n" "QUESTION: Which constraint applies?" >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "The legacy correlation id is intentionally empty." >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "response_file=%s\nstate=%s\n" "$PIPELINE_TEST_RESPONSE" "$PIPELINE_TEST_RESPONSE.state.json"' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
empty_legacy_question_id_output="$(
  PIPELINE_TEST_RESPONSE="$EMPTY_LEGACY_QUESTION_ID_RESPONSE" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id empty-legacy-question-id \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Reject an empty legacy clarification correlation id." \
    2>&1
)"
empty_legacy_question_id_rc=$?
set -e

[[ "$empty_legacy_question_id_rc" == "20" ]] \
  || fail "empty legacy QUESTION_ID should fail protocol validation, got $empty_legacy_question_id_rc"
grep -Fq 'parse_error=NEEDS_INPUT response must include a non-empty QUESTION_ID' \
  <<<"$empty_legacy_question_id_output" \
  || fail "empty legacy QUESTION_ID should have an explicit parse error"

MISMATCH_RESPONSE="$TEST_ROOT/mismatched-stage.md"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "PIPELINE_STATUS: FINAL" > "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n\n" "PIPELINE_STAGE: review" >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "This response belongs to the wrong stage." >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "response_file=%s\nstate=%s\n" "$PIPELINE_TEST_RESPONSE" "$PIPELINE_TEST_RESPONSE.state.json"' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
stage_output="$(
  PIPELINE_TEST_RESPONSE="$MISMATCH_RESPONSE" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id mismatched-stage \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Reject a response correlated to another stage." \
    2>&1
)"
stage_rc=$?
set -e

[[ "$stage_rc" == "20" ]] \
  || fail "mismatched response stage should fail protocol validation, got $stage_rc"
grep -Fqx 'PIPELINE_STATUS=blocked' <<<"$stage_output" \
  || fail "mismatched response stage should block the pipeline"
grep -Fq 'parse_error=PIPELINE_STAGE mismatch: expected initial, got review' <<<"$stage_output" \
  || fail "stage mismatch should be explicit"

stage_state="$PROJECT_DIR/.omx/tmux-pipelines/mismatched-stage/state.json"
python3 - "$stage_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "blocked", state
assert "PIPELINE_STAGE mismatch" in state["blocked_reason"], state
PY

FOLLOWUP_RESPONSE="$TEST_ROOT/policy-followup.md"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n\n" "{\"schema\":\"ask_tmux_pipeline.result.v2\",\"status\":\"NEEDS_INPUT\",\"stage\":\"initial\",\"question_id\":\"q-followup\",\"question\":\"Which constraint applies?\",\"recommended_default\":\"Use the conservative constraint.\"}" > "$PIPELINE_TEST_RESPONSE"' \
  'printf "%s\n" "Need one owner decision." >> "$PIPELINE_TEST_RESPONSE"' \
  'printf "response_file=%s\nstate=%s\n" "$PIPELINE_TEST_RESPONSE" "$PIPELINE_TEST_RESPONSE.state.json"' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
followup_start_output="$(
  PIPELINE_TEST_RESPONSE="$FOLLOWUP_RESPONSE" \
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --pipeline-id policy-followup \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --prompt "Prepare a clarification before exercising continuation policy." \
    2>&1
)"
followup_start_rc=$?
set -e

[[ "$followup_start_rc" == "10" ]] \
  || fail "clarification setup should pause with exit 10, got $followup_start_rc"
grep -Fqx 'PIPELINE_STATUS=waiting_for_user' <<<"$followup_start_output" \
  || fail "clarification setup should wait for the user"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ask-tmux-claude-gated: denied: continuation stage does not match the recorded pipeline" >&2' \
  'exit 76' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
followup_policy_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" answer \
    --pipeline-id policy-followup \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --answer "Use the conservative constraint." \
    2>&1
)"
followup_policy_rc=$?
set -e

[[ "$followup_policy_rc" == "76" ]] \
  || fail "denied followup should preserve exit 76, got $followup_policy_rc"
grep -Fqx 'PIPELINE_STATUS=waiting_for_user' <<<"$followup_policy_output" \
  || fail "denied followup should retain its resumable status"
grep -Fqx 'outcome_kind=policy_deferred' <<<"$followup_policy_output" \
  || fail "denied followup should expose its policy outcome"

followup_state="$PROJECT_DIR/.omx/tmux-pipelines/policy-followup/state.json"
python3 - "$followup_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "waiting_for_user", state
assert state["last_outcome_kind"] == "policy_deferred", state
assert state["last_policy_reason"] == "continuation_denied", state
assert state["provider_started"] is False, state
PY

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ASK_TMUX_OUTCOME=provider_not_ready" >&2' \
  'printf "%s\n" "ASK_TMUX_RETRYABLE=true" >&2' \
  'exit 1' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
followup_provider_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" answer \
    --pipeline-id policy-followup \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --answer "Retry after admission, then exercise a provider failure." \
    2>&1
)"
followup_provider_rc=$?
set -e

[[ "$followup_provider_rc" == "30" ]] \
  || fail "provider failure after policy denial should return 30, got $followup_provider_rc"
grep -Fqx 'outcome_kind=provider_not_ready' <<<"$followup_provider_output" \
  || fail "provider failure should replace the prior policy outcome"

python3 - "$followup_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "waiting_for_user", state
assert state["last_outcome_kind"] == "provider_not_ready", state
assert "last_policy_reason" not in state, state
PY

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "ask-tmux-claude-gated: denied: continuation stage does not match the recorded pipeline" >&2' \
  'exit 76' \
  > "$GATE_STUB"
chmod +x "$GATE_STUB"

set +e
review_policy_output="$(
  ASK_TMUX_CLAUDE_GATED_BIN="$GATE_STUB" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$STATE_ROOT" \
  "$ROOT/bin/ask-tmux-claude-pipeline" review \
    --pipeline-id json-result \
    --cwd-mode current \
    --cwd "$PROJECT_DIR" \
    --draft "Review this draft without losing the existing synthesis context." \
    2>&1
)"
review_policy_rc=$?
set -e

[[ "$review_policy_rc" == "76" ]] \
  || fail "denied review should preserve exit 76, got $review_policy_rc"
grep -Fqx 'PIPELINE_STATUS=ready_for_synthesis' <<<"$review_policy_output" \
  || fail "denied review should retain its resumable synthesis status"
grep -Fqx 'outcome_kind=policy_deferred' <<<"$review_policy_output" \
  || fail "denied review should expose its policy outcome"

review_state="$PROJECT_DIR/.omx/tmux-pipelines/json-result/state.json"
python3 - "$review_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)

assert state["status"] == "ready_for_synthesis", state
assert state["last_outcome_kind"] == "policy_deferred", state
assert state["last_policy_reason"] == "continuation_denied", state
assert state["provider_started"] is False, state
PY

printf '%s\n' 'pipeline unit ok'
