#!/usr/bin/env bash
set -euo pipefail

CC_CLAUDE_BIN="${CC_CLAUDE_BIN:-$HOME/.local/bin/cc-claude}"
CC_DEEPSEEK_BIN="${CC_DEEPSEEK_BIN:-$HOME/.local/bin/cc-deepseek}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$CC_CLAUDE_BIN" ]] || fail "missing executable cc-claude launcher: $CC_CLAUDE_BIN"
[[ -x "$CC_DEEPSEEK_BIN" ]] || fail "missing executable cc-deepseek launcher: $CC_DEEPSEEK_BIN"

test_root="$(mktemp -d /tmp/ask-tmux-provider-wrapper-unit.XXXXXX)"
test_config="$test_root/config"
test_bin="$test_root/bin"
mkdir -p "$test_config/claude-providers" "$test_bin"
trap 'rm -rf "$test_root"' EXIT

: > "$test_config/claude-providers/providers.env.gpg"
chmod 600 "$test_config/claude-providers/providers.env.gpg"

cat > "$test_bin/gpg" <<'EOF'
#!/bin/sh
cat <<'CONFIG'
DEEPSEEK_AUTH_TOKEN='test-deepseek-secret'
DEEPSEEK_MODEL='deepseek-v4-pro[1m]'
DEEPSEEK_SUBAGENT_MODEL='deepseek-v4-flash'
DEEPSEEK_EFFORT_LEVEL='max'
CLAUDE_PROVIDER_BASE_URL='https://claude-provider.invalid'
CLAUDE_PROVIDER_AUTH_TOKEN='test-claude-secret'
CLAUDE_PROVIDER_API_KEY=''
CLAUDE_PROVIDER_MODEL='legacy-model-must-not-win'
CONFIG
EOF

cat > "$test_bin/claude" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version)
    printf '%s\n' '2.1.220 (Claude Code)'
    ;;
  --help)
    printf '%s\n' '--dangerously-skip-permissions'
    ;;
  *)
    printf 'ANTHROPIC_BASE_URL=%s\n' "${ANTHROPIC_BASE_URL:-UNSET}"
    printf 'ANTHROPIC_MODEL=%s\n' "${ANTHROPIC_MODEL:-UNSET}"
    printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n' "${ANTHROPIC_DEFAULT_OPUS_MODEL:-UNSET}"
    printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-UNSET}"
    printf 'CLAUDE_CODE_SUBAGENT_MODEL=%s\n' "${CLAUDE_CODE_SUBAGENT_MODEL:-UNSET}"
    printf 'CLAUDE_CODE_EFFORT_LEVEL=%s\n' "${CLAUDE_CODE_EFFORT_LEVEL:-UNSET}"
    printf 'ANTHROPIC_AUTH_PRESENT=%s\n' "$(
      if [ -n "${ANTHROPIC_AUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ]; then
        printf yes
      else
        printf no
      fi
    )"
    printf 'CLAUDE_PROVIDER_SECRET_PRESENT=%s\n' "$(
      if [ -n "${CLAUDE_PROVIDER_AUTH_TOKEN:-}${CLAUDE_PROVIDER_API_KEY:-}" ]; then
        printf yes
      else
        printf no
      fi
    )"
    printf 'DEEPSEEK_SECRET_PRESENT=%s\n' "$(
      if [ -n "${DEEPSEEK_AUTH_TOKEN:-}" ]; then
        printf yes
      else
        printf no
      fi
    )"
    ;;
esac
EOF
chmod +x "$test_bin/gpg" "$test_bin/claude"

run_launcher() {
  env -i \
    HOME="$HOME" \
    PATH="$test_bin:/usr/bin:/bin:/opt/homebrew/bin" \
    XDG_CONFIG_HOME="$test_config" \
    CLAUDE_CONFIG_DIR="$HOME/.claude" \
    "$@"
}

claude_output="$(run_launcher "$CC_CLAUDE_BIN" --routing-test)"
grep -Fqx 'ANTHROPIC_BASE_URL=https://claude-provider.invalid' <<<"$claude_output" \
  || fail 'cc-claude did not preserve its provider endpoint'
grep -Fqx 'ANTHROPIC_MODEL=claude-opus-5' <<<"$claude_output" \
  || fail 'cc-claude did not default to claude-opus-5'
grep -Fqx 'ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5' <<<"$claude_output" \
  || fail 'cc-claude did not map the opus alias to claude-opus-5'
grep -Fqx 'CLAUDE_CODE_SUBAGENT_MODEL=UNSET' <<<"$claude_output" \
  || fail 'cc-claude unexpectedly forced a subagent model'
grep -Fqx 'CLAUDE_CODE_EFFORT_LEVEL=UNSET' <<<"$claude_output" \
  || fail 'cc-claude should leave effort selection to the caller'
grep -Fqx 'ANTHROPIC_AUTH_PRESENT=yes' <<<"$claude_output" \
  || fail 'cc-claude did not pass provider authentication'
grep -Fqx 'CLAUDE_PROVIDER_SECRET_PRESENT=no' <<<"$claude_output" \
  || fail 'cc-claude leaked launcher-only Claude credentials'
grep -Fqx 'DEEPSEEK_SECRET_PRESENT=no' <<<"$claude_output" \
  || fail 'cc-claude leaked the DeepSeek credential'

claude_override_output="$(
  run_launcher env CC_CLAUDE_MODEL=claude-opus-4-8 "$CC_CLAUDE_BIN" --routing-test
)"
grep -Fqx 'ANTHROPIC_MODEL=claude-opus-4-8' <<<"$claude_override_output" \
  || fail 'cc-claude did not honor a one-off model override'

claude_effort_override_output="$(
  run_launcher env CC_CLAUDE_EFFORT_LEVEL=medium "$CC_CLAUDE_BIN" --routing-test
)"
grep -Fqx 'CLAUDE_CODE_EFFORT_LEVEL=UNSET' <<<"$claude_effort_override_output" \
  || fail 'cc-claude should not translate environment effort; callers pass --effort explicitly'

deepseek_output="$(run_launcher "$CC_DEEPSEEK_BIN" --routing-test)"
grep -Fqx 'ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its provider endpoint'
grep -Fqx 'ANTHROPIC_MODEL=deepseek-v4-pro[1m]' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its main model'
grep -Fqx 'ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro[1m]' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its opus-family mapping'
grep -Fqx 'ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its fast model'
grep -Fqx 'CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its subagent model'
grep -Fqx 'CLAUDE_CODE_EFFORT_LEVEL=max' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not preserve its effort level'
grep -Fqx 'ANTHROPIC_AUTH_PRESENT=yes' <<<"$deepseek_output" \
  || fail 'cc-deepseek did not pass provider authentication'
grep -Fqx 'CLAUDE_PROVIDER_SECRET_PRESENT=no' <<<"$deepseek_output" \
  || fail 'cc-deepseek leaked the Claude-provider credential'
grep -Fqx 'DEEPSEEK_SECRET_PRESENT=no' <<<"$deepseek_output" \
  || fail 'cc-deepseek leaked its launcher-only credential'

printf '%s\n' 'provider wrapper unit ok'
