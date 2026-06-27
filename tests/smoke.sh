#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d /tmp/ask-tmux-pipeline-smoke.XXXXXX)"

cleanup() {
  rm -rf "$TMPDIR"
  while IFS= read -r state_file; do
    rm -f "$state_file"
  done < <(
    find "$HOME/.omx/state/tmux-pipelines" -type f -name '*.json' -print 2>/dev/null |
      while IFS= read -r candidate; do
        if grep -q "$TMPDIR" "$candidate" 2>/dev/null; then
          printf '%s\n' "$candidate"
        fi
      done
  )
  find "$HOME/.omx/state/tmux-pipelines" -type d -empty -delete 2>/dev/null || true
  while IFS= read -r state_file; do
    rm -f "$state_file"
  done < <(
    find "$HOME/.omx/state/consultants" -type f -name '*.json' -print 2>/dev/null |
      while IFS= read -r candidate; do
        if grep -q "$TMPDIR" "$candidate" 2>/dev/null; then
          printf '%s\n' "$candidate"
        fi
      done
  )
  find "$HOME/.omx/state/consultants" -type d -empty -delete 2>/dev/null || true
  while IFS= read -r session; do
    tmux kill-session -t "$session" 2>/dev/null || true
  done < <(tmux list-sessions -F '#S' 2>/dev/null | grep '^ask-tmux-' || true)
}
trap cleanup EXIT

bash -n "$ROOT"/bin/ask-tmux-*

"$ROOT/bin/ask-tmux-claude" send \
  --stub \
  --key consultant-smoke-claude \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --materials "$ROOT/README.md" \
  --prompt "Smoke consultant Claude path." \
  --wait \
  --release now >/dev/null

stripped_path="/usr/bin:/bin:/usr/sbin:/sbin"
env -i HOME="$HOME" USER="${USER:-}" PATH="$stripped_path" SHELL="${SHELL:-/bin/sh}" \
  "$ROOT/bin/ask-tmux-codex" send \
    --stub \
    --key consultant-smoke-codex \
    --cwd-mode current \
    --cwd "$TMPDIR" \
    --materials "$ROOT/README.md" \
    --prompt "Smoke consultant Codex path." \
    --wait \
    --release now >/dev/null

"$ROOT/bin/ask-tmux-codex" send \
  --stub \
  --key consultant-smoke-release \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --materials "$ROOT/README.md" \
  --prompt "Smoke consultant release path." \
  --no-wait >/dev/null
"$ROOT/bin/ask-tmux-codex" release --key consultant-smoke-release --cwd-mode current --cwd "$TMPDIR" >/dev/null

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
