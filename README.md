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

The diagrams use compact labels and explicit Mermaid Markdown line wrapping to render cleanly on GitHub. Exact command forms are shown in the quick guide above and the command-selection guide.

### Overall Command Choice

```mermaid
flowchart TD
    accTitle: Overall Command Choice
    accDescr: Command selection flow showing whether to review existing material, mirror a prompt, answer a clarification, review a draft, or recover pipeline state

    choose_task{"`Choose
    task`"}
    choose_task -->|Files| send_command["`send`"]
    choose_task -->|Prompt| start_command["`start`"]
    choose_task -->|Mirror| pure_alias["`pure`"]
    choose_task -->|Question| answer_command["`answer`"]
    choose_task -->|Draft| review_command["`review`"]
    choose_task -->|State| inspect_command["`inspect`"]
```

### Review Existing Material

Use this when the input is already in files or artifacts and you want review/comment/suggest.

```mermaid
flowchart TD
    accTitle: Review Existing Material
    accDescr: Review flow for sending existing files or artifacts to a reusable tmux Claude or Codex consultant session

    existing_material["`Existing
    files`"] --> choose_reviewer{"`Choose
    reviewer`"}
    choose_reviewer --> send_packet["`send`"]
    send_packet --> tmux_review["`tmux
    review`"]
    tmux_review --> response_file["`response
    file`"]
    response_file --> owner_apply["`apply`"]
```

### Same Prompt With Owner Synthesis

Use this when the current CLI should remain responsible for the final answer.

```mermaid
flowchart TD
    accTitle: Same Prompt Synthesis
    accDescr: Same-prompt flow where the owner CLI and a tmux CLI work in parallel, then the owner synthesizes the final answer

    owner_prompt["`Owner
    prompt`"] --> start_pipeline["`start`"]
    start_pipeline --> tmux_work["`tmux
    work`"]
    start_pipeline --> owner_work["`owner
    work`"]
    tmux_work --> status_check{Status}
    status_check -->|Ready| read_context["`read
    context`"]
    status_check -->|Question| ask_user["`ask
    user`"]
    status_check -->|Blocked| report_blocker["`report
    blocker`"]
    ask_user --> send_answer["`answer`"]
    send_answer --> status_check
    owner_work --> read_context
    read_context --> final_answer["`final
    answer`"]
```

### Pure / Mirror Mode

Use this when you mainly want the other CLI's answer.

```mermaid
flowchart TD
    accTitle: Pure Mirror Mode
    accDescr: Pure mode flow where the owner CLI mainly relays the tmux Claude or Codex answer, with clarification and blocker paths

    prompt_x["`Prompt
    X`"] --> pure_command["`pure`"]
    pure_command --> tmux_answer["`tmux
    answer`"]
    tmux_answer --> status_check{Status}
    status_check -->|Ready| relay_answer["`relay
    answer`"]
    status_check -->|Question| answer_user["`answer
    user`"]
    status_check -->|Blocked| report_blocker["`report
    blocker`"]
```

### Clarification Relay

Use this after a pipeline exits with code `10` and prints `PIPELINE_STATUS=waiting_for_user`.

```mermaid
flowchart TD
    accTitle: Clarification Relay
    accDescr: Clarification flow for relaying a tmux CLI question to the user and sending the answer back into the same pipeline

    tmux_question["`tmux
    question`"] --> ask_owner["`ask
    user`"]
    ask_owner --> user_answer["`user
    answer`"]
    user_answer --> run_answer["`answer`"]
    run_answer --> next_status{Status}
    next_status -->|Ready| read_context["`read
    context`"]
    next_status -->|Question| ask_owner
    next_status -->|Blocked| report_blocker["`report
    blocker`"]
```

### Draft Review Before Final Answer

Use this when you have a current CLI draft and want tmux Claude/Codex to critique it before finalizing.

```mermaid
flowchart TD
    accTitle: Draft Review Flow
    accDescr: Draft review flow where the owner CLI asks tmux Claude or Codex to critique a draft before the final answer is sent

    ready_context["`ready
    context`"] --> owner_draft["`owner
    draft`"]
    owner_draft --> run_review["`review`"]
    run_review --> tmux_critique["`tmux
    critique`"]
    tmux_critique --> update_context["`update
    context`"]
    update_context --> send_final["`send
    final`"]
```

### Recovery And Inspection

Use this when you need to inspect a previous pipeline, recover after an interruption, or fetch the final context again.

```mermaid
flowchart TD
    accTitle: Recovery Inspection Flow
    accDescr: Recovery flow for locating a pipeline ID, checking status, and choosing whether to fetch context, answer a question, inspect a blocker, or resume

    have_id{Have ID?}
    have_id -->|Yes| run_status["`status`"]
    have_id -->|No| find_id["`find
    ID`"]
    find_id --> run_status
    run_status --> status_check{Status}
    status_check -->|Ready| final_context["`final
    context`"]
    status_check -->|Question| run_answer["`answer`"]
    status_check -->|Blocked| inspect_blocker["`inspect
    blocker`"]
    status_check -->|Unclear| run_resume["`resume`"]
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

MIT License. See [LICENSE](LICENSE).
