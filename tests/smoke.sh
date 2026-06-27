#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d /tmp/ask-tmux-pipeline-smoke.XXXXXX)"

if ! command -v rg >/dev/null 2>&1; then
  rg() {
    local fixed=false quiet=false line_numbers=false recursive=false pattern target
    local flags=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -Fq|-qF) fixed=true; quiet=true; shift ;;
        -F) fixed=true; shift ;;
        -q) quiet=true; shift ;;
        -n) line_numbers=true; shift ;;
        --) shift; break ;;
        -*) printf 'rg fallback unsupported option: %s\n' "$1" >&2; return 2 ;;
        *) break ;;
      esac
    done
    [[ $# -ge 1 ]] || { printf 'rg fallback requires a pattern\n' >&2; return 2; }
    pattern="$1"
    shift
    for target in "$@"; do
      [[ -d "$target" ]] && recursive=true
    done
    if [[ "$fixed" == "true" ]]; then flags+=("-F"); else flags+=("-E"); fi
    [[ "$quiet" == "true" ]] && flags+=("-q")
    [[ "$line_numbers" == "true" ]] && flags+=("-n")
    [[ "$recursive" == "true" ]] && flags+=("-R")
    grep "${flags[@]}" -- "$pattern" "$@"
  }
fi

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
bash "$ROOT/tests/consultant-unit.sh"

compat_pattern='(^|[[:space:]])(mapfile|readarray)([[:space:]]|$)|local -n|\$\{[A-Za-z_][A-Za-z0-9_]*,,|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^'
if compat_hits="$(rg -n "$compat_pattern" "$ROOT/bin" 2>&1)"; then
  printf '%s\n' "$compat_hits" >&2
  exit 1
else
  compat_status=$?
  if [[ "$compat_status" -ne 1 ]]; then
    printf '%s\n' "$compat_hits" >&2
    exit "$compat_status"
  fi
fi

claude_smoke_out="$("$ROOT/bin/ask-tmux-claude" send \
  --stub \
  --key consultant-smoke-claude \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --materials "$ROOT/README.md" \
  --prompt "Smoke consultant Claude path." \
  --wait \
  --release now)"
printf '%s\n' "$claude_smoke_out" | rg -q 'Stub consultant response for:'
printf '%s\n' "$claude_smoke_out" | rg -q 'Smoke consultant Claude path'

stripped_path="/usr/bin:/bin:/usr/sbin:/sbin"
claude_stripped_out="$(env -i HOME="$HOME" USER="${USER:-}" PATH="$stripped_path" SHELL="${SHELL:-/bin/sh}" \
  "$ROOT/bin/ask-tmux-claude" send \
    --stub \
    --key consultant-smoke-claude-stripped \
    --cwd-mode current \
    --cwd "$TMPDIR" \
    --materials "$ROOT/README.md" \
    --prompt "Smoke consultant Claude stripped path." \
    --wait \
    --release now)"
printf '%s\n' "$claude_stripped_out" | rg -q 'Stub consultant response for:'
printf '%s\n' "$claude_stripped_out" | rg -q 'Smoke consultant Claude stripped path'

codex_stripped_out="$(env -i HOME="$HOME" USER="${USER:-}" PATH="$stripped_path" SHELL="${SHELL:-/bin/sh}" \
  "$ROOT/bin/ask-tmux-codex" send \
    --stub \
    --key consultant-smoke-codex \
    --cwd-mode current \
    --cwd "$TMPDIR" \
    --materials "$ROOT/README.md" \
    --prompt "Smoke consultant Codex path." \
    --wait \
    --release now)"
printf '%s\n' "$codex_stripped_out" | rg -q 'Stub consultant response for:'
printf '%s\n' "$codex_stripped_out" | rg -q 'Smoke consultant Codex path'

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
