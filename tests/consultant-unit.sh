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

original_tmux_function="$(declare -f tmux)"
tmux() {
  case "$1" in
    display-message)
      if [[ "$*" != *'%42'* ]]; then
        printf '%s\n' "can't find pane: ${3:-unknown}" >&2
        return 1
      fi
      printf '%%42\n'
      ;;
    list-panes)
      printf '%%42\n'
      ;;
    *)
      command tmux "$@"
      ;;
  esac
}

pane_target_for_session_checked test-session \
  || fail "should discover tmux pane IDs without assuming window 0"
[[ "$TMUX_RESOLVED_PANE" == '%42' ]] || fail "should retain the discovered stable pane ID"
pane_target_for_session_checked test-session '%42' \
  || fail "should preserve a valid recorded pane ID"
[[ "$TMUX_RESOLVED_PANE" == '%42' ]] || fail "should retain a valid recorded pane ID"
pane_target_for_session_checked test-session 'test-session:0.0' \
  || fail "should recover from an invalid legacy pane target"
[[ "$TMUX_RESOLVED_PANE" == '%42' ]] || fail "should replace invalid legacy pane targets"
eval "$original_tmux_function"

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

codex_auto_review_loading='
╭─────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.146.0-alpha.3.1)            │
│                                                 │
│ model:       loading   /model to change         │
│ directory:   ~/Downloads/Datasets_Miscellaneous │
│ permissions: YOLO mode                          │
╰─────────────────────────────────────────────────╯

› Run /review on my current changes

  codex-auto-review default · ~/Downloads/Datasets_Miscellaneous
'

codex_auto_review_ready='
╭───────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.146.0-alpha.3.1)                  │
│                                                       │
│ model:       codex-auto-review max   /model to change │
│ directory:   ~/Downloads/Datasets_Miscellaneous       │
│ permissions: YOLO mode                                │
╰───────────────────────────────────────────────────────╯

  Tip: Try the Desktop app. Run '"'"'codex app'"'"' or visit
  https://chatgpt.com/codex?app-landing-page=true

• Starting MCP servers (1/2): codex_apps (7s • esc to interrupt)

› Run /review on my current changes

  codex-auto-review max · ~/Downloads/Datasets_Miscellaneous
'

ready_with_placeholder_composer='
⚠ Skipped loading 133 skill(s) due to invalid SKILL.md files.

› Write tests for @filename

  gpt-5.6-sol high · /tmp/project
'

active_with_placeholder_composer='
› Write tests for @filename

◦ Working (4s • esc to interrupt)

  gpt-5.6-sol high · /tmp/project
'

update_with_placeholder_shape='
› 1. Update now
  2. Skip
  3. Skip until next version
'

hooks_with_placeholder_shape='
  Hooks need review

› 1. Review hooks
  2. Trust all and continue
'

trust_with_placeholder_shape='
  Do you trust the contents of this directory?

› 1. Yes, continue
  2. No, quit
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

[[ "$(shell_quote '/tmp/ask tmux response.md')" == "'/tmp/ask tmux response.md'" ]] \
  || fail "response paths with spaces must be shell-quoted in prompts"
stub_space_root="$(mktemp -d /tmp/ask-tmux-stub-space.XXXXXX)"
stub_space_response="$stub_space_root/response folder/response.md"
stub_space_b64="$(printf '%s' "$stub_space_response" | base64 | tr -d '\n')"
stub_space_line="ASK_TMUX_RESPONSE=$(shell_quote "$stub_space_response") ASK_TMUX_RESPONSE_B64=$stub_space_b64 ASK_TMUX_SENTINEL=<<<ASK_TMUX_DONE:stub-space>>>"
stub_space_output="$(printf '%s\n' "$stub_space_line" | eval "$(provider_launch_command codex true)")"
[[ -f "$stub_space_response" ]] \
  || fail "stub transport must decode a response path containing spaces"
grep -Fq "$stub_space_response" <<<"$stub_space_output" \
  || fail "stub transport must preserve the quoted response path"
rm -rf "$stub_space_root"

assert_not_ready codex "$trust_plus_banner_no_composer"
assert_ready codex "$ready_with_stale_trust"
assert_not_ready codex "$codex_auto_review_loading"
assert_ready codex "$codex_auto_review_ready"
assert_ready codex "$ready_with_placeholder_composer"
assert_not_ready codex "$active_with_placeholder_composer"
assert_not_ready codex "$update_with_placeholder_shape"
assert_not_ready codex "$hooks_with_placeholder_shape"
assert_not_ready codex "$trust_with_placeholder_shape"
assert_ready claude "$claude_ready_with_status"
text_contains_sentinel "$wrapped_sentinel" "$sentinel" || fail "wrapped sentinel was not detected"
[[ "$(claude_gateway_524_count 'Documentation mentions API Error: 524 without a provider error block.')" == "0" ]] \
  || fail "a documentation-only 524 mention should not be classified as a provider failure"
[[ "$(claude_gateway_524_count $'● API Error: 524 {"status":524,"error_code":524,\n"error_name":"origin_response_timeout","retryable":true}')" == "1" ]] \
  || fail "the real Claude 2.1.220 gateway error rendering should be classified"

original_tmux_session_liveness="$(declare -f tmux_session_liveness)"
original_tmux_control_command="$(declare -f tmux_control_command)"
identity_session_fixture="$(mktemp /tmp/ask-tmux-identity-session.XXXXXX)"
identity_pane_fixture="$(mktemp /tmp/ask-tmux-identity-pane.XXXXXX)"
tmux_session_liveness() {
  printf '%s\n' "$1" > "$identity_session_fixture"
  return 0
}
tmux_control_command() {
  [[ "$1" == "capture-pane" ]] || return 1
  printf '%s\n' "$4" > "$identity_pane_fixture"
  TMUX_CONTROL_STDOUT="ASK_TMUX_STUB_READY"
  TMUX_CONTROL_EXIT=0
  return 0
}
wait_for_ready codex true fixture-session %42 0 false \
  || fail "stub readiness should succeed"
[[ "$(sed -n '1p' "$identity_session_fixture")" == "fixture-session" ]] \
  || fail "readiness must check liveness with the session name"
[[ "$(sed -n '1p' "$identity_pane_fixture")" == "%42" ]] \
  || fail "readiness must capture with the stable pane ID"
rm -f "$identity_session_fixture" "$identity_pane_fixture"

provider_timeout_fixture="$(mktemp /tmp/ask-tmux-provider-timeout.XXXXXX)"
rm -f "$provider_timeout_fixture"
tmux_session_liveness() { return 0; }
tmux_control_command() {
  [[ "$1" == "capture-pane" ]] || return 1
  TMUX_CONTROL_EXIT=0
  if [[ -e "$provider_timeout_fixture" ]]; then
    TMUX_CONTROL_STDOUT=$'● API Error: 524 {"status":524,"error_code":524,\n"error_name":"origin_response_timeout","retryable":true}\nCloudflare origin did not return a complete response within the 120-second Proxy Read Timeout'
  else
    : > "$provider_timeout_fixture"
    TMUX_CONTROL_STDOUT="Claude is working"
  fi
  return 0
}
if wait_for_done "fixture-session" "%fixture" "<<<DONE>>>" "/tmp/ask-tmux-no-response-fixture" 0 0 claude; then
  provider_timeout_rc=0
else
  provider_timeout_rc=$?
fi
if wait_for_done "fixture-session" "%fixture" "<<<DONE>>>" "/tmp/ask-tmux-no-response-fixture" 0 0 claude; then
  stale_provider_timeout_rc=0
else
  stale_provider_timeout_rc=$?
fi
eval "$original_tmux_session_liveness"
eval "$original_tmux_control_command"
rm -f "$provider_timeout_fixture"
[[ "$provider_timeout_rc" == "4" ]] \
  || fail "Claude gateway API Error 524 should be classified as a provider failure"
[[ "$stale_provider_timeout_rc" == "2" ]] \
  || fail "a stale Claude gateway error should not fail a later request"

completion_response_fixture="$(mktemp /tmp/ask-tmux-complete-response.XXXXXX)"
printf '%s\n' 'Completed review body.' '<<<COMPLETE>>>' > "$completion_response_fixture"
response_file_is_complete "$completion_response_fixture" '<<<COMPLETE>>>' 0 \
  || fail "a fresh response with its terminal completion marker should be complete"
strip_response_completion_marker "$completion_response_fixture" '<<<COMPLETE>>>' \
  || fail "completion marker should be removable after verification"
grep -Fqx 'Completed review body.' "$completion_response_fixture" \
  || fail "stripping the completion marker must preserve response content"
if grep -Fq '<<<COMPLETE>>>' "$completion_response_fixture"; then
  fail "completion marker should not leak into the delivered response"
fi
rm -f "$completion_response_fixture"

original_wait_for_done="$(declare -f wait_for_done)"
original_wait_for_ready="$(declare -f wait_for_ready)"
original_send_prompt_to_pane="$(declare -f send_prompt_to_pane)"
original_log_event="$(declare -f log_event)"
original_info="$(declare -f info)"
original_sleep="$(declare -f sleep 2>/dev/null || true)"
retry_response_fixture="$(mktemp /tmp/ask-tmux-retry-response.XXXXXX)"
retry_prompt_fixture="$(mktemp /tmp/ask-tmux-retry-prompt.XXXXXX)"
printf '%s\n' 'Preserved partial finding.' > "$retry_response_fixture"
retry_wait_calls=0
wait_for_done() {
  retry_wait_calls="$((retry_wait_calls + 1))"
  if [[ "$retry_wait_calls" == "1" ]]; then
    return 4
  fi
  printf '%s\n' 'Completed resumed finding.' '<<<COMPLETE>>>' >> "$retry_response_fixture"
  return 0
}
wait_for_ready() { return 0; }
send_prompt_to_pane() {
  printf '%s\n' "$2" > "$retry_prompt_fixture"
  return 0
}
log_event() { :; }
info() { :; }
sleep() { :; }
CLAUDE_524_MAX_RETRIES=2
CLAUDE_524_BACKOFF_SECONDS=0
wait_for_done_resilient fixture-session %fixture '<<<DONE>>>' \
  "$retry_response_fixture" 0 0 claude '<<<COMPLETE>>>' false 0 false \
  "$retry_response_fixture" \
  || fail "a 524 should resume the same Claude session and complete"
[[ "$retry_wait_calls" == "2" && "$WAIT_RECOVERY_RETRY_COUNT" == "1" ]] \
  || fail "524 recovery should retry exactly the interrupted turn"
grep -Fqx 'Preserved partial finding.' "$retry_response_fixture" \
  || fail "524 recovery must preserve partial response work"
grep -Fqx 'Completed resumed finding.' "$retry_response_fixture" \
  || fail "524 recovery must retain resumed response work"
grep -Fq 'Do not redo completed inspection or omit any requested scope.' "$retry_prompt_fixture" \
  || fail "524 recovery prompt must preserve full scope"
eval "$original_wait_for_done"
eval "$original_wait_for_ready"
eval "$original_send_prompt_to_pane"
eval "$original_log_event"
eval "$original_info"
if [[ -n "$original_sleep" ]]; then eval "$original_sleep"; else unset -f sleep; fi
rm -f "$retry_response_fixture" "$retry_prompt_fixture"

scope_complete_fixture="$(mktemp /tmp/ask-tmux-scope-complete.XXXXXX)"
scope_incomplete_fixture="$(mktemp /tmp/ask-tmux-scope-incomplete.XXXXXX)"
printf '%s\n' 'ASK_TMUX_SCOPE_CHECK_V1' 'STATUS: COMPLETE' > "$scope_complete_fixture"
printf '%s\n' 'ASK_TMUX_SCOPE_CHECK_V1' 'STATUS: INCOMPLETE' > "$scope_incomplete_fixture"
[[ "$(scope_check_status "$scope_complete_fixture")" == "COMPLETE" ]] \
  || fail "scope protocol should parse COMPLETE"
[[ "$(scope_check_status "$scope_incomplete_fixture")" == "INCOMPLETE" ]] \
  || fail "scope protocol should parse INCOMPLETE"
rm -f "$scope_complete_fixture" "$scope_incomplete_fixture"

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

original_tmux_control_command="$(declare -f tmux_control_command)"
delivery_call_log="$(mktemp /tmp/ask-tmux-delivery-calls.XXXXXX)"
sleep() { :; }
tmux_control_command() {
  printf '%s\n' "$*" >> "$delivery_call_log"
  TMUX_CONTROL_COMMAND="${1:-tmux}"
  TMUX_CONTROL_EXIT=0
  TMUX_CONTROL_STDOUT=""
  TMUX_CONTROL_STDERR=""
  TMUX_CONTROL_KIND=""
  TMUX_CONTROL_RETRYABLE="true"
  case "$1" in
    set-buffer)
      return 0
      ;;
    paste-buffer)
      TMUX_CONTROL_EXIT=42
      TMUX_CONTROL_STDERR="paste-buffer transport failed"
      TMUX_CONTROL_KIND="tmux_control_failed"
      return 1
      ;;
    delete-buffer)
      return 0
      ;;
    *)
      return 99
      ;;
  esac
}
set +e
send_prompt_to_pane "%42" "fixture prompt" codex "fixture prompt"
paste_failure_rc=$?
set -e
[[ "$paste_failure_rc" == "1" ]] || fail "pre-Enter paste failure should remain a definite delivery failure"
grep -Fq 'delete-buffer -b ask-tmux-send-' "$delivery_call_log" \
  || fail "paste failure should clean the named tmux buffer"
[[ "$TMUX_CONTROL_EXIT" == "42" && "$TMUX_CONTROL_STDERR" == "paste-buffer transport failed" ]] \
  || fail "buffer cleanup should preserve the original paste failure evidence"

: > "$delivery_call_log"
tmux_control_command() {
  printf '%s\n' "$*" >> "$delivery_call_log"
  TMUX_CONTROL_COMMAND="${1:-tmux}"
  TMUX_CONTROL_EXIT=0
  TMUX_CONTROL_STDOUT=""
  TMUX_CONTROL_STDERR=""
  TMUX_CONTROL_KIND=""
  TMUX_CONTROL_RETRYABLE="true"
  case "$1" in
    set-buffer|paste-buffer|send-keys)
      return 0
      ;;
    capture-pane)
      TMUX_CONTROL_EXIT=1
      TMUX_CONTROL_STDERR="error connecting to /private/tmp/tmux-501/default (Operation not permitted)"
      TMUX_CONTROL_KIND="tmux_socket_denied"
      TMUX_CONTROL_RETRYABLE="false"
      return 1
      ;;
    *)
      return 99
      ;;
  esac
}
set +e
send_prompt_to_pane "%42" "fixture prompt" codex "fixture prompt"
accepted_unconfirmed_rc=$?
set -e
[[ "$accepted_unconfirmed_rc" == "2" ]] \
  || fail "control loss after Enter should be accepted-but-unconfirmed"
[[ "$TMUX_PROMPT_DELIVERY_PHASE" == "accepted_unconfirmed" ]] \
  || fail "post-Enter control loss should expose the accepted-unconfirmed phase"
[[ "$TMUX_CONTROL_KIND" == "tmux_socket_denied" ]] \
  || fail "accepted-unconfirmed delivery should retain the underlying control evidence"
eval "$original_tmux_control_command"
unset -f sleep
rm -f "$delivery_call_log"

case "$codex_launch_cmd" in
  env\ PATH=*HOME=*codex\ --dangerously-bypass-approvals-and-sandbox) ;;
  *) fail "Codex launch should pass the runner PATH/HOME into tmux" ;;
esac

attach_tmux_fixture="$(mktemp /tmp/ask-tmux-attach-client.XXXXXX)"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${1:-}" == "has-session" ]]; then' \
  '  if [[ "${ATTACH_MODE:-live}" == "denied" ]]; then' \
  '    printf "%s\n" "error connecting to /private/tmp/tmux-501/default (Operation not permitted)" >&2' \
  '    exit 1' \
  '  fi' \
  '  exit 0' \
  'fi' \
  'exit 99' \
  > "$attach_tmux_fixture"
chmod +x "$attach_tmux_fixture"
attach_state_root="$(mktemp -d /tmp/ask-tmux-attach-state.XXXXXX)"
original_state_root="$STATE_ROOT"
STATE_ROOT="$attach_state_root"
attach_resolved_cwd="$(resolve_cwd /tmp current)"
attach_project_slug="$(project_slug_from_path "$attach_resolved_cwd")"
attach_key="configured-attach"
attach_key_id="$(key_id_from_key "$attach_key")"
attach_state_file="$(state_file_for codex "$attach_project_slug" "$attach_key_id")"
write_state "$attach_state_file" codex "$attach_key" "$attach_project_slug" fixture-session %42 "$attach_resolved_cwd" /tmp/packet.md live manual "" /tmp/response.md false
attach_display="$(
  ASK_TMUX_TMUX_BIN="$attach_tmux_fixture" \
    cmd_attach --provider codex --key "$attach_key" --cwd "$attach_resolved_cwd" --cwd-mode current
)"
[[ "$attach_display" == "$attach_tmux_fixture attach -t fixture-session" ]] \
  || fail "attach command should resolve and display the configured tmux binary"
set +e
attach_denied_output="$(
  ATTACH_MODE=denied \
  ASK_TMUX_TMUX_BIN="$attach_tmux_fixture" \
    cmd_attach --provider codex --key "$attach_key" --cwd "$attach_resolved_cwd" --cwd-mode current \
    2>&1
)"
attach_denied_rc=$?
set -e
[[ "$attach_denied_rc" == "1" ]] || fail "attach control denial should fail"
grep -Fqx 'ASK_TMUX_OUTCOME=tmux_runtime_socket_denied' <<<"$attach_denied_output" \
  || fail "attach control denial should retain its typed runtime outcome"
STATE_ROOT="$original_state_root"
rm -f "$attach_tmux_fixture"
rm -rf "$attach_state_root"

gated_tmp="$(mktemp -d /tmp/ask-tmux-claude-gated-unit.XXXXXX)"
gated_home="$gated_tmp/home"
gated_stub_dir="$gated_tmp/stub-bin"
gated_stub_log="$gated_tmp/stub.log"
python_bin="$(command -v python3)"
mkdir -p "$gated_home" "$gated_stub_dir" "$gated_tmp/empty-bin"
trap 'rm -rf "$gated_tmp"' EXIT

printf '%s\n' '#!/bin/sh' 'exit 0' > "$gated_stub_dir/cc-claude"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$gated_stub_dir/cc-deepseek"
chmod +x "$gated_stub_dir/cc-claude" "$gated_stub_dir/cc-deepseek"

claude_default_launch_cmd="$(
  PATH="$gated_stub_dir:$PATH" provider_launch_command claude false
)"
claude_deepseek_launch_cmd="$(
  PATH="$gated_stub_dir:$PATH" ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
    provider_launch_command claude false
)"
claude_opus5_launch_cmd="$(
  PATH="$gated_stub_dir:$PATH" provider_launch_command claude false claude-opus-5
)"
claude_low_effort_launch_cmd="$(
  PATH="$gated_stub_dir:$PATH" provider_launch_command claude false claude-opus-5 low
)"
[[ "$claude_default_launch_cmd" == *"$gated_stub_dir/cc-claude"* &&
   "$claude_default_launch_cmd" == *"--bare"* &&
   "$claude_default_launch_cmd" == *"--disable-slash-commands"* &&
   "$claude_default_launch_cmd" == *"--no-chrome"* &&
   "$claude_default_launch_cmd" == *"--dangerously-skip-permissions"* ]] \
  || fail "Claude launch should use a bare isolated cc-claude runtime"
[[ "$CLAUDE_RUNTIME_FLAGS" == "--bare --disable-slash-commands --no-chrome --dangerously-skip-permissions" ]] \
  || fail "Claude runtime flags should have one diagnostic and execution source of truth"
[[ "$claude_deepseek_launch_cmd" == *"$gated_stub_dir/cc-deepseek"* &&
   "$claude_deepseek_launch_cmd" == *"--bare"* &&
   "$claude_deepseek_launch_cmd" == *"--dangerously-skip-permissions"* ]] \
  || fail "DeepSeek launch should use a bare isolated cc-deepseek runtime"
[[ "$claude_opus5_launch_cmd" == *"$gated_stub_dir/cc-claude"* &&
   "$claude_opus5_launch_cmd" == *"--model"* &&
   "$claude_opus5_launch_cmd" == *"claude-opus-5"* ]] \
  || fail "Claude launch should accept an explicit Opus 5 model pin"
[[ "$claude_low_effort_launch_cmd" == *"--model 'claude-opus-5'"* &&
   "$claude_low_effort_launch_cmd" == *"--effort 'low'"* ]] \
  || fail "Claude launch should pass an explicit effort level to cc-claude"
claude_default_send_out="$(
  PATH="$gated_stub_dir:$PATH" cmd_send \
    --provider claude \
    --stub \
    --dry-run \
    --cwd /tmp \
    --cwd-mode current \
    --key default-high-effort \
    --prompt smoke
)"
grep -Fq 'DRY_RUN claude_effort=high' <<<"$claude_default_send_out" \
  || fail "Claude send should default to high effort"

packet_contract_fixture="$(mktemp /tmp/ask-tmux-packet-contract.XXXXXX)"
write_packet "$packet_contract_fixture" claude review /tmp "Review fully." \
  /tmp/response.md '<<<DONE>>>' '<<<COMPLETE>>>'
grep -Fq 'bounded passes' "$packet_contract_fixture" \
  || fail "Claude packet should require bounded incremental response writes"
grep -Fq '<<<COMPLETE>>>' "$packet_contract_fixture" \
  || fail "Claude packet should carry a durable response completion marker"
if grep -Fq '### ``' "$packet_contract_fixture"; then
  fail "an empty materials array must not create a phantom missing material"
fi
rm -f "$packet_contract_fixture"
if (
  PATH="$gated_stub_dir:$PATH"
  ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek
  export PATH ASK_TMUX_CLAUDE_LAUNCHER
  provider_launch_command claude false claude-opus-5
) >/dev/null 2>&1; then
  fail "DeepSeek launch should reject a Claude model pin"
fi
if (
  PATH="$gated_stub_dir:$PATH"
  provider_launch_command claude false claude-opus-5 turbo
) >/dev/null 2>&1; then
  fail "Claude launch should reject an unsupported effort level"
fi
if (
  PATH="$gated_stub_dir:$PATH"
  ASK_TMUX_CLAUDE_LAUNCHER=claude
  export PATH ASK_TMUX_CLAUDE_LAUNCHER
  provider_launch_command claude false
) >/dev/null 2>&1; then
  fail "Claude launch should reject a launcher outside the provider allowlist"
fi

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
' "$test_home/.local/state/ask-tmux/review-budget.json" "$kind" "$decision" "$exit_code"
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
mkdir -p "$corrupt_state_home/.local/state/ask-tmux"
printf '{broken' > "$corrupt_state_home/.local/state/ask-tmux/review-budget.json"
if corrupt_state_out="$(env -i HOME="$corrupt_state_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check \
    --gate-reason external_review_required --cwd "$gated_tmp" 2>&1)"; then
  fail "malformed review budget state should deny"
else
  corrupt_state_rc=$?
fi
[[ "$corrupt_state_rc" == "78" ]] || fail "malformed review budget state should exit 78"
printf '%s\n' "$corrupt_state_out" | grep -q 'review budget state is unreadable or malformed' || fail "malformed state denial should be explicit"
[[ "$(cat "$corrupt_state_home/.local/state/ask-tmux/review-budget.json")" == '{broken' ]] || fail "malformed review budget state must not be overwritten"

corrupt_log_home="$gated_tmp/corrupt-log-home"
mkdir -p "$corrupt_log_home/.local/state/ask-tmux/consultants"
printf 'not-json\n' > "$corrupt_log_home/.local/state/ask-tmux/consultants/log.jsonl"
if corrupt_log_out="$(env -i HOME="$corrupt_log_home" PATH="$gated_tmp/empty-bin" \
  "$python_bin" "$ROOT/bin/ask-tmux-claude-gated" check \
    --gate-reason external_review_required --cwd "$gated_tmp" 2>&1)"; then
  fail "malformed consultant log should deny"
else
  corrupt_log_rc=$?
fi
[[ "$corrupt_log_rc" == "78" ]] || fail "malformed consultant log should exit 78"
printf '%s\n' "$corrupt_log_out" | grep -q 'consultant log contains malformed JSON' || fail "malformed consultant log denial should be explicit"
[[ "$(cat "$corrupt_log_home/.local/state/ask-tmux/consultants/log.jsonl")" == 'not-json' ]] || fail "malformed consultant log must not be overwritten"

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
grep -q '"kind": "send_dry_run"' "$concurrent_home/.local/state/ask-tmux/review-budget.json" || fail "completed reservation should remain in the ledger"

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
' "$grant_home/.local/state/ask-tmux/review-budget.json" pipeline:grant-regression grant-key "$pipeline_root_digest" || \
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
' "$grant_home/.local/state/ask-tmux/review-budget.json"
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
' "$root_isolation_home/.local/state/ask-tmux/review-budget.json" "$root_a_digest"
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
' "$same_root_home/.local/state/ask-tmux/review-budget.json")"
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
' "$same_root_home/.local/state/ask-tmux/review-budget.json" "$old_grant_id"
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
' "$same_root_home/.local/state/ask-tmux/review-budget.json")"
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
' "$same_root_home/.local/state/ask-tmux/review-budget.json" "$old_grant_id" "$fresh_grant_id" || \
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
