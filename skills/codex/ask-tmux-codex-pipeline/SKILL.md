---
name: ask-tmux-codex-pipeline
description: Pipeline the current owner prompt through a reusable tmux Codex session, relay Codex clarification questions back to the current CLI/user, optionally send the current CLI draft back to Codex for review, and synthesize Codex work into the final answer. Use when the user asks for ask-tmux-codex-pipeline, ask-tmux-codex-pure, same prompt to tmux Codex, Codex pipeline, Codex pure mirror, tmux Codex clarification relay, or Codex review of the current CLI answer.
---

# Ask Tmux Codex Pipeline

Use `/home/h3031/bin/ask-tmux-codex-pipeline` when the same owner prompt should run through a reusable tmux Codex session as part of the current answer workflow.

Use the lower-level `ask-tmux-codex` skill for simple one-off consultant review. Use this pipeline skill when clarification relay, final synthesis, or optional draft review is needed.

## Modes

- `synthesize` is the default. Send the owner prompt to tmux Codex, continue local reasoning, then merge Codex's final work into the current answer.
- `mirror` is the pure mode. Use `/home/h3031/bin/ask-tmux-codex-pure` or `--mode mirror` when the desired behavior is mainly "same prompt to tmux Codex, return Codex's work."
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

## Clarification Relay

The command prints stable markers. If it exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user exactly the printed `question`, include `recommended_default` when present, and stop the current turn.

The tmux consultant response header is strict: each header field must be exactly one physical line, followed by one blank line before the body.

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

- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize the final current-CLI response.
- `PIPELINE_STATUS=waiting_for_user`: ask the printed question and wait.
- `PIPELINE_STATUS=blocked`: report the blocker and relevant artifact path.
- Exit code `30`: the underlying tmux consultant transport failed; inspect the printed output artifact or retry after checking `status`/`capture`.

Use `status`, `resume`, and `final-context` with `--pipeline-id` when recovering a pipeline. Treat `~/.omx/state/tmux-pipelines/current.json` as advisory only; if more than one pipeline may exist, use explicit `--pipeline-id` and `--cwd`.

## Safety

The underlying tmux consultant uses the existing ask-tmux runner and elevated local CLI permissions. Send only trusted materials. The pipeline prompt keeps Codex read-only except for required response files.
