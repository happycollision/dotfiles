# git-ht: Remove the location gate; add a path-vs-branch check to `destroy`

**Date:** 2026-07-28
**File under change:** `bin/git-ht` (plus `test/git-ht-test.sh`)

## Problem

`git-ht` currently treats the configured `happy-trees.worktreesDir` as a hard
operational gate. The helper `validate_worktree_dir()` fails any
`checkout`/`remove`/`destroy` on a worktree whose path is not exactly
`<worktreesDir>/<branch>`. It is called from `cmd_checkout` (existing-worktree
branch), `cmd_remove`, and `cmd_destroy`.

The configured location is a sensible **default for where to create** worktrees,
but it should not gate operations on worktrees that legitimately live elsewhere.
Two consequences today:

1. A worktree created outside `worktreesDir` (perfectly valid git) cannot be
   operated on by git-ht at all.
2. `cmd_remove` and `cmd_destroy` do not just gate on the location — they
   **reconstruct** the target path as `<worktreesDir>/<branch>` and hand that to
   `git worktree remove`, rather than using the path git already tracks. So even
   without the gate they would target the wrong (nonexistent) path for an
   off-location worktree.

## Core idea

The config location is a **creation default**, not an operational gate. Remove
the hard `validate_worktree_dir` gate everywhere. Replace the underlying concept
of "matches the configured location" with a location-agnostic one: **does the
worktree's path reflect the branch it contains?** — i.e. the worktree path ends
with the full branch name (trailing path segments).

This new concept is applied differently per command:

| Command    | Path-vs-branch check | Rationale |
|------------|----------------------|-----------|
| `checkout` | none                 | Only creation uses the default location; operating on an existing worktree acts on its real path. |
| `remove`   | none                 | Non-destructive (worktree removal + *conditional* local-branch cleanup); the branch was named explicitly, so intent is clear. |
| `destroy`  | **gate** (overridable) | Deletes local **and** remote branches; a worktree whose path does not reflect its branch was likely repurposed via `git checkout`, so stop and confirm. |
| `list`     | informational flag   | Never blocks; surfaces likely-repurposed worktrees to the user. |

## Shared helper: `path_matches_branch`

Add one helper so the rule is defined in exactly one place:

```
path_matches_branch <worktree_path> <branch>
  → success (0) if <worktree_path> ends with "/<branch>"
  → failure (1) otherwise
```

Matching is on **trailing path segments**, i.e. the path must end with the full
branch name. This is exactly what git-ht produces on creation:

- Branch `my-feature` → created at `<worktreesDir>/my-feature`; a path ending
  `.../my-feature` matches.
- Branch `feature/login` → created at `<worktreesDir>/feature/login`; the path
  must end `.../feature/login` (both segments), not merely `.../login`.

Examples:

| Worktree path                          | Branch            | Match? |
|----------------------------------------|-------------------|--------|
| `/anywhere/my-feature`                 | `my-feature`      | yes    |
| `/repo.worktrees/my-feature`           | `my-feature`      | yes    |
| `/tmp/custom/feature/login`            | `feature/login`   | yes    |
| `/repo.worktrees/wrong-path`           | `list-mismatch`   | no     |
| `/tmp/scratch`                         | `my-feature`      | no     |
| `/tmp/custom/login`                    | `feature/login`   | no     |

Implementation note: compare against a `/`-prefixed branch to avoid a false
positive where a branch is a *suffix substring* of the final segment (e.g. path
`.../my-feature` must not match branch `feature`). Anchoring on `/<branch>` at
end-of-string handles this.

## Changes to `bin/git-ht`

### 1. Delete `validate_worktree_dir()` (lines 411–430) and all three call sites
- `cmd_checkout` line 665
- `cmd_remove` line 782
- `cmd_destroy` line 867

### 2. `cmd_checkout`
Remove the `validate_worktree_dir "$branch"` call in the existing-worktree
branch. The code already holds `existing_wt_path` from
`get_worktree_path_for_branch` (line 662) and runs exec against it. No other
change. The `[base]`-not-valid error and the "next steps" output are unchanged.

### 3. `cmd_remove`
Stop reconstructing the path from config. Currently:

```
local worktrees_dir=$(get_worktrees_dir)
local worktree_path="$worktrees_dir/$name"
```

Replace with resolution of the **real** path git tracks:

```
local worktree_path=$(get_worktree_path_for_branch "$name" || true)
if [ -z "$worktree_path" ]; then
  printf "Error: No worktree found for branch '%s'\n" "$name" >&2
  exit 1
fi
```

No path-vs-branch gate. `git worktree remove` then operates on git's own
recorded path (location-agnostic). `--force` continues to mean dirty-override
only (passed through to `git worktree remove --force`). The conditional
local-branch cleanup block that follows is unchanged.

### 4. `cmd_destroy`
Resolve the real path the same way as `cmd_remove` (error cleanly if no worktree
exists for the branch). Keep the existing default-branch protection
(`is_default_branch`), which runs first.

When `--force` is **not** set, evaluate **both** gates up front, before removing
anything, and report all applicable reasons in a single message:

- **Path/branch mismatch** — flagged when `path_matches_branch "$worktree_path"
  "$name"` fails, **unless** `happy-trees.failDestroyOnPathMismatch` is `false`
  (default `true`).
- **Dirty working directory** — flagged when `git -C "$worktree_path" status
  --porcelain` produces any output.

If either (or both) applies, print one message that lists every applicable
reason, notes that `--force` overrides all of them, then exit non-zero **without
taking any action**. The mismatch reason uses this exact wording:

> The worktree's path usually indicates the branch it contains, but this one
> does not. This suggests that the worktree was created for a purpose other than
> hosting its current branch. Pass the `--force` flag to continue. You may
> disable this check with `git config happy-trees.failDestroyOnPathMismatch false`

When a dirty working directory is *also* present, the message must additionally
state that the worktree has uncommitted changes and that `--force` will override
that as well — so the user is not surprised that `--force` blows past a dirty
tree in addition to the mismatch.

With `--force`, skip **both** gates (this matches today's behavior for the dirty
check and extends it to the mismatch check). The subsequent worktree removal,
local-branch delete, and remote-branch delete are unchanged.

Interaction note: `failDestroyOnPathMismatch=false` disables **only** the
mismatch gate. A dirty working directory still blocks `destroy` without
`--force`.

### 5. `cmd_list` (lines 1146–1150)
Replace the location-comparison flag with the shared helper. Flag a worktree
when `path_matches_branch` fails — regardless of parent directory. The
detached-HEAD branch of the loop is unchanged. Reword the flag from:

```
! path mismatch (likely wrong branch is checked out)
```

to:

```
! path does not match branch (git checkout run inside?)
```

`list` always flags informationally and **ignores**
`failDestroyOnPathMismatch` (that config governs only the destroy gate).

### 6. Help text (`show_help`)
- Remove the "Directory validation" technical note (lines 183–189) describing
  the removed hard-fail gate.
- Update the `git ht list` description (lines 44–50) to describe the new
  branch-vs-path flagging (a worktree whose path does not end with its branch
  name is flagged; detached HEAD is flagged).
- In the `git ht destroy` section, document that `--force` overrides **both** a
  path/branch mismatch and a dirty working directory.
- In the Configuration section, document
  `happy-trees.failDestroyOnPathMismatch` (default `true`; set `false` to let
  `destroy` proceed on a path/branch mismatch without `--force`).

## Tests (`test/git-ht-test.sh`)

- **Existing** mismatch `list` test (lines 336–340): the worktree at
  `other-location/wrong-path` on branch `list-mismatch-branch` still fails the
  new rule (tail `wrong-path` ≠ branch), so it is still flagged. Update the
  comment and the asserted string from `path mismatch` to the new wording
  (`path does not match branch`).
- **Add** — off-location, name-matching worktree: create a worktree at a custom
  location whose trailing path equals its branch (e.g.
  `$SANDBOX/other-location/custom-ok` on branch `custom-ok`). Assert `list` does
  **not** flag it; assert `git ht remove custom-ok` succeeds; (separately)
  assert `git ht destroy` on such a worktree succeeds with no gate tripped.
- **Add** — destroy blocked by mismatch: an off-purpose worktree (tail ≠ branch)
  destroyed without `--force` fails; output contains the mismatch explanation
  and the `failDestroyOnPathMismatch` config hint. With `--force`, it succeeds.
- **Add** — destroy blocked by mismatch **and** dirty: a mismatched worktree
  with uncommitted changes, destroyed without `--force`, produces a message
  listing **both** reasons.
- **Add** — `failDestroyOnPathMismatch false`: a mismatched (but clean) worktree
  can be destroyed without `--force`; a mismatched **and dirty** worktree still
  blocks without `--force` (config disables only the mismatch gate).

## Out of scope

- `worktreesDir` config semantics — it remains the creation default.
- Interactive selectors (`checkout`/`remove`/`destroy` fzf entry building).
- `setup` command.
- `cmd_remove`'s conditional local-branch cleanup logic (remote-SHA comparison).
