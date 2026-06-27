---
name: ask-tmux-claude
description: >-
  Launch or reuse a Claude tmux consultant session for review, comments,
  suggestions, planning critique, design discussion, or external Claude second
  opinion. Use when the user says ask Claude, ask Claude in tmux,
  ask-tmux-claude, ask-tux-claude, external Claude reviewer, Claude consultant,
  Claude review/comment/suggest, have Claude review Codex's session/work, or
  repeated Claude consultation should preserve context.
---

# Ask Tmux Claude

Use this skill when the user explicitly wants Claude to review, comment, suggest, plan, critique, or act as a reusable background consultant through tmux.

The shared runner is:

```bash
/home/h3031/bin/ask-tmux-consultant
```

The Claude wrapper is:

```bash
/home/h3031/bin/ask-tmux-claude
```

The typo-compatible alias is also supported:

```bash
/home/h3031/bin/ask-tux-claude
```

`ask-tux-claude` is only a compatibility alias for the historical typo; prefer the canonical `ask-tmux-claude` spelling in docs and scripts.

## Default Pattern

Prepare materials as files, then send Claude a short pointer prompt:

```bash
ask-tmux-claude send \
  --key reviewer \
  --cwd /path/to/project \
  --materials /path/to/material.md \
  --prompt "Review, comment, and suggest. Focus on blockers, missed assumptions, verification gaps, and concrete next actions." \
  --auto-trust \
  --wait
```

Use `--key` to name the reusable consultant identity for a project or stage. Reuse is the default. Use `--fresh --replace` when a clean consultant context is required.

## Stage Workflow Use

Inside Hermes Round 5 stages, use Claude as an optional consultant:

```bash
ask-tmux-claude send \
  --key S06-reviewer \
  --cwd /path/to/stage/worktree \
  --materials /path/to/run_dir/STAGE_SESSION_PROMPT.md \
  --materials /path/to/run_dir/FULL_HANDOFF.md \
  --task review \
  --auto-trust \
  --wait
```

Claude is advisory unless the GOAL or reviewer gate explicitly makes the review blocking.

## Lifecycle Commands

```bash
ask-tmux-claude status --key reviewer --cwd /path/to/project
ask-tmux-claude capture --key reviewer --cwd /path/to/project --lines 240 --artifact
ask-tmux-claude attach --key reviewer --cwd /path/to/project
ask-tmux-claude release --key reviewer --cwd /path/to/project
ask-tmux-claude cleanup --stale-after 24h
ask-tmux-claude gc --stale-after 24h
ask-tmux-claude doctor
```

Use `--cwd` on `capture`, `attach`, and `release` whenever a generic key such as `reviewer` may exist in more than one project. The runner keeps same-key consultants separate by project and by a collision-safe key hash; ambiguous lifecycle commands fail instead of choosing or releasing the wrong session.

## Safety Rules

- Use file-backed packets; do not paste giant specs directly into tmux.
- Default to read-only review/comment/suggest behavior.
- Treat the packet safety boundary as an instruction to the model, not an OS sandbox. The runner launches Claude with elevated local permissions, so only send trusted materials and do not grant write scope casually.
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
- `--auto-trust`: allow automatic confirmation of Claude workspace trust prompt.
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
~/.omx/state/consultants/claude/
```

Operations are logged under:

```text
~/.omx/consultants/log.jsonl
```

Do not treat tmux pane scrollback as the authoritative result. The response file is the data plane; tmux is only the control plane.

Raw `.omx` files are the v1 integration surface. Do not assume OMX MCP/state APIs are used by this runner.

For `--no-wait`, use `status --key ... --cwd ...` to reconcile completed response/sentinel pairs before sending again.
