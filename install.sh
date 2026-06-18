#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

mkdir -p "$BIN_DIR" "$CODEX_SKILLS_DIR" "$CLAUDE_SKILLS_DIR"

cp -a "$ROOT/bin/." "$BIN_DIR/"
chmod +x "$BIN_DIR"/ask-tmux-*
if [[ -f "$BIN_DIR/ask-tux-claude" ]]; then
  chmod +x "$BIN_DIR/ask-tux-claude"
fi

cp -a "$ROOT/skills/codex/." "$CODEX_SKILLS_DIR/"
cp -a "$ROOT/skills/claude/." "$CLAUDE_SKILLS_DIR/"

printf 'Installed ask-tmux scripts to %s\n' "$BIN_DIR"
printf 'Installed Codex skills to %s\n' "$CODEX_SKILLS_DIR"
printf 'Installed Claude skills to %s\n' "$CLAUDE_SKILLS_DIR"
