# git-ht v2 Design

## Summary

Rewrite git-ht command layer to match the updated documentation. Keep existing utility functions (get_config, get_repo_root, expand_path_tokens, etc.) and setup command logic. Replace `create` with `checkout`/`co`, simplify `remove`, add `destroy`, add interactive fzf selectors, add directory validation, rename `openWith` config to `exec`.

## Decisions

- **Approach:** Layered rewrite (Option C) -- keep proven utility functions, rewrite command functions and dispatcher.
- **fzf:** Hard requirement for interactive mode only. Commands still work without fzf if all arguments are provided.
- **exec:** Always runs on both create and switch, including config default. `-e` overrides config, `-E` skips it.
- **SHA comparison for remove:** Strict match using locally available refs, no auto-fetch.
- **Default branch protection (destroy):** Checks both local and remote default branch.
- **Directory validation:** Every command that operates on a named worktree validates path matches expected `<worktrees_dir>/<branch>`.
- **No cd behavior:** Script cannot change caller's shell directory. Users can write their own shell wrapper or use `--exec`.
- **Setup command:** No longer accepts branch-name argument. Must be run from inside a worktree.
- **Config rename:** `happy-trees.openWith` -> `happy-trees.exec` (update gitconfig too).

## Architecture

### Kept as-is
- `get_config()`, `get_repo_root()`, `get_repo_name()`, `get_remote_default_branch()`
- `branch_exists_local()`, `branch_exists_remote()`, `is_current_branch()`
- `expand_path_tokens()`, `is_linked_worktree()`, `get_worktree_path_for_branch()`
- `get_worktrees_dir()` (remove the custom_dir parameter since `-d` flag is gone)
- `cmd_setup()` (remove branch-name argument support)

### New helper functions
- `require_fzf()` -- check fzf is available, error with message if not
- `validate_worktree_dir(branch)` -- verify worktree path for branch matches `<worktrees_dir>/<branch>`
- `is_default_branch(branch)` -- check if branch is the default (local or remote)
- `run_exec(worktree_path, exec_cmd, no_exec)` -- handle exec logic (config default, override, skip)
- `select_worktree_interactive(exclude_default)` -- fzf selector for existing worktrees
- `select_branch_interactive()` -- fzf selector for checkout (worktrees first, then branches by recency)

### New/rewritten commands
- `cmd_checkout()` -- replaces `cmd_create`. Handles: interactive selection, existing worktree (exec only), create from existing branch, create new branch. Runs setup + exec.
- `cmd_remove()` -- rewritten. Simplified flags (just `--force`). Auto-deletes local branch if remote SHA matches. Interactive selector.
- `cmd_destroy()` -- new. Removes worktree, deletes local branch, deletes remote branch. Default branch protection. Interactive selector.

### Dispatcher changes
- Add `checkout`/`co` -> `cmd_checkout`
- Add `destroy` -> `cmd_destroy`
- Remove `create` from public commands

### Config changes
- `happy-trees.openWith` -> `happy-trees.exec` in gitconfig
