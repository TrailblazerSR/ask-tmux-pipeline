---
name: ask-tmux-codex
description: Ask Codex through a reusable tmux consultant session only when the user explicitly names ask-tmux-codex or asks for an ask-tmux Codex reviewer/consultant. Do not use for generic requests to call another Codex session, including on HPC, unless ask-tmux-codex is explicitly requested.
allowed-tools: Bash Read Grep Glob
---

# Ask Tmux Codex

Use the current machine's local `ask-tmux-codex` wrapper for Codex consultation from Claude or shell workflows. Do not SSH to another host, call a remote wrapper, or use a Mac wrapper for HPC work from this skill. Cross-machine access is only for explicitly requested repo/install alignment.

## Quick Start

```bash
ask-tmux-codex send --key reviewer --cwd /path/to/project --materials path/to/material.md --prompt "review, comment, and suggest" --auto-trust
```

For pasted material:

```bash
printf '%s\n' "$TEXT" | ask-tmux-codex send --key reviewer --cwd /path/to/project --materials - --prompt "challenge this plan" --auto-trust
```

## Lifecycle

```bash
ask-tmux-codex status --all
ask-tmux-codex capture --key reviewer --cwd /path/to/project --lines 240 --artifact
ask-tmux-codex attach --key reviewer --cwd /path/to/project
ask-tmux-codex release --key reviewer --cwd /path/to/project
ask-tmux-codex cleanup --stale-after 24h
ask-tmux-codex gc --stale-after 24h
ask-tmux-codex doctor
```

Reuse a live same-key session by default. Use `--key` as the consultant identity. Same-key sessions are separated by project and by a collision-safe key hash. Use `--cwd` with `capture`, `attach`, and `release` whenever the key could exist in multiple projects; ambiguous lifecycle commands fail instead of guessing. State is global under `~/.omx/state/consultants/`; logs are under `~/.omx/consultants/log.jsonl`; packets and responses are project-local under `.omx/consultants/`.

By default `send` waits for a response file plus done sentinel and prints the response. Use `--no-wait` only when the owner session should continue immediately. After `--no-wait`, run `ask-tmux-codex status --key <key> --cwd <project>` to reconcile a completed sentinel/response pair before reusing the same key. A busy same-key session rejects new prompts unless the prior sentinel and response file prove completion.

## Safety

Packets default to read-only review/comment/suggest instructions. Do not grant write scope unless the user explicitly asks for persistent edits.

The only default write allowed is the required response file named in the packet. This is an instruction boundary, not an OS sandbox: the runner launches Codex with elevated local permissions, so only send trusted materials. Raw `.omx` files are the v1 integration surface.

## Test Without Cost

```bash
ask-tmux-codex send --stub --key smoke --cwd /path/to/project --materials <path> --prompt "review, comment, and suggest"
ask-tmux-codex capture --key smoke --cwd /path/to/project --lines 80
ask-tmux-codex release --key smoke --cwd /path/to/project
```
