#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/bin/ask-tmux-consultant"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_ready() {
  local provider="$1" text="$2"
  pane_is_ready "$provider" false "$text" || fail "expected $provider pane to be ready"
}

assert_not_ready() {
  local provider="$1" text="$2"
  if pane_is_ready "$provider" false "$text"; then
    fail "expected $provider pane not to be ready"
  fi
}

trust_plus_banner_no_composer='
> You are in /tmp/project

  Do you trust the contents of this directory?

› 1. Yes, continue
  2. No, quit

╭──────────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.132.0)                               │
│ model:       gpt-5.5 xhigh   fast   /model to change     │
│ permissions: YOLO mode                                   │
╰──────────────────────────────────────────────────────────╯
'

ready_with_stale_trust='
> You are in /tmp/project
  Do you trust the contents of this directory?
› 1. Yes, continue
  2. No, quit

╭──────────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.132.0)                               │
│ model:       gpt-5.5 xhigh   fast   /model to change     │
│ permissions: YOLO mode                                   │
╰──────────────────────────────────────────────────────────╯

›

  gpt-5.5 xhigh fast · /tmp/project
'

claude_ready_with_status='
╭─── Claude Code v2.1.195 ─────────────────────────────────────────────────────╮
│                 Welcome back!                                                │
│   Opus 4.8 (1M context) · API Usage Billing                                  │
│              ~/ask-tmux-pipeline                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

────────────────────────────────────────────────────────────────────────────────
❯ 
────────────────────────────────────────────────────────────────────────────────
  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents
'

wrapped_sentinel='
• <<<ASK_TMUX_DONE:codex:repo-live-
  codex-double-20738-06a3d76b:1782555029:20738>>>
'
sentinel='<<<ASK_TMUX_DONE:codex:repo-live-codex-double-20738-06a3d76b:1782555029:20738>>>'

update_prompt_two='
› 1. Update now
  2. Skip
  3. Skip until next version
'

update_prompt_three='
› 1. Update now
  2. Later
  3. Skip until next version
'

update_prompt_no_skip='
› 1. Update now
  2. Install
'

hooks_review_prompt='
  Hooks need review
  5 hooks are new or changed.

› 1. Review hooks
  2. Trust all and continue
  3. Continue without trusting (hooks won'\''t run)

  Press enter to confirm or esc to go back
'

submitted_text='
› ASK_TMUX_RESPONSE=/tmp/response.md ASK_TMUX_SENTINEL=<<<ASK_TMUX_DONE:x>>> Read and follow this review packet

⚠ Skill descriptions were shortened
◦ Working (4s • esc to interrupt)
'

unsent_text='
› ASK_TMUX_RESPONSE=/tmp/response.md ASK_TMUX_SENTINEL=<<<ASK_TMUX_DONE:x>>> Read and follow this review packet

  gpt-5.5 xhigh fast · /tmp/project
'

stale_activity_then_unsent_text='
◦ Working (12s • esc to interrupt)

› ASK_TMUX_RESPONSE=/tmp/response.md ASK_TMUX_SENTINEL=<<<ASK_TMUX_DONE:x>>> Read and follow this review packet

  gpt-5.5 xhigh fast · /tmp/project
'

collapsed_unsent_text='
› [Pasted Content 1024 chars]_TMUX_SENTINEL value on its own final line.

  gpt-5.5 xhigh fast · /tmp/project
'

codex_launch_cmd="$(provider_launch_command codex false)"

assert_not_ready codex "$trust_plus_banner_no_composer"
assert_ready codex "$ready_with_stale_trust"
assert_ready claude "$claude_ready_with_status"
text_contains_sentinel "$wrapped_sentinel" "$sentinel" || fail "wrapped sentinel was not detected"
[[ "$(codex_update_prompt_choice "$update_prompt_two")" == "2" ]] || fail "expected update prompt choice 2"
[[ "$(codex_update_prompt_choice "$update_prompt_three")" == "3" ]] || fail "expected update prompt choice 3"
if codex_update_prompt_choice "$update_prompt_no_skip" >/dev/null; then
  fail "update prompt without a skip option should not choose blindly"
fi
[[ "$(codex_hooks_prompt_choice "$hooks_review_prompt")" == "2" ]] || fail "expected hooks review prompt choice 2"
if codex_prompt_needs_second_submit "$submitted_text" "ASK_TMUX_RESPONSE=/tmp/response.md"; then
  fail "submitted Codex prompt should not need a second Enter"
fi
codex_prompt_needs_second_submit "$unsent_text" "ASK_TMUX_RESPONSE=/tmp/response.md" || fail "unsent Codex prompt should need a second Enter"
codex_prompt_needs_second_submit "$stale_activity_then_unsent_text" "ASK_TMUX_RESPONSE=/tmp/response.md" || fail "stale activity before an unsent prompt should not suppress second Enter"
codex_prompt_needs_second_submit "$collapsed_unsent_text" "ASK_TMUX_RESPONSE=/tmp/response.md" || fail "collapsed pasted Codex prompt should need a second Enter"
case "$codex_launch_cmd" in
  env\ PATH=*HOME=*codex\ --dangerously-bypass-approvals-and-sandbox) ;;
  *) fail "Codex launch should pass the runner PATH/HOME into tmux" ;;
esac

gated_tmp="$(mktemp -d /tmp/ask-tmux-claude-gated-unit.XXXXXX)"
gated_home="$gated_tmp/home"
gated_stub_dir="$gated_tmp/stub-bin"
gated_stub_log="$gated_tmp/stub.log"
python_bin="$(command -v python3)"
mkdir -p "$gated_home" "$gated_stub_dir" "$gated_tmp/empty-bin"
trap 'rm -rf "$gated_tmp"' EXIT

write_success_transport() {
  local target="$1"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "transport:%s\\n" "$*" >> "$STUB_LOG"' \
    'exit 0' \
    > "$target"
  chmod +x "$target"
}

run_gated_with_stub() {
  local test_home="$1" transport="$2" transport_log="$3"
  shift 3
  env -i HOME="$test_home" PATH="/usr/bin:/bin" STUB_LOG="$transport_log" \
    ASK_TMUX_CLAUDE_BIN="$transport" \
    "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" "$@"
}

transport_line_count() {
  local transport_log="$1"
  if [[ -f "$transport_log" ]]; then
    wc -l < "$transport_log" | tr -d ' '
  else
    printf '0\n'
  fi
}

ledger_event_count() {
  local test_home="$1" kind="$2" decision="$3" exit_code="$4"
  "$python_bin" -c '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
kind, decision, exit_code = sys.argv[2:5]
events = json.loads(path.read_text())["events"]
matches = []
for event in events:
    if event.get("kind") != kind:
        continue
    if decision != "*" and event.get("decision") != decision:
        continue
    if exit_code != "*" and int(event.get("exit_code", -999)) != int(exit_code):
        continue
    matches.append(event)
print(len(matches))
' "$test_home/.omx/state/review-budget.json" "$kind" "$decision" "$exit_code"
}

assert_ledger_event_count() {
  local test_home="$1" kind="$2" decision="$3" exit_code="$4" expected="$5"
  local actual
  actual="$(ledger_event_count "$test_home" "$kind" "$decision" "$exit_code")"
  [[ "$actual" == "$expected" ]] || \
    fail "expected $expected ledger event(s) for $kind/$decision/$exit_code, got $actual"
}

assert_no_pipeline_reservations() {
  local test_home="$1"
  assert_ledger_event_count "$test_home" send_reservation '*' '*' 0
  assert_ledger_event_count "$test_home" continuation_reservation '*' '*' 0
}

hex_digest() {
  printf '%064x\n' "$1"
}

expect_gated_deny_without_transport() {
  local test_home="$1" transport="$2" transport_log="$3" expected_message="$4"
  local before after denial_out denial_rc
  shift 4
  before="$(transport_line_count "$transport_log")"
  if denial_out="$(run_gated_with_stub "$test_home" "$transport" "$transport_log" "$@" 2>&1)"; then
    fail "expected gated command to deny: $expected_message"
  else
    denial_rc=$?
  fi
  [[ "$denial_rc" == "76" ]] || fail "gated denial should exit 76, got $denial_rc"
  printf '%s\n' "$denial_out" | grep -Fq "$expected_message" || \
    fail "gated denial should mention: $expected_message"
  after="$(transport_line_count "$transport_log")"
  [[ "$after" == "$before" ]] || fail "gated denial must not invoke raw transport"
}

policy_out="$(env -i HOME="$gated_home" PATH="/usr/bin:/bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" policy)"
printf '%s\n' "$policy_out" | grep -q '"provider": "claude"' || fail "gated policy should work without raw transport"

if missing_reason_out="$(env -i HOME="$gated_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check --cwd "$gated_tmp" 2>&1)"; then
  fail "missing gate reason should deny"
else
  missing_reason_rc=$?
fi
[[ "$missing_reason_rc" == "76" ]] || fail "missing gate reason should exit 76"
printf '%s\n' "$missing_reason_out" | grep -q '"message": "missing --gate-reason"' || fail "missing reason denial should be explicit"

if unsupported_reason_out="$(env -i HOME="$gated_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check --gate-reason invented_gate --cwd "$gated_tmp" 2>&1)"; then
  fail "unsupported gate reason should deny"
else
  unsupported_reason_rc=$?
fi
[[ "$unsupported_reason_rc" == "76" ]] || fail "unsupported gate reason should exit 76"
printf '%s\n' "$unsupported_reason_out" | grep -q 'unsupported --gate-reason: invented_gate' || fail "unsupported reason denial should be explicit"

corrupt_state_home="$gated_tmp/corrupt-state-home"
mkdir -p "$corrupt_state_home/.omx/state"
printf '{broken' > "$corrupt_state_home/.omx/state/review-budget.json"
if corrupt_state_out="$(env -i HOME="$corrupt_state_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check \
    --gate-reason external_review_required --cwd "$gated_tmp" 2>&1)"; then
  fail "malformed review budget state should deny"
else
  corrupt_state_rc=$?
fi
[[ "$corrupt_state_rc" == "78" ]] || fail "malformed review budget state should exit 78"
printf '%s\n' "$corrupt_state_out" | grep -q 'review budget state is unreadable or malformed' || fail "malformed state denial should be explicit"
[[ "$(cat "$corrupt_state_home/.omx/state/review-budget.json")" == '{broken' ]] || fail "malformed review budget state must not be overwritten"

corrupt_log_home="$gated_tmp/corrupt-log-home"
mkdir -p "$corrupt_log_home/.omx/consultants"
printf 'not-json\n' > "$corrupt_log_home/.omx/consultants/log.jsonl"
if corrupt_log_out="$(env -i HOME="$corrupt_log_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check \
    --gate-reason external_review_required --cwd "$gated_tmp" 2>&1)"; then
  fail "malformed consultant log should deny"
else
  corrupt_log_rc=$?
fi
[[ "$corrupt_log_rc" == "78" ]] || fail "malformed consultant log should exit 78"
printf '%s\n' "$corrupt_log_out" | grep -q 'consultant log contains malformed JSON' || fail "malformed consultant log denial should be explicit"
[[ "$(cat "$corrupt_log_home/.omx/consultants/log.jsonl")" == 'not-json' ]] || fail "malformed consultant log must not be overwritten"

printf '%s\n' \
  '#!/bin/sh' \
  'printf "override:%s\\n" "$*" >> "$STUB_LOG"' \
  > "$gated_tmp/override-transport"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "path:%s\\n" "$*" >> "$STUB_LOG"' \
  > "$gated_stub_dir/ask-tmux-claude"
chmod +x "$gated_tmp/override-transport" "$gated_stub_dir/ask-tmux-claude"

env -i HOME="$gated_home" PATH="$gated_stub_dir:/usr/bin:/bin" STUB_LOG="$gated_stub_log" \
  ASK_TMUX_CLAUDE_BIN="$gated_tmp/override-transport" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" send \
    --gate-reason explicit_user_request --cwd "$gated_tmp" --dry-run >/dev/null 2>&1
grep -q '^override:send ' "$gated_stub_log" || fail "ASK_TMUX_CLAUDE_BIN should take precedence"

env -i HOME="$gated_home" PATH="$gated_stub_dir:/usr/bin:/bin" STUB_LOG="$gated_stub_log" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" status >/dev/null 2>&1
grep -q '^path:status$' "$gated_stub_log" || fail "raw transport should resolve from PATH"
[[ "$(wc -l < "$gated_stub_log" | tr -d ' ')" == "2" ]] || fail "only transport stubs should have been called"

concurrent_home="$gated_tmp/concurrent-home"
concurrent_log="$gated_tmp/concurrent.log"
concurrent_stub="$gated_tmp/concurrent-transport"
mkdir -p "$concurrent_home"
printf '%s\n' \
  '#!/bin/sh' \
  'sleep 1' \
  'printf "send:%s\\n" "$*" >> "$STUB_LOG"' \
  > "$concurrent_stub"
chmod +x "$concurrent_stub"
(
  set +e
  env -i HOME="$concurrent_home" PATH="/usr/bin:/bin" STUB_LOG="$concurrent_log" \
    ASK_TMUX_CLAUDE_BIN="$concurrent_stub" \
    "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" send \
      --gate-reason external_review_required --gate-fingerprint concurrent-one \
      --cwd "$gated_tmp" --dry-run >/dev/null 2>&1
  printf '%s\n' "$?" > "$gated_tmp/concurrent-one.rc"
) &
concurrent_one_pid=$!
(
  set +e
  env -i HOME="$concurrent_home" PATH="/usr/bin:/bin" STUB_LOG="$concurrent_log" \
    ASK_TMUX_CLAUDE_BIN="$concurrent_stub" \
    "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" send \
      --gate-reason external_review_required --gate-fingerprint concurrent-two \
      --cwd "$gated_tmp" --dry-run >/dev/null 2>&1
  printf '%s\n' "$?" > "$gated_tmp/concurrent-two.rc"
) &
concurrent_two_pid=$!
wait "$concurrent_one_pid" "$concurrent_two_pid"
[[ "$(sort "$gated_tmp"/concurrent-*.rc | tr '\n' ' ')" == '0 76 ' ]] || fail "concurrent sends should reserve one slot and deny the other"
[[ "$(wc -l < "$concurrent_log" | tr -d ' ')" == "1" ]] || fail "concurrent sends should invoke exactly one transport stub"
grep -q '"kind": "send_dry_run"' "$concurrent_home/.omx/state/review-budget.json" || fail "completed reservation should remain in the ledger"

pipeline_cwd="$gated_tmp/pipeline-cwd"
pipeline_other_cwd="$gated_tmp/pipeline-other-cwd"
pipeline_root_digest="$(hex_digest 1001)"
pipeline_stage_digest="$(hex_digest 1002)"
pipeline_changed_digest="$(hex_digest 1003)"
mkdir -p "$pipeline_cwd" "$pipeline_other_cwd"

# A successful pipeline start records a scoped grant, then root/key/cwd,
# missing-grant, and expired-grant mismatches all fail closed without transport.
grant_home="$gated_tmp/grant-home"
grant_transport="$gated_tmp/grant-transport"
grant_log="$gated_tmp/grant-transport.log"
mkdir -p "$grant_home"
write_success_transport "$grant_transport"
run_gated_with_stub "$grant_home" "$grant_transport" "$grant_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:grant-regression \
  --gate-pipeline-start \
  --gate-content-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key grant-key \
  --prompt pipeline-start >/dev/null 2>&1
[[ "$(transport_line_count "$grant_log")" == "1" ]] || fail "pipeline start should invoke one fake transport"
assert_ledger_event_count "$grant_home" send allow 0 1
assert_no_pipeline_reservations "$grant_home"
"$python_bin" -c '
import json
import sys

events = json.load(open(sys.argv[1]))["events"]
matches = [
    event for event in events
    if event.get("kind") == "send"
    and event.get("decision") == "allow"
    and event.get("exit_code") == 0
    and event.get("pipeline_start") is True
    and event.get("fingerprint") == sys.argv[2]
    and event.get("consultant_key") == sys.argv[3]
    and event.get("content_digest") == sys.argv[4]
]
assert len(matches) == 1, matches
' "$grant_home/.omx/state/review-budget.json" pipeline:grant-regression grant-key "$pipeline_root_digest" || \
  fail "pipeline start ledger entry should preserve its scoped grant fields"

no_grant_message='pipeline continuation has no successful same-project start within the continuation TTL'
expect_gated_deny_without_transport \
  "$grant_home" "$grant_transport" "$grant_log" "$no_grant_message" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:grant-regression \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_changed_digest" \
  --cwd "$pipeline_cwd" \
  --key grant-key \
  --prompt root-mismatch
expect_gated_deny_without_transport \
  "$grant_home" "$grant_transport" "$grant_log" "$no_grant_message" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:grant-regression \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key wrong-key \
  --prompt key-mismatch
expect_gated_deny_without_transport \
  "$grant_home" "$grant_transport" "$grant_log" "$no_grant_message" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:grant-regression \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_other_cwd" \
  --key grant-key \
  --prompt cwd-mismatch

missing_grant_home="$gated_tmp/missing-grant-home"
mkdir -p "$missing_grant_home"
expect_gated_deny_without_transport \
  "$missing_grant_home" "$grant_transport" "$grant_log" "$no_grant_message" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:missing-grant \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key missing-key \
  --prompt missing-grant

"$python_bin" -c '
import json
import sys

path = sys.argv[1]
state = json.load(open(path))
for event in state["events"]:
    if event.get("kind") == "send" and event.get("pipeline_start") is True:
        event["ts"] = "2000-01-01T00:00:00+00:00"
with open(path, "w") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
' "$grant_home/.omx/state/review-budget.json"
expect_gated_deny_without_transport \
  "$grant_home" "$grant_transport" "$grant_log" "$no_grant_message" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:grant-regression \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key grant-key \
  --prompt expired-grant
assert_no_pipeline_reservations "$grant_home"

# Two identical continuations race on the same grant. The reservation makes
# exactly one transport call; the competing invocation is denied.
continuation_concurrent_home="$gated_tmp/continuation-concurrent-home"
continuation_concurrent_transport="$gated_tmp/continuation-concurrent-transport"
continuation_start_log="$gated_tmp/continuation-concurrent-start.log"
continuation_concurrent_log="$gated_tmp/continuation-concurrent.log"
mkdir -p "$continuation_concurrent_home"
printf '%s\n' \
  '#!/bin/sh' \
  'sleep 1' \
  'printf "transport:%s\\n" "$*" >> "$STUB_LOG"' \
  'exit 0' \
  > "$continuation_concurrent_transport"
chmod +x "$continuation_concurrent_transport"
run_gated_with_stub \
  "$continuation_concurrent_home" "$continuation_concurrent_transport" "$continuation_start_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:concurrent-continuation \
  --gate-pipeline-start \
  --gate-content-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key concurrent-key \
  --prompt pipeline-start >/dev/null 2>&1
for contender in one two; do
  (
    set +e
    run_gated_with_stub \
      "$continuation_concurrent_home" "$continuation_concurrent_transport" "$continuation_concurrent_log" send \
      --gate-reason external_review_required \
      --gate-fingerprint pipeline:concurrent-continuation \
      --gate-continuation answer:1 \
      --gate-content-digest "$pipeline_stage_digest" \
      --gate-root-digest "$pipeline_root_digest" \
      --cwd "$pipeline_cwd" \
      --key concurrent-key \
      --prompt continuation-one >/dev/null 2>&1
    printf '%s\n' "$?" > "$gated_tmp/continuation-concurrent-$contender.rc"
  ) &
done
wait
[[ "$(sort "$gated_tmp"/continuation-concurrent-*.rc | tr '\n' ' ')" == '0 76 ' ]] || \
  fail "identical concurrent continuations should yield statuses 0 and 76"
[[ "$(transport_line_count "$continuation_concurrent_log")" == "1" ]] || \
  fail "identical concurrent continuations should invoke one fake transport"
assert_ledger_event_count "$continuation_concurrent_home" send allow 0 1
assert_ledger_event_count "$continuation_concurrent_home" continuation_send allow 0 1
assert_ledger_event_count "$continuation_concurrent_home" continuation_send deny 76 1
assert_no_pipeline_reservations "$continuation_concurrent_home"

# A failed continuation may retry only the exact same content digest. A changed
# digest is denied before transport, while the identical retry can succeed.
retry_home="$gated_tmp/retry-home"
retry_transport="$gated_tmp/retry-transport"
retry_log="$gated_tmp/retry-transport.log"
mkdir -p "$retry_home"
printf '%s\n' \
  '#!/bin/sh' \
  'count=0' \
  '[ ! -f "$STUB_LOG" ] || count=$(wc -l < "$STUB_LOG" | tr -d " ")' \
  'printf "transport:%s\\n" "$*" >> "$STUB_LOG"' \
  '[ "$count" -ne 1 ] || exit 42' \
  'exit 0' \
  > "$retry_transport"
chmod +x "$retry_transport"
run_gated_with_stub "$retry_home" "$retry_transport" "$retry_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:retry-content \
  --gate-pipeline-start \
  --gate-content-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key retry-key \
  --prompt pipeline-start >/dev/null 2>&1
if retry_first_out="$(run_gated_with_stub "$retry_home" "$retry_transport" "$retry_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:retry-content \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key retry-key \
  --prompt failed-continuation 2>&1)"; then
  fail "first continuation transport should fail in the retry fixture"
else
  retry_first_rc=$?
fi
[[ "$retry_first_rc" == "42" ]] || fail "failed continuation fixture should exit 42"
expect_gated_deny_without_transport \
  "$retry_home" "$retry_transport" "$retry_log" \
  'failed pipeline continuation may be retried only with identical stage content' send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:retry-content \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_changed_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key retry-key \
  --prompt changed-content
run_gated_with_stub "$retry_home" "$retry_transport" "$retry_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:retry-content \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key retry-key \
  --prompt identical-retry >/dev/null 2>&1
[[ "$(transport_line_count "$retry_log")" == "3" ]] || \
  fail "start, failed continuation, and identical retry should be the only transport calls"
assert_ledger_event_count "$retry_home" continuation_send allow 42 1
assert_ledger_event_count "$retry_home" continuation_send deny 76 1
assert_ledger_event_count "$retry_home" continuation_send allow 0 1
assert_no_pipeline_reservations "$retry_home"

# Failed allowed attempts consume the same lifecycle cap. After eight identical
# transport failures, the ninth retry is denied before transport.
failed_cap_home="$gated_tmp/failed-cap-home"
failed_cap_transport="$gated_tmp/failed-cap-transport"
failed_cap_log="$gated_tmp/failed-cap-transport.log"
mkdir -p "$failed_cap_home"
printf '%s\n' \
  '#!/bin/sh' \
  'count=0' \
  '[ ! -f "$STUB_LOG" ] || count=$(wc -l < "$STUB_LOG" | tr -d " ")' \
  'printf "transport:%s\\n" "$*" >> "$STUB_LOG"' \
  '[ "$count" -eq 0 ] && exit 0' \
  'exit 42' \
  > "$failed_cap_transport"
chmod +x "$failed_cap_transport"
run_gated_with_stub "$failed_cap_home" "$failed_cap_transport" "$failed_cap_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:failed-cap \
  --gate-pipeline-start \
  --gate-content-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key failed-cap-key \
  --prompt pipeline-start >/dev/null 2>&1
for (( failed_attempt = 1; failed_attempt <= 8; failed_attempt++ )); do
  if failed_attempt_out="$(run_gated_with_stub \
    "$failed_cap_home" "$failed_cap_transport" "$failed_cap_log" send \
    --gate-reason external_review_required \
    --gate-fingerprint pipeline:failed-cap \
    --gate-continuation answer:1 \
    --gate-content-digest "$pipeline_stage_digest" \
    --gate-root-digest "$pipeline_root_digest" \
    --cwd "$pipeline_cwd" \
    --key failed-cap-key \
    --prompt failed-retry 2>&1)"; then
    fail "failed-cap transport attempt $failed_attempt should fail"
  else
    failed_attempt_rc=$?
  fi
  [[ "$failed_attempt_rc" == "42" ]] || \
    fail "failed-cap transport attempt $failed_attempt should exit 42"
done
expect_gated_deny_without_transport \
  "$failed_cap_home" "$failed_cap_transport" "$failed_cap_log" \
  'pipeline continuation cap reached: 8/8' send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:failed-cap \
  --gate-continuation answer:1 \
  --gate-content-digest "$pipeline_stage_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key failed-cap-key \
  --prompt ninth-failed-retry
[[ "$(transport_line_count "$failed_cap_log")" == "9" ]] || \
  fail "failed cap should call transport for one start and eight failed attempts"
assert_ledger_event_count "$failed_cap_home" continuation_send allow 42 8
assert_ledger_event_count "$failed_cap_home" continuation_send deny 76 1
assert_no_pipeline_reservations "$failed_cap_home"

# Eight sequential continuations fit the lifecycle grant; the ninth is denied
# by the cap without invoking raw transport.
cap_home="$gated_tmp/cap-home"
cap_transport="$gated_tmp/cap-transport"
cap_log="$gated_tmp/cap-transport.log"
mkdir -p "$cap_home"
write_success_transport "$cap_transport"
run_gated_with_stub "$cap_home" "$cap_transport" "$cap_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:cap-eight \
  --gate-pipeline-start \
  --gate-content-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key cap-key \
  --prompt pipeline-start >/dev/null 2>&1
for (( continuation_index = 1; continuation_index <= 8; continuation_index++ )); do
  continuation_digest="$(hex_digest "$((2000 + continuation_index))")"
  run_gated_with_stub "$cap_home" "$cap_transport" "$cap_log" send \
    --gate-reason external_review_required \
    --gate-fingerprint pipeline:cap-eight \
    --gate-continuation "answer:$continuation_index" \
    --gate-content-digest "$continuation_digest" \
    --gate-root-digest "$pipeline_root_digest" \
    --cwd "$pipeline_cwd" \
    --key cap-key \
    --prompt "continuation-$continuation_index" >/dev/null 2>&1
done
ninth_digest="$(hex_digest 2009)"
expect_gated_deny_without_transport \
  "$cap_home" "$cap_transport" "$cap_log" 'pipeline continuation cap reached: 8/8' send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:cap-eight \
  --gate-continuation answer:9 \
  --gate-content-digest "$ninth_digest" \
  --gate-root-digest "$pipeline_root_digest" \
  --cwd "$pipeline_cwd" \
  --key cap-key \
  --prompt continuation-nine
[[ "$(transport_line_count "$cap_log")" == "9" ]] || \
  fail "pipeline cap fixture should call transport for one start and eight continuations"
assert_ledger_event_count "$cap_home" continuation_send allow 0 8
assert_ledger_event_count "$cap_home" continuation_send deny 76 1
assert_no_pipeline_reservations "$cap_home"

# Reusing a pipeline ID/key/cwd after root A expires must create an isolated
# root-B lifecycle. Root-A answer:1 is neither a duplicate nor sequence proof
# for root B.
root_isolation_home="$gated_tmp/root-isolation-home"
root_isolation_transport="$gated_tmp/root-isolation-transport"
root_isolation_log="$gated_tmp/root-isolation-transport.log"
root_a_digest="$(hex_digest 3001)"
root_b_digest="$(hex_digest 3002)"
root_a_stage_digest="$(hex_digest 3003)"
root_b_stage_one_digest="$(hex_digest 3004)"
root_b_stage_two_digest="$(hex_digest 3005)"
mkdir -p "$root_isolation_home"
write_success_transport "$root_isolation_transport"
run_gated_with_stub \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-pipeline-start \
  --gate-content-digest "$root_a_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-a-start >/dev/null 2>&1
run_gated_with_stub \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-continuation answer:1 \
  --gate-content-digest "$root_a_stage_digest" \
  --gate-root-digest "$root_a_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-a-answer-one >/dev/null 2>&1
"$python_bin" -c '
import json
import sys

path, root_a = sys.argv[1:3]
state = json.load(open(path))
for event in state["events"]:
    if (
        event.get("kind") == "send"
        and event.get("pipeline_start") is True
        and event.get("content_digest") == root_a
    ):
        event["ts"] = "2000-01-01T00:00:00+00:00"
with open(path, "w") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
' "$root_isolation_home/.omx/state/review-budget.json" "$root_a_digest"
run_gated_with_stub \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-pipeline-start \
  --gate-content-digest "$root_b_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-b-start >/dev/null 2>&1
expect_gated_deny_without_transport \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" \
  'pipeline continuation is out of sequence; missing successful answer:1' send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-continuation answer:2 \
  --gate-content-digest "$root_b_stage_two_digest" \
  --gate-root-digest "$root_b_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-b-answer-two-too-early
run_gated_with_stub \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-continuation answer:1 \
  --gate-content-digest "$root_b_stage_one_digest" \
  --gate-root-digest "$root_b_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-b-answer-one >/dev/null 2>&1
run_gated_with_stub \
  "$root_isolation_home" "$root_isolation_transport" "$root_isolation_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:root-isolation \
  --gate-continuation answer:2 \
  --gate-content-digest "$root_b_stage_two_digest" \
  --gate-root-digest "$root_b_digest" \
  --cwd "$pipeline_cwd" \
  --key root-isolation-key \
  --prompt root-b-answer-two >/dev/null 2>&1
[[ "$(transport_line_count "$root_isolation_log")" == "5" ]] || \
  fail "root isolation should call transport for two starts and three scoped continuations"
assert_ledger_event_count "$root_isolation_home" send allow 0 2
assert_ledger_event_count "$root_isolation_home" continuation_send allow 0 3
assert_ledger_event_count "$root_isolation_home" continuation_send deny 76 1
assert_no_pipeline_reservations "$root_isolation_home"

# Reusing the exact same pipeline identity and root after the original grant
# expires must still create a new lifecycle. The grant ID, not just the root
# digest, scopes duplicate, retry, ordering, and cap evidence.
same_root_home="$gated_tmp/same-root-home"
same_root_transport="$gated_tmp/same-root-transport"
same_root_log="$gated_tmp/same-root-transport.log"
same_root_digest="$(hex_digest 4001)"
same_root_answer_one_digest="$(hex_digest 4002)"
same_root_answer_two_digest="$(hex_digest 4003)"
old_failed_review_digest="$(hex_digest 4004)"
fresh_review_digest="$(hex_digest 4005)"
mkdir -p "$same_root_home"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "transport:%s\\n" "$*" >> "$STUB_LOG"' \
  'case "$*" in' \
  '  *"--prompt old-failed-review"*) exit 42 ;;' \
  'esac' \
  'exit 0' \
  > "$same_root_transport"
chmod +x "$same_root_transport"
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-pipeline-start \
  --gate-content-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt old-start >/dev/null 2>&1
old_grant_id="$("$python_bin" -c '
import json
import sys

events = json.load(open(sys.argv[1]))["events"]
starts = [event for event in events if event.get("kind") == "send" and event.get("pipeline_start") is True]
print(starts[-1].get("grant_id", ""))
' "$same_root_home/.omx/state/review-budget.json")"
[[ -n "$old_grant_id" ]] || fail "old pipeline start should receive a grant ID"
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-continuation answer:1 \
  --gate-content-digest "$same_root_answer_one_digest" \
  --gate-root-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt old-answer-one >/dev/null 2>&1
for (( old_failure = 1; old_failure <= 7; old_failure++ )); do
  if old_failure_out="$(run_gated_with_stub \
    "$same_root_home" "$same_root_transport" "$same_root_log" send \
    --gate-reason external_review_required \
    --gate-fingerprint pipeline:same-root-new-grant \
    --gate-continuation review:1 \
    --gate-content-digest "$old_failed_review_digest" \
    --gate-root-digest "$same_root_digest" \
    --cwd "$pipeline_cwd" \
    --key same-root-key \
    --prompt old-failed-review 2>&1)"; then
    fail "old-grant failed-review attempt $old_failure should fail"
  else
    old_failure_rc=$?
  fi
  [[ "$old_failure_rc" == "42" ]] || \
    fail "old-grant failed-review attempt $old_failure should exit 42"
done
"$python_bin" -c '
import json
import sys

path, old_grant = sys.argv[1:3]
state = json.load(open(path))
for event in state["events"]:
    if (
        event.get("kind") == "send"
        and event.get("pipeline_start") is True
        and event.get("grant_id") == old_grant
    ):
        event["ts"] = "2000-01-01T00:00:00+00:00"
with open(path, "w") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
' "$same_root_home/.omx/state/review-budget.json" "$old_grant_id"
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-pipeline-start \
  --gate-content-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt fresh-start >/dev/null 2>&1
fresh_grant_id="$("$python_bin" -c '
import json
import sys

events = json.load(open(sys.argv[1]))["events"]
starts = [event for event in events if event.get("kind") == "send" and event.get("pipeline_start") is True]
print(starts[-1].get("grant_id", ""))
' "$same_root_home/.omx/state/review-budget.json")"
[[ -n "$fresh_grant_id" ]] || fail "fresh same-root pipeline start should receive a grant ID"
[[ "$fresh_grant_id" != "$old_grant_id" ]] || fail "fresh same-root pipeline start should receive a distinct grant ID"

expect_gated_deny_without_transport \
  "$same_root_home" "$same_root_transport" "$same_root_log" \
  'pipeline continuation is out of sequence; missing successful answer:1' send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-continuation answer:2 \
  --gate-content-digest "$same_root_answer_two_digest" \
  --gate-root-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt fresh-answer-two-too-early
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-continuation answer:1 \
  --gate-content-digest "$same_root_answer_one_digest" \
  --gate-root-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt fresh-answer-one >/dev/null 2>&1
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-continuation answer:2 \
  --gate-content-digest "$same_root_answer_two_digest" \
  --gate-root-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt fresh-answer-two >/dev/null 2>&1
run_gated_with_stub "$same_root_home" "$same_root_transport" "$same_root_log" send \
  --gate-reason external_review_required \
  --gate-fingerprint pipeline:same-root-new-grant \
  --gate-continuation review:1 \
  --gate-content-digest "$fresh_review_digest" \
  --gate-root-digest "$same_root_digest" \
  --cwd "$pipeline_cwd" \
  --key same-root-key \
  --prompt fresh-review-content >/dev/null 2>&1
[[ "$(transport_line_count "$same_root_log")" == "13" ]] || \
  fail "same-root fixture should make thirteen fake transport calls"
"$python_bin" -c '
import json
import sys

path, old_grant, fresh_grant = sys.argv[1:4]
events = json.load(open(path))["events"]
old_allowed = [
    event for event in events
    if event.get("kind") == "continuation_send"
    and event.get("decision") == "allow"
    and event.get("grant_id") == old_grant
]
fresh_allowed = [
    event for event in events
    if event.get("kind") == "continuation_send"
    and event.get("decision") == "allow"
    and event.get("grant_id") == fresh_grant
]
fresh_denied = [
    event for event in events
    if event.get("kind") == "continuation_send"
    and event.get("decision") == "deny"
    and event.get("grant_id") == fresh_grant
]
assert len(old_allowed) == 8, old_allowed
assert len([event for event in old_allowed if event.get("exit_code") == 42]) == 7, old_allowed
assert len(fresh_allowed) == 3, fresh_allowed
assert {event.get("continuation") for event in fresh_allowed} == {"answer:1", "answer:2", "review:1"}, fresh_allowed
assert len(fresh_denied) == 1 and fresh_denied[0].get("continuation") == "answer:2", fresh_denied
' "$same_root_home/.omx/state/review-budget.json" "$old_grant_id" "$fresh_grant_id" || \
  fail "same-root continuation evidence should remain isolated by grant ID"
assert_no_pipeline_reservations "$same_root_home"

if absent_transport_out="$(env -i HOME="$gated_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" status 2>&1)"; then
  fail "missing raw transport should fail closed"
else
  absent_transport_rc=$?
fi
[[ "$absent_transport_rc" == "127" ]] || fail "missing raw transport should exit 127"
[[ "$absent_transport_out" == "ask-tmux-claude binary not found" ]] || fail "missing raw transport should report a concise error"

printf 'consultant unit ok\n'
