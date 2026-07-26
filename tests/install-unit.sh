#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d /tmp/ask-tmux-install-unit.XXXXXX)"
CONCURRENCY_PID=""
CONCURRENCY_CONTINUE=""

cleanup() {
  if [[ -n "$CONCURRENCY_CONTINUE" ]]; then
    : > "$CONCURRENCY_CONTINUE" 2>/dev/null || true
  fi
  if [[ -n "$CONCURRENCY_PID" ]]; then
    kill "$CONCURRENCY_PID" 2>/dev/null || true
    wait "$CONCURRENCY_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

install_with_destinations() {
  local home_root="$1" bin_root="$2" codex_root="$3"
  local claude_root="$4" backup_root="$5"
  shift 5
  env \
    HOME="$home_root" \
    BIN_DIR="$bin_root" \
    CODEX_SKILLS_DIR="$codex_root" \
    CLAUDE_SKILLS_DIR="$claude_root" \
    ASK_TMUX_BACKUP_DIR="$backup_root" \
    "$@" \
    "$ROOT/install.sh"
}

install_in_with_backup() {
  local case_root="$1" backup_root="$2"
  shift 2
  install_with_destinations \
    "$case_root/home" \
    "$case_root/bin" \
    "$case_root/codex-skills" \
    "$case_root/claude-skills" \
    "$backup_root" \
    "$@"
}

install_in() {
  local case_root="$1"
  shift
  install_in_with_backup "$case_root" "$case_root/backups" "$@"
}

success_root="$TEST_ROOT/success"
mkdir -p \
  "$success_root/home" \
  "$success_root/bin" \
  "$success_root/codex-skills/ask-tmux-claude" \
  "$success_root/codex-skills/unrelated-skill" \
  "$success_root/claude-skills/ask-tmux-codex" \
  "$success_root/claude-skills/unrelated-skill" \
  "$success_root/backups/prior-transaction"

printf '%s\n' 'old-bin-content' > "$success_root/bin/ask-tmux-claude"
printf '%s\n' 'old-codex-skill' > "$success_root/codex-skills/ask-tmux-claude/SKILL.md"
printf '%s\n' 'old-claude-skill' > "$success_root/claude-skills/ask-tmux-codex/SKILL.md"
printf '%s\n' 'keep-bin' > "$success_root/bin/unrelated-bin"
printf '%s\n' 'keep-codex' > "$success_root/codex-skills/unrelated-skill/KEEP"
printf '%s\n' 'keep-claude' > "$success_root/claude-skills/unrelated-skill/KEEP"
printf '%s\n' 'keep-prior-backup' > "$success_root/backups/prior-transaction/KEEP"

success_out="$(install_in "$success_root")"
manifest_path="$(printf '%s\n' "$success_out" | sed -n 's/^manifest=//p' | tail -1)"
current_manifest_path="$(
  printf '%s\n' "$success_out" | sed -n 's/^current_manifest=//p' | tail -1
)"
release_id="$(printf '%s\n' "$success_out" | sed -n 's/^release_id=//p' | tail -1)"

[[ -n "$manifest_path" && -f "$manifest_path" ]] \
  || fail "successful install did not report a manifest"
[[ -n "$current_manifest_path" && -f "$current_manifest_path" ]] \
  || fail "successful install did not report its current manifest"
cmp -s "$manifest_path" "$current_manifest_path" \
  || fail "release and current manifests disagree"
[[ "$release_id" =~ ^[0-9a-f]{64}$ ]] \
  || fail "successful install did not report a SHA-256 release id"

cmp -s "$ROOT/bin/ask-tmux-claude" "$success_root/bin/ask-tmux-claude" \
  || fail "binary content was not installed"
[[ -x "$success_root/bin/ask-tmux-claude" ]] \
  || fail "installed binary is not executable"
cmp -s \
  "$ROOT/skills/codex/ask-tmux-claude/SKILL.md" \
  "$success_root/codex-skills/ask-tmux-claude/SKILL.md" \
  || fail "Codex skill content was not installed"
cmp -s \
  "$ROOT/skills/claude/ask-tmux-codex/SKILL.md" \
  "$success_root/claude-skills/ask-tmux-codex/SKILL.md" \
  || fail "Claude skill content was not installed"

[[ "$(cat "$success_root/bin/unrelated-bin")" == "keep-bin" ]] \
  || fail "unrelated binary was modified"
[[ "$(cat "$success_root/codex-skills/unrelated-skill/KEEP")" == "keep-codex" ]] \
  || fail "unrelated Codex skill was modified"
[[ "$(cat "$success_root/claude-skills/unrelated-skill/KEEP")" == "keep-claude" ]] \
  || fail "unrelated Claude skill was modified"
[[ "$(cat "$success_root/backups/prior-transaction/KEEP")" == "keep-prior-backup" ]] \
  || fail "a prior backup was modified"

transaction_root="$(dirname "$manifest_path")"
[[ "$(cat "$transaction_root/backups/bin/ask-tmux-claude")" == "old-bin-content" ]] \
  || fail "replaced binary was not backed up"
[[ "$(cat "$transaction_root/backups/codex-skills/ask-tmux-claude/SKILL.md")" == "old-codex-skill" ]] \
  || fail "replaced Codex skill was not backed up"
[[ "$(cat "$transaction_root/backups/claude-skills/ask-tmux-codex/SKILL.md")" == "old-claude-skill" ]] \
  || fail "replaced Claude skill was not backed up"

python3 - \
  "$ROOT" \
  "$manifest_path" \
  "$success_root/bin" \
  "$success_root/codex-skills" \
  "$success_root/claude-skills" <<'PY'
import glob
import hashlib
import json
import os
import stat
import sys

repo_root, manifest_path, bin_dir, codex_dir, claude_dir = sys.argv[1:]

with open(manifest_path, "rb") as handle:
    raw = handle.read()
manifest = json.loads(raw)

canonical = (
    json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    + "\n"
).encode("ascii")
assert raw == canonical, "manifest is not canonical JSON"
assert set(manifest) == {
    "active_targets",
    "entries",
    "owner",
    "release_id",
    "roots",
    "schema_version",
    "tombstones",
}
assert manifest["schema_version"] == 2
assert manifest["owner"] == "ask-tmux-pipeline"
assert manifest["roots"] == {
    "bin": os.path.realpath(bin_dir),
    "claude-skills": os.path.realpath(claude_dir),
    "codex-skills": os.path.realpath(codex_dir),
}
assert manifest["tombstones"] == []

entries = manifest["entries"]
paths = [entry["path"] for entry in entries]
assert paths == sorted(paths), "manifest entries are not sorted"
assert len(paths) == len(set(paths)), "manifest contains duplicate paths"
assert all(set(entry) == {"mode", "path", "sha256"} for entry in entries)

active_targets = manifest["active_targets"]
assert active_targets == sorted(active_targets, key=lambda entry: entry["path"])
assert all(set(entry) == {"path", "type"} for entry in active_targets)
content_material = json.dumps(
    {"active_targets": active_targets, "entries": entries},
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
expected_release_id = hashlib.sha256(content_material).hexdigest()
assert manifest["release_id"] == expected_release_id


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


expected = {}
expected_targets = []
for pattern in ("ask-tmux-*", "ask-tux-*"):
    for source in glob.glob(os.path.join(repo_root, "bin", pattern)):
        if os.path.isfile(source):
            logical = "bin/" + os.path.basename(source)
            expected[logical] = digest(source)
            expected_targets.append({"path": logical, "type": "file"})

for family in ("codex", "claude"):
    source_root = os.path.join(repo_root, "skills", family)
    logical_root = family + "-skills"
    for source in glob.glob(os.path.join(source_root, "*")):
        if os.path.isdir(source):
            expected_targets.append(
                {
                    "path": logical_root + "/" + os.path.basename(source),
                    "type": "directory",
                }
            )
    for current, directories, filenames in os.walk(source_root):
        directories.sort()
        filenames.sort()
        for filename in filenames:
            source = os.path.join(current, filename)
            relative = os.path.relpath(source, source_root)
            expected[logical_root + "/" + relative.replace(os.sep, "/")] = digest(source)

actual = {entry["path"]: entry["sha256"] for entry in entries}
assert actual == expected, (sorted(actual), sorted(expected))
assert active_targets == sorted(expected_targets, key=lambda entry: entry["path"])

for entry in entries:
    logical = entry["path"]
    if logical.startswith("bin/"):
        installed = os.path.join(bin_dir, logical[len("bin/"):])
    elif logical.startswith("codex-skills/"):
        installed = os.path.join(codex_dir, logical[len("codex-skills/"):])
    elif logical.startswith("claude-skills/"):
        installed = os.path.join(claude_dir, logical[len("claude-skills/"):])
    else:
        raise AssertionError(logical)
    assert digest(installed) == entry["sha256"], installed
    installed_mode = format(stat.S_IMODE(os.stat(installed).st_mode), "04o")
    assert installed_mode == entry["mode"], installed
PY

second_root="$TEST_ROOT/second-success"
mkdir -p \
  "$second_root/home" \
  "$second_root/bin" \
  "$second_root/codex-skills" \
  "$second_root/claude-skills" \
  "$second_root/backups"
second_out="$(install_in "$second_root")"
second_release_id="$(printf '%s\n' "$second_out" | sed -n 's/^release_id=//p' | tail -1)"
[[ "$second_release_id" == "$release_id" ]] \
  || fail "identical source cohorts produced different release ids"

overlap_root="$TEST_ROOT/overlap"
mkdir -p \
  "$overlap_root/home" \
  "$overlap_root/shared" \
  "$overlap_root/claude-skills" \
  "$overlap_root/backups"
ln -s "$overlap_root/shared" "$overlap_root/shared-alias"
if overlap_out="$(
  env \
    HOME="$overlap_root/home" \
    BIN_DIR="$overlap_root/shared" \
    CODEX_SKILLS_DIR="$overlap_root/shared-alias/ask-tmux-claude" \
    CLAUDE_SKILLS_DIR="$overlap_root/claude-skills" \
    ASK_TMUX_BACKUP_DIR="$overlap_root/backups" \
    "$ROOT/install.sh" \
    2>&1
)"; then
  fail "overlapping physical install targets unexpectedly succeeded"
fi
printf '%s\n' "$overlap_out" | grep -Fq 'overlapping install targets' \
  || fail "overlap rejection did not identify the conflicting targets"
[[ -z "$(find "$overlap_root/shared" -mindepth 1 -print -quit)" ]] \
  || fail "overlap rejection staged or activated a target"

state_tombstone_root="$TEST_ROOT/state-tombstone-overlap"
mkdir -p \
  "$state_tombstone_root/home" \
  "$state_tombstone_root/bin" \
  "$state_tombstone_root/codex-skills" \
  "$state_tombstone_root/claude-skills" \
  "$state_tombstone_root/backups"
state_tombstone_legacy="$state_tombstone_root/backups/current-manifest.json"
python3 - \
  "$state_tombstone_legacy" \
  "$state_tombstone_root/bin" \
  "$state_tombstone_root/codex-skills" \
  "$state_tombstone_root/claude-skills" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, bin_root, codex_root, claude_root = sys.argv[1:]
active_targets = [
    {"path": "bin/.ask-tmux-pipeline-state", "type": "directory"}
]
entries = [
    {
        "mode": "0644",
        "path": "bin/.ask-tmux-pipeline-state/SENTINEL",
        "sha256": "0" * 64,
    }
]
content_material = json.dumps(
    {"active_targets": active_targets, "entries": entries},
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
manifest = {
    "active_targets": active_targets,
    "entries": entries,
    "owner": "ask-tmux-pipeline",
    "release_id": hashlib.sha256(content_material).hexdigest(),
    "roots": {
        "bin": os.path.realpath(bin_root),
        "claude-skills": os.path.realpath(claude_root),
        "codex-skills": os.path.realpath(codex_root),
    },
    "schema_version": 2,
    "tombstones": [],
}
with open(manifest_path, "w", encoding="ascii", newline="\n") as handle:
    handle.write(
        json.dumps(
            manifest,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    )
PY
cp -p "$state_tombstone_legacy" \
  "$state_tombstone_root/legacy.before"
if state_tombstone_out="$(
  install_in \
    "$state_tombstone_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER=0 \
    2>&1
)"; then
  fail "legacy tombstone overlapping canonical installer state unexpectedly succeeded"
fi
printf '%s\n' "$state_tombstone_out" |
  grep -Fq 'tombstone overlaps canonical installer state: bin/.ask-tmux-pipeline-state' \
  || fail "state-overlapping tombstone was not rejected during planning"
cmp -s \
  "$state_tombstone_root/legacy.before" \
  "$state_tombstone_legacy" \
  || fail "state-overlap rejection modified the crafted legacy ledger"
[[ -z "$(find "$state_tombstone_root/bin" -maxdepth 1 -name 'ask-tmux-*' -print -quit)" ]] \
  || fail "state-overlap rejection activated a binary target"
if find "$state_tombstone_root" \
  -type d -name '.ask-tmux-install.lock' -print -quit | grep -q .; then
  fail "state-overlap rejection left a destination-root lock behind"
fi

dangling_claimed_root="$TEST_ROOT/dangling-claimed-current"
mkdir -p \
  "$dangling_claimed_root/home" \
  "$dangling_claimed_root/bin" \
  "$dangling_claimed_root/codex-skills" \
  "$dangling_claimed_root/claude-skills" \
  "$dangling_claimed_root/backups"
dangling_claimed_seed="$(install_in "$dangling_claimed_root")"
dangling_claimed_current="$(
  printf '%s\n' "$dangling_claimed_seed" |
    sed -n 's/^current_manifest=//p' |
    tail -1
)"
[[ -f "$dangling_claimed_current" ]] \
  || fail "claimed dangling-manifest fixture lacks canonical state"
mv "$dangling_claimed_current" \
  "$dangling_claimed_root/current-manifest.saved"
ln -s "$dangling_claimed_root/missing-current-manifest" \
  "$dangling_claimed_current"
if dangling_claimed_out="$(install_in "$dangling_claimed_root" 2>&1)"; then
  fail "dangling claimed canonical manifest was treated as absent"
fi
printf '%s\n' "$dangling_claimed_out" |
  grep -Fq 'claimed canonical manifest is not a regular file' \
  || fail "dangling claimed canonical manifest rejection was not explicit"
[[ -L "$dangling_claimed_current" ]] \
  || fail "claimed dangling-manifest rejection modified the suspect ledger"
cmp -s "$ROOT/bin/ask-tmux-claude" \
  "$dangling_claimed_root/bin/ask-tmux-claude" \
  || fail "claimed dangling-manifest rejection modified an installed target"
if find "$dangling_claimed_root" \
  -type d -name '.ask-tmux-install.lock' -print -quit | grep -q .; then
  fail "claimed dangling-manifest rejection left a destination-root lock"
fi

dangling_legacy_root="$TEST_ROOT/dangling-unclaimed-legacy"
mkdir -p \
  "$dangling_legacy_root/home" \
  "$dangling_legacy_root/bin" \
  "$dangling_legacy_root/codex-skills" \
  "$dangling_legacy_root/claude-skills" \
  "$dangling_legacy_root/backups"
ln -s "$dangling_legacy_root/missing-legacy-manifest" \
  "$dangling_legacy_root/backups/current-manifest.json"
if dangling_legacy_out="$(install_in "$dangling_legacy_root" 2>&1)"; then
  fail "dangling unclaimed legacy manifest was treated as absent"
fi
printf '%s\n' "$dangling_legacy_out" |
  grep -Fq 'current manifest is not a regular file' \
  || fail "dangling unclaimed legacy rejection was not explicit"
[[ -L "$dangling_legacy_root/backups/current-manifest.json" ]] \
  || fail "dangling legacy rejection modified the suspect ledger"
[[ -z "$(find "$dangling_legacy_root/bin" -maxdepth 1 -name 'ask-tmux-*' -print -quit)" ]] \
  || fail "dangling legacy rejection activated a binary target"
if find "$dangling_legacy_root" \
  -type d -name '.ask-tmux-install.lock' -print -quit | grep -q .; then
  fail "dangling legacy rejection left a destination-root lock"
fi

lock_root="$TEST_ROOT/stale-lock"
mkdir -p \
  "$lock_root/home" \
  "$lock_root/bin" \
  "$lock_root/codex-skills" \
  "$lock_root/claude-skills" \
  "$lock_root/backups"
lock_seed_out="$(install_in "$lock_root")"
lock_current="$(
  printf '%s\n' "$lock_seed_out" |
    sed -n 's/^current_manifest=//p' |
    tail -1
)"
[[ -f "$lock_current" ]] || fail "stale-lock fixture lacks an ownership ledger"
lock_path="$(
  dirname "$(dirname "$lock_current")"
)/.ask-tmux-install.lock"
mkdir "$lock_path"
printf '%s\n' 'pre-existing-stale-lock' \
  > "$lock_path/owner"
cp -p "$lock_current" "$lock_root/current-manifest.before"
if lock_out="$(install_in "$lock_root" 2>&1)"; then
  fail "installer ignored an existing lock"
fi
printf '%s\n' "$lock_out" |
  grep -Fq "$lock_path" \
  || fail "lock rejection did not report the stale lock path"
[[ "$(cat "$lock_path/owner")" == "pre-existing-stale-lock" ]] \
  || fail "installer modified a lock it did not own"
cmp -s "$lock_root/current-manifest.before" "$lock_current" \
  || fail "lock rejection modified the ownership ledger"
cmp -s "$ROOT/bin/ask-tmux-claude" "$lock_root/bin/ask-tmux-claude" \
  || fail "lock rejection modified an installed target"

concurrency_root="$TEST_ROOT/cross-backup-concurrency"
mkdir -p \
  "$concurrency_root/home" \
  "$concurrency_root/bin" \
  "$concurrency_root/codex-skills" \
  "$concurrency_root/claude-skills" \
  "$concurrency_root/backups-a" \
  "$concurrency_root/backups-b" \
  "$concurrency_root/control"
concurrency_pause="$concurrency_root/control/install"
concurrency_continue="$concurrency_pause.continue"
concurrency_first_out="$concurrency_root/first.out"
concurrency_backup_a_physical="$(cd "$concurrency_root/backups-a" && pwd -P)"
concurrency_backup_b_physical="$(cd "$concurrency_root/backups-b" && pwd -P)"
CONCURRENCY_CONTINUE="$concurrency_continue"
install_in_with_backup \
  "$concurrency_root" \
  "$concurrency_root/backups-a" \
  ASK_TMUX_INSTALL_TEST_MODE=1 \
  ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE="$concurrency_pause" \
  > "$concurrency_first_out" 2>&1 &
CONCURRENCY_PID=$!

concurrency_ready=0
for ((attempt=0; attempt < 200; attempt++)); do
  if [[ -f "$concurrency_pause.ready" ]]; then
    concurrency_ready=1
    break
  fi
  if ! kill -0 "$CONCURRENCY_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if [[ "$concurrency_ready" != "1" ]]; then
  : > "$concurrency_continue"
  wait "$CONCURRENCY_PID" 2>/dev/null || true
  CONCURRENCY_PID=""
  fail "first alternate-backup installer did not pause with its canonical lock held"
fi

if concurrency_second_out="$(
  install_in_with_backup \
    "$concurrency_root" \
    "$concurrency_root/backups-b" \
    2>&1
)"; then
  : > "$concurrency_continue"
  wait "$CONCURRENCY_PID" 2>/dev/null || true
  CONCURRENCY_PID=""
  fail "same destinations with a different backup root bypassed the active lock"
fi
printf '%s\n' "$concurrency_second_out" |
  grep -Fq 'installer root lock exists at ' \
  || fail "cross-backup concurrency rejection did not report the canonical lock"
if printf '%s\n' "$concurrency_second_out" |
  grep -Fq "$concurrency_backup_b_physical"; then
  fail "cross-backup concurrency still scoped the lock to the mutable backup root"
fi

: > "$concurrency_continue"
if ! wait "$CONCURRENCY_PID"; then
  CONCURRENCY_PID=""
  fail "first alternate-backup installer failed after its test pause was released"
fi
CONCURRENCY_PID=""
CONCURRENCY_CONTINUE=""
concurrency_current="$(
  sed -n 's/^current_manifest=//p' "$concurrency_first_out" | tail -1
)"
[[ -n "$concurrency_current" && -f "$concurrency_current" ]] \
  || fail "first alternate-backup installer did not publish its ownership ledger"
case "$concurrency_current" in
  "$concurrency_backup_a_physical"/*|"$concurrency_backup_b_physical"/*)
    fail "ownership ledger remains scoped to a mutable backup root"
    ;;
esac

partial_concurrency_root="$TEST_ROOT/partial-overlap-concurrency"
mkdir -p \
  "$partial_concurrency_root/home-a" \
  "$partial_concurrency_root/home-b" \
  "$partial_concurrency_root/shared-bin" \
  "$partial_concurrency_root/codex-a" \
  "$partial_concurrency_root/claude-a" \
  "$partial_concurrency_root/codex-b" \
  "$partial_concurrency_root/claude-b" \
  "$partial_concurrency_root/backups-a" \
  "$partial_concurrency_root/backups-b" \
  "$partial_concurrency_root/control"
partial_pause="$partial_concurrency_root/control/install"
partial_continue="$partial_pause.continue"
partial_first_out="$partial_concurrency_root/first.out"
CONCURRENCY_CONTINUE="$partial_continue"
install_with_destinations \
  "$partial_concurrency_root/home-a" \
  "$partial_concurrency_root/shared-bin" \
  "$partial_concurrency_root/codex-a" \
  "$partial_concurrency_root/claude-a" \
  "$partial_concurrency_root/backups-a" \
  ASK_TMUX_INSTALL_TEST_MODE=1 \
  ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE="$partial_pause" \
  > "$partial_first_out" 2>&1 &
CONCURRENCY_PID=$!

partial_ready=0
for ((attempt=0; attempt < 200; attempt++)); do
  if [[ -f "$partial_pause.ready" ]]; then
    partial_ready=1
    break
  fi
  if ! kill -0 "$CONCURRENCY_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if [[ "$partial_ready" != "1" ]]; then
  : > "$partial_continue"
  wait "$CONCURRENCY_PID" 2>/dev/null || true
  CONCURRENCY_PID=""
  fail "partial-overlap fixture did not pause with destination locks held"
fi

if partial_second_out="$(
  install_with_destinations \
    "$partial_concurrency_root/home-b" \
    "$partial_concurrency_root/shared-bin" \
    "$partial_concurrency_root/codex-b" \
    "$partial_concurrency_root/claude-b" \
    "$partial_concurrency_root/backups-b" \
    2>&1
)"; then
  : > "$partial_continue"
  wait "$CONCURRENCY_PID" 2>/dev/null || true
  CONCURRENCY_PID=""
  fail "concurrent partial-overlap installer bypassed the shared-root lock"
fi
printf '%s\n' "$partial_second_out" |
  grep -Fq 'installer root lock exists at ' \
  || fail "partial-overlap concurrency rejection did not report a root lock"
partial_shared_bin_physical="$(
  cd "$partial_concurrency_root/shared-bin" && pwd -P
)"
printf '%s\n' "$partial_second_out" |
  grep -Fq "$partial_shared_bin_physical/.ask-tmux-pipeline-state/.ask-tmux-install.lock" \
  || fail "partial-overlap concurrency did not identify the shared destination root"

: > "$partial_continue"
if ! wait "$CONCURRENCY_PID"; then
  CONCURRENCY_PID=""
  fail "partial-overlap owner installer failed after its pause was released"
fi
CONCURRENCY_PID=""
CONCURRENCY_CONTINUE=""

partial_first_current="$(
  sed -n 's/^current_manifest=//p' "$partial_first_out" | tail -1
)"
[[ -f "$partial_first_current" ]] \
  || fail "partial-overlap owner install did not publish its exact-tuple ledger"
cp -p "$partial_first_current" \
  "$partial_concurrency_root/first-current.before"
if partial_sequential_out="$(
  install_with_destinations \
    "$partial_concurrency_root/home-b" \
    "$partial_concurrency_root/shared-bin" \
    "$partial_concurrency_root/codex-b" \
    "$partial_concurrency_root/claude-b" \
    "$partial_concurrency_root/backups-b" \
    2>&1
)"; then
  fail "sequential partial-overlap installer split ownership of a shared root"
fi
printf '%s\n' "$partial_sequential_out" |
  grep -Fq 'destination root ownership conflict at ' \
  || fail "sequential partial-overlap rejection did not report ownership conflict"
printf '%s\n' "$partial_sequential_out" |
  grep -Fq "$partial_shared_bin_physical/.ask-tmux-pipeline-state/root-owner.json" \
  || fail "sequential partial-overlap rejection did not identify the shared root claim"
cmp -s \
  "$partial_concurrency_root/first-current.before" \
  "$partial_first_current" \
  || fail "sequential partial-overlap attempt modified the owning tuple ledger"
if find \
  "$partial_concurrency_root/codex-b" \
  "$partial_concurrency_root/claude-b" \
  -mindepth 1 -maxdepth 1 -name 'ask-tmux-*' -print -quit | grep -q .; then
  fail "sequential partial-overlap rejection activated an unowned skill target"
fi

guard_root="$TEST_ROOT/injection-guard"
mkdir -p \
  "$guard_root/home" \
  "$guard_root/bin" \
  "$guard_root/codex-skills" \
  "$guard_root/claude-skills" \
  "$guard_root/backups"
if guard_out="$(install_in "$guard_root" ASK_TMUX_INSTALL_FAIL_AFTER=1 2>&1)"; then
  fail "test-only failure injection was accepted without test mode"
fi
printf '%s\n' "$guard_out" | grep -Fq 'ASK_TMUX_INSTALL_TEST_MODE=1' \
  || fail "failure injection guard did not explain the required test mode"
[[ -z "$(find "$guard_root/bin" -mindepth 1 -print -quit)" ]] \
  || fail "guarded failure injection modified the binary root"

for signal_phase in after-backup-move after-activation-move; do
  signal_root="$TEST_ROOT/signal-$signal_phase"
  mkdir -p \
    "$signal_root/home" \
    "$signal_root/bin" \
    "$signal_root/codex-skills" \
    "$signal_root/claude-skills" \
    "$signal_root/backups/prior-transaction"
  printf '%s\n' "old-$signal_phase" > "$signal_root/bin/ask-tmux-claude"
  printf '%s\n' "unrelated-$signal_phase" > "$signal_root/bin/unrelated-bin"
  printf '%s\n' "prior-$signal_phase" \
    > "$signal_root/backups/prior-transaction/KEEP"

  if signal_out="$(
    install_in \
      "$signal_root" \
      ASK_TMUX_INSTALL_TEST_MODE=1 \
      ASK_TMUX_INSTALL_TEST_SIGNAL_AT="$signal_phase" \
      ASK_TMUX_INSTALL_TEST_SIGNAL_TARGET=bin/ask-tmux-claude \
      2>&1
  )"; then
    fail "$signal_phase signal hook unexpectedly succeeded"
  fi
  printf '%s\n' "$signal_out" |
    grep -Fq "test signal at $signal_phase for bin/ask-tmux-claude" \
    || fail "$signal_phase signal hook was not reported"
  [[ "$(cat "$signal_root/bin/ask-tmux-claude")" == "old-$signal_phase" ]] \
    || fail "$signal_phase did not restore the target"
  [[ "$(cat "$signal_root/bin/unrelated-bin")" == "unrelated-$signal_phase" ]] \
    || fail "$signal_phase modified an unrelated target"
  [[ "$(cat "$signal_root/backups/prior-transaction/KEEP")" == "prior-$signal_phase" ]] \
    || fail "$signal_phase modified a prior backup"
  if find "$signal_root" \
    -type d -name '.ask-tmux-install.lock' -print -quit | grep -q .; then
    fail "$signal_phase left the owned installer lock behind"
  fi
  if find \
    "$signal_root/bin" \
    "$signal_root/codex-skills" \
    "$signal_root/claude-skills" \
    -name '.*.ask-tmux-stage.*' -print -quit | grep -q .; then
    fail "$signal_phase left a staged target behind"
  fi
done

rollback_root="$TEST_ROOT/rollback"
mkdir -p \
  "$rollback_root/home" \
  "$rollback_root/bin" \
  "$rollback_root/codex-skills/ask-tmux-claude" \
  "$rollback_root/claude-skills/ask-tmux-claude" \
  "$rollback_root/claude-skills/ask-tmux-codex" \
  "$rollback_root/backups/prior-transaction"

printf '%s\n' 'rollback-old-first' > "$rollback_root/bin/ask-tmux-claude"
printf '%s\n' 'rollback-old-third' > "$rollback_root/bin/ask-tmux-claude-gated"
printf '%s\n' 'rollback-old-codex' > "$rollback_root/codex-skills/ask-tmux-claude/SKILL.md"
printf '%s\n' 'rollback-old-claude' > "$rollback_root/claude-skills/ask-tmux-claude/SKILL.md"
printf '%s\n' 'rollback-untouched-claude' > "$rollback_root/claude-skills/ask-tmux-codex/SKILL.md"
printf '%s\n' 'rollback-unrelated' > "$rollback_root/bin/unrelated-bin"
printf '%s\n' 'rollback-prior-backup' > "$rollback_root/backups/prior-transaction/KEEP"

rollback_bin_count=0
for source in "$ROOT"/bin/ask-tmux-* "$ROOT"/bin/ask-tux-*; do
  [[ -f "$source" ]] || continue
  rollback_bin_count=$((rollback_bin_count + 1))
done
rollback_codex_count=0
for source in "$ROOT"/skills/codex/*; do
  [[ -d "$source" ]] || continue
  rollback_codex_count=$((rollback_codex_count + 1))
done
rollback_fail_after=$((rollback_bin_count + rollback_codex_count + 1))

if rollback_out="$(
  install_in \
    "$rollback_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER="$rollback_fail_after" \
    2>&1
)"; then
  fail "injected mid-activation failure unexpectedly succeeded"
fi
printf '%s\n' "$rollback_out" |
  grep -Fq "injected failure after $rollback_fail_after operations" \
  || fail "injected failure was not reported"

[[ "$(cat "$rollback_root/bin/ask-tmux-claude")" == "rollback-old-first" ]] \
  || fail "rollback did not restore the first replaced target"
[[ "$(cat "$rollback_root/bin/ask-tmux-claude-gated")" == "rollback-old-third" ]] \
  || fail "rollback did not restore a later replaced target"
[[ ! -e "$rollback_root/bin/ask-tmux-claude-dual" ]] \
  || fail "rollback did not remove a transaction-created target"
[[ "$(cat "$rollback_root/codex-skills/ask-tmux-claude/SKILL.md")" == "rollback-old-codex" ]] \
  || fail "rollback did not restore an activated Codex target"
[[ "$(cat "$rollback_root/claude-skills/ask-tmux-claude/SKILL.md")" == "rollback-old-claude" ]] \
  || fail "rollback did not restore an activated Claude target"
[[ "$(cat "$rollback_root/claude-skills/ask-tmux-codex/SKILL.md")" == "rollback-untouched-claude" ]] \
  || fail "rollback modified an unactivated Claude target"
[[ "$(cat "$rollback_root/bin/unrelated-bin")" == "rollback-unrelated" ]] \
  || fail "rollback modified an unrelated target"
[[ "$(cat "$rollback_root/backups/prior-transaction/KEEP")" == "rollback-prior-backup" ]] \
  || fail "rollback modified a prior backup"

if find \
  "$rollback_root/bin" \
  "$rollback_root/codex-skills" \
  "$rollback_root/claude-skills" \
  -name '.*.ask-tmux-stage.*' -print -quit | grep -q .; then
  fail "rollback left staged targets behind"
fi
if find "$rollback_root/backups" -maxdepth 1 -name '.ask-tmux-install.*' -print -quit | grep -q .; then
  fail "successful rollback left its transaction backup directory behind"
fi

rollback_rm_failure_root="$TEST_ROOT/rollback-rm-failure"
mkdir -p \
  "$rollback_rm_failure_root/home" \
  "$rollback_rm_failure_root/bin" \
  "$rollback_rm_failure_root/codex-skills" \
  "$rollback_rm_failure_root/claude-skills" \
  "$rollback_rm_failure_root/backups"
printf '%s\n' 'rollback-rm-old' \
  > "$rollback_rm_failure_root/bin/ask-tmux-claude"

if rollback_rm_failure_out="$(
  install_in \
    "$rollback_rm_failure_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER=1 \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_AT=remove-target \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_TARGET=bin/ask-tmux-claude \
    2>&1
)"; then
  fail "injected rollback rm failure unexpectedly succeeded"
fi
printf '%s\n' "$rollback_rm_failure_out" |
  grep -Fq 'injected rollback remove-target failure for bin/ask-tmux-claude' \
  || fail "injected rollback rm failure was not reported"
printf '%s\n' "$rollback_rm_failure_out" |
  grep -Fq 'rollback incomplete; recovery files and lock remain at ' \
  || fail "rollback rm failure did not fail closed"
rollback_rm_recovery="$(
  printf '%s\n' "$rollback_rm_failure_out" |
    sed -n 's/^install: rollback incomplete; recovery files and lock remain at //p' |
    tail -1
)"
[[ -n "$rollback_rm_recovery" && -d "$rollback_rm_recovery" ]] \
  || fail "rollback rm failure did not retain its transaction record"
[[ "$(cat "$rollback_rm_recovery/backups/bin/ask-tmux-claude")" == "rollback-rm-old" ]] \
  || fail "rollback rm failure did not retain the prior target backup"
cmp -s \
  "$ROOT/bin/ask-tmux-claude" \
  "$rollback_rm_failure_root/bin/ask-tmux-claude" \
  || fail "rollback rm failure did not leave the failed target for recovery"
grep -Fq $'rollback_remove_pending\tbin/ask-tmux-claude' \
  "$rollback_rm_recovery/journal.tsv" \
  || fail "rollback rm failure did not retain its pending journal phase"
if grep -Eq $'rollback_(removed|restored)\tbin/ask-tmux-claude' \
  "$rollback_rm_recovery/journal.tsv"; then
  fail "rollback rm failure recorded a completed rollback phase"
fi
[[ -n "$(
  find "$rollback_rm_failure_root" \
    -type d -name '.ask-tmux-install.lock' -print -quit
)" ]] || fail "rollback rm failure did not retain the installer lock"

rollback_mv_failure_root="$TEST_ROOT/rollback-mv-failure"
mkdir -p \
  "$rollback_mv_failure_root/home" \
  "$rollback_mv_failure_root/bin" \
  "$rollback_mv_failure_root/codex-skills" \
  "$rollback_mv_failure_root/claude-skills" \
  "$rollback_mv_failure_root/backups"
printf '%s\n' 'rollback-mv-old' \
  > "$rollback_mv_failure_root/bin/ask-tmux-claude"

if rollback_mv_failure_out="$(
  install_in \
    "$rollback_mv_failure_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER=1 \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_AT=restore-backup \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_TARGET=bin/ask-tmux-claude \
    2>&1
)"; then
  fail "injected rollback mv failure unexpectedly succeeded"
fi
printf '%s\n' "$rollback_mv_failure_out" |
  grep -Fq 'injected rollback restore-backup failure for bin/ask-tmux-claude' \
  || fail "injected rollback mv failure was not reported"
printf '%s\n' "$rollback_mv_failure_out" |
  grep -Fq 'rollback incomplete; recovery files and lock remain at ' \
  || fail "rollback mv failure did not fail closed"
rollback_mv_recovery="$(
  printf '%s\n' "$rollback_mv_failure_out" |
    sed -n 's/^install: rollback incomplete; recovery files and lock remain at //p' |
    tail -1
)"
[[ -n "$rollback_mv_recovery" && -d "$rollback_mv_recovery" ]] \
  || fail "rollback mv failure did not retain its transaction record"
[[ "$(cat "$rollback_mv_recovery/backups/bin/ask-tmux-claude")" == "rollback-mv-old" ]] \
  || fail "rollback mv failure did not retain the prior target backup"
[[ ! -e "$rollback_mv_failure_root/bin/ask-tmux-claude" ]] \
  || fail "rollback mv failure left an ambiguous replacement target"
grep -Fq $'rollback_removed\tbin/ask-tmux-claude' \
  "$rollback_mv_recovery/journal.tsv" \
  || fail "rollback mv failure did not record the completed removal"
grep -Fq $'rollback_restore_pending\tbin/ask-tmux-claude' \
  "$rollback_mv_recovery/journal.tsv" \
  || fail "rollback mv failure did not retain its pending restore phase"
if grep -Fq $'rollback_restored\tbin/ask-tmux-claude' \
  "$rollback_mv_recovery/journal.tsv"; then
  fail "rollback mv failure recorded a completed restore"
fi
[[ -n "$(
  find "$rollback_mv_failure_root" \
    -type d -name '.ask-tmux-install.lock' -print -quit
)" ]] || fail "rollback mv failure did not retain the installer lock"

rollback_journal_failure_root="$TEST_ROOT/rollback-journal-failure"
mkdir -p \
  "$rollback_journal_failure_root/home" \
  "$rollback_journal_failure_root/bin" \
  "$rollback_journal_failure_root/codex-skills" \
  "$rollback_journal_failure_root/claude-skills" \
  "$rollback_journal_failure_root/backups"
printf '%s\n' 'rollback-journal-old' \
  > "$rollback_journal_failure_root/bin/ask-tmux-claude"

if rollback_journal_failure_out="$(
  install_in \
    "$rollback_journal_failure_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER=1 \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_AT=journal-write \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_TARGET=bin/ask-tmux-claude \
    ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_PHASE=rollback_removed \
    2>&1
)"; then
  fail "injected rollback journal failure unexpectedly succeeded"
fi
printf '%s\n' "$rollback_journal_failure_out" |
  grep -Fq 'injected rollback journal-write failure for bin/ask-tmux-claude at rollback_removed' \
  || fail "injected rollback journal failure was not reported"
printf '%s\n' "$rollback_journal_failure_out" |
  grep -Fq 'rollback incomplete; recovery files and lock remain at ' \
  || fail "rollback journal failure did not fail closed"
rollback_journal_recovery="$(
  printf '%s\n' "$rollback_journal_failure_out" |
    sed -n 's/^install: rollback incomplete; recovery files and lock remain at //p' |
    tail -1
)"
[[ -n "$rollback_journal_recovery" && -d "$rollback_journal_recovery" ]] \
  || fail "rollback journal failure did not retain its transaction record"
[[ "$(cat "$rollback_journal_recovery/backups/bin/ask-tmux-claude")" == "rollback-journal-old" ]] \
  || fail "rollback journal failure did not retain the prior target backup"
[[ ! -e "$rollback_journal_failure_root/bin/ask-tmux-claude" ]] \
  || fail "rollback journal failure left an ambiguous replacement target"
grep -Fq $'rollback_remove_pending\tbin/ask-tmux-claude' \
  "$rollback_journal_recovery/journal.tsv" \
  || fail "rollback journal failure lost its pending removal evidence"
if grep -Eq $'rollback_(removed|restored)\tbin/ask-tmux-claude' \
  "$rollback_journal_recovery/journal.tsv"; then
  fail "rollback journal failure recorded a completed rollback phase"
fi
[[ -n "$(
  find "$rollback_journal_failure_root" \
    -type d -name '.ask-tmux-install.lock' -print -quit
)" ]] || fail "rollback journal failure did not retain the installer lock"

seed_retired_current_manifest() {
  local case_root="$1" backup_root="${2:-$1/backups}"
  local initial_out current_manifest

  mkdir -p \
    "$case_root/home" \
    "$case_root/bin" \
    "$case_root/codex-skills" \
    "$case_root/claude-skills" \
    "$backup_root"
  initial_out="$(install_in_with_backup "$case_root" "$backup_root")"
  current_manifest="$(
    printf '%s\n' "$initial_out" | sed -n 's/^current_manifest=//p' | tail -1
  )"
  [[ -f "$current_manifest" ]] \
    || fail "retired-target fixture lacks a current manifest"

  printf '%s\n' 'owned-retired-bin' > "$case_root/bin/ask-tmux-retired"
  mkdir -p "$case_root/codex-skills/ask-tmux-retired"
  printf '%s\n' 'owned-retired-skill' \
    > "$case_root/codex-skills/ask-tmux-retired/SKILL.md"
  printf '%s\n' 'keep-unrelated-bin' > "$case_root/bin/unrelated-bin"
  mkdir -p "$case_root/codex-skills/unrelated-skill"
  printf '%s\n' 'keep-unrelated-skill' \
    > "$case_root/codex-skills/unrelated-skill/KEEP"

  python3 - \
    "$current_manifest" \
    "$case_root/bin/ask-tmux-retired" \
    "$case_root/codex-skills/ask-tmux-retired/SKILL.md" <<'PY'
import hashlib
import json
import os
import stat
import sys

manifest_path, retired_bin, retired_skill = sys.argv[1:]
with open(manifest_path, encoding="ascii") as handle:
    manifest = json.load(handle)


def entry(logical, path):
    with open(path, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    return {
        "mode": format(stat.S_IMODE(os.stat(path).st_mode), "04o"),
        "path": logical,
        "sha256": digest,
    }


manifest["active_targets"].extend(
    [
        {"path": "bin/ask-tmux-retired", "type": "file"},
        {"path": "codex-skills/ask-tmux-retired", "type": "directory"},
    ]
)
manifest["active_targets"].sort(key=lambda item: item["path"])
manifest["entries"].extend(
    [
        entry("bin/ask-tmux-retired", retired_bin),
        entry(
            "codex-skills/ask-tmux-retired/SKILL.md",
            retired_skill,
        ),
    ]
)
manifest["entries"].sort(key=lambda item: item["path"])
manifest["tombstones"] = []
content_material = json.dumps(
    {
        "active_targets": manifest["active_targets"],
        "entries": manifest["entries"],
    },
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
manifest["release_id"] = hashlib.sha256(content_material).hexdigest()
canonical = (
    json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    + "\n"
)
with open(manifest_path, "w", encoding="ascii", newline="\n") as handle:
    handle.write(canonical)
PY

  printf '%s\n' "$current_manifest"
}

alternate_backup_root="$TEST_ROOT/alternate-backup-tombstone"
alternate_backup_a="$alternate_backup_root/backups-a"
alternate_backup_b="$alternate_backup_root/backups-b"
alternate_prior_current="$(
  seed_retired_current_manifest "$alternate_backup_root" "$alternate_backup_a"
)"
alternate_backup_a_physical="$(cd "$alternate_backup_a" && pwd -P)"
mkdir -p "$alternate_backup_b"
alternate_backup_b_physical="$(cd "$alternate_backup_b" && pwd -P)"
printf '%s\n' 'conflicting legacy ledger must not override canonical ownership' \
  > "$alternate_backup_b/current-manifest.json"
case "$alternate_prior_current" in
  "$alternate_backup_a_physical"/*|"$alternate_backup_b_physical"/*)
    fail "alternate-backup fixture ownership ledger is not destination-derived"
    ;;
esac
alternate_backup_out="$(
  install_in_with_backup "$alternate_backup_root" "$alternate_backup_b"
)"
alternate_backup_current="$(
  printf '%s\n' "$alternate_backup_out" |
    sed -n 's/^current_manifest=//p' |
    tail -1
)"
alternate_backup_manifest="$(
  printf '%s\n' "$alternate_backup_out" |
    sed -n 's/^manifest=//p' |
    tail -1
)"
[[ "$alternate_backup_current" == "$alternate_prior_current" ]] \
  || fail "changing backup roots changed the canonical ownership ledger"
[[ "$(cat "$alternate_backup_b/current-manifest.json")" == \
  "conflicting legacy ledger must not override canonical ownership" ]] \
  || fail "canonical ownership did not take precedence over alternate legacy state"
[[ ! -e "$alternate_backup_root/bin/ask-tmux-retired" ]] \
  || fail "alternate-backup install lost ownership of a retired binary"
[[ ! -e "$alternate_backup_root/codex-skills/ask-tmux-retired" ]] \
  || fail "alternate-backup install lost ownership of a retired skill"
[[ "$(cat "$alternate_backup_root/bin/unrelated-bin")" == "keep-unrelated-bin" ]] \
  || fail "alternate-backup tombstone modified an unrelated binary"
[[ "$(cat "$alternate_backup_root/codex-skills/unrelated-skill/KEEP")" == "keep-unrelated-skill" ]] \
  || fail "alternate-backup tombstone modified an unrelated skill"
case "$alternate_backup_manifest" in
  "$alternate_backup_b_physical"/.ask-tmux-install.*/*) ;;
  *) fail "alternate-backup transaction was not retained under the selected backup root" ;;
esac
[[ "$(cat "$(dirname "$alternate_backup_manifest")/backups/bin/ask-tmux-retired")" == "owned-retired-bin" ]] \
  || fail "alternate-backup transaction did not retain the retired binary"

tombstone_root="$TEST_ROOT/tombstone-success"
tombstone_prior_manifest="$(seed_retired_current_manifest "$tombstone_root")"
tombstone_prior_transaction_count="$(
  find "$tombstone_root/backups" \
    -maxdepth 1 -type d -name '.ask-tmux-install.*' -print | wc -l | tr -d ' '
)"
tombstone_out="$(install_in "$tombstone_root")"
tombstone_manifest="$(
  printf '%s\n' "$tombstone_out" | sed -n 's/^manifest=//p' | tail -1
)"
tombstone_current="$(
  printf '%s\n' "$tombstone_out" | sed -n 's/^current_manifest=//p' | tail -1
)"
[[ ! -e "$tombstone_root/bin/ask-tmux-retired" ]] \
  || fail "retired owned binary was not tombstoned"
[[ ! -e "$tombstone_root/codex-skills/ask-tmux-retired" ]] \
  || fail "retired owned skill was not tombstoned"
[[ "$(cat "$tombstone_root/bin/unrelated-bin")" == "keep-unrelated-bin" ]] \
  || fail "tombstone reconciliation modified an unrelated binary"
[[ "$(cat "$tombstone_root/codex-skills/unrelated-skill/KEEP")" == "keep-unrelated-skill" ]] \
  || fail "tombstone reconciliation modified an unrelated skill"
cmp -s "$tombstone_manifest" "$tombstone_current" \
  || fail "tombstone release was not installed as the current manifest"
tombstone_transaction_root="$(dirname "$tombstone_manifest")"
[[ "$(cat "$tombstone_transaction_root/backups/bin/ask-tmux-retired")" == "owned-retired-bin" ]] \
  || fail "tombstoned binary was not retained in the transaction backup"
[[ "$(cat "$tombstone_transaction_root/backups/codex-skills/ask-tmux-retired/SKILL.md")" == "owned-retired-skill" ]] \
  || fail "tombstoned skill was not retained in the transaction backup"
[[ -f "$tombstone_transaction_root/backups/metadata/current-manifest.json" ]] \
  || fail "the previous current manifest was not retained"
tombstone_transaction_count="$(
  find "$tombstone_root/backups" \
    -maxdepth 1 -type d -name '.ask-tmux-install.*' -print | wc -l | tr -d ' '
)"
[[ "$tombstone_transaction_count" -eq $((tombstone_prior_transaction_count + 1)) ]] \
  || fail "tombstone install did not preserve its prior transaction record"

python3 - "$tombstone_current" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="ascii") as handle:
    manifest = json.load(handle)
assert manifest["tombstones"] == [
    {"path": "bin/ask-tmux-retired", "type": "file"},
    {"path": "codex-skills/ask-tmux-retired", "type": "directory"},
]
active = {item["path"] for item in manifest["active_targets"]}
entries = {item["path"] for item in manifest["entries"]}
assert "bin/ask-tmux-retired" not in active
assert "codex-skills/ask-tmux-retired" not in active
assert "bin/ask-tmux-retired" not in entries
assert "codex-skills/ask-tmux-retired/SKILL.md" not in entries
PY

tombstone_rollback_root="$TEST_ROOT/tombstone-rollback"
tombstone_rollback_current="$(
  seed_retired_current_manifest "$tombstone_rollback_root"
)"
cp -p "$tombstone_rollback_current" \
  "$tombstone_rollback_root/current-manifest.before"
tombstone_active_count="$(
  python3 - "$tombstone_rollback_current" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="ascii") as handle:
    print(len(json.load(handle)["active_targets"]) - 2)
PY
)"
tombstone_fail_after=$((tombstone_active_count + 1))
tombstone_rollback_transaction_count="$(
  find "$tombstone_rollback_root/backups" \
    -maxdepth 1 -type d -name '.ask-tmux-install.*' -print | wc -l | tr -d ' '
)"
if tombstone_rollback_out="$(
  install_in \
    "$tombstone_rollback_root" \
    ASK_TMUX_INSTALL_TEST_MODE=1 \
    ASK_TMUX_INSTALL_FAIL_AFTER="$tombstone_fail_after" \
    2>&1
)"; then
  fail "tombstone rollback injection unexpectedly succeeded"
fi
printf '%s\n' "$tombstone_rollback_out" |
  grep -Fq "injected failure after $tombstone_fail_after operations" \
  || fail "tombstone rollback injection was not reported"
[[ "$(cat "$tombstone_rollback_root/bin/ask-tmux-retired")" == "owned-retired-bin" ]] \
  || fail "tombstone rollback did not restore the retired binary"
[[ "$(cat "$tombstone_rollback_root/codex-skills/ask-tmux-retired/SKILL.md")" == "owned-retired-skill" ]] \
  || fail "tombstone rollback did not preserve the retired skill"
[[ "$(cat "$tombstone_rollback_root/bin/unrelated-bin")" == "keep-unrelated-bin" ]] \
  || fail "tombstone rollback modified an unrelated binary"
cmp -s \
  "$tombstone_rollback_root/current-manifest.before" \
  "$tombstone_rollback_current" \
  || fail "tombstone rollback modified the prior current manifest"
if find "$tombstone_rollback_root" \
  -type d -name '.ask-tmux-install.lock' -print -quit | grep -q .; then
  fail "tombstone rollback left the installer lock behind"
fi
tombstone_rollback_transaction_count_after="$(
  find "$tombstone_rollback_root/backups" \
    -maxdepth 1 -type d -name '.ask-tmux-install.*' -print | wc -l | tr -d ' '
)"
[[ "$tombstone_rollback_transaction_count_after" -eq "$tombstone_rollback_transaction_count" ]] \
  || fail "failed tombstone transaction left a new backup record"

printf '%s\n' 'install unit ok'
