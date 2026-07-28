# Claude Opus 5 Reliability Runbook

This runbook is the durable operating and verification contract for
`ask-tmux-claude`, `cc-claude`, and Claude Opus 5. Use it when launching a
review, diagnosing an incomplete response, handling `API Error: 524`, or
claiming that a transport defect has been fixed.

## Required Launch Path

Automated or agent-initiated reviews must use the gated wrapper:

```bash
ask-tmux-claude-gated send \
  --gate-reason explicit_user_request \
  --key PROJECT-STAGE-reviewer \
  --cwd /absolute/path/to/project \
  --materials /absolute/path/to/material.md \
  --model claude-opus-5 \
  --effort high \
  --prompt "Review every requested item. Identify blockers, missing assumptions, verification gaps, and concrete next actions." \
  --wait
```

Use `explicit_user_request` only when the current user explicitly requested
Claude. The raw `ask-tmux-claude` transport is for deliberate gate debugging or
an explicitly authorized bypass.

The runner must resolve Claude through `cc-claude` and launch it with:

```text
--bare --disable-slash-commands --no-chrome --dangerously-skip-permissions
```

`--bare` is mandatory. It prevents owner plugins, hooks, MCP servers, memories,
and automatically discovered instructions from contaminating the independent
review and consuming the context budget before the packet is read.

Do not set a shared `ANTHROPIC_MODEL`. Pass `--model claude-opus-5 --effort
high` through ask-tmux when an explicit pin is required. Do not pass those
flags to `cc-deepseek`; that launcher owns its separate model and effort
mapping.

## Response and Completion Contract

The packet, response, and scope-audit files are authoritative. Tmux is only the
control plane.

Claude must:

1. Read the file-backed packet and every listed material.
2. Start the response file early.
3. Write or append in bounded passes so completed work survives a provider
   interruption.
4. Cover the complete owner prompt without narrowing it.
5. Append the exact response-completion marker only after substantive coverage
   is complete.
6. Print the pane sentinel only after completing the response file.

The runner must then perform a separate scope audit. The audit must enumerate
every explicit deliverable, numbered request, section, constraint, and required
decision in the owner prompt and map each to substantive response content.

These are not proof of completion:

- a pane sentinel by itself;
- a response file that merely exists;
- a model-written statement that the work is complete;
- headings without substantive content;
- promises or forward references to sections that do not exist;
- a completion marker without full scope coverage.

Missing coverage must trigger a bounded revision in the same Opus 5 session.
If revisions are exhausted, report `provider_scope_incomplete` and preserve
both the response and the last scope-audit artifact.

## HTTP 524 Recovery

`API Error: 524` means the provider gateway reached its origin-response time
limit. Increasing `--wait-timeout` does not extend that upstream limit.

The required recovery is:

1. Classify the event as `provider_gateway_timeout_524`.
2. Treat it as retryable.
3. Preserve the existing response file and completed sections.
4. Wait the configured bounded backoff.
5. Resume the same Claude session, model, effort, packet, and response file.
6. Continue missing work rather than restarting the review.
7. Run the strict scope audit after response completion.

Never respond to a 524 by silently lowering effort, switching models, switching
providers, discarding partial output, or starting an unrelated fresh session.

If bounded recovery is exhausted, emit `retryable=true` and report the retained
partial-response path. Do not report the review as complete.

## Diagnostic Procedure

Run these before changing code:

```bash
ask-tmux-claude preflight --json
ask-tmux-claude doctor
ask-tmux-claude status --key KEY --cwd /absolute/path/to/project
ask-tmux-claude capture --key KEY --cwd /absolute/path/to/project --lines 240 --artifact
```

Inspect the durable response, packet, scope audit, state record, and provider
transcript. Distinguish:

- tmux control or prompt-delivery failure;
- provider readiness or process exit;
- local completion timeout;
- provider gateway 524;
- missing response;
- incomplete scope.

Do not infer the cause from decorative terminal activity glyphs or a single
error line.

## “Issue Addressed” Acceptance Gate

Never claim that an Opus 5 transport issue is fixed from grep output, error
recognition, a stub-only test, or an unverified consultant report.

A complete fix requires all applicable evidence:

1. A deterministic regression test reproduces the original failure mode.
2. The test fails before the repair and passes after it.
3. Syntax, unit, preflight, provider-wrapper, installer, and tmux smoke tests
   pass.
4. A live, non-private Opus 5/high probe verifies the actual provider route.
5. A live synthetic full-scope workload verifies incremental delivery,
   completeness auditing, and same-session revision.
6. The scope audit proves every synthetic requirement is covered.
7. Source and installed-runtime hashes match after activation.
8. Installed `preflight`, `doctor`, and an isolated installed-binary
   transaction pass.
9. Changed files, commands, untested areas, retained artifacts, and remaining
   external risks are reported.

If the original reproduction contains unpublished, controlled, credentialed,
or otherwise protected material, do not resend it to an external provider
without explicit data-export approval. Use a structurally equivalent synthetic
acceptance workload and disclose that limitation.

The upstream gateway can never be proven infallible. The acceptance claim is
that ask-tmux preserves work, recovers within configured bounds, reports typed
failure correctly, and never accepts incomplete scope as success.

## Maintainer Verification Commands

From the repository root:

```bash
bash -n bin/ask-tmux-consultant
bash -n bin/ask-tmux-pipeline
bash tests/consultant-unit.sh
bash tests/pipeline-unit.sh
bash tests/preflight-unit.sh
bash tests/provider-wrapper-unit.sh
bash tests/install-unit.sh
bash tests/smoke.sh
git diff --check
```

After an explicitly approved installation, compare source and installed
hashes, then run:

```bash
ask-tmux-claude preflight --json
ask-tmux-claude doctor
```

`doctor` must show `cc-claude` with the complete bare-runtime flag set.
