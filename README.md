# ask-tmux-pipeline

Stateful tmux-backed Claude/Codex consultant and prompt-pipeline tools for Codex CLI and Claude CLI workflows.

This repo packages two layers:

- Low-level consultant sessions: `ask-tmux-claude`, `ask-tmux-codex`
- Same-prompt pipeline sessions: `ask-tmux-claude-pipeline`, `ask-tmux-codex-pipeline`, plus `*-pure` mirror aliases

The low-level layer is for review/comment/suggest workflows over existing files. The pipeline layer sends the current prompt to a tmux Claude/Codex session, relays clarification questions back to the owner CLI, optionally asks the tmux CLI to review an owner draft, and emits a final context artifact for synthesis.

## Repo Name

Recommended GitHub name: `ask-tmux-pipeline`.

Why: it matches the command family, is provider-neutral, and is short enough to remember.

## Requirements

- Bash
- tmux
- ripgrep (`rg`)
- Python 3
- Claude CLI and/or Codex CLI for live usage

The tools launch Claude/Codex with elevated local permissions, matching the local `ask-tmux` workflow they came from. Only send trusted materials.

## Install

```bash
./install.sh
```

By default this installs:

- scripts to `$HOME/bin`
- Codex skills to `$HOME/.codex/skills`
- Claude skills to `$HOME/.claude/skills`

Override paths if needed:

```bash
BIN_DIR=/usr/local/bin CODEX_SKILLS_DIR=/path/to/codex/skills CLAUDE_SKILLS_DIR=/path/to/claude/skills ./install.sh
```

## Quick Guide

Review existing material with Claude:

```bash
ask-tmux-claude send \
  --key reviewer \
  --cwd /path/to/project \
  --materials /path/to/material.md \
  --prompt "Review, comment, and suggest." \
  --wait
```

Send the same prompt to tmux Claude and synthesize the result in the owner CLI:

```bash
ask-tmux-claude-pipeline start \
  --cwd /path/to/project \
  --prompt "PROMPT X"
```

Pure/mirror mode:

```bash
ask-tmux-claude-pure --cwd /path/to/project --prompt "PROMPT X"
ask-tmux-codex-pure --cwd /path/to/project --prompt "PROMPT X"
```

Continue after a pipeline asks a user question:

```bash
ask-tmux-claude-pipeline answer \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --answer "USER ANSWER"
```

Ask tmux Claude to review the owner CLI draft:

```bash
ask-tmux-claude-pipeline review \
  --pipeline-id <id> \
  --cwd /path/to/project \
  --draft "CURRENT CLI DRAFT"
```

For more examples, see [docs/command-selection-guide.md](docs/command-selection-guide.md).

## Flowcharts

### Overall Command Choice

```mermaid
flowchart TD
  A{What situation are you in?}
  A -->|Review existing files, plans, diffs, or summaries| B[ask-tmux-claude send<br/>ask-tmux-codex send]
  A -->|Send the same prompt to another CLI and synthesize locally| C[ask-tmux-claude-pipeline start<br/>ask-tmux-codex-pipeline start]
  A -->|Mostly use the other CLI's answer| D[ask-tmux-claude-pure<br/>ask-tmux-codex-pure]
  A -->|The tmux CLI asked a user question| E[ask-tmux-*-pipeline answer]
  A -->|Ask tmux CLI to review your draft| F[ask-tmux-*-pipeline review]
  A -->|Inspect or recover a previous pipeline| G[status<br/>resume<br/>final-context]
```

### Review Existing Material

Use this when the input is already in files or artifacts and you want review/comment/suggest.

```mermaid
flowchart TD
  A[Existing material] --> B[Choose reviewer<br/>Claude or Codex]
  B --> C[ask-tmux-claude send<br/>or ask-tmux-codex send]
  C --> D[Reusable tmux consultant reads packet]
  D --> E[Response file is written]
  E --> F[Owner CLI applies or summarizes comments]
```

### Same Prompt With Owner Synthesis

Use this when the current CLI should remain responsible for the final answer.

```mermaid
flowchart TD
  A[Prompt X in owner CLI] --> B[ask-tmux-*-pipeline start]
  B --> C[Tmux Claude or Codex works on same prompt]
  B --> D[Owner CLI continues reasoning]
  C --> E{Pipeline status}
  E -->|ready_for_synthesis| F[Read final_context]
  E -->|waiting_for_user| G[Ask user the printed question]
  E -->|blocked| H[Report blocker and artifact path]
  G --> I[ask-tmux-*-pipeline answer]
  I --> E
  D --> F
  F --> J[Owner CLI writes final synthesized answer]
```

### Pure / Mirror Mode

Use this when you mainly want the other CLI's answer.

```mermaid
flowchart TD
  A[Prompt X] --> B[ask-tmux-claude-pure<br/>or ask-tmux-codex-pure]
  B --> C[Tmux CLI answers]
  C --> D{Pipeline status}
  D -->|ready_for_synthesis| E[Owner CLI relays or lightly summarizes final_context]
  D -->|waiting_for_user| F[Ask user question, then run answer]
  D -->|blocked| G[Report blocker]
```

### Clarification Relay

Use this after a pipeline exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`.

```mermaid
flowchart TD
  A[Pipeline prints question and recommended_default] --> B[Owner CLI asks user exactly that question]
  B --> C[User answers]
  C --> D[ask-tmux-*-pipeline answer<br/>--pipeline-id id<br/>--answer user-answer]
  D --> E{New pipeline status}
  E -->|ready_for_synthesis| F[Read final_context]
  E -->|waiting_for_user| B
  E -->|blocked| G[Report blocker and artifacts]
```

### Draft Review Before Final Answer

Use this when you have a current CLI draft and want tmux Claude/Codex to critique it before finalizing.

```mermaid
flowchart TD
  A[Pipeline has ready_for_synthesis context] --> B[Owner CLI drafts answer]
  B --> C[ask-tmux-*-pipeline review<br/>--pipeline-id id<br/>--draft draft-text]
  C --> D[Tmux CLI reviews original prompt, tmux work, and draft]
  D --> E[Updated final_context includes review]
  E --> F[Owner CLI revises and sends final answer]
```

### Recovery And Inspection

Use this when you need to inspect a previous pipeline, recover after an interruption, or fetch the final context again.

```mermaid
flowchart TD
  A[Have pipeline-id?] -->|Yes| B[Run status with --pipeline-id and --cwd]
  A -->|No| C[Find pipeline-id from prior output or state]
  C --> B
  B --> D{Status}
  D -->|ready_for_synthesis| E[final-context]
  D -->|waiting_for_user| F[answer]
  D -->|blocked| G[Inspect blocker and artifacts]
  D -->|unclear| H[resume]
```

## Validation

```bash
tests/smoke.sh
```

The smoke test uses `--stub`, so it does not call live Claude or Codex.

## Safety

- Prefer file-backed packets over pasted giant prompts.
- Keep `--cwd` explicit.
- Use `--pipeline-id` for `answer`, `review`, `status`, `resume`, and `final-context`.
- Treat `~/.omx/state/tmux-pipelines/current.json` as advisory only.
- Do not send secrets, credentials, cookies, or personal login material.

## Friend Links

- [linux.do](https://linux.do) - learn AI @ linux.do

## License

No license has been selected yet.
