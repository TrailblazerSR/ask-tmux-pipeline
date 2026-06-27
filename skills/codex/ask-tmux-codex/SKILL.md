---
name: ask-tmux-codex
description: >-
  Launch or reuse a Codex tmux consultant session only when the user explicitly
  names ask-tmux-codex or asks for an ask-tmux Codex reviewer/consultant.
  Do not use this skill for generic requests to call another Codex session,
  including Codex sessions on an HPC server, unless ask-tmux-codex is explicitly
  requested.
---

# Ask Tmux Codex

Use this skill when the user explicitly wants `ask-tmux-codex` to run a separate Codex CLI session in tmux for review, comment, suggest, plan, critique, or a fresh-context second opinion.

## Local-Machine Rule

Use only the wrapper installed on the current machine. Do not SSH to another host, call a remote wrapper, or use a Mac wrapper for HPC work from this skill. Cross-machine access is only for explicitly requested repo/install alignment.

Expected local wrapper locations are:

```bash
ask-tmux-codex
/Users/timotheeshi/.local/bin/ask-tmux-codex
/home/h3031/bin/ask-tmux-codex
```

## Default Pattern

Prepare materials as files, then send the consultant a short pointer prompt:

```bash
ask-tmux-codex send \
  --key reviewer \
  --cwd /path/to/project \
  --materials /path/to/material.md \
  --prompt "Review, comment, and suggest. Focus on blockers, missed assumptions, verification gaps, and concrete next actions." \
  --auto-trust \
  --wait
```

Use `--key` to name the reusable consultant identity for a project or stage. Reuse is the default. Use `--fresh --replace` when a clean consultant context is required.

## Stage Workflow Use

Inside Hermes Round 5 stages, use a second Codex session as an optional independent reviewer or planner:

```bash
ask-tmux-codex send \
  --key S06-codex-reviewer \
  --cwd /path/to/stage/worktree \
  --materials /path/to/run_dir/STAGE_SESSION_PROMPT.md \
  --materials /path/to/run_dir/FULL_HANDOFF.md \
  --task review \
  --auto-trust \
  --wait
```

The consultant is advisory unless the GOAL or reviewer gate explicitly makes the review blocking.

## Lifecycle Commands

```bash
ask-tmux-codex status --key reviewer --cwd /path/to/project
ask-tmux-codex capture --key reviewer --cwd /path/to/project --lines 240 --artifact
ask-tmux-codex attach --key reviewer --cwd /path/to/project
ask-tmux-codex release --key reviewer --cwd /path/to/project
ask-tmux-codex cleanup --stale-after 24h
ask-tmux-codex gc --stale-after 24h
ask-tmux-codex doctor
```

Use `--cwd` on `capture`, `attach`, and `release` whenever a generic key such as `reviewer` may exist in more than one project. The runner keeps same-key consultants separate by project and by a collision-safe key hash; ambiguous lifecycle commands fail instead of choosing or releasing the wrong session.

## Safety Rules

- Use file-backed packets; do not paste giant specs directly into tmux.
- Default to read-only review/comment/suggest behavior.
- Treat the packet safety boundary as an instruction to the model, not an OS sandbox. The runner launches Codex with elevated local permissions, so only send trusted materials and do not grant write scope casually.
- The only default write allowed is the required response file named in the packet.
- Do not grant persistent write permission unless the user explicitly authorizes the write scope.
- Do not send secrets, credentials, cookies, or personal login material.
- If a consultant is busy, do not send a second prompt to the same key; wait, capture, attach, or release.
- Release stage consultant sessions after committed handoff and seal unless the stage is in `REQUEST_REVIEW` or failure recovery.

## Useful Flags

- `--stub`: no-cost local shell stub for tests.
- `--dry-run`: show planned session, state, packet, and response paths without launching.
- `--cwd PATH`: project or stage root used to scope packets, state lookup, and lifecycle commands.
- `--cwd-mode project|parent|git|current`: how to resolve `--cwd`; `current` respects explicit `--cwd` and otherwise uses the caller shell directory.
- `--wait` / `--no-wait`: block for the response file or leave the session busy for later polling.
- `--ready-timeout SECONDS`: readiness wait.
- `--wait-timeout SECONDS`: response wait.
- `--auto-trust`: allow automatic confirmation of Codex workspace trust prompt.
- `--release now`: release the tmux session after a successful response.

## Output Contract

The runner writes a packet under:

```text
<cwd>/.omx/consultants/packets/
```

The consultant must write its response under:

```text
<cwd>/.omx/consultants/responses/
```

State lives under:

```text
~/.omx/state/consultants/codex/
```

Operations are logged under:

```text
~/.omx/consultants/log.jsonl
```

Do not treat tmux pane scrollback as the authoritative result. The response file is the data plane; tmux is only the control plane.

Raw `.omx` files are the v1 integration surface. Do not assume OMX MCP/state APIs are used by this runner.

For `--no-wait`, use `status --key ... --cwd ...` to reconcile completed response/sentinel pairs before sending again.
