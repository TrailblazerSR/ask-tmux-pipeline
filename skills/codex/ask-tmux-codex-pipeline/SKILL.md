---
name: ask-tmux-codex-pipeline
description: >-
  Pipeline the current owner prompt through a reusable tmux Codex session,
  relay Codex clarification questions back to the current CLI/user, optionally
  send the current CLI draft back to Codex for review, and synthesize Codex work
  into the final answer. Use for ask-tmux-codex-pipeline, ask-tmux-codex-pure,
  same prompt to tmux Codex, Codex pipeline, Codex pure mirror, tmux Codex
  clarification relay, or Codex review of the current CLI answer.
---

# Ask Tmux Codex Pipeline

Use the local `ask-tmux-codex-pipeline` found on `PATH` when the same owner prompt should run through a reusable tmux Codex session as part of the current answer workflow. Do not hard-code another machine's home directory.

Use the lower-level `ask-tmux-codex` skill for simple one-off consultant review. Use this pipeline skill when clarification relay, final synthesis, or optional draft review is needed.

## Modes

- `synthesize` is the default. Send the owner prompt to tmux Codex, continue local reasoning, then merge Codex's final work into the current answer.
- `mirror` is the pure mode. Use `ask-tmux-codex-pure` or `--mode mirror` when the desired behavior is mainly "same prompt to tmux Codex, return Codex's work."
- `review` starts with the prompt and expects a later `review` command with the current CLI draft.

## Start

For the current user prompt, pass the prompt text or a prompt file:

```bash
ask-tmux-codex-pipeline start \
  --cwd /path/to/project \
  --prompt "PROMPT X FROM THE CURRENT CLI"
```

For pure mirror mode:

```bash
ask-tmux-codex-pure --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
```

Add `--materials path` for relevant files. Use `--stub` for no-cost validation.

Before a live send, run `ask-tmux-codex preflight --json`. It checks tmux
control access from the current caller without creating a session or calling a
provider.

## Clarification Relay

The command prints stable markers. If it exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user exactly the printed `question`, include `recommended_default` when present, and stop the current turn.

The preferred consultant response starts with a one-line
`ask_tmux_pipeline.result.v2` JSON envelope followed by one blank line. Its
`stage` must match the requested stage. A `NEEDS_INPUT` result requires
non-empty string fields `question_id` and `question`; `recommended_default`
is an optional string. The legacy positional header remains accepted during
migration.

After the user answers, resume the same pipeline:

```bash
ask-tmux-codex-pipeline answer \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --answer "USER ANSWER"
```

Do not start a second pipeline for the answer. The runner includes the original prompt, previous Codex response, and user answer as artifacts so continuation can recover even if live tmux context was lost.

## Optional Review

When the user asks Codex to review the current CLI answer, draft the current answer first, then run:

```bash
ask-tmux-codex-pipeline review \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --draft "CURRENT CLI DRAFT"
```

Use the resulting `final_context` file to revise the final answer. The final context includes the original prompt, Codex work, user answers, the draft, and Codex review.

## Output Contract

Important markers:

- `PIPELINE_STATUS=waiting_for_consultant`: the tmux consultant is active; use the printed `monitor=...` command rather than replacing the pipeline because an outer task runner has not streamed further output.
- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize the final current-CLI response.
- `PIPELINE_STATUS=waiting_for_user`: ask the printed question and wait.
- `PIPELINE_STATUS=blocked`: report the blocker and relevant artifact path.
- Exit code `30`: inspect `outcome_kind` and any printed `outcome_artifact`
  before retrying; it can identify a tmux-control, provider-readiness,
  provider-exit, missing-response, completion-timeout, or gateway failure.
- `tmux_prompt_delivery_unconfirmed` with `retryable=false`: Enter reached the
  provider but confirmation was lost. Inspect the retained session and state;
  do not automatically resend.

Use `status`, `resume`, and `final-context` with `--pipeline-id` when recovering a pipeline. Treat `~/.local/state/ask-tmux/tmux-pipelines/current.json` as advisory only; if more than one pipeline may exist, use explicit `--pipeline-id` and `--cwd`.

## Safety

The underlying tmux consultant uses the existing ask-tmux runner and elevated local CLI permissions. Send only trusted materials. The pipeline prompt keeps Codex read-only except for required response files.
