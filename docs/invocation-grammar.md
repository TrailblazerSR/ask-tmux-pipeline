# Ask-Tmux Invocation Grammar

This document is the canonical usage contract for choosing an ask-tmux command,
provider launcher, model, effort, and continuation path. Use it when generating
commands automatically or reviewing a command before execution.

## Core Rule

Choose the workflow first, then choose the provider. Do not infer the provider
from the model name, and do not replace a managed wrapper with a direct
`claude` invocation.

1. Existing files need one review: use a low-level `send`.
2. The current prompt needs clarification relay or synthesis: use `pipeline start`.
3. An existing pipeline needs more input: use `answer` or `review` with its
   explicit `--pipeline-id`.
4. Both Claude and DeepSeek are explicitly requested: use the dual wrapper for
   a one-off review, not for a pipeline continuation.

## Provider Matrix

| Requested reviewer | Command family | Launcher selection | Model option | Effort option |
|---|---|---|---|---|
| Claude | `ask-tmux-claude*` | Default `cc-claude` | Optional Claude-only `--model` | Optional; default `high` |
| DeepSeek | `ask-tmux-claude*` | Prefix the initial command with `ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek` | Forbidden; wrapper-owned | Forbidden; wrapper-owned `max` |
| Claude and DeepSeek | `ask-tmux-claude-dual` | Two isolated lanes | Each launcher owns its mapping | Each launcher owns its effort |
| Codex | `ask-tmux-codex*` | Codex runner | Not a Claude option | Not a Claude option |

`cc-claude` and `cc-deepseek` are isolated provider launchers. Never export a
shared `ANTHROPIC_MODEL` to select between them. Never use a bare `claude`
launcher as a substitute for either wrapper.

## Command Grammar

The notation below uses `[]` for optional items, `{}` for repeated items, and
`|` for alternatives.

```text
CLAUDE_LAUNCHER  := cc-claude | cc-deepseek
CLAUDE_EFFORT    := low | medium | high | xhigh | max

MATERIALS        := { --materials PATH }
CLAUDE_TUNING    := [ --model MODEL ] [ --effort CLAUDE_EFFORT ]
COMMON_SEND      := --key KEY --cwd PATH MATERIALS --prompt TEXT --wait

CLAUDE_REVIEW    :=
  ask-tmux-claude-gated send
    --gate-reason explicit_user_request
    COMMON_SEND
    CLAUDE_TUNING

DEEPSEEK_REVIEW  :=
  ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek
  ask-tmux-claude-gated send
    --gate-reason explicit_user_request
    COMMON_SEND

DUAL_REVIEW      :=
  ask-tmux-claude-dual send
    --gate-reason explicit_user_request
    COMMON_SEND

CLAUDE_START     :=
  ask-tmux-claude-pipeline start
    --cwd PATH
    ( --prompt TEXT | --prompt-file PATH )
    MATERIALS
    CLAUDE_TUNING

DEEPSEEK_START   :=
  ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek
  ask-tmux-claude-pipeline start
    --cwd PATH
    ( --prompt TEXT | --prompt-file PATH )
    MATERIALS

CONTINUATION     :=
  ask-tmux-claude-pipeline
    ( answer --answer TEXT
    | review --draft TEXT
    | status
    | resume
    | final-context )
    --pipeline-id ID
    --cwd PATH
```

The Claude pipeline internally uses the gated transport with
`--gate-reason external_review_required`. Do not bypass that gate or add the
gate option manually to `pipeline start`.

## Valid Examples

One Claude review using the default Opus mapping and `high` effort:

```bash
ask-tmux-claude-gated send \
  --gate-reason explicit_user_request \
  --key architecture-review \
  --cwd "$PWD" \
  --materials docs/design.md \
  --prompt "Review the design for blockers and verification gaps." \
  --wait
```

One DeepSeek review using its provider-owned model mapping and `max` effort:

```bash
ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
ask-tmux-claude-gated send \
  --gate-reason explicit_user_request \
  --key architecture-review-deepseek \
  --cwd "$PWD" \
  --materials docs/design.md \
  --prompt "Review the design for blockers and verification gaps." \
  --wait
```

Start a Claude pipeline with an explicit model pin:

```bash
ask-tmux-claude-pipeline start \
  --cwd "$PWD" \
  --model claude-opus-5 \
  --effort high \
  --prompt "Analyse the current design and propose the smallest safe change."
```

Resume the exact pipeline after a clarification:

```bash
ask-tmux-claude-pipeline answer \
  --pipeline-id "$pipeline_id" \
  --cwd "$PWD" \
  --answer "$user_answer"
```

## Invalid Forms

Do not use any of these:

```bash
# Wrong: bypasses the isolated provider wrapper.
ASK_TMUX_CLAUDE_LAUNCHER=claude ask-tmux-claude send ...

# Wrong: DeepSeek owns its model and effort configuration.
ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
ask-tmux-claude-pipeline start --model claude-opus-5 --effort high ...

# Wrong: creates a new lifecycle instead of continuing the existing one.
ask-tmux-claude-pipeline start --prompt "The user's clarification is ..." ...

# Wrong: dual review is not a continuation transport.
ask-tmux-claude-dual answer --pipeline-id "$pipeline_id" ...

# Wrong: a gateway timeout is not repaired by extending the local wait.
ask-tmux-claude-pipeline start --wait-timeout 1800 ...
```

## Continuation Invariants

At `start`, the pipeline persists the selected:

- provider launcher;
- requested model;
- requested effort.

Every `answer` and `review` reuses that tuple. An ambient
`ASK_TMUX_CLAUDE_LAUNCHER` value must not switch an existing pipeline. Use the
same explicit `--pipeline-id` and `--cwd`; do not rely on
`~/.omx/state/tmux-pipelines/current.json` when multiple pipelines may exist.

If a different provider or model is genuinely required, start a new pipeline
and identify it as a new review lane. Do not mutate the identity of an existing
pipeline.

## Preflight

Before a consequential live request:

```bash
ask-tmux-claude preflight --json
ask-tmux-claude doctor
ask-tmux-claude-pipeline doctor
```

`preflight --json` performs a non-mutating `list-sessions` control query from
the current caller context. `tmux_server_absent` is non-blocking because a send
can create the server. `tmux_socket_denied`, `tmux_protocol_mismatch`,
`tmux_client_missing`, and `tmux_control_failed` block the send before provider
launch, gate admission, or new request artifacts. Existing continuation state
is retained.

Check routing without a provider call:

```bash
ask-tmux-claude-pipeline start \
  --dry-run \
  --cwd "$PWD" \
  --prompt "routing check"

ASK_TMUX_CLAUDE_LAUNCHER=cc-deepseek \
ask-tmux-claude-pipeline start \
  --dry-run \
  --cwd "$PWD" \
  --prompt "routing check"
```

For Claude, the dry run should report `claude_launcher=cc-claude` and
`requested_effort=high`. For DeepSeek, it should report
`claude_launcher=cc-deepseek` with blank requested model and effort fields,
because the DeepSeek wrapper owns both.

## Result Envelope

New consultant responses start with one compact JSON object followed by one
blank line:

```json
{"schema":"ask_tmux_pipeline.result.v2","status":"FINAL","stage":"initial"}
```

`status` is `FINAL`, `NEEDS_INPUT`, or `BLOCKED`. `NEEDS_INPUT` also carries
non-empty string fields `question_id` and `question`, plus optional string
field `recommended_default`. `stage` must match the requested stage. The
legacy positional header remains accepted during migration, but new
integrations should emit the JSON envelope.

## Failure Grammar

- `PIPELINE_STATUS=waiting_for_user` with exit code `10`: relay the printed
  question and continue with `answer`; do not start over.
- `PIPELINE_STATUS=ready_for_synthesis`: read `final_context` and synthesize.
- `PIPELINE_STATUS=blocked`: report the blocker and artifact path.
- `outcome_kind=policy_deferred` with exit code `76`: no provider was launched.
  An initial denial has `PIPELINE_STATUS=policy_deferred`; a denied answer or
  review retains its resumable pipeline status. Read `policy_reason` and wait
  for or explicitly resolve that admission condition.
- Exit code `30`: read `outcome_kind` and any printed `outcome_artifact` before retrying.
  Common kinds distinguish tmux control access, provider readiness or exit,
  missing response, completion timeout, and gateway timeout.
- `tmux_prompt_delivery_unconfirmed` with `retryable=false`: Enter reached the
  provider, but the post-submit control check failed. The provider may still be
  running; inspect the retained session and state before any deliberate retry.
- `provider_gateway_timeout_524`: the provider gateway ended a turn at its
  origin-response limit. The runner preserves the partial response and
  automatically resumes the same session and full scope for a bounded number
  of attempts. It never switches providers or reduces effort. If recovery is
  exhausted, the outcome remains `retryable=true` and the partial artifact is
  retained.
- `provider_scope_incomplete`: the strict response audit exhausted its bounded
  completion revisions. Read the preserved response and scope-audit artifact;
  do not treat a model-written completion marker as proof of coverage.

## Automatic-Use Checklist

Before executing a generated command, verify all of the following:

- The user explicitly requested external Claude or DeepSeek review when the
  action consumes a provider request.
- The workflow is `send`, `start`, or a continuation for the intended lifecycle.
- `--cwd` points to the intended local project.
- Existing material uses `--materials`; large packets are file-backed.
- Claude uses `cc-claude`; DeepSeek is selected only with the explicit launcher
  prefix.
- DeepSeek has no `--model` or `--effort` flags.
- Continuations reuse the original `--pipeline-id`.
- A 524 response is either recovered in the same scoped session or reported as
  a retryable provider timeout, never misdiagnosed as a tmux readiness failure.

For the full diagnosis, recovery, and “issue addressed” acceptance procedure,
follow [Claude Opus 5 Reliability Runbook](claude-opus5-reliability-runbook.md).
