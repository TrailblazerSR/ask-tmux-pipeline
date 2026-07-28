---
name: ask-tmux-claude-pipeline
description: Pipeline the current owner prompt through a reusable tmux Claude session, relay Claude clarification questions back to the current CLI/user, optionally send the current CLI draft back to Claude for review, and synthesize Claude work into the final answer. Use when the user asks for ask-tmux-claude-pipeline, ask-tmux-claude-pure, same prompt to tmux Claude, Claude pipeline, Claude pure mirror, tmux Claude clarification relay, or Claude review of the current CLI answer.
allowed-tools: Bash Read Grep Glob
---

# Ask Tmux Claude Pipeline

Use the local `ask-tmux-claude-pipeline` found on `PATH` when the same owner prompt should run through a reusable tmux Claude session as part of the current answer workflow. Do not hard-code another machine's home directory.

Use lower-level `ask-tmux-claude` for simple one-off consultant review. Use this pipeline skill when clarification relay, final synthesis, or optional draft review is needed.

Every Claude pipeline stage is automatic review traffic. The dispatcher must invoke local `ask-tmux-claude-gated send --gate-reason external_review_required` and fail closed if that gate is unavailable. Never replace this route with the raw `ask-tmux-claude` transport.

One successful initial stage consumes one automatic-review budget slot. Follow-up answers and draft reviews are allowed only as ordered continuations of the same project, consultant key, pipeline fingerprint, and content-digest grant. The grant has a fixed 24-hour lifetime and an eight-continuation cap; unrelated pipelines remain subject to the normal daily caps and 20-minute project cooldown.

Pipelines default to `cc-claude`, which owns the Claude-provider model mapping
(`claude-opus-5` on the aligned Mac and HPC installs); prefix an explicitly requested
DeepSeek pipeline with `ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek`, which owns its
separate DeepSeek main/subagent mapping. Never export a shared
`ANTHROPIC_MODEL` in the pipeline dispatcher. `--model claude-opus-5` is an
optional Claude-only pin. Claude pipelines default to `high` effort and accept
a Claude-only `--effort` override. Both options are rejected with
`cc-deepseek`, which retains its provider-owned `max` effort. The pipeline
persists the initial launcher, model, and effort for every continuation.

Claude `API Error: 524` is recorded as `provider_gateway_timeout_524`.
The runner preserves partial work and resumes the same session and complete
scope for bounded attempts. It never lowers effort or switches providers
automatically. Exhausted recovery remains `retryable=true`.
`ask-tmux-claude-dual` is an
explicit one-off review wrapper, not a substitute for this single-consultant
pipeline or its continuation grant.

## Modes

- `synthesize` is the default. Send the owner prompt to tmux Claude, continue local reasoning, then merge Claude's final work into the current answer.
- `mirror` is the pure mode. Use `ask-tmux-claude-pure` or `--mode mirror` when the desired behavior is mainly "same prompt to tmux Claude, return Claude's work."
- `review` starts with the prompt and expects a later `review` command with the current CLI draft.

## Start

```bash
ask-tmux-claude-pipeline start --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
ask-tmux-claude-pure --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
```

Add `--materials path` for relevant files. Use `--stub` for no-cost validation.

Before a live send, run `ask-tmux-claude preflight --json`. It checks tmux
control access from the current caller without creating a session or calling a
provider.

## Clarification Relay

If the command exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user exactly the printed `question`, include `recommended_default` when present, and stop the current turn.

The preferred consultant response starts with a one-line
`ask_tmux_pipeline.result.v2` JSON envelope followed by one blank line. Its
`stage` must match the requested stage. A `NEEDS_INPUT` result requires
non-empty string fields `question_id` and `question`; `recommended_default`
is an optional string. The legacy positional header remains accepted during
migration.

After the user answers:

```bash
ask-tmux-claude-pipeline answer --pipeline-id <id> --cwd /path/to/project --answer "USER ANSWER"
```

Do not start a second pipeline for the answer.

## Optional Review

```bash
ask-tmux-claude-pipeline review --pipeline-id <id> --cwd /path/to/project --draft "CURRENT CLI DRAFT"
```

Use the resulting `final_context` file to revise the final answer.

## Output Contract

- `PIPELINE_STATUS=waiting_for_consultant`: the tmux consultant is active; use the printed `monitor=...` command rather than replacing the pipeline because an outer task runner has not streamed further output.
- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize the final current-CLI response.
- `PIPELINE_STATUS=waiting_for_user`: ask the printed question and wait.
- `PIPELINE_STATUS=blocked`: report the blocker and relevant artifact path.
- `outcome_kind=policy_deferred` with exit code `76`: the gate denied
  admission and no provider was launched; read `policy_reason`. An initial
  denial has `PIPELINE_STATUS=policy_deferred`; a denied continuation retains
  its resumable pipeline status.
- Exit code `30`: inspect `outcome_kind` and any printed `outcome_artifact`
  before retrying; it can identify a tmux-control, provider-readiness,
  provider-exit, missing-response, completion-timeout, or gateway failure.
- `tmux_prompt_delivery_unconfirmed` with `retryable=false`: Enter reached the
  provider but confirmation was lost. Inspect the retained session and state;
  do not automatically resend.
- `provider_scope_incomplete`: the strict response audit exhausted its bounded
  completion revisions; inspect the retained response and audit artifact.

Use explicit `--pipeline-id` and `--cwd` when more than one pipeline may exist.

## Safety

The underlying tmux consultant uses elevated local CLI permissions. Send only trusted materials. The pipeline prompt keeps Claude read-only except for required response files.
