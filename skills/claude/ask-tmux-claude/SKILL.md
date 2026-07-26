---
name: ask-tmux-claude
description: Ask Claude through a reusable tmux consultant session and make this the default path for Claude review/comment/suggest requests. Use when the user says ask Claude, ask a Claude, ask Claude in tmux, external Claude reviewer, consultant Claude session, Claude review, Claude comment, Claude suggestion, review comment and suggest with Claude, get Claude's review, have Claude inspect materials, have Claude review Codex's session/work, review this session with Claude, or when repeated Claude consultation should preserve context across turns.
allowed-tools: Bash Read Grep Glob
---

# Ask Tmux Claude

Use the current machine's local `ask-tmux-claude-gated` wrapper for Claude consultation. It budgets automatic sends before invoking the raw `ask-tmux-claude` transport. Do not SSH to another host, call a remote wrapper, or use a Mac wrapper for HPC work from this skill. Cross-machine access is only for explicitly requested repo/install alignment.

## Provider Selection and Explicit Dual Review

The default launcher is `cc-claude`, which owns the Claude-provider model
mapping (`claude-opus-5` on the aligned Mac and HPC installs). Use
`ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek` for an explicitly requested DeepSeek
review; that launcher owns its separate DeepSeek main/subagent mapping. Never
export a shared `ANTHROPIC_MODEL`. Only those two launcher values are accepted
and the runner preflights encrypted credentials before detaching tmux. Use
`--model claude-opus-5` only with `cc-claude`; it is rejected with
`cc-deepseek`. `--effort low|medium|high|xhigh|max` is likewise Claude-only.
Claude defaults to `high`; DeepSeek retains its provider-owned `max` effort.

`API Error: 524` means the configured provider gateway reached its 120-second
origin-response limit. Increasing the ask-tmux `--wait-timeout` cannot extend
that upstream deadline. The runner should fail the request promptly. Retry
once only after splitting the task, requesting a concise response, or lowering
`--effort`; do not silently change the model or provider.

For an explicitly requested dual review, use `ask-tmux-claude-dual send` with
`--gate-reason explicit_user_request`. It concurrently runs isolated,
gated `cc-claude` and `cc-deepseek` lanes using derived keys
`<key>:cc-claude` and `<key>:cc-deepseek`. It is advisory/read-only by default
and consumes two provider requests; never substitute it for pipeline traffic.

## Quick Start

```bash
ask-tmux-claude-gated send --gate-reason explicit_user_request --key reviewer --cwd /path/to/project --materials path/to/material.md --prompt "review, comment, and suggest" --auto-trust
```

For pasted material:

```bash
printf '%s\n' "$TEXT" | ask-tmux-claude-gated send --gate-reason explicit_user_request --key reviewer --cwd /path/to/project --materials - --prompt "review, comment, and suggest" --auto-trust
```

## Lifecycle

```bash
ask-tmux-claude status --all
ask-tmux-claude capture --key reviewer --cwd /path/to/project --lines 240 --artifact
ask-tmux-claude attach --key reviewer --cwd /path/to/project
ask-tmux-claude release --key reviewer --cwd /path/to/project
ask-tmux-claude cleanup --stale-after 24h
ask-tmux-claude gc --stale-after 24h
ask-tmux-claude preflight --json
ask-tmux-claude doctor
```

`preflight --json` is read-only and verifies tmux control access from the
current caller before a live send.

Reuse a live same-key session by default. Use `--key` as the consultant identity. Same-key sessions are separated by project and by a collision-safe key hash. Use `--cwd` with `capture`, `attach`, and `release` whenever the key could exist in multiple projects; ambiguous lifecycle commands fail instead of guessing. Use `--fresh` only for a new independent consultation; release first or pass `--replace` if a same-key session exists. State is global under `~/.omx/state/consultants/`; logs are under `~/.omx/consultants/log.jsonl`; packets and responses are project-local under `.omx/consultants/`. The canonical command is `ask-tmux-claude`; `ask-tux-claude` is only a typo-compatible wrapper.

By default `send` waits for a response file plus done sentinel and prints the response. Use `--no-wait` only when the owner session should continue immediately. After `--no-wait`, run `ask-tmux-claude status --key <key> --cwd <project>` to reconcile a completed sentinel/response pair before reusing the same key. A busy same-key session rejects new prompts unless the prior sentinel and response file prove completion.

## Safety

Packets default to read-only review/comment/suggest instructions. Do not grant write scope unless the user explicitly asks for persistent edits.

The only default write allowed is the required response file named in the packet. This is an instruction boundary, not an OS sandbox: the runner launches Claude with elevated local permissions, so only send trusted materials. Raw `.omx` files are the v1 integration surface.

## Test Without Cost

```bash
ask-tmux-claude-gated send --gate-reason explicit_user_request --stub --key smoke --cwd /path/to/project --materials <path> --prompt "review, comment, and suggest"
ask-tmux-claude capture --key smoke --cwd /path/to/project --lines 80
ask-tmux-claude release --key smoke --cwd /path/to/project
```
