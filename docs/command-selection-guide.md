# Tmux Pipeline Command Selection Guide

This guide answers which command family to use. For the canonical provider,
model, effort, and continuation contract, see
[Ask-Tmux Invocation Grammar](invocation-grammar.md).

## Primary Decision

Use low-level `ask-tmux-claude` / `ask-tmux-codex` when the user wants a consultant to review, comment, suggest, critique, or inspect specific materials.

Use `ask-tmux-claude-pipeline` / `ask-tmux-codex-pipeline` when the user wants the same current prompt routed through another CLI as part of the current answer workflow, including clarification relay and final synthesis.

Use `ask-tmux-claude-pure` / `ask-tmux-codex-pure` when the user wants the same prompt mirrored to tmux Claude/Codex with minimal owner-side synthesis.

## Commands By Situation

### 1. Simple Claude Review

Use when the user says: "ask Claude to review/comment/suggest", "get Claude's critique", "have Claude inspect this plan", or "Claude second opinion".

```bash
ask-tmux-claude-gated send \
  --gate-reason explicit_user_request \
  --key reviewer \
  --cwd /path/to/project \
  --materials /path/to/material.md \
  --prompt "Review, comment, and suggest. Focus on blockers, missed assumptions, verification gaps, and concrete next actions." \
  --wait
```

For an explicitly requested dual-provider review, use
`ask-tmux-claude-dual send` with the same arguments. It runs isolated gated
`cc-claude` and `cc-deepseek` lanes concurrently, labels both results, and
costs two provider requests. Do not use it for automatic pipeline traffic.
The aligned Mac and HPC `cc-claude` launchers pin `claude-opus-5`; `cc-deepseek`
retains its own DeepSeek main/subagent mapping. Keep model selection inside
each launcher rather than exporting a shared `ANTHROPIC_MODEL`. An explicit
Claude pin may use `--model claude-opus-5`; the command rejects that option
with `cc-deepseek`. Claude pipelines default to `high` effort; DeepSeek retains
its provider-owned `max` effort. Pipelines preserve their initial
launcher/model/effort tuple across continuations.

### 2. Simple Codex Review

Use when the user wants another Codex session as an external reviewer.

```bash
ask-tmux-codex send \
  --key reviewer \
  --cwd /path/to/project \
  --materials /path/to/material.md \
  --prompt "Review, comment, and suggest. Focus on blockers, missed assumptions, verification gaps, and concrete next actions." \
  --wait
```

### 3. Same Prompt Through Tmux Claude, Then Synthesize

Use when prompt X should be sent to tmux Claude while the current CLI remains responsible for final synthesis.

The dispatcher treats every Claude pipeline stage as automatic review traffic and routes it through `ask-tmux-claude-gated` with `--gate-reason external_review_required`. It fails closed when that local gate is unavailable; do not bypass it with the raw transport. The initial stage consumes one budget slot. Later answers and draft reviews are bounded, ordered continuations of the same project/key/pipeline and content-digest grant for up to 24 hours and eight continuation sends; a different pipeline still encounters the normal caps and cooldown.

```bash
ask-tmux-claude-pipeline start \
  --cwd /path/to/project \
  --prompt "PROMPT X FROM THE CURRENT CLI"
```

If output says `PIPELINE_STATUS=ready_for_synthesis`, read `final_context`.

### 4. Same Prompt Through Tmux Codex, Then Synthesize

Use when prompt X should be sent to tmux Codex while the current CLI remains responsible for final synthesis.

```bash
ask-tmux-codex-pipeline start \
  --cwd /path/to/project \
  --prompt "PROMPT X FROM THE CURRENT CLI"
```

If output says `PIPELINE_STATUS=ready_for_synthesis`, read `final_context`.

### 5. Pure/Mirror Mode

Use when the user asks for `ask-tmux-claude-pure`, `ask-tmux-codex-pure`, or wants the other CLI's answer with minimal current-CLI synthesis.

```bash
ask-tmux-claude-pure --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
ask-tmux-codex-pure --cwd /path/to/project --prompt "PROMPT X FROM THE CURRENT CLI"
```

### 6. Clarification Relay

If pipeline output exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`, ask the user the printed `question`.

After the user answers:

```bash
ask-tmux-claude-pipeline answer \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --answer "USER ANSWER"
```

Use `ask-tmux-codex-pipeline answer` for Codex pipelines.

### 7. Optional Review Of Current CLI Draft

Use when the user wants the tmux CLI to review the current CLI's draft before the final answer.

```bash
ask-tmux-claude-pipeline review \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --draft "CURRENT CLI DRAFT"
```

Use `ask-tmux-codex-pipeline review` for Codex pipelines.

### 8. Recovery And Status

Use explicit `--pipeline-id` when more than one pipeline may exist.

```bash
ask-tmux-claude-pipeline status --pipeline-id <id> --cwd /path/to/project
ask-tmux-claude-pipeline resume --pipeline-id <id> --cwd /path/to/project
ask-tmux-claude-pipeline final-context --pipeline-id <id> --cwd /path/to/project
```

## Short Rule

- Review existing material: `ask-tmux-claude-gated send` or `ask-tmux-codex send`.
- Route this same prompt into another CLI: `ask-tmux-*-pipeline start`.
- Mirror with minimal synthesis: `ask-tmux-*-pure`.
- Continue after consultant asks a question: `ask-tmux-*-pipeline answer`.
- Have the other CLI review the current CLI's draft: `ask-tmux-*-pipeline review`.
