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

gateway_timeout_kind="$(
  bash -c 'source "$1"; consultant_failure_kind claude 1 "$2"' _ \
    "$ROOT/bin/ask-tmux-pipeline" \
    'ERROR: Claude provider gateway returned API Error 524 before completion.'
)"
[[ "$gateway_timeout_kind" == "provider_gateway_timeout_524" ]]

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

for script in "$ROOT"/bin/ask-tmux-*; do
  if head -n 1 "$script" | grep -q 'bash'; then
    bash -n "$script"
  fi
done
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

gate_stub_dir="$TMPDIR/pipeline-gate-stubs"
raw_stub="$TMPDIR/pipeline-raw-transport"
raw_trap="$gate_stub_dir/ask-tmux-claude"
raw_log="$TMPDIR/pipeline-raw-calls.log"
raw_trap_log="$TMPDIR/pipeline-raw-trap.log"
gate_response_dir="$TMPDIR/pipeline-gate-responses"
pipeline_state_root="$TMPDIR/pipeline-state"
gate_home="$TMPDIR/pipeline-gate-home"
mkdir -p "$gate_stub_dir" "$gate_response_dir" "$pipeline_state_root" "$gate_home"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "${1:-}" == "send" ]] || exit 96' \
  'printf "raw:%s|launcher=%s|audit=%s\n" "$*" "${ASK_TMUX_CLAUDE_LAUNCHER:-}" "${ASK_TMUX_LOG_PATH:-$HOME/.omx/consultants/log.jsonl}" >> "$PIPELINE_RAW_LOG"' \
  'cwd=""; shift' \
  'while [[ $# -gt 0 ]]; do case "$1" in --cwd) cwd="$2"; shift 2 ;; --cwd=*) cwd="${1#*=}"; shift ;; *) shift ;; esac; done' \
  '[[ -n "$cwd" ]] || exit 96' \
  'audit_log="${ASK_TMUX_LOG_PATH:-$HOME/.omx/consultants/log.jsonl}"' \
  'mkdir -p "$(dirname "$audit_log")"' \
  'printf '\''{"ts":"%s","event":"send","provider":"claude","session":"stub","status":"sent","detail":"%s/.omx/consultants/packets/stub.md"}\n'\'' "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" "$cwd" >> "$audit_log"' \
  'response_file="$(mktemp "$PIPELINE_GATE_RESPONSE_DIR/response.XXXXXX")"' \
  'state_file="$response_file.state.json"' \
  'printf "{}\n" > "$state_file"' \
  'printf "response_file=%s\nstate=%s\n" "$response_file" "$state_file"' \
  > "$raw_stub"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "raw-trap:%s\n" "$*" >> "$PIPELINE_RAW_TRAP_LOG"' \
  'exit 97' \
  > "$raw_trap"
chmod +x "$raw_stub" "$raw_trap"

pipeline_gate_env=(
  env
  "HOME=$gate_home"
  "PATH=$gate_stub_dir:$PATH"
  "ASK_TMUX_CLAUDE_GATED_BIN=$ROOT/bin/ask-tmux-claude-gated"
  "ASK_TMUX_CLAUDE_BIN=$raw_stub"
  "ASK_TMUX_PIPELINE_STATE_ROOT=$pipeline_state_root"
  "PIPELINE_RAW_LOG=$raw_log"
  "PIPELINE_RAW_TRAP_LOG=$raw_trap_log"
  "PIPELINE_GATE_RESPONSE_DIR=$gate_response_dir"
)

"${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-pipeline" doctor >/dev/null
if invalid_gate_out="$(ASK_TMUX_CLAUDE_GATED_BIN="$TMPDIR/missing-gated-wrapper" \
  ASK_TMUX_PIPELINE_STATE_ROOT="$pipeline_state_root" \
  "$ROOT/bin/ask-tmux-pipeline" doctor 2>&1)"; then
  printf 'pipeline doctor should fail closed for an invalid configured Claude gate\n' >&2
  exit 1
fi
printf '%s\n' "$invalid_gate_out" | rg -q 'configured ask-tmux-claude-gated is not installed or executable'

if deepseek_model_out="$(ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
  "${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --model claude-opus-5 \
    --dry-run \
    --cwd-mode current \
    --cwd "$TMPDIR" \
    --prompt "DeepSeek must reject Claude model pins" 2>&1)"; then
  printf 'DeepSeek pipeline should reject an explicit Claude model pin\n' >&2
  exit 1
else
  deepseek_model_rc=$?
fi
[[ "$deepseek_model_rc" == "2" ]]
printf '%s\n' "$deepseek_model_out" | rg -q -- '--model and --effort are not supported with cc-deepseek'

if deepseek_effort_out="$(ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
  "${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" start \
    --effort high \
    --dry-run \
    --cwd-mode current \
    --cwd "$TMPDIR" \
    --prompt "DeepSeek must retain its provider-owned effort" 2>&1)"; then
  printf 'DeepSeek pipeline should reject an explicit Claude effort\n' >&2
  exit 1
else
  deepseek_effort_rc=$?
fi
[[ "$deepseek_effort_rc" == "2" ]]
printf '%s\n' "$deepseek_effort_out" | rg -q -- '--model and --effort are not supported with cc-deepseek'

start_out="$(ASK_TMUX_CLAUDE_LAUNCHER=cc-claude \
  "${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" start \
  --model claude-opus-5 \
  --stub \
  --stub-status needs-input \
  --stub-question "Smoke question?" \
  --stub-recommended "Use the smoke default." \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --prompt "Smoke prompt" 2>&1)" && start_rc=0 || start_rc=$?

if [[ "$start_rc" != "10" ]]; then
  printf '%s\n' "$start_out" >&2
  find "$TMPDIR/.omx/tmux-pipelines" -type f -name 'consultant-initial-*.out' -exec sed -n '1,200p' {} \; >&2
fi
printf '%s\n' "$start_out" | rg -q '^PIPELINE_STATUS=waiting_for_user$'
[[ "$start_rc" == "10" ]]

pipeline_id="$(printf '%s\n' "$start_out" | sed -n 's/^pipeline_id=//p' | tail -1)"
[[ -n "$pipeline_id" ]]

answer_out="$(ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
  "${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" answer \
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

review_out="$(ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
  "${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" review \
  --stub \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --pipeline-id "$pipeline_id" \
  --draft "Smoke owner draft." 2>&1)" && review_rc=0 || review_rc=$?
if [[ "$review_rc" != "0" ]]; then
  printf '%s\n' "$review_out" >&2
fi
[[ "$review_rc" == "0" ]]
printf '%s\n' "$review_out" | rg -q '^PIPELINE_STATUS=ready_for_synthesis$'
review_context="$(printf '%s\n' "$review_out" | sed -n 's/^final_context=//p' | tail -1)"
[[ -f "$review_context" ]]
rg -q 'Smoke owner draft' "$review_context"
[[ "$(grep -c '^raw:send ' "$raw_log")" == "3" ]]
[[ "$(grep -c -- '--model claude-opus-5' "$raw_log")" == "3" ]]
[[ "$(grep -c -- '--effort high' "$raw_log")" == "3" ]]
[[ "$(grep -c '|launcher=cc-claude|' "$raw_log")" == "3" ]]
[[ ! -e "$raw_trap_log" ]]
main_audit="$gate_home/.omx/consultants/log.jsonl"
continuation_audit="$gate_home/.omx/consultants/continuations.jsonl"
[[ "$(grep -c '"event":"send"' "$main_audit")" == "1" ]]
[[ "$(grep -c '"event":"send"' "$continuation_audit")" == "2" ]]
python3 - "$gate_home/.omx/state/review-budget.json" "$pipeline_id" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
fingerprint = f"pipeline:{sys.argv[2]}"
allowed = [
    event for event in state["events"]
    if event.get("decision") == "allow" and event.get("fingerprint") == fingerprint
]
roots = [event for event in allowed if event.get("kind") == "send" and event.get("exit_code") == 0]
continuations = [
    event for event in allowed
    if event.get("kind") == "continuation_send" and event.get("exit_code") == 0
]
assert len(roots) == 1, roots
assert roots[0].get("budget_counted") is True
assert [event.get("continuation") for event in continuations] == ["answer:1", "review:1"]
assert all(event.get("budget_counted") is False for event in continuations)
PY

unrelated_out="$("${pipeline_gate_env[@]}" "$ROOT/bin/ask-tmux-claude-pipeline" start \
  --stub \
  --pipeline-id unrelated-cooldown \
  --release now \
  --cwd-mode current \
  --cwd "$TMPDIR" \
  --prompt "Unrelated pipeline should be denied by cooldown" 2>&1)" && unrelated_rc=0 || unrelated_rc=$?
[[ "$unrelated_rc" == "76" ]]
printf '%s\n' "$unrelated_out" | rg -q '^PIPELINE_STATUS=policy_deferred$'
printf '%s\n' "$unrelated_out" | rg -q '^outcome_kind=policy_deferred$'
printf '%s\n' "$unrelated_out" | rg -q '^policy_reason=project_cooldown$'
[[ "$(grep -c '^raw:send ' "$raw_log")" == "3" ]]
python3 - "$gate_home/.omx/state/review-budget.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
denials = [
    event for event in state["events"]
    if event.get("decision") == "deny"
    and event.get("fingerprint") == "pipeline:unrelated-cooldown"
]
assert len(denials) == 1, denials
assert "project cooldown active" in denials[0].get("message", ""), denials[0]
PY

missing_digest="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if missing_prior_out="$(HOME="$gate_home" ASK_TMUX_CLAUDE_BIN="$raw_stub" \
  PIPELINE_RAW_LOG="$raw_log" PIPELINE_GATE_RESPONSE_DIR="$gate_response_dir" \
  "$ROOT/bin/ask-tmux-claude-gated" send \
    --gate-reason external_review_required \
    --gate-fingerprint pipeline:missing-prior \
    --gate-continuation answer:1 \
    --gate-root-digest "$missing_digest" \
    --gate-content-digest "$missing_digest" \
    --key pipeline-missing-prior \
    --cwd "$TMPDIR" --dry-run 2>&1)"; then
  printf 'missing-prior continuation should fail closed\n' >&2
  exit 1
else
  missing_prior_rc=$?
fi
[[ "$missing_prior_rc" == "76" ]]
printf '%s\n' "$missing_prior_out" | rg -q 'no successful same-project start'

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
