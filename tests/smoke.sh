#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d /tmp/ask-tmux-pipeline-smoke.XXXXXX)"

cleanup() {
  rm -rf "$TMPDIR"
  while IFS= read -r state_file; do
    rm -f "$state_file"
  done < <(find "$HOME/.omx/state/tmux-pipelines" -type f -name '*.json' -print 2>/dev/null | xargs -r grep -l "$TMPDIR" 2>/dev/null || true)
  find "$HOME/.omx/state/tmux-pipelines" -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

bash -n "$ROOT"/bin/ask-tmux-*

"$ROOT/bin/ask-tmux-pipeline" doctor >/dev/null

start_out="$("$ROOT/bin/ask-tmux-claude-pipeline" start \
  --stub \
  --stub-status needs-input \
  --stub-question "Smoke question?" \
  --stub-recommended "Use the smoke default." \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --prompt "Smoke prompt" 2>&1)" && start_rc=0 || start_rc=$?

printf '%s\n' "$start_out" | rg -q '^PIPELINE_STATUS=waiting_for_user$'
[[ "$start_rc" == "10" ]]

pipeline_id="$(printf '%s\n' "$start_out" | sed -n 's/^pipeline_id=//p' | tail -1)"
[[ -n "$pipeline_id" ]]

answer_out="$("$ROOT/bin/ask-tmux-claude-pipeline" answer \
  --stub \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --pipeline-id "$pipeline_id" \
  --answer "Use the smoke default." 2>&1)"

printf '%s\n' "$answer_out" | rg -q '^PIPELINE_STATUS=ready_for_synthesis$'
final_context="$(printf '%s\n' "$answer_out" | sed -n 's/^final_context=//p' | tail -1)"
[[ -f "$final_context" ]]
rg -q 'Smoke prompt' "$final_context"
rg -q 'Smoke question' "$final_context"

malformed_out="$("$ROOT/bin/ask-tmux-codex-pipeline" start \
  --stub \
  --stub-status malformed \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --prompt "Malformed smoke prompt" 2>&1)" && malformed_rc=0 || malformed_rc=$?

printf '%s\n' "$malformed_out" | rg -q '^PIPELINE_STATUS=blocked$'
[[ "$malformed_rc" == "20" ]]

printf 'smoke ok\n'
