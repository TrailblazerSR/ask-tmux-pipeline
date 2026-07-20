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

Pipelines default to `cc-claude`; prefix an explicitly requested DeepSeek
pipeline with `ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek`. `ask-tmux-claude-dual`
is an explicit one-off review wrapper, not a substitute for this
single-consultant pipeline or its continuation grant.

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

## Clarification Relay

If the command exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user exactly the printed `question`, include `recommended_default` when present, and stop the current turn.

The tmux consultant response header is strict: each header field must be exactly one physical line, followed by one blank line before the body.

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

- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize the final current-CLI response.
- `PIPELINE_STATUS=waiting_for_user`: ask the printed question and wait.
- `PIPELINE_STATUS=blocked`: report the blocker and relevant artifact path.
- Exit code `30`: the underlying tmux consultant transport failed; inspect the printed output artifact or retry after checking `status`/`capture`.

Use explicit `--pipeline-id` and `--cwd` when more than one pipeline may exist.

## Safety

The underlying tmux consultant uses elevated local CLI permissions. Send only trusted materials. The pipeline prompt keeps Claude read-only except for required response files.
