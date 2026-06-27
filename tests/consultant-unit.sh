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

printf 'consultant unit ok\n'
