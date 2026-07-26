#!/usr/bin/env bash
set -euo pipefail

LC_ALL=C
export LC_ALL

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
BACKUP_ROOT="${ASK_TMUX_BACKUP_DIR:-$HOME/.local/share/ask-tmux-pipeline/backups}"

FAIL_AFTER="${ASK_TMUX_INSTALL_FAIL_AFTER:-}"
TEST_SIGNAL_AT="${ASK_TMUX_INSTALL_TEST_SIGNAL_AT:-}"
TEST_SIGNAL_TARGET="${ASK_TMUX_INSTALL_TEST_SIGNAL_TARGET:-}"
TEST_ROLLBACK_FAIL_AT="${ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_AT:-}"
TEST_ROLLBACK_FAIL_TARGET="${ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_TARGET:-}"
TEST_ROLLBACK_FAIL_PHASE="${ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_PHASE:-}"
TEST_PAUSE_AFTER_LOCK_FILE="${ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE:-}"

sources=()
targets=()
categories=()
logical_targets=()
target_types=()
operations=()
staging_paths=()
phases=()
prior_expected=()

WORK_ROOT=""
TRANSACTION_ROOT=""
MANIFEST_PATH=""
CURRENT_MANIFEST=""
CURRENT_MANIFEST_INPUT=""
LEGACY_CURRENT_MANIFEST=""
JOURNAL_PATH=""
LOCK_PATH=""
LOCK_TOKEN=""
LOCK_HELD_COUNT=0
KEEP_LOCK=0
ACTIVATION_STARTED=0
COMMITTED=0
ROLLBACK_DONE=0
RELEASE_ID=""
INSTALL_ID=""
STATE_ROOT=""
COORDINATION_ROOT_COUNT=0
coordination_roots=()
lock_paths=()

die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

install_signal_traps() {
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

remove_transaction_root() {
  [[ -n "$TRANSACTION_ROOT" && -d "$TRANSACTION_ROOT" ]] || return 0
  case "$TRANSACTION_ROOT" in
    "$BACKUP_ROOT"/.ask-tmux-install.*)
      rm -rf -- "$TRANSACTION_ROOT"
      ;;
    *)
      printf 'install: refusing to remove unexpected transaction path: %s\n' \
        "$TRANSACTION_ROOT" >&2
      return 1
      ;;
  esac
}

cleanup_staging() {
  local staging_path work_parent

  for staging_path in "${staging_paths[@]}"; do
    [[ -n "$staging_path" ]] || continue
    if [[ -e "$staging_path" || -L "$staging_path" ]]; then
      rm -rf -- "$staging_path"
    fi
  done

  if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]]; then
    work_parent="${TMPDIR:-/tmp}"
    case "$WORK_ROOT" in
      "$work_parent"/ask-tmux-install-plan.*) rm -rf -- "$WORK_ROOT" ;;
      *)
        printf 'install: refusing to remove unexpected work path: %s\n' \
          "$WORK_ROOT" >&2
        ;;
    esac
  fi
}

release_locks() {
  local index owner_token="" release_failed=0

  for ((index=LOCK_HELD_COUNT - 1; index >= 0; index--)); do
    LOCK_PATH="${lock_paths[index]}"
    owner_token=""
    if [[ -f "$LOCK_PATH/owner" ]]; then
      IFS= read -r owner_token < "$LOCK_PATH/owner" || true
    fi
    if [[ "$owner_token" != "$LOCK_TOKEN" ]]; then
      printf 'install: refusing to release root lock with different owner: %s\n' \
        "$LOCK_PATH" >&2
      release_failed=1
      continue
    fi

    if ! rm -f -- "$LOCK_PATH/owner"; then
      printf 'install: could not remove installer root-lock owner: %s\n' \
        "$LOCK_PATH" >&2
      release_failed=1
      continue
    fi
    if ! rmdir "$LOCK_PATH"; then
      printf 'install: could not release installer root lock: %s\n' \
        "$LOCK_PATH" >&2
      release_failed=1
    fi
  done
  LOCK_HELD_COUNT=0
  [[ "$release_failed" == "0" ]]
}

record_phase() {
  local index="$1" phase="$2"

  if [[ "$TEST_ROLLBACK_FAIL_AT" == "journal-write" \
    && "$TEST_ROLLBACK_FAIL_TARGET" == "${logical_targets[index]}" \
    && "$TEST_ROLLBACK_FAIL_PHASE" == "$phase" ]]; then
    printf 'install: injected rollback journal-write failure for %s at %s\n' \
      "${logical_targets[index]}" "$phase" >&2
    return 1
  fi

  if [[ -n "$JOURNAL_PATH" ]]; then
    if ! printf '%s\t%s\t%s\n' \
      "$index" \
      "$phase" \
      "${logical_targets[index]}" \
      >> "$JOURNAL_PATH"; then
      printf 'install: could not record %s for %s\n' \
        "$phase" "${logical_targets[index]}" >&2
      return 1
    fi
  fi
  phases[index]="$phase"
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

maybe_inject_rollback_failure() {
  local action="$1" index="$2"

  if [[ "$TEST_ROLLBACK_FAIL_AT" == "$action" \
    && "$TEST_ROLLBACK_FAIL_TARGET" == "${logical_targets[index]}" ]]; then
    printf 'install: injected rollback %s failure for %s\n' \
      "$action" "${logical_targets[index]}" >&2
    return 1
  fi
  return 0
}

rollback_remove_target() {
  local index="$1" target="$2"

  record_phase "$index" rollback_remove_pending || return 1
  maybe_inject_rollback_failure remove-target "$index" || return 1
  if ! rm -rf -- "$target"; then
    printf 'install: could not remove rollback target: %s\n' "$target" >&2
    return 1
  fi
  record_phase "$index" rollback_removed || return 1
}

rollback_restore_backup() {
  local index="$1" backup="$2" target="$3"

  record_phase "$index" rollback_restore_pending || return 1
  maybe_inject_rollback_failure restore-backup "$index" || return 1
  if ! mv "$backup" "$target"; then
    printf 'install: could not restore rollback backup: %s -> %s\n' \
      "$backup" "$target" >&2
    return 1
  fi
  record_phase "$index" rollback_restored || return 1
}

rollback() {
  local index phase target backup stage operation
  local target_present backup_present stage_present rollback_failed=0

  [[ "$ROLLBACK_DONE" == "0" ]] || return 0
  ROLLBACK_DONE=1

  for ((index=${#targets[@]} - 1; index >= 0; index--)); do
    phase="${phases[index]:-planned}"
    target="${targets[index]}"
    operation="${operations[index]}"
    stage="${staging_paths[index]:-}"
    backup="$TRANSACTION_ROOT/backups/${categories[index]}/$(basename "$target")"

    target_present=0
    backup_present=0
    stage_present=0
    path_exists "$target" && target_present=1
    path_exists "$backup" && backup_present=1
    if [[ -n "$stage" ]]; then
      path_exists "$stage" && stage_present=1
    fi

    case "$phase" in
      planned|tombstone_noop|rollback_restored|rollback_removed)
        continue
        ;;

      backup_pending|backup_done)
        if [[ "$backup_present" == "1" && "$target_present" == "0" ]]; then
          if ! rollback_restore_backup "$index" "$backup" "$target"; then
            rollback_failed=1
          fi
        elif [[ "$backup_present" == "0" && "$target_present" == "1" ]]; then
          :
        else
          printf 'install: ambiguous rollback state for %s at %s\n' \
            "${logical_targets[index]}" "$phase" >&2
          rollback_failed=1
        fi
        ;;

      activation_pending)
        if [[ "$stage_present" == "0" && "$target_present" == "1" ]]; then
          if ! rollback_remove_target "$index" "$target"; then
            rollback_failed=1
            continue
          fi
          target_present=0
        elif [[ "$stage_present" == "1" && "$target_present" == "0" ]]; then
          :
        elif [[ "$stage_present" == "0" && "$target_present" == "0" ]]; then
          :
        else
          printf 'install: ambiguous activation rollback state for %s\n' \
            "${logical_targets[index]}" >&2
          rollback_failed=1
          continue
        fi

        if [[ "$backup_present" == "1" && "$target_present" == "0" ]]; then
          if ! rollback_restore_backup "$index" "$backup" "$target"; then
            rollback_failed=1
          fi
        elif [[ "$backup_present" == "1" ]]; then
          printf 'install: rollback target blocks backup restore: %s\n' \
            "$target" >&2
          rollback_failed=1
        fi
        ;;

      activated)
        if [[ "$target_present" == "1" ]]; then
          if ! rollback_remove_target "$index" "$target"; then
            rollback_failed=1
            continue
          fi
          target_present=0
        fi
        if [[ "$backup_present" == "1" && "$target_present" == "0" ]]; then
          if ! rollback_restore_backup "$index" "$backup" "$target"; then
            rollback_failed=1
          fi
        fi
        ;;

      tombstoned)
        if [[ "$target_present" == "1" ]]; then
          printf 'install: tombstone rollback target unexpectedly exists: %s\n' \
            "$target" >&2
          rollback_failed=1
        elif [[ "$backup_present" == "1" ]]; then
          if ! rollback_restore_backup "$index" "$backup" "$target"; then
            rollback_failed=1
          fi
        fi
        ;;

      rollback_remove_pending|rollback_restore_pending)
        printf 'install: rollback was interrupted for %s; manual recovery required\n' \
          "${logical_targets[index]}" >&2
        rollback_failed=1
        ;;

      *)
        printf 'install: unknown rollback phase %s for %s\n' \
          "$phase" "${logical_targets[index]}" >&2
        rollback_failed=1
        ;;
    esac
  done

  if [[ "$rollback_failed" == "0" ]]; then
    remove_transaction_root || return 1
    printf '%s\n' 'install: activation failed; restored the previous cohort' >&2
    return 0
  fi

  printf 'install: rollback incomplete; recovery files and lock remain at %s\n' \
    "$TRANSACTION_ROOT" >&2
  return 1
}

on_exit() {
  local status=$?

  trap - EXIT
  trap '' INT TERM HUP
  set +e

  if [[ "$COMMITTED" != "1" && -n "$TRANSACTION_ROOT" ]]; then
    if [[ "$ACTIVATION_STARTED" == "1" ]]; then
      if ! rollback; then
        KEEP_LOCK=1
      fi
    else
      remove_transaction_root
    fi
  fi

  cleanup_staging
  if [[ "$KEEP_LOCK" != "1" ]]; then
    release_locks
  fi
  exit "$status"
}

trap on_exit EXIT
install_signal_traps

if ! command -v python3 >/dev/null 2>&1; then
  die "python3 is required"
fi

if [[ -n "$FAIL_AFTER" \
  || -n "$TEST_SIGNAL_AT" \
  || -n "$TEST_SIGNAL_TARGET" \
  || -n "$TEST_ROLLBACK_FAIL_AT" \
  || -n "$TEST_ROLLBACK_FAIL_TARGET" \
  || -n "$TEST_ROLLBACK_FAIL_PHASE" \
  || -n "$TEST_PAUSE_AFTER_LOCK_FILE" ]]; then
  if [[ "${ASK_TMUX_INSTALL_TEST_MODE:-}" != "1" ]]; then
    die "installer failure hooks are test-only; set ASK_TMUX_INSTALL_TEST_MODE=1"
  fi
fi

if [[ -n "$FAIL_AFTER" ]]; then
  case "$FAIL_AFTER" in
    *[!0-9]*|'') die "ASK_TMUX_INSTALL_FAIL_AFTER must be a non-negative integer" ;;
  esac
  FAIL_AFTER=$((10#$FAIL_AFTER))
fi

if [[ -n "$TEST_SIGNAL_AT" || -n "$TEST_SIGNAL_TARGET" ]]; then
  case "$TEST_SIGNAL_AT" in
    after-backup-move|after-activation-move) ;;
    *) die "ASK_TMUX_INSTALL_TEST_SIGNAL_AT is invalid" ;;
  esac
  [[ -n "$TEST_SIGNAL_TARGET" ]] \
    || die "ASK_TMUX_INSTALL_TEST_SIGNAL_TARGET is required"
fi

if [[ -n "$TEST_ROLLBACK_FAIL_AT" \
  || -n "$TEST_ROLLBACK_FAIL_TARGET" \
  || -n "$TEST_ROLLBACK_FAIL_PHASE" ]]; then
  case "$TEST_ROLLBACK_FAIL_AT" in
    remove-target|restore-backup)
      [[ -z "$TEST_ROLLBACK_FAIL_PHASE" ]] \
        || die "ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_PHASE applies only to journal-write"
      ;;
    journal-write)
      case "$TEST_ROLLBACK_FAIL_PHASE" in
        rollback_remove_pending|rollback_removed|rollback_restore_pending|rollback_restored) ;;
        *) die "ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_PHASE is invalid" ;;
      esac
      ;;
    *) die "ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_AT is invalid" ;;
  esac
  [[ -n "$TEST_ROLLBACK_FAIL_TARGET" ]] \
    || die "ASK_TMUX_INSTALL_TEST_ROLLBACK_FAIL_TARGET is required"
fi

if [[ -n "$TEST_PAUSE_AFTER_LOCK_FILE" ]]; then
  case "$TEST_PAUSE_AFTER_LOCK_FILE" in
    *$'\n'*|*$'\t'*) die "ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE is invalid" ;;
  esac
  [[ -d "$(dirname "$TEST_PAUSE_AFTER_LOCK_FILE")" ]] \
    || die "ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE parent does not exist"
  [[ ! -e "$TEST_PAUSE_AFTER_LOCK_FILE.ready" \
    && ! -e "$TEST_PAUSE_AFTER_LOCK_FILE.continue" ]] \
    || die "ASK_TMUX_INSTALL_TEST_PAUSE_AFTER_LOCK_FILE markers already exist"
fi

add_operation() {
  sources+=("$1")
  targets+=("$2")
  categories+=("$3")
  logical_targets+=("$4")
  target_types+=("$5")
  operations+=("$6")
  staging_paths+=("${7:-}")
  phases+=("planned")
  prior_expected+=("0")
}

bin_count=0
codex_count=0
claude_count=0

for source in "$ROOT"/bin/ask-tmux-* "$ROOT"/bin/ask-tux-*; do
  [[ -f "$source" ]] || continue
  base="$(basename "$source")"
  add_operation "$source" "" bin "bin/$base" file install ""
  bin_count=$((bin_count + 1))
done

for source in "$ROOT"/skills/codex/*; do
  [[ -d "$source" ]] || continue
  base="$(basename "$source")"
  add_operation \
    "$source" "" codex-skills "codex-skills/$base" directory install ""
  codex_count=$((codex_count + 1))
done

for source in "$ROOT"/skills/claude/*; do
  [[ -d "$source" ]] || continue
  base="$(basename "$source")"
  add_operation \
    "$source" "" claude-skills "claude-skills/$base" directory install ""
  claude_count=$((claude_count + 1))
done

[[ "$bin_count" -gt 0 ]] || die "no bin targets found"
[[ "$codex_count" -gt 0 ]] || die "no Codex skill targets found"
[[ "$claude_count" -gt 0 ]] || die "no Claude skill targets found"

ACTIVE_COUNT="${#logical_targets[@]}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ask-tmux-install-plan.XXXXXX")"
NORMALIZED_PATHS="$WORK_ROOT/normalized-paths.txt"

preflight_args=()
for ((index=0; index < ACTIVE_COUNT; index++)); do
  preflight_args+=("${logical_targets[index]}" "${target_types[index]}")
done

python3 - \
  "$NORMALIZED_PATHS" \
  "$BIN_DIR" \
  "$CODEX_SKILLS_DIR" \
  "$CLAUDE_SKILLS_DIR" \
  "$BACKUP_ROOT" \
  "$ACTIVE_COUNT" \
  "${preflight_args[@]}" <<'PY'
import os
import re
import sys
import hashlib
import json

output_path, bin_root, codex_root, claude_root, backup_root, count_text = sys.argv[1:7]
arguments = sys.argv[7:]
count = int(count_text)
if len(arguments) != count * 2:
    raise SystemExit("invalid physical-target preflight plan")

for value in (bin_root, codex_root, claude_root, backup_root):
    if "\n" in value or "\t" in value or "\0" in value:
        raise SystemExit("install roots may not contain tabs or newlines")

roots = {
    "bin": os.path.realpath(os.path.abspath(bin_root)),
    "codex-skills": os.path.realpath(os.path.abspath(codex_root)),
    "claude-skills": os.path.realpath(os.path.abspath(claude_root)),
}
backup = os.path.realpath(os.path.abspath(backup_root))
if "/" in set(roots.values()) | {backup}:
    raise SystemExit("install and backup roots may not be the filesystem root")

identity_material = json.dumps(
    roots,
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
install_id = hashlib.sha256(identity_material).hexdigest()
state_root = os.path.join(
    roots["bin"],
    ".ask-tmux-pipeline-state",
    install_id,
)
coordination_roots = sorted(
    {
        os.path.join(root, ".ask-tmux-pipeline-state")
        for root in roots.values()
    }
)


def target_for(logical):
    match = re.fullmatch(
        r"(bin|codex-skills|claude-skills)/([A-Za-z0-9._-]+)",
        logical,
    )
    if not match:
        raise SystemExit(f"unsafe logical install target: {logical}")
    if match.group(2) in {".", ".."}:
        raise SystemExit(f"unsafe logical install target: {logical}")
    return os.path.normpath(os.path.join(roots[match.group(1)], match.group(2)))


planned = []
for offset in range(0, len(arguments), 2):
    logical, target_type = arguments[offset:offset + 2]
    if target_type not in {"file", "directory"}:
        raise SystemExit(f"invalid target type for {logical}")
    planned.append((logical, target_for(logical)))


def overlaps(left, right):
    common = os.path.commonpath([left, right])
    return common == left or common == right


for index, (logical, target) in enumerate(planned):
    if overlaps(target, backup):
        raise SystemExit(
            f"install target overlaps backup root: {logical} -> {target} <> {backup}"
        )
    for other_logical, other_target in planned[:index]:
        if overlaps(target, other_target):
            raise SystemExit(
                "overlapping install targets: "
                f"{other_logical} -> {other_target} <> {logical} -> {target}"
            )

for logical, target in planned:
    for coordination_root in coordination_roots:
        if overlaps(target, coordination_root):
            raise SystemExit(
                f"install target overlaps canonical installer state: "
                f"{logical} -> {target} <> {coordination_root}"
            )

for coordination_root in coordination_roots:
    if overlaps(coordination_root, backup):
        raise SystemExit(
            f"installer state overlaps backup root: "
            f"{coordination_root} <> {backup}"
        )

with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
    handle.write(roots["bin"] + "\n")
    handle.write(roots["codex-skills"] + "\n")
    handle.write(roots["claude-skills"] + "\n")
    handle.write(backup + "\n")
    handle.write(install_id + "\n")
    handle.write(state_root + "\n")
    handle.write(str(len(coordination_roots)) + "\n")
    for coordination_root in coordination_roots:
        handle.write(coordination_root + "\n")
    for _, target in planned:
        handle.write(target + "\n")
PY

{
  IFS= read -r BIN_DIR
  IFS= read -r CODEX_SKILLS_DIR
  IFS= read -r CLAUDE_SKILLS_DIR
  IFS= read -r BACKUP_ROOT
  IFS= read -r INSTALL_ID
  IFS= read -r STATE_ROOT
  IFS= read -r COORDINATION_ROOT_COUNT
  for ((index=0; index < COORDINATION_ROOT_COUNT; index++)); do
    IFS= read -r coordination_roots[index]
  done
  for ((index=0; index < ACTIVE_COUNT; index++)); do
    IFS= read -r targets[index]
  done
} < "$NORMALIZED_PATHS"

[[ "$INSTALL_ID" =~ ^[0-9a-f]{64}$ ]] \
  || die "canonical installation identity is invalid"
[[ "$COORDINATION_ROOT_COUNT" =~ ^[1-9][0-9]*$ ]] \
  || die "canonical coordination-root count is invalid"
CURRENT_MANIFEST="$STATE_ROOT/current-manifest.json"
LEGACY_CURRENT_MANIFEST="$BACKUP_ROOT/current-manifest.json"

mkdir -p \
  "$BIN_DIR" \
  "$CODEX_SKILLS_DIR" \
  "$CLAUDE_SKILLS_DIR" \
  "$BACKUP_ROOT" \
  "$STATE_ROOT"
for coordination_root in "${coordination_roots[@]}"; do
  mkdir -p "$coordination_root"
  lock_paths+=("$coordination_root/.ask-tmux-install.lock")
done

LOCK_TOKEN="pid=$$:ppid=$PPID:root=$ROOT:install_id=$INSTALL_ID"
trap '' INT TERM HUP
for LOCK_PATH in "${lock_paths[@]}"; do
  if mkdir "$LOCK_PATH" 2>/dev/null; then
    if ! printf '%s\n' "$LOCK_TOKEN" > "$LOCK_PATH/owner"; then
      rmdir "$LOCK_PATH" 2>/dev/null || true
      install_signal_traps
      die "could not record installer root-lock owner: $LOCK_PATH"
    fi
    LOCK_HELD_COUNT=$((LOCK_HELD_COUNT + 1))
  else
    install_signal_traps
    die "installer root lock exists at $LOCK_PATH; stale locks fail closed and require inspection"
  fi
done
install_signal_traps

if [[ -n "$TEST_PAUSE_AFTER_LOCK_FILE" ]]; then
  if ! printf '%s\n' "$LOCK_PATH" > "$TEST_PAUSE_AFTER_LOCK_FILE.ready"; then
    die "could not record the after-lock test pause"
  fi
  pause_attempt=0
  while [[ ! -e "$TEST_PAUSE_AFTER_LOCK_FILE.continue" ]]; do
    pause_attempt=$((pause_attempt + 1))
    if [[ "$pause_attempt" -ge 600 ]]; then
      die "after-lock test pause timed out"
    fi
    sleep 0.05
  done
fi

if path_exists "$CURRENT_MANIFEST"; then
  CURRENT_MANIFEST_INPUT="$CURRENT_MANIFEST"
elif path_exists "$LEGACY_CURRENT_MANIFEST"; then
  CURRENT_MANIFEST_INPUT="$LEGACY_CURRENT_MANIFEST"
else
  CURRENT_MANIFEST_INPUT="$CURRENT_MANIFEST"
fi

ROOT_CLAIM_STAGE="$WORK_ROOT/root-owner.json"
root_claim_args=()
for coordination_root in "${coordination_roots[@]}"; do
  root_claim_args+=("$coordination_root/root-owner.json")
done

python3 - \
  "$ROOT_CLAIM_STAGE" \
  "$CURRENT_MANIFEST" \
  "$INSTALL_ID" \
  "$BIN_DIR" \
  "$CODEX_SKILLS_DIR" \
  "$CLAUDE_SKILLS_DIR" \
  "$COORDINATION_ROOT_COUNT" \
  "${root_claim_args[@]}" <<'PY'
import json
import os
import re
import sys

(
    output_path,
    canonical_manifest,
    install_id,
    bin_root,
    codex_root,
    claude_root,
    count_text,
) = sys.argv[1:8]
claim_paths = sys.argv[8:]
count = int(count_text)
if len(claim_paths) != count:
    raise SystemExit("invalid destination-root ownership plan")
if not re.fullmatch(r"[0-9a-f]{64}", install_id):
    raise SystemExit("invalid destination-root ownership identity")

claim = {
    "install_id": install_id,
    "owner": "ask-tmux-pipeline",
    "roots": {
        "bin": bin_root,
        "claude-skills": claude_root,
        "codex-skills": codex_root,
    },
    "schema_version": 1,
}
canonical = (
    json.dumps(claim, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    + "\n"
).encode("ascii")

existing_count = 0
for claim_path in claim_paths:
    if not os.path.lexists(claim_path):
        continue
    existing_count += 1
    if os.path.islink(claim_path) or not os.path.isfile(claim_path):
        raise SystemExit(
            f"invalid destination root ownership claim: {claim_path}"
        )
    with open(claim_path, "rb") as handle:
        raw = handle.read()
    try:
        existing = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"invalid destination root ownership claim at "
            f"{claim_path}: {error}"
        )
    if raw != (
        json.dumps(
            existing,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("ascii"):
        raise SystemExit(
            f"destination root ownership claim is not canonical: {claim_path}"
        )
    if existing != claim:
        claimed_id = (
            existing.get("install_id", "<invalid>")
            if isinstance(existing, dict)
            else "<invalid>"
        )
        raise SystemExit(
            f"destination root ownership conflict at {claim_path}: "
            f"claimed install_id={claimed_id}; requested install_id={install_id}"
        )

if existing_count:
    if (
        not os.path.lexists(canonical_manifest)
        or os.path.islink(canonical_manifest)
        or not os.path.isfile(canonical_manifest)
    ):
        raise SystemExit(
            "claimed canonical manifest is not a regular file: "
            f"{canonical_manifest}"
        )

with open(output_path, "wb") as handle:
    handle.write(canonical)
PY

TOMBSTONE_PLAN="$WORK_ROOT/tombstones.tsv"
current_args=()
for ((index=0; index < ACTIVE_COUNT; index++)); do
  current_args+=(
    "${logical_targets[index]}"
    "${target_types[index]}"
    "${targets[index]}"
  )
done

python3 - \
  "$CURRENT_MANIFEST_INPUT" \
  "$TOMBSTONE_PLAN" \
  "$BIN_DIR" \
  "$CODEX_SKILLS_DIR" \
  "$CLAUDE_SKILLS_DIR" \
  "$BACKUP_ROOT" \
  "$STATE_ROOT" \
  "$ACTIVE_COUNT" \
  "$COORDINATION_ROOT_COUNT" \
  "${current_args[@]}" \
  "${coordination_roots[@]}" <<'PY'
import hashlib
import json
import os
import re
import sys

(
    current_path,
    output_path,
    bin_root,
    codex_root,
    claude_root,
    backup_root,
    state_root,
    count_text,
    coordination_count_text,
) = sys.argv[1:10]
arguments = sys.argv[10:]
count = int(count_text)
coordination_count = int(coordination_count_text)
if len(arguments) != count * 3 + coordination_count:
    raise SystemExit("invalid current-manifest reconciliation plan")
current_arguments = arguments[:count * 3]
coordination_roots = arguments[count * 3:]

new_targets = {}
new_physical = []
for offset in range(0, len(current_arguments), 3):
    logical, target_type, physical = current_arguments[offset:offset + 3]
    new_targets[logical] = target_type
    new_physical.append((logical, physical))

if not os.path.lexists(current_path):
    open(output_path, "w", encoding="utf-8").close()
    raise SystemExit(0)
if os.path.islink(current_path) or not os.path.isfile(current_path):
    raise SystemExit(f"current manifest is not a regular file: {current_path}")

with open(current_path, "rb") as handle:
    raw = handle.read()
try:
    manifest = json.loads(raw)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid current manifest: {error}")

expected_keys = {
    "active_targets",
    "entries",
    "owner",
    "release_id",
    "roots",
    "schema_version",
    "tombstones",
}
if set(manifest) != expected_keys:
    raise SystemExit("current manifest has an unsupported schema")
if manifest["schema_version"] != 2 or manifest["owner"] != "ask-tmux-pipeline":
    raise SystemExit("current manifest is not owned by ask-tmux-pipeline schema 2")

canonical = (
    json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    + "\n"
).encode("ascii")
if raw != canonical:
    raise SystemExit("current manifest is not canonical JSON")

expected_roots = {
    "bin": bin_root,
    "claude-skills": claude_root,
    "codex-skills": codex_root,
}
if manifest["roots"] != expected_roots:
    raise SystemExit(
        "current manifest roots differ from requested physical install roots"
    )

active_targets = manifest["active_targets"]
entries = manifest["entries"]
if active_targets != sorted(active_targets, key=lambda item: item.get("path", "")):
    raise SystemExit("current manifest active targets are not sorted")
if entries != sorted(entries, key=lambda item: item.get("path", "")):
    raise SystemExit("current manifest entries are not sorted")

content_material = json.dumps(
    {"active_targets": active_targets, "entries": entries},
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
if manifest["release_id"] != hashlib.sha256(content_material).hexdigest():
    raise SystemExit("current manifest release id does not match its active cohort")

safe_target = re.compile(
    r"^(bin|codex-skills|claude-skills)/([A-Za-z0-9._-]+)$"
)
prior_targets = {}
for item in active_targets:
    if set(item) != {"path", "type"} or not isinstance(item["path"], str):
        raise SystemExit("current manifest contains an invalid active target")
    match = safe_target.fullmatch(item["path"])
    if (
        not match
        or match.group(2) in {".", ".."}
        or item["type"] not in {"file", "directory"}
    ):
        raise SystemExit(f"current manifest contains unsafe target: {item}")
    if item["path"] in prior_targets:
        raise SystemExit(f"current manifest repeats target: {item['path']}")
    prior_targets[item["path"]] = item["type"]

entry_paths = set()
for entry in entries:
    if set(entry) != {"mode", "path", "sha256"}:
        raise SystemExit("current manifest contains an invalid file entry")
    if (
        not isinstance(entry["path"], str)
        or not re.fullmatch(r"[0-7]{4}", entry["mode"])
        or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])
        or entry["path"] in entry_paths
    ):
        raise SystemExit("current manifest contains an unsafe file entry")
    entry_paths.add(entry["path"])

for logical, target_type in prior_targets.items():
    if target_type == "file":
        owned_entries = [path for path in entry_paths if path == logical]
    else:
        owned_entries = [
            path for path in entry_paths if path.startswith(logical + "/")
        ]
    if not owned_entries:
        raise SystemExit(f"current manifest target has no owned entries: {logical}")

for logical in new_targets:
    if logical in prior_targets and new_targets[logical] != prior_targets[logical]:
        raise SystemExit(f"managed target changed type: {logical}")

roots = {
    "bin": bin_root,
    "codex-skills": codex_root,
    "claude-skills": claude_root,
}
backup = backup_root
protected_state_roots = sorted(set(coordination_roots + [state_root]))


def physical_for(logical):
    match = safe_target.fullmatch(logical)
    if not match or match.group(2) in {".", ".."}:
        raise SystemExit(f"unsafe tombstone target: {logical}")
    return os.path.normpath(os.path.join(roots[match.group(1)], match.group(2)))


def overlaps(left, right):
    common = os.path.commonpath([left, right])
    return common == left or common == right


tombstones = []
for logical in sorted(set(prior_targets) - set(new_targets)):
    physical = physical_for(logical)
    if overlaps(physical, backup):
        raise SystemExit(f"tombstone overlaps backup root: {logical}")
    for protected_state_root in protected_state_roots:
        if overlaps(physical, protected_state_root):
            raise SystemExit(
                f"tombstone overlaps canonical installer state: "
                f"{logical} -> {physical} <> {protected_state_root}"
            )
    for active_logical, active_physical in new_physical:
        if overlaps(physical, active_physical):
            raise SystemExit(
                f"tombstone overlaps active target: {logical} <> {active_logical}"
            )
    for _, _, other_physical in tombstones:
        if overlaps(physical, other_physical):
            raise SystemExit(f"overlapping tombstone targets: {logical}")
    tombstones.append((logical, prior_targets[logical], physical))

with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
    for logical, target_type, physical in tombstones:
        handle.write(f"{logical}\t{target_type}\t{physical}\n")
PY

while IFS=$'\t' read -r logical target_type target; do
  [[ -n "$logical" ]] || continue
  case "$logical" in
    bin/*) category=bin ;;
    codex-skills/*) category=codex-skills ;;
    claude-skills/*) category=claude-skills ;;
    *) die "invalid tombstone category: $logical" ;;
  esac
  add_operation "" "$target" "$category" "$logical" "$target_type" remove ""
done < "$TOMBSTONE_PLAN"

TOMBSTONE_START="$ACTIVE_COUNT"
TOMBSTONE_COUNT=$((${#logical_targets[@]} - ACTIVE_COUNT))

for ((index=0; index < ACTIVE_COUNT; index++)); do
  source="${sources[index]}"
  target="${targets[index]}"
  base="$(basename "$target")"
  target_parent="$(dirname "$target")"

  if [[ "${target_types[index]}" == "file" ]]; then
    staging_paths[index]="$(
      mktemp "$target_parent/.${base}.ask-tmux-stage.XXXXXX"
    )"
    stage="${staging_paths[index]}"
    cp -p "$source" "$stage"
    chmod +x "$stage"
  else
    staging_paths[index]="$(
      mktemp -d "$target_parent/.${base}.ask-tmux-stage.XXXXXX"
    )"
    stage="${staging_paths[index]}"
    cp -a "$source/." "$stage/"
  fi
done

MANIFEST_STAGE="$WORK_ROOT/manifest.json"
manifest_args=()
for ((index=0; index < ACTIVE_COUNT; index++)); do
  manifest_args+=(
    "${sources[index]}"
    "${staging_paths[index]}"
    "${logical_targets[index]}"
    "${target_types[index]}"
  )
done
for ((index=TOMBSTONE_START; index < TOMBSTONE_START + TOMBSTONE_COUNT; index++)); do
  manifest_args+=("${logical_targets[index]}" "${target_types[index]}")
done

RELEASE_ID="$(
  python3 - \
    "$MANIFEST_STAGE" \
    "$BIN_DIR" \
    "$CODEX_SKILLS_DIR" \
    "$CLAUDE_SKILLS_DIR" \
    "$ACTIVE_COUNT" \
    "$TOMBSTONE_COUNT" \
    "${manifest_args[@]}" <<'PY'
import hashlib
import json
import os
import stat
import sys

(
    manifest_path,
    bin_root,
    codex_root,
    claude_root,
    active_count_text,
    tombstone_count_text,
) = sys.argv[1:7]
arguments = sys.argv[7:]
active_count = int(active_count_text)
tombstone_count = int(tombstone_count_text)
expected_length = active_count * 4 + tombstone_count * 2
if len(arguments) != expected_length:
    raise SystemExit("invalid staged manifest plan")


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def regular_file(path, description):
    if os.path.islink(path) or not os.path.isfile(path):
        raise SystemExit(f"{description} is not a regular file: {path}")


def tree(path, description):
    if os.path.islink(path) or not os.path.isdir(path):
        raise SystemExit(f"{description} is not a directory: {path}")
    result = {}
    for current, directories, filenames in os.walk(path, followlinks=False):
        directories.sort()
        filenames.sort()
        for directory in directories:
            candidate = os.path.join(current, directory)
            if os.path.islink(candidate):
                raise SystemExit(f"{description} contains a symlink: {candidate}")
        for filename in filenames:
            candidate = os.path.join(current, filename)
            regular_file(candidate, description)
            relative = os.path.relpath(candidate, path).replace(os.sep, "/")
            result[relative] = digest(candidate)
    return result


entries = []
active_targets = []
seen_paths = set()
offset = 0
for _ in range(active_count):
    source, stage, logical, target_type = arguments[offset:offset + 4]
    offset += 4
    active_targets.append({"path": logical, "type": target_type})

    if target_type == "file":
        regular_file(source, "source")
        regular_file(stage, "staged target")
        if digest(source) != digest(stage):
            raise SystemExit(f"staged target differs from source: {logical}")
        if not stat.S_IMODE(os.stat(stage).st_mode) & 0o111:
            raise SystemExit(f"staged command is not executable: {logical}")
        staged_files = {"": digest(stage)}
    elif target_type == "directory":
        source_files = tree(source, "source tree")
        staged_files = tree(stage, "staged tree")
        if "SKILL.md" not in staged_files:
            raise SystemExit(f"staged skill lacks SKILL.md: {logical}")
        if source_files != staged_files:
            raise SystemExit(f"staged tree differs from source: {logical}")
    else:
        raise SystemExit(f"unknown target type: {target_type}")

    for relative in sorted(staged_files):
        path = logical if not relative else f"{logical}/{relative}"
        if path in seen_paths:
            raise SystemExit(f"duplicate manifest path: {path}")
        seen_paths.add(path)
        staged_path = stage if not relative else os.path.join(
            stage, *relative.split("/")
        )
        entries.append(
            {
                "mode": format(stat.S_IMODE(os.stat(staged_path).st_mode), "04o"),
                "path": path,
                "sha256": staged_files[relative],
            }
        )

tombstones = []
for _ in range(tombstone_count):
    logical, target_type = arguments[offset:offset + 2]
    offset += 2
    tombstones.append({"path": logical, "type": target_type})

active_targets.sort(key=lambda item: item["path"])
entries.sort(key=lambda item: item["path"])
tombstones.sort(key=lambda item: item["path"])
content_material = json.dumps(
    {"active_targets": active_targets, "entries": entries},
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("ascii")
release_id = hashlib.sha256(content_material).hexdigest()
manifest = {
    "active_targets": active_targets,
    "entries": entries,
    "owner": "ask-tmux-pipeline",
    "release_id": release_id,
    "roots": {
        "bin": bin_root,
        "claude-skills": claude_root,
        "codex-skills": codex_root,
    },
    "schema_version": 2,
    "tombstones": tombstones,
}
canonical = (
    json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    + "\n"
)
with open(manifest_path, "w", encoding="ascii", newline="\n") as handle:
    handle.write(canonical)
print(release_id)
PY
)"

[[ "$RELEASE_ID" =~ ^[0-9a-f]{64}$ ]] || die "manifest release id is invalid"
[[ -s "$MANIFEST_STAGE" ]] || die "manifest was not generated"

for ((index=0; index < COORDINATION_ROOT_COUNT; index++)); do
  claim_target="${coordination_roots[index]}/root-owner.json"
  add_operation \
    "$ROOT_CLAIM_STAGE" \
    "$claim_target" \
    "metadata-root-$index" \
    "metadata/root-owner-$index.json" \
    file \
    metadata \
    ""
  claim_index=$((${#logical_targets[@]} - 1))
  staging_paths[claim_index]="$(
    mktemp "${coordination_roots[index]}/.root-owner.ask-tmux-stage.XXXXXX"
  )"
  cp -p "$ROOT_CLAIM_STAGE" "${staging_paths[claim_index]}"
done

add_operation \
  "$MANIFEST_STAGE" \
  "$CURRENT_MANIFEST" \
  metadata \
  metadata/current-manifest.json \
  file \
  metadata \
  ""
metadata_index=$((${#logical_targets[@]} - 1))
staging_paths[metadata_index]="$(
  mktemp "$STATE_ROOT/.current-manifest.ask-tmux-stage.XXXXXX"
)"
CURRENT_MANIFEST_STAGE="${staging_paths[metadata_index]}"
cp -p "$MANIFEST_STAGE" "$CURRENT_MANIFEST_STAGE"

if [[ -n "$TEST_SIGNAL_TARGET" ]]; then
  signal_target_found=0
  for logical in "${logical_targets[@]}"; do
    if [[ "$logical" == "$TEST_SIGNAL_TARGET" ]]; then
      signal_target_found=1
      break
    fi
  done
  [[ "$signal_target_found" == "1" ]] \
    || die "test signal target is not in the transaction: $TEST_SIGNAL_TARGET"
fi

TRANSACTION_ROOT="$(mktemp -d "$BACKUP_ROOT/.ask-tmux-install.XXXXXX")"
MANIFEST_PATH="$TRANSACTION_ROOT/manifest.json"
JOURNAL_PATH="$TRANSACTION_ROOT/journal.tsv"
cp -p "$MANIFEST_STAGE" "$MANIFEST_PATH"
printf '%s\n' 'index	phase	logical_target' > "$JOURNAL_PATH"

maybe_test_signal() {
  local signal_at="$1" logical="$2"

  if [[ "$TEST_SIGNAL_AT" == "$signal_at" && "$TEST_SIGNAL_TARGET" == "$logical" ]]; then
    printf 'install: test signal at %s for %s\n' "$signal_at" "$logical" >&2
    kill -TERM "$$"
    die "test signal hook did not terminate the installer"
  fi
}

ACTIVATION_STARTED=1
operation_count=0
if [[ -n "$FAIL_AFTER" && "$FAIL_AFTER" -eq 0 ]]; then
  die "injected failure after 0 operations"
fi

for ((index=0; index < ${#targets[@]}; index++)); do
  target="${targets[index]}"
  stage="${staging_paths[index]}"
  operation="${operations[index]}"
  backup="$TRANSACTION_ROOT/backups/${categories[index]}/$(basename "$target")"

  if path_exists "$target"; then
    prior_expected[index]=1
    mkdir -p "$(dirname "$backup")"
    record_phase "$index" backup_pending
    if ! mv "$target" "$backup"; then
      die "could not back up target: $target"
    fi
    maybe_test_signal after-backup-move "${logical_targets[index]}"
    record_phase "$index" backup_done
  fi

  if [[ "$operation" == "remove" ]]; then
    if [[ "${prior_expected[index]}" == "1" ]]; then
      record_phase "$index" tombstoned
    else
      record_phase "$index" tombstone_noop
    fi
  else
    record_phase "$index" activation_pending
    if ! mv "$stage" "$target"; then
      die "could not activate target: $target"
    fi
    maybe_test_signal after-activation-move "${logical_targets[index]}"
    record_phase "$index" activated
  fi

  operation_count=$((operation_count + 1))
  if [[ -n "$FAIL_AFTER" && "$operation_count" -eq "$FAIL_AFTER" ]]; then
    die "injected failure after $operation_count operations"
  fi
done

COMMITTED=1

printf 'Installed ask-tmux scripts to %s\n' "$BIN_DIR"
printf 'Installed Codex skills to %s\n' "$CODEX_SKILLS_DIR"
printf 'Installed Claude skills to %s\n' "$CLAUDE_SKILLS_DIR"
printf 'release_id=%s\n' "$RELEASE_ID"
printf 'manifest=%s\n' "$MANIFEST_PATH"
printf 'current_manifest=%s\n' "$CURRENT_MANIFEST"
if [[ -d "$TRANSACTION_ROOT/backups" ]]; then
  printf 'Replaced files were backed up to %s\n' "$TRANSACTION_ROOT/backups"
fi
