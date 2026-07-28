# git-ht Location Restriction Removal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the hard `worktreesDir` location gate from `git-ht`, replacing it with a location-agnostic "does the path reflect the branch?" concept that is informational in `list`, an overridable gate in `destroy`, and absent from `checkout`/`remove`.

**Architecture:** `git-ht` is a single POSIX `sh` script (`bin/git-ht`). A shared helper `path_matches_branch` centralizes the new rule (path ends with `/<branch>`). `list` uses it to flag; `destroy` uses it (plus a dirty-worktree check) to gate before deleting branches; `remove`/`destroy` resolve the worktree's real tracked path via the existing `get_worktree_path_for_branch` instead of reconstructing it from config.

**Tech Stack:** POSIX shell (`/bin/sh`), git worktree porcelain, a bespoke assertion harness in `test/git-ht-test.sh` (`assert_success`, `assert_failure`, `assert_output_contains`).

---

## Reference: spec

Full design at `docs/superpowers/specs/2026-07-28-git-ht-location-restriction-design.md`. Read it before starting.

## Testing conventions (read before Task 1)

- The suite is `test/git-ht-test.sh`. Run the whole suite with:
  ```bash
  ./test/git-ht-test.sh
  ```
- All test bodies live inside the `run_all_tests()` function (roughly lines
  292–1221). That function is invoked **four times** — once per repo mode:
  `normal`, `bare`, `normal-noremote`, `bare-noremote`. **Every new test must
  pass in all four modes.** The mismatch/dirty tests added here need no remote,
  so they are safe in all modes. Guard any remote-dependent step with
  `if [ $HAS_REMOTE -eq 1 ]; then ... fi` (see existing destroy tests around
  line 826). Our new tests do not push, so no guard is needed.
- The `git_ht` shell function (line 281) invokes `"$GIT_HT_PATH" "$@"`.
- Worktrees created by `git_ht co <name>` land at
  `$SANDBOX/test-repo.worktrees/<name>` (config is set at line 259).
- To create an **off-location** worktree in a test, call `git worktree add`
  directly with a path outside `test-repo.worktrees`, e.g.
  `git worktree add "$SANDBOX/other-location/<path>" -b <branch>`. Clean these up
  with `git worktree remove` + `git branch -D` like the existing list-mismatch
  test (lines 336–354).
- Assertion helpers:
  - `assert_success "<cmd>" "<label>"` — passes if `<cmd>` exits 0.
  - `assert_failure "<cmd>" "<label>"` — passes if `<cmd>` exits non-zero.
  - `assert_output_contains "<cmd>" "<grep-pattern>" "<label>"` — passes if
    stdout+stderr of `<cmd>` matches the pattern (`grep -q`). The pattern is a
    basic regex; escape nothing fancy, prefer plain substrings.
  - `assert_file_not_exists "<path>" "<label>"`.

## File structure

- **Modify only:** `bin/git-ht` — the whole behavior change.
- **Modify only:** `test/git-ht-test.sh` — updated + new assertions.
- No new files. No changes elsewhere.

---

## Task 1: Add the `path_matches_branch` helper and make `list` use it

**Files:**
- Modify: `bin/git-ht` (add helper near the other small helpers ~line 442; rewrite the flag logic in `cmd_list` ~lines 1146–1150)
- Modify: `test/git-ht-test.sh` (List test group, ~lines 336–354)

The `list` command is the natural way to TDD the helper: it exercises
`path_matches_branch` end-to-end and never blocks, so we can assert both the
"flag" and "no flag" outcomes.

- [ ] **Step 1: Update the existing list-mismatch test wording and add the name-matching case**

In `test/git-ht-test.sh`, find the block at lines 336–340:

```sh
  # Create a mismatched worktree (manually add worktree at wrong path)
  mkdir -p "$SANDBOX/other-location"
  git worktree add "$SANDBOX/other-location/wrong-path" -b list-mismatch-branch
  assert_output_contains "git_ht list" "path mismatch" "list flags worktree with path mismatch"
  assert_output_contains "git_ht list" "list-mismatch-branch" "list shows mismatched worktree branch name"
```

Replace it with (new wording + a new name-matching worktree that must NOT be flagged):

```sh
  # A worktree whose final path segment does NOT match its branch name is
  # flagged (git checkout was likely run inside it). Location is irrelevant —
  # this one lives outside worktreesDir but is flagged because the path
  # ("wrong-path") does not reflect the branch ("list-mismatch-branch").
  mkdir -p "$SANDBOX/other-location"
  git worktree add "$SANDBOX/other-location/wrong-path" -b list-mismatch-branch
  assert_output_contains "git_ht list" "path does not match branch" "list flags worktree whose path does not reflect its branch"
  assert_output_contains "git_ht list" "list-mismatch-branch" "list shows mismatched worktree branch name"

  # A worktree at a CUSTOM location whose final path segment DOES match its
  # branch name must NOT be flagged. This is the behavior the location-gate
  # removal is all about.
  git worktree add "$SANDBOX/other-location/custom-ok" -b custom-ok
  list_ok_output=$(git_ht list 2>&1)
  if echo "$list_ok_output" | grep -q "custom-ok" && ! echo "$list_ok_output" | grep "custom-ok" | grep -q "!"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Off-location worktree with matching name is not flagged\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Off-location worktree with matching name is not flagged\n"
    printf "  Output: %s\n" "$list_ok_output"
  fi
```

Then extend the cleanup block at lines 350–354 to also remove `custom-ok`:

```sh
  # Clean up worktrees for subsequent tests
  git worktree remove "$SANDBOX/other-location/wrong-path"
  git worktree remove "$SANDBOX/other-location/custom-ok"
  git worktree remove "$SANDBOX/other-location/detached-wt"
  git branch -D list-mismatch-branch 2>/dev/null || true
  git branch -D custom-ok 2>/dev/null || true
  git_ht remove list-test-1 --force 2>/dev/null || true
```

(The `detached-wt` line already exists between these — keep it in its current
order relative to the surrounding lines; only add the two `custom-ok` lines.)

- [ ] **Step 2: Run the list tests to verify they fail**

Run:
```bash
./test/git-ht-test.sh 2>&1 | grep -A1 -i "path does not match branch\|matching name is not flagged"
```
Expected: FAIL on "list flags worktree whose path does not reflect its branch"
(current output says "path mismatch", not "path does not match branch"), and
the new "not flagged" test may pass or fail depending on current behavior — the
point is the wording assertion fails now. The suite exits non-zero.

- [ ] **Step 3: Add the `path_matches_branch` helper**

In `bin/git-ht`, add this helper. Place it immediately after the
`is_default_branch()` function (which ends at line 442, right before
`# Run exec command with worktree path`):

```sh
# Check whether a worktree's path reflects the branch it contains.
# The path must END WITH "/<branch>" (trailing path segments). This is exactly
# what git-ht produces on creation:
#   branch "my-feature"    -> <dir>/my-feature      (ends with /my-feature)
#   branch "feature/login" -> <dir>/feature/login   (ends with /feature/login)
# Anchoring on a leading slash avoids a false match where the branch is only a
# suffix substring of the final segment (path .../my-feature vs branch "feature").
# Args: worktree_path, branch
# Returns 0 if the path reflects the branch, 1 otherwise.
path_matches_branch() {
  local worktree_path="$1"
  local branch="$2"
  case "$worktree_path" in
    */"$branch") return 0 ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Rewrite the `cmd_list` flag logic to use the helper**

In `bin/git-ht`, `cmd_list()`, replace the branch-handling block at lines
1144–1150:

```sh
      local current_branch=$(echo "$line" | sed 's|^branch refs/heads/||')
      local expected_path="$worktrees_dir/$current_branch"
      if [ "$current_path" = "$expected_path" ]; then
        printf "%s\t%s\n" "$current_branch" "$current_path"
      else
        printf "%s\t%s\t! path mismatch (likely wrong branch is checked out)\n" "$current_branch" "$current_path"
      fi
```

with:

```sh
      local current_branch=$(echo "$line" | sed 's|^branch refs/heads/||')
      if path_matches_branch "$current_path" "$current_branch"; then
        printf "%s\t%s\n" "$current_branch" "$current_path"
      else
        printf "%s\t%s\t! path does not match branch (git checkout run inside?)\n" "$current_branch" "$current_path"
      fi
```

Note: `worktrees_dir` is still computed at the top of `cmd_list` (line 1129) but
is now unused there. Remove the line `local worktrees_dir=$(get_worktrees_dir)`
at line 1129 to avoid a dead assignment.

- [ ] **Step 5: Run the list tests to verify they pass**

Run:
```bash
./test/git-ht-test.sh 2>&1 | grep -i "path does not match branch\|matching name is not flagged\|Properly named worktree"
```
Expected: all three PASS (✓). No `path mismatch` wording remains.

- [ ] **Step 6: Commit**

```bash
git add bin/git-ht test/git-ht-test.sh
git commit -m "feat(git-ht): add path_matches_branch helper; list flags by branch not location

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Remove `validate_worktree_dir` and make `remove` use the real path

**Files:**
- Modify: `bin/git-ht` (delete `validate_worktree_dir` ~lines 410–430; `cmd_checkout` ~line 665; `cmd_remove` ~lines 781–785)
- Modify: `test/git-ht-test.sh` (Remove test group, ~line 744)

- [ ] **Step 1: Write a failing test — `remove` works on an off-location worktree**

In `test/git-ht-test.sh`, at the END of the "Remove - Basic" test group (just
before the "Remove - Auto Branch Cleanup" group begins at line 758), add:

```sh
  # Remove must work on a worktree that lives OUTSIDE worktreesDir, as long as
  # a worktree exists for the named branch. remove is non-destructive and the
  # branch was named explicitly, so location is irrelevant.
  git worktree add "$SANDBOX/other-location/rm-offloc" -b rm-offloc
  assert_success "git_ht remove rm-offloc" "Remove works on an off-location worktree"
  assert_file_not_exists "$SANDBOX/other-location/rm-offloc" "Off-location worktree removed"
  git branch -D rm-offloc 2>/dev/null || true
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
./test/git-ht-test.sh 2>&1 | grep -i "off-location worktree"
```
Expected: FAIL on "Remove works on an off-location worktree" — today
`validate_worktree_dir` rejects it (path ≠ `<worktreesDir>/rm-offloc`), and
`cmd_remove` would target the wrong reconstructed path anyway.

- [ ] **Step 3: Delete the `validate_worktree_dir` function**

In `bin/git-ht`, delete the entire function and its leading comment at lines
410–430:

```sh
# Validate that a worktree's actual path matches the expected path from config
validate_worktree_dir() {
  local branch="$1"
  local actual_path=$(get_worktree_path_for_branch "$branch" || true)

  if [ -z "$actual_path" ]; then
    printf "Error: No worktree found for branch '%s'\n" "$branch" >&2
    exit 1
  fi

  local expected_path="$(get_worktrees_dir)/$branch"

  if [ "$actual_path" != "$expected_path" ]; then
    printf "Error: Worktree directory mismatch for '%s'\n" "$branch" >&2
    printf "  Expected: %s\n" "$expected_path" >&2
    printf "  Actual:   %s\n" "$actual_path" >&2
    printf "\nThis can happen if 'git checkout' was run inside the worktree.\n" >&2
    printf "git-ht cannot reliably operate on this worktree.\n" >&2
    exit 1
  fi
}
```

- [ ] **Step 4: Remove the `validate_worktree_dir` call in `cmd_checkout`**

In `cmd_checkout`, the existing-worktree branch currently reads (lines 663–666):

```sh
  if [ -n "$existing_wt_path" ]; then
    # Worktree exists — validate directory and run exec
    validate_worktree_dir "$branch"

    if [ -n "$base" ]; then
```

Change to:

```sh
  if [ -n "$existing_wt_path" ]; then
    # Worktree exists — run exec against its real path
    if [ -n "$base" ]; then
```

(Delete the `validate_worktree_dir "$branch"` line and the blank line after it,
and update the comment.)

- [ ] **Step 5: Make `cmd_remove` resolve and use the real worktree path**

In `cmd_remove`, replace lines 781–785:

```sh
  # Validate worktree directory
  validate_worktree_dir "$name"

  local worktrees_dir=$(get_worktrees_dir)
  local worktree_path="$worktrees_dir/$name"
```

with:

```sh
  # Resolve the worktree's real tracked path (location-agnostic). remove is
  # non-destructive, so there is no path/branch gate here.
  local worktree_path=$(get_worktree_path_for_branch "$name" || true)
  if [ -z "$worktree_path" ]; then
    printf "Error: No worktree found for branch '%s'\n" "$name" >&2
    exit 1
  fi
```

- [ ] **Step 5b: Remove the `validate_worktree_dir` call site in `cmd_destroy`**

`cmd_destroy` still calls the now-deleted function; leaving it would break the
suite. Resolve the real path here too (Task 3 layers the gates on top of this).
In `cmd_destroy`, replace lines 866–870:

```sh
  # Validate worktree directory
  validate_worktree_dir "$name"

  local worktrees_dir=$(get_worktrees_dir)
  local worktree_path="$worktrees_dir/$name"
```

with:

```sh
  # Resolve the worktree's real tracked path (location-agnostic).
  local worktree_path=$(get_worktree_path_for_branch "$name" || true)
  if [ -z "$worktree_path" ]; then
    printf "Error: No worktree found for branch '%s'\n" "$name" >&2
    exit 1
  fi
```

Note: at this point `destroy` still passes `--force` through to
`git worktree remove` and relies on git's own dirty check (the pre-existing
"Regular destroy fails on dirty worktree" test still passes because
`git worktree remove` refuses a dirty tree). Task 3 replaces this with the
explicit dual-gate. Because we resolve the real path now, the existing destroy
tests continue to pass in this intermediate state.

- [ ] **Step 6: Run the full suite to verify remove passes and nothing regressed**

Run:
```bash
./test/git-ht-test.sh
```
Expected: exits 0, "All tests passed!". "Remove works on an off-location
worktree" and "Off-location worktree removed" now PASS; all existing
remove/checkout tests still PASS; and the existing destroy tests still PASS
because Step 5b kept `cmd_destroy` working (real path + git's own dirty
refusal). The suite is green.

- [ ] **Step 7: Commit**

```bash
git add bin/git-ht test/git-ht-test.sh
git commit -m "feat(git-ht): drop location gate; act on real worktree path

Delete validate_worktree_dir and its checkout/remove/destroy call sites;
remove and destroy now resolve the worktree's real tracked path instead of
reconstructing it from config.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Gate `destroy` on path/branch mismatch and dirty worktree

**Files:**
- Modify: `bin/git-ht` (`cmd_destroy` ~lines 855–892)
- Modify: `test/git-ht-test.sh` (Destroy test groups, ~lines 824–852)

`destroy` deletes local + remote branches, so it keeps a gate — but a
location-agnostic one. Without `--force` it checks BOTH path/branch mismatch
(unless `happy-trees.failDestroyOnPathMismatch` is `false`, default `true`) AND
a dirty working directory, reporting every applicable reason at once before
acting. `--force` overrides both.

- [ ] **Step 1: Write failing tests for the destroy gates**

In `test/git-ht-test.sh`, at the END of the "Destroy - Basic" test group (after
line 852, before the "Destroy - default branch protection" group at line 855),
add:

```sh
  # --- Destroy path/branch mismatch gate ---------------------------------
  # An off-purpose worktree (path does not reflect its branch) must NOT be
  # destroyed without --force, and the error must explain why + name the config.
  git worktree add "$SANDBOX/other-location/wrong-dest" -b destroy-mismatch
  assert_failure "git_ht destroy destroy-mismatch" "Destroy blocks on path/branch mismatch"
  assert_output_contains "git_ht destroy destroy-mismatch" "path usually indicates the branch" "Mismatch message explains why"
  assert_output_contains "git_ht destroy destroy-mismatch" "failDestroyOnPathMismatch" "Mismatch message names the config to disable it"
  # --force overrides the mismatch gate.
  assert_success "git_ht destroy destroy-mismatch --force" "Force destroy overrides mismatch gate"
  assert_file_not_exists "$SANDBOX/other-location/wrong-dest" "Mismatched worktree removed by force destroy"
  git branch -D destroy-mismatch 2>/dev/null || true

  # --- Destroy reports BOTH mismatch and dirty together ------------------
  git worktree add "$SANDBOX/other-location/wrong-dirty" -b destroy-both
  echo "dirty" > "$SANDBOX/other-location/wrong-dirty/dirty.txt"
  git -C "$SANDBOX/other-location/wrong-dirty" add dirty.txt
  assert_output_contains "git_ht destroy destroy-both" "path usually indicates the branch" "Combined message reports mismatch"
  assert_output_contains "git_ht destroy destroy-both" "uncommitted changes" "Combined message reports dirty worktree"
  assert_success "git_ht destroy destroy-both --force" "Force destroy overrides both gates"
  git branch -D destroy-both 2>/dev/null || true

  # --- failDestroyOnPathMismatch=false disables ONLY the mismatch gate ----
  git config happy-trees.failDestroyOnPathMismatch false
  # Clean mismatched worktree: destroy succeeds without --force.
  git worktree add "$SANDBOX/other-location/wrong-clean" -b destroy-cfg-clean
  assert_success "git_ht destroy destroy-cfg-clean" "Config-disabled mismatch gate lets clean destroy proceed"
  git branch -D destroy-cfg-clean 2>/dev/null || true
  # Dirty mismatched worktree: still blocked (config disables mismatch, not dirty).
  git worktree add "$SANDBOX/other-location/wrong-cfgdirty" -b destroy-cfg-dirty
  echo "dirty" > "$SANDBOX/other-location/wrong-cfgdirty/dirty.txt"
  git -C "$SANDBOX/other-location/wrong-cfgdirty" add dirty.txt
  assert_failure "git_ht destroy destroy-cfg-dirty" "Dirty worktree still blocks destroy when mismatch gate is config-disabled"
  assert_success "git_ht destroy destroy-cfg-dirty --force" "Force destroy proceeds on dirty when mismatch gate is config-disabled"
  git branch -D destroy-cfg-dirty 2>/dev/null || true
  git config --unset happy-trees.failDestroyOnPathMismatch

  # --- Off-location but name-matching worktree destroys cleanly -----------
  git worktree add "$SANDBOX/other-location/dest-ok" -b dest-ok
  assert_success "git_ht destroy dest-ok" "Off-location name-matching worktree destroys with no gate tripped"
  git branch -D dest-ok 2>/dev/null || true
```

- [ ] **Step 2: Run the destroy tests to verify they fail**

Run:
```bash
./test/git-ht-test.sh 2>&1 | grep -i "mismatch\|both gates\|config-disabled\|no gate tripped"
```
Expected: multiple FAILs — after Task 2, `cmd_destroy` resolves the real path
and relies on git's own dirty refusal, but it has no path/branch mismatch gate,
no custom mismatch/dirty messages, and no `failDestroyOnPathMismatch` handling.
So the mismatch, combined-message, config, and "no gate tripped" assertions all
fail. The suite exits non-zero.

- [ ] **Step 3: Rewrite the middle of `cmd_destroy`**

In `bin/git-ht`, `cmd_destroy()`, the block AS LEFT BY TASK 2 reads (the
default-branch check, the real-path resolution added in Task 2 Step 5b, then the
removal):

```sh
  # Check default branch protection
  if is_default_branch "$name"; then
    printf "Error: Cannot destroy the default branch '%s'\n" "$name" >&2
    exit 1
  fi

  # Resolve the worktree's real tracked path (location-agnostic).
  local worktree_path=$(get_worktree_path_for_branch "$name" || true)
  if [ -z "$worktree_path" ]; then
    printf "Error: No worktree found for branch '%s'\n" "$name" >&2
    exit 1
  fi

  # Remove the worktree
  if [ $force -eq 1 ]; then
    git worktree remove --force "$worktree_path"
  else
    git worktree remove "$worktree_path"
  fi
```

Replace it with:

```sh
  # Check default branch protection
  if is_default_branch "$name"; then
    printf "Error: Cannot destroy the default branch '%s'\n" "$name" >&2
    exit 1
  fi

  # Resolve the worktree's real tracked path (location-agnostic).
  local worktree_path=$(get_worktree_path_for_branch "$name" || true)
  if [ -z "$worktree_path" ]; then
    printf "Error: No worktree found for branch '%s'\n" "$name" >&2
    exit 1
  fi

  # Without --force, evaluate BOTH gates up front and report every applicable
  # reason together, because --force overrides all of them. Take no action if
  # any gate trips.
  if [ $force -eq 0 ]; then
    local blocked=0

    # Gate 1: path/branch mismatch (unless disabled by config; default on).
    local fail_on_mismatch=$(get_config "happy-trees.failDestroyOnPathMismatch" "true")
    if [ "$fail_on_mismatch" != "false" ] && ! path_matches_branch "$worktree_path" "$name"; then
      blocked=1
      printf "Error: Refusing to destroy '%s'\n" "$name" >&2
      printf "  The worktree's path usually indicates the branch it contains, but this one\n" >&2
      printf "  does not. This suggests that the worktree was created for a purpose other\n" >&2
      printf "  than hosting its current branch.\n" >&2
      printf "    Path:   %s\n" "$worktree_path" >&2
      printf "    Branch: %s\n" "$name" >&2
      printf "  You may disable this check with:\n" >&2
      printf "    git config happy-trees.failDestroyOnPathMismatch false\n" >&2
    fi

    # Gate 2: dirty working directory.
    if [ -n "$(git -C "$worktree_path" status --porcelain 2>/dev/null)" ]; then
      blocked=1
      printf "Error: Worktree '%s' has uncommitted changes.\n" "$name" >&2
    fi

    if [ $blocked -eq 1 ]; then
      printf "\nPass the --force flag to continue (this overrides all of the above).\n" >&2
      exit 1
    fi
  fi

  # Remove the worktree (--force also overrides git's own dirty check).
  if [ $force -eq 1 ]; then
    git worktree remove --force "$worktree_path"
  else
    git worktree remove "$worktree_path"
  fi
```

- [ ] **Step 4: Run the full suite to verify destroy passes and nothing regressed**

Run:
```bash
./test/git-ht-test.sh
```
Expected: exits 0, "All tests passed!". The existing "Regular destroy fails on
dirty worktree" / "Force destroy succeeds on dirty worktree" tests (lines
849–850) still PASS (they use an on-location worktree — mismatch gate does not
fire, dirty gate does), and all new destroy tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/git-ht test/git-ht-test.sh
git commit -m "feat(git-ht): gate destroy on path/branch mismatch and dirty tree

Both gates checked up front and reported together; --force overrides both.
Mismatch gate is disablable via happy-trees.failDestroyOnPathMismatch.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Update help text and documentation

**Files:**
- Modify: `bin/git-ht` (`show_help` — `git ht list` section ~lines 44–50, `git ht destroy` section ~lines 100–114, Configuration section ~lines 142–181, Technical notes ~lines 183–196)

No test changes. Verified by the existing help assertions plus manual read.

- [ ] **Step 1: Update the `git ht list` help description**

In `show_help()`, replace lines 44–50:

```
git ht list:
  List all linked worktrees and flag any that are incompatible with git-ht.

  Worktrees whose directory path does not match the expected naming convention
  (<worktrees-dir>/<branch>) are flagged — this typically means 'git checkout'
  was run inside the worktree to switch branches. Detached HEAD worktrees are
  also flagged since they have no branch association.
```

with:

```
git ht list:
  List all linked worktrees and flag any whose identity is unclear.

  A worktree's path normally ends with the name of the branch it was created
  for. When the trailing path segments do NOT match the checked-out branch, the
  worktree is flagged — this typically means 'git checkout' was run inside it to
  switch branches, so the path no longer reflects its contents. The location of
  the worktree does not matter; only whether the path reflects the branch.
  Detached HEAD worktrees are also flagged since they have no branch association.
```

- [ ] **Step 2: Update the `git ht destroy` help section**

In `show_help()`, replace the destroy section at lines 100–114:

```
git ht destroy [branch] [options]:
  Remove a worktree and delete both the local and remote branches associated
  with it if they exist.

  Cannot be run on the default branch (local or remote).

  If no [branch] is provided, git-ht will prompt interactively (requires fzf)
  to select from all currently registered worktrees. The default branch is
  excluded from the interactive list.

  Note: If you run this from within the worktree being destroyed, your shell
  will be left in a stale directory. You will need to cd elsewhere manually.

  Options:
    --force                    Remove even if working directory is dirty
```

with:

```
git ht destroy [branch] [options]:
  Remove a worktree and delete both the local and remote branches associated
  with it if they exist.

  Cannot be run on the default branch (local or remote).

  Before acting, destroy refuses (without --force) if either:
    - the worktree's path does not reflect its branch (see 'git ht list'),
      unless disabled via happy-trees.failDestroyOnPathMismatch, or
    - the worktree has uncommitted changes.
  Both conditions are reported together, and --force overrides both.

  If no [branch] is provided, git-ht will prompt interactively (requires fzf)
  to select from all currently registered worktrees. The default branch is
  excluded from the interactive list.

  Note: If you run this from within the worktree being destroyed, your shell
  will be left in a stale directory. You will need to cd elsewhere manually.

  Options:
    --force                    Destroy even on a path/branch mismatch or a dirty
                               working directory
```

- [ ] **Step 3: Document the new config key in the Configuration section**

In `show_help()`, find the end of the `happy-trees.setupLocation` config block
(the examples ending at line 179, right before the line
`  Use --global flag to set config globally...` at line 181). Insert a new
config block immediately after the setupLocation examples and before that
`Use --global` line:

```

    git config happy-trees.failDestroyOnPathMismatch <true|false>
      When true (default), 'git ht destroy' refuses to act (without --force) on
      a worktree whose path does not reflect its branch. Set to false to allow
      destroy to proceed on such worktrees without --force. Does not affect the
      dirty-working-directory check, and does not affect 'git ht list' flagging.
      Example: git config happy-trees.failDestroyOnPathMismatch false
```

- [ ] **Step 4: Replace the stale "Directory validation" technical note**

In `show_help()`, the Technical notes block at lines 183–196 currently reads:

```
Technical notes:
  Directory validation:
    All commands verify that a worktree's actual directory matches the expected
    path derived from worktreesDir config. If a mismatch is detected, the
    command will fail. This can happen if you manually run 'git checkout' inside
    a worktree to switch its branch — git-ht can no longer reliably determine
    the worktree's identity and will refuse to operate on it.

  Changing worktreesDir:
    If you change the happy-trees.worktreesDir setting, existing worktrees
    created under the old directory will no longer be found by git-ht. You will
    need to remove them manually with 'git worktree remove' before recreating
    them under the new location.
```

Replace the "Directory validation" note (keep "Changing worktreesDir" as-is):

```
Technical notes:
  Worktree identity:
    git-ht identifies worktrees by branch name and operates on whatever path
    git has recorded for that branch, so worktrees may live anywhere — the
    worktreesDir setting is only the default location for NEW worktrees. As a
    convenience, 'git ht list' flags any worktree whose path no longer reflects
    its branch, and 'git ht destroy' refuses such worktrees without --force
    (see happy-trees.failDestroyOnPathMismatch).

  Changing worktreesDir:
    If you change the happy-trees.worktreesDir setting, existing worktrees
    created under the old directory will no longer be found by git-ht. You will
    need to remove them manually with 'git worktree remove' before recreating
    them under the new location.
```

Note: the "Changing worktreesDir" paragraph is now partly inaccurate (git-ht
finds worktrees by branch regardless of location), but it concerns a different
setting and is out of scope for this change — leave it untouched.

- [ ] **Step 5: Verify help still renders and existing help assertions pass**

Run:
```bash
./bin/git-ht help | sed -n '/git ht destroy/,/Options:/p'
```
Expected: shows the new destroy section including the "refuses (without --force)"
text.

Run:
```bash
./test/git-ht-test.sh 2>&1 | grep -i "help\|All tests passed"
```
Expected: all help-related assertions PASS; suite exits 0.

- [ ] **Step 6: Commit**

```bash
git add bin/git-ht
git commit -m "docs(git-ht): update help for location-agnostic list/destroy + new config

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Full-suite verification across all repo modes

**Files:** none (verification only)

- [ ] **Step 1: Run the entire git-ht suite**

Run:
```bash
./test/git-ht-test.sh
```
Expected: The four passes (`normal`, `bare`, `normal repo no remote`,
`bare repo no remote`) all run, and the summary prints "All tests passed!" with
`Tests failed: 0`. Exit code 0.

- [ ] **Step 2: Run the aggregate test runner**

Run:
```bash
./test/run-tests.sh
```
Expected: both `git-ht-test.sh` and `killport-test.sh` pass; exit 0.

- [ ] **Step 3: Confirm no stale references remain**

Run:
```bash
grep -n "validate_worktree_dir\|path mismatch\|Worktree directory mismatch" bin/git-ht
```
Expected: no output (all removed).

- [ ] **Step 4: Final commit if anything was adjusted**

If steps surfaced fixes, commit them:
```bash
git add -A
git commit -m "test(git-ht): verify location-restriction removal across repo modes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
If nothing changed, skip this step.

---

## Self-review notes (for the implementer's awareness)

- **Spec coverage:** Helper (Task 1) · list flag reword + location-agnostic
  (Task 1) · delete gate + call sites (Task 2) · remove real-path (Task 2) ·
  checkout drop-validate (Task 2) · destroy dual-gate + wording + config +
  --force-both (Task 3) · off-location name-matching remove/destroy succeed
  (Tasks 2 & 3) · config disables mismatch only, dirty still blocks (Task 3) ·
  help/config/technical-note docs (Task 4). All spec sections mapped.
- **Cross-task naming:** `path_matches_branch <path> <branch>` (returns 0/1) is
  defined in Task 1 and reused verbatim in `cmd_list` (Task 1) and `cmd_destroy`
  (Task 3). Config key `happy-trees.failDestroyOnPathMismatch` (default via
  `get_config ... "true"`, compared `!= "false"`) is consistent across Task 3
  code, Task 3 tests, and Task 4 docs.
- **Green between every commit:** Task 2 deletes `validate_worktree_dir` and
  ALL THREE of its call sites in the same task — checkout (Step 4), remove
  (Step 5), and destroy (Step 5b) — so no task ever leaves a call to a deleted
  function. After Task 2, `cmd_destroy` still works (real path + git's own dirty
  refusal), so the pre-existing destroy tests stay green; Task 3 then layers the
  explicit mismatch/dirty gates on top. Every task's final commit is on a green
  suite.
```
