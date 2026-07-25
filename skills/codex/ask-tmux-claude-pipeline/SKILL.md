---
name: ask-tmux-claude-pipeline
description: >-
  Pipeline the current owner prompt through a reusable tmux Claude session,
  relay Claude clarification questions back to the current CLI/user, optionally
  send the current CLI draft back to Claude for review, and synthesize Claude
  work into the final answer. Use for ask-tmux-claude-pipeline,
  ask-tmux-claude-pure, same prompt to tmux Claude, Claude pipeline, Claude pure
  mirror, tmux Claude clarification relay, or Claude review of the current CLI
  answer.
---

# Ask Tmux Claude Pipeline

Use the local `ask-tmux-claude-pipeline` found on `PATH` when the same owner prompt should run through a reusable tmux Claude session as part of the current answer workflow. Do not hard-code another machine's home directory.

Use the lower-level `ask-tmux-claude` skill for simple one-off consultant review. Use this pipeline skill when clarification relay, final synthesis, or optional draft review is needed.

Every Claude pipeline stage is automatic review traffic. The dispatcher must invoke local `ask-tmux-claude-gated send --gate-reason external_review_required` and fail closed if that gate is unavailable. Never replace this route with the raw `ask-tmux-claude` transport.

One successful initial stage consumes one automatic-review budget slot. Follow-up answers and draft reviews are allowed only as ordered continuations of the same project, consultant key, pipeline fingerprint, and content-digest grant. The grant has a fixed 24-hour lifetime and an eight-continuation cap; unrelated pipelines remain subject to the normal daily caps and 20-minute project cooldown.

## Provider Selection and Dual Boundary

Pipelines default to `cc-claude`, which owns the Claude-provider model mapping
(`claude-opus-5` on the aligned Mac and HPC installs); prefix an explicitly requested
DeepSeek pipeline with `ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek`, which owns its
separate DeepSeek main/subagent mapping. Never export a shared
`ANTHROPIC_MODEL` in the pipeline dispatcher. `--model claude-opus-5` is an
optional Claude-only pin. Claude pipelines use `high` effort by default and
accept a Claude-only `--effort` override. Both options are rejected with
`cc-deepseek`, which retains its provider-owned `max` effort. The initial
launcher/model/effort tuple is retained for every continuation. Unlock encrypted credentials once
interactively before a detached launch. `ask-tmux-claude-dual` is only for
explicitly requested, one-off dual-provider review packets. Do not substitute
it into the single-consultant pipeline continuation flow; preserve its two
labelled outputs and synthesize them locally instead.

## Modes

- `synthesize` is the default. Send the owner prompt to tmux Claude, continue local reasoning, then merge Claude's final work into the current answer.
- `mirror` is the pure mode. Use `ask-tmux-claude-pure` or `--mode mirror` when the desired behavior is mainly "same prompt to tmux Claude, return Claude's work."
- `review` starts with the prompt and expects a later `review` command with the current CLI draft.

## Start

For the current user prompt, pass the prompt text or a prompt file:

```bash
ask-tmux-claude-pipeline start \
  --cwd /path/to/project \
  --prompt "PROMPT X FROM THE CURRENT CLI"
```

For pure mirror mode:

```bash
ask-tmux-claude-pure --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
```

Add `--materials path` for relevant files. Use `--stub` for no-cost validation.

## Clarification Relay

The command prints stable markers. If it exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user exactly the printed `question`, include `recommended_default` when present, and stop the current turn.

The tmux consultant response header is strict: each header field must be exactly one physical line, followed by one blank line before the body.

After the user answers, resume the same pipeline:

```bash
ask-tmux-claude-pipeline answer \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --answer "USER ANSWER"
```

Do not start a second pipeline for the answer. The runner includes the original prompt, previous Claude response, and user answer as artifacts so continuation can recover even if live tmux context was lost.

## Optional Review

When the user asks Claude to review the current CLI answer, draft the current answer first, then run:

```bash
ask-tmux-claude-pipeline review \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --draft "CURRENT CLI DRAFT"
```

Use the resulting `final_context` file to revise the final answer. The final context includes the original prompt, Claude work, user answers, the draft, and Claude review.

## Output Contract

Important markers:

- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize the final current-CLI response.
- `PIPELINE_STATUS=waiting_for_user`: ask the printed question and wait.
- `PIPELINE_STATUS=blocked`: report the blocker and relevant artifact path.
- Exit code `30`: the underlying tmux consultant transport failed; inspect the printed output artifact or retry after checking `status`/`capture`.

The pipeline classifies Claude `API Error: 524` as
`provider_gateway_timeout_524`. Do not automatically lower effort, switch
providers, or retry the unchanged workload. Keep the default `high` unless the
user explicitly chooses a smaller task or a lower one-off effort.

Use `status`, `resume`, and `final-context` with `--pipeline-id` when recovering a pipeline. Treat `~/.omx/state/tmux-pipelines/current.json` as advisory only; if more than one pipeline may exist, use explicit `--pipeline-id` and `--cwd`.

## Safety

The underlying tmux consultant uses the existing ask-tmux runner and elevated local CLI permissions. Send only trusted materials. The pipeline prompt keeps Claude read-only except for required response files.
