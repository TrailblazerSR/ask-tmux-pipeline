---
name: ask-tmux-claude
description: Ask Claude through a reusable tmux consultant session and make this the default path for Claude review/comment/suggest requests. Use when the user says ask Claude, ask a Claude, ask Claude in tmux, external Claude reviewer, consultant Claude session, Claude review, Claude comment, Claude suggestion, review comment and suggest with Claude, get Claude's review, have Claude inspect materials, have Claude review Codex's session/work, review this session with Claude, or when repeated Claude consultation should preserve context across turns.
allowed-tools: Bash Read Grep Glob
---

# Ask Tmux Claude

Use `/home/h3031/bin/ask-tmux-claude` for Claude consultation. Prefer it over non-interactive Claude calls for review/comment/suggest work.

## Quick Start

```bash
ask-tmux-claude send --key reviewer --cwd /path/to/project --materials path/to/material.md --prompt "review, comment, and suggest" --auto-trust
```

For pasted material:

```bash
printf '%s\n' "$TEXT" | ask-tmux-claude send --key reviewer --cwd /path/to/project --materials - --prompt "review, comment, and suggest" --auto-trust
```

## Lifecycle

```bash
ask-tmux-claude status --all
ask-tmux-claude capture --key reviewer --cwd /path/to/project --lines 240 --artifact
ask-tmux-claude attach --key reviewer --cwd /path/to/project
ask-tmux-claude release --key reviewer --cwd /path/to/project
ask-tmux-claude cleanup --stale-after 24h
ask-tmux-claude gc --stale-after 24h
ask-tmux-claude doctor
```

Reuse a live same-key session by default. Use `--key` as the consultant identity. Same-key sessions are separated by project and by a collision-safe key hash. Use `--cwd` with `capture`, `attach`, and `release` whenever the key could exist in multiple projects; ambiguous lifecycle commands fail instead of guessing. Use `--fresh` only for a new independent consultation; release first or pass `--replace` if a same-key session exists. State is global under `~/.omx/state/consultants/`; logs are under `~/.omx/consultants/log.jsonl`; packets and responses are project-local under `.omx/consultants/`. The canonical command is `ask-tmux-claude`; `ask-tux-claude` is only a typo-compatible wrapper.

By default `send` waits for a response file plus done sentinel and prints the response. Use `--no-wait` only when the owner session should continue immediately. After `--no-wait`, run `ask-tmux-claude status --key <key> --cwd <project>` to reconcile a completed sentinel/response pair before reusing the same key. A busy same-key session rejects new prompts unless the prior sentinel and response file prove completion.

## Safety

Packets default to read-only review/comment/suggest instructions. Do not grant write scope unless the user explicitly asks for persistent edits.

The only default write allowed is the required response file named in the packet. This is an instruction boundary, not an OS sandbox: the runner launches Claude with elevated local permissions, so only send trusted materials. Raw `.omx` files are the v1 integration surface.

## Test Without Cost

```bash
ask-tmux-claude send --stub --key smoke --cwd /path/to/project --materials <path> --prompt "review, comment, and suggest"
ask-tmux-claude capture --key smoke --cwd /path/to/project --lines 80
ask-tmux-claude release --key smoke --cwd /path/to/project
```
