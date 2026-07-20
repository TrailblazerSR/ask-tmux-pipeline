#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
BACKUP_ROOT="${ASK_TMUX_BACKUP_DIR:-$HOME/.local/share/ask-tmux-pipeline/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
staging_paths=()

mkdir -p "$BIN_DIR" "$CODEX_SKILLS_DIR" "$CLAUDE_SKILLS_DIR"

cleanup() {
  local staging_path
  for staging_path in "${staging_paths[@]}"; do
    if [[ -e "$staging_path" || -L "$staging_path" ]]; then
      rm -rf "$staging_path"
    fi
  done
  return 0
}
trap cleanup EXIT

install_file() {
  local source="$1" target="$2" category="$3" base stage backup
  base="$(basename "$target")"
  stage="$(mktemp "$(dirname "$target")/.${base}.stage.XXXXXX")"
  staging_paths+=("$stage")
  cp -p "$source" "$stage"
  chmod +x "$stage"
  if [[ -e "$target" || -L "$target" ]]; then
    backup="$BACKUP_ROOT/$category/$base"
    mkdir -p "$(dirname "$backup")"
    mv "$target" "$backup"
    if ! mv "$stage" "$target"; then
      mv "$backup" "$target"
      return 1
    fi
  else
    mv "$stage" "$target"
  fi
}

install_directory() {
  local source="$1" target="$2" category="$3" base stage backup
  base="$(basename "$target")"
  stage="$(mktemp -d "$(dirname "$target")/.${base}.stage.XXXXXX")"
  staging_paths+=("$stage")
  cp -a "$source/." "$stage/"
  if [[ -e "$target" || -L "$target" ]]; then
    backup="$BACKUP_ROOT/$category/$base"
    mkdir -p "$(dirname "$backup")"
    mv "$target" "$backup"
    if ! mv "$stage" "$target"; then
      mv "$backup" "$target"
      return 1
    fi
  else
    mv "$stage" "$target"
  fi
}

for source in "$ROOT"/bin/ask-tmux-* "$ROOT"/bin/ask-tux-*; do
  [[ -f "$source" ]] || continue
  install_file "$source" "$BIN_DIR/$(basename "$source")" bin
done

for source in "$ROOT"/skills/codex/*; do
  [[ -d "$source" ]] || continue
  install_directory "$source" "$CODEX_SKILLS_DIR/$(basename "$source")" codex-skills
done

for source in "$ROOT"/skills/claude/*; do
  [[ -d "$source" ]] || continue
  install_directory "$source" "$CLAUDE_SKILLS_DIR/$(basename "$source")" claude-skills
done

printf 'Installed ask-tmux scripts to %s\n' "$BIN_DIR"
printf 'Installed Codex skills to %s\n' "$CODEX_SKILLS_DIR"
printf 'Installed Claude skills to %s\n' "$CLAUDE_SKILLS_DIR"
if [[ -d "$BACKUP_ROOT" ]]; then
  printf 'Replaced files were backed up to %s\n' "$BACKUP_ROOT"
fi
