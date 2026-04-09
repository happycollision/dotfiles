# git-ht v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite git-ht command layer to match updated documentation — new checkout/destroy commands, simplified remove, interactive fzf selectors, directory validation, config rename.

**Architecture:** Keep existing utility functions (lines 218-378 of bin/git-ht). Rewrite command functions and dispatcher. Add new helpers for fzf, validation, exec, and default branch detection.

**Tech Stack:** POSIX shell (#!/bin/sh), fzf for interactive selection, git plumbing commands.

---

### Task 1: Simplify `get_worktrees_dir` — remove custom_dir parameter

The `-d`/`--worktrees-dir` flag is removed from the public API. Simplify `get_worktrees_dir()` to not accept a parameter.

**Files:**
- Modify: `bin/git-ht:354-379`

**Step 1: Simplify `get_worktrees_dir`**

Replace the function at lines 354-379 with:

```sh
# Get worktrees directory path (absolute)
get_worktrees_dir() {
  local repo_root=$(get_repo_root)
  local result_dir=""

  result_dir=$(get_config "happy-trees.worktreesDir" "<repo_root>/../<repo_name>.worktrees")

  # Expand tokens
  result_dir=$(expand_path_tokens "$result_dir")

  # Make absolute if relative
  if [ "${result_dir#/}" = "$result_dir" ]; then
    result_dir="$repo_root/$result_dir"
  fi

  echo "$result_dir"
}
```

**Step 2: Verify no callers pass an argument**

Run: `grep -n 'get_worktrees_dir' bin/git-ht`
Expected: Only the function definition and calls with no arguments (callers will be rewritten in later tasks).

**Step 3: Commit**

```bash
git add bin/git-ht
git commit -m "refactor(git-ht): simplify get_worktrees_dir, remove custom_dir param"
```

---

### Task 2: Simplify `cmd_setup` — remove branch-name argument

Setup must now be run from inside a worktree. Remove the branch-name positional argument.

**Files:**
- Modify: `bin/git-ht:618-869` (cmd_setup function)

**Step 1: Rewrite cmd_setup**

Replace the entire `cmd_setup` function with:

```sh
# Setup subcommand
cmd_setup() {
  local init_mode=0
  local init_path=""

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --init)
        init_mode=1
        shift
        # Check if next argument is a path (not another flag and not empty)
        if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
          init_path="$1"
          shift
        fi
        ;;
      -*)
        printf "Error: Unknown option: %s\n" "$1" >&2
        printf "Usage: git ht setup [--init [path]]\n" >&2
        exit 1
        ;;
      *)
        printf "Error: Unexpected argument: %s\n" "$1" >&2
        printf "Usage: git ht setup [--init [path]]\n" >&2
        exit 1
        ;;
    esac
  done

  # Init mode: Create template setup script (keep existing logic unchanged)
  if [ $init_mode -eq 1 ]; then
    local repo_root=$(get_repo_root)
    local setup_script=""
    local config_value=""
    local is_shell_script=1

    # Check if setupLocation is already configured
    local existing_config=$(get_config "happy-trees.setupLocation" "")
    if [ -n "$existing_config" ]; then
      printf "Error: Setup location is already configured: %s\n" "$existing_config" >&2
      printf "\nTo reconfigure, first unset the existing config:\n" >&2
      printf "  git config --unset happy-trees.setupLocation\n" >&2
      printf "\nThen run 'git ht setup --init' again.\n" >&2
      exit 1
    fi

    # Determine script path and config value based on init_path
    if [ -z "$init_path" ]; then
      setup_script="$repo_root/setup-worktree.sh"
      config_value="<repo_root>/setup-worktree.sh"
    elif [ "${init_path#/}" != "$init_path" ] || [ "${init_path#~}" != "$init_path" ]; then
      setup_script=$(echo "$init_path" | sed "s|^~|$HOME|")
      config_value="$init_path"
    else
      setup_script="$repo_root/$init_path"
      config_value="<repo_root>/$init_path"
    fi

    # Check if destination file already exists
    if [ -e "$setup_script" ]; then
      printf "Error: File already exists at destination: %s\n" "$setup_script" >&2
      printf "\nTo proceed, either:\n" >&2
      printf "  1. Choose a different path: git ht setup --init <new-path>\n" >&2
      printf "  2. Remove the existing file: rm %s\n" "$setup_script" >&2
      exit 1
    fi

    # Check file extension
    local extension="${setup_script##*.}"
    if [ "$extension" != "sh" ] && [ "$extension" != "$setup_script" ]; then
      is_shell_script=0
    fi

    # Create parent directory if needed
    local script_dir=$(dirname "$setup_script")
    if [ ! -d "$script_dir" ]; then
      mkdir -p "$script_dir"
    fi

    # Create the template script
    if [ $is_shell_script -eq 1 ]; then
      cat > "$setup_script" <<TMPL
#!/usr/bin/env bash
# Happy Trees - Worktree Setup Script
#
# No idea what this is? Look here:
# https://github.com/happycollision/dotfiles/blob/master/bin/git-ht
#
# This script is automatically run by 'git ht setup' (which itself is run at the
# end of 'git ht checkout ...') to configure new worktrees. It will receive two
# arguments when Happy Trees runs it:
#
# Arguments:
#   \$1 - Main repository root (absolute path)
#   \$2 - Target worktree root (absolute path)
#
# Git Config:
#   This script location was originally configured via:
#   git config happy-trees.setupLocation "$config_value"
#
#   If you rename or move this script, update the config:
#   git config happy-trees.setupLocation "<new-location>"
#
#   Supported tokens: <repo_root>, <repo_name>, <worktree_root>

REPO_ROOT="\$1"
WORKTREE_ROOT="\$2"

# Add your setup commands below:
# Examples:
#   cp "\$REPO_ROOT/.env.example" "\$WORKTREE_ROOT/.env"
#   cd "\$WORKTREE_ROOT" && npm install
#   cd "\$WORKTREE_ROOT" && bundle install
#
#
# CAUTION: Behavior regarding \`pwd\` is undefined until any command you run with
# might change it. If you need to be in a certain location, handle that
# explicitly.

echo "Setup complete for worktree: \$WORKTREE_ROOT"
TMPL
    else
      cat > "$setup_script" <<TMPL
# Worktree Setup Script
#
# NOTE: This file has a non-.sh extension (.$extension). You will need to:
#   1. Add the appropriate shebang for your language (e.g., #!/usr/bin/env node)
#   2. Translate the template below to your chosen language
#   3. Ensure the script can be executed with two positional arguments:
#      - \$1 / argv[1] - Main repository root (absolute path)
#      - \$2 / argv[2] - Target worktree root (absolute path)
#   4. Make the script executable: chmod +x $setup_script
#
# This script is automatically run by 'git ht setup' to configure new worktrees.
#
# Git Config:
#   This script location is configured via:
#   git config happy-trees.setupLocation "$config_value"
#
#   Supported tokens: <repo_root>, <repo_name>, <worktree_root>

# Example pseudocode:
# REPO_ROOT = argv[1]      // First positional argument
# WORKTREE_ROOT = argv[2]  // Second positional argument
#
# // Add your setup commands:
# // copy(REPO_ROOT + "/.env.example", WORKTREE_ROOT + "/.env")
# // exec("npm install", cwd=WORKTREE_ROOT)
#
# print("Setup complete for worktree: " + WORKTREE_ROOT)
TMPL
    fi

    # Make script executable (for shell scripts)
    if [ $is_shell_script -eq 1 ]; then
      chmod +x "$setup_script"
    fi

    # Set git config
    git config happy-trees.setupLocation "$config_value"

    printf "Setup script created: %s\n" "$setup_script"
    printf "Git config set: happy-trees.setupLocation = %s\n" "$config_value"

    if [ $is_shell_script -eq 0 ]; then
      printf "\n${YELLOW:-}Note:${NC:-} Non-.sh extension detected. Please:\n"
      printf "  1. Add the appropriate shebang for your language\n"
      printf "  2. Translate the template to your chosen language\n"
      printf "  3. Make the script executable: chmod +x %s\n" "$setup_script"
    fi

    printf "\nNext steps:\n"
    printf "1. Edit %s to add your setup commands\n" "$setup_script"
    printf "2. Run 'git ht setup' from inside a worktree\n"

    exit 0
  fi

  # Run mode: Execute setup script for a worktree
  local repo_root=$(get_repo_root)

  # Read setup location from config
  local setup_location=$(get_config "happy-trees.setupLocation" "")
  if [ -z "$setup_location" ]; then
    printf "Error: Setup location not configured\n" >&2
    printf "Run 'git ht setup --init' to create a setup script and configure it\n" >&2
    exit 1
  fi

  # Must be in a linked worktree
  if ! is_linked_worktree; then
    printf "Error: Not in a linked worktree\n" >&2
    printf "Run this command from inside a worktree.\n" >&2
    exit 1
  fi
  local worktree_root=$(git rev-parse --show-toplevel)

  # Expand tokens in setup location
  local setup_script=$(expand_path_tokens "$setup_location" "$worktree_root")

  # Check if script exists
  if [ ! -f "$setup_script" ]; then
    printf "Error: Setup script not found: %s\n" "$setup_script" >&2
    printf "Configured location: %s\n" "$setup_location" >&2
    exit 1
  fi

  # Check if script is executable
  if [ ! -x "$setup_script" ]; then
    printf "Error: Setup script is not executable: %s\n" "$setup_script" >&2
    printf "Run: chmod +x %s\n" "$setup_script" >&2
    exit 1
  fi

  # Execute the setup script
  printf "Running setup for worktree: %s\n" "$worktree_root"
  printf "Using setup script: %s\n\n" "$setup_script"

  if "$setup_script" "$repo_root" "$worktree_root"; then
    printf "\nSetup completed successfully\n"
    exit 0
  else
    printf "\nWarning: Setup script failed with exit code %d\n" $? >&2
    exit 1
  fi
}
```

Key changes: removed `branch_name` variable and its parsing/usage, updated error messages to remove branch-name references, changed "git ht create" to "git ht checkout" in template comment, updated next steps to remove branch-name option.

**Step 2: Commit**

```bash
git add bin/git-ht
git commit -m "refactor(git-ht): remove branch-name arg from setup, must run from worktree"
```

---

### Task 3: Add new helper functions

Add `require_fzf`, `validate_worktree_dir`, `is_default_branch`, and `run_exec` helpers. Insert these after the existing utility functions (after `get_worktrees_dir`, before the command functions).

**Files:**
- Modify: `bin/git-ht` — insert after `get_worktrees_dir()` function

**Step 1: Add `require_fzf`**

Insert after `get_worktrees_dir`:

```sh
# Check that fzf is available (required for interactive selection)
require_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf "Error: fzf is required for interactive selection\n" >&2
    printf "Install fzf or provide the branch name as an argument\n" >&2
    exit 1
  fi
}
```

**Step 2: Add `validate_worktree_dir`**

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

**Step 3: Add `is_default_branch`**

```sh
# Check if a branch name matches the default branch (local or remote)
is_default_branch() {
  local branch="$1"
  local default_ref=$(get_remote_default_branch)

  # default_ref might be "origin/main", "origin/master", "main", or "master"
  # Strip "origin/" prefix if present to get the bare branch name
  local default_name="${default_ref#origin/}"

  [ "$branch" = "$default_name" ]
}
```

**Step 4: Add `run_exec`**

```sh
# Run exec command with worktree path
# Args: worktree_path, exec_override, no_exec_flag
run_exec() {
  local worktree_path="$1"
  local exec_override="$2"
  local no_exec="$3"

  if [ "$no_exec" = "1" ]; then
    return
  fi

  local exec_cmd="$exec_override"
  if [ -z "$exec_cmd" ]; then
    exec_cmd=$(get_config "happy-trees.exec" "")
  fi

  if [ -z "$exec_cmd" ]; then
    return
  fi

  if command -v "$exec_cmd" >/dev/null 2>&1; then
    "$exec_cmd" "$worktree_path" || printf "Warning: '%s' command failed\n" "$exec_cmd" >&2
  else
    printf "Warning: Command '%s' not found\n" "$exec_cmd" >&2
  fi
}
```

**Step 5: Commit**

```bash
git add bin/git-ht
git commit -m "feat(git-ht): add require_fzf, validate_worktree_dir, is_default_branch, run_exec helpers"
```

---

### Task 4: Add interactive selector helpers

Add `select_worktree_interactive` and `select_branch_interactive` functions.

**Files:**
- Modify: `bin/git-ht` — insert after the helpers from Task 3

**Step 1: Add `select_worktree_interactive`**

```sh
# Interactive fzf selector for existing worktrees
# Args: exclude_default (0 or 1)
# Outputs: selected branch name
select_worktree_interactive() {
  local exclude_default="$1"
  require_fzf

  local worktree_list=""
  local current_path=""
  local current_branch=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "^worktree "; then
      current_path=$(echo "$line" | sed 's/^worktree //')
    elif echo "$line" | grep -q "^branch "; then
      current_branch=$(echo "$line" | sed 's|^branch refs/heads/||')
      # Skip the main repo worktree (it's not a linked worktree)
      local repo_root=$(get_repo_root)
      if [ "$current_path" = "$repo_root" ]; then
        current_path=""
        current_branch=""
        continue
      fi
      # Skip default branch if requested
      if [ "$exclude_default" = "1" ] && is_default_branch "$current_branch"; then
        current_path=""
        current_branch=""
        continue
      fi
      worktree_list="${worktree_list}${current_branch}\t(worktree: ${current_path})\n"
      current_path=""
      current_branch=""
    elif [ -z "$line" ]; then
      current_path=""
      current_branch=""
    fi
  done <<WTEOF
$(git worktree list --porcelain)
WTEOF

  if [ -z "$worktree_list" ]; then
    printf "Error: No worktrees found\n" >&2
    exit 1
  fi

  local selected
  selected=$(printf "$worktree_list" | fzf --ansi --prompt="Select worktree: " --header="Worktrees") || exit 1
  echo "$selected" | awk '{print $1}'
}
```

**Step 2: Add `select_branch_interactive`**

```sh
# Interactive fzf selector for checkout — worktrees first, then branches by recency
# Outputs: selected branch name
select_branch_interactive() {
  require_fzf

  local entries=""
  local repo_root=$(get_repo_root)

  # Collect worktree branches
  local wt_branches=""
  local current_path=""
  local current_branch=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "^worktree "; then
      current_path=$(echo "$line" | sed 's/^worktree //')
    elif echo "$line" | grep -q "^branch "; then
      current_branch=$(echo "$line" | sed 's|^branch refs/heads/||')
      if [ "$current_path" != "$repo_root" ]; then
        entries="${entries}${current_branch}\t(worktree)\n"
        wt_branches="${wt_branches}${current_branch}\n"
      fi
      current_path=""
      current_branch=""
    elif [ -z "$line" ]; then
      current_path=""
      current_branch=""
    fi
  done <<WTEOF
$(git worktree list --porcelain)
WTEOF

  # Collect non-worktree branches sorted by most recent commit
  # Local branches first, then remote tracking branches
  while IFS= read -r ref; do
    local name=$(echo "$ref" | sed 's|^refs/heads/||; s|^refs/remotes/||')
    local bare_name=$(echo "$name" | sed 's|^origin/||')

    # Skip if already a worktree
    if printf "$wt_branches" | grep -qx "$bare_name"; then
      continue
    fi

    # Determine label
    if echo "$ref" | grep -q "^refs/heads/"; then
      entries="${entries}${bare_name}\t(local)\n"
    elif echo "$ref" | grep -q "^refs/remotes/"; then
      # Skip origin/HEAD
      if echo "$name" | grep -q "/HEAD$"; then
        continue
      fi
      # Skip if we already listed this as a local branch
      if printf "$wt_branches" | grep -qx "$bare_name" || echo "$entries" | grep -q "^${bare_name}	"; then
        continue
      fi
      entries="${entries}${bare_name}\t(remote: ${name})\n"
    fi
  done <<BREOF
$(git for-each-ref --sort=-committerdate --format='%(refname)' refs/heads/ refs/remotes/origin/)
BREOF

  if [ -z "$entries" ]; then
    printf "Error: No branches found\n" >&2
    exit 1
  fi

  local selected
  selected=$(printf "$entries" | fzf --ansi --prompt="Select branch: " --header="Branches (worktrees listed first)") || exit 1
  echo "$selected" | awk '{print $1}'
}
```

**Step 2: Commit**

```bash
git add bin/git-ht
git commit -m "feat(git-ht): add interactive fzf selectors for worktrees and branches"
```

---

### Task 5: Rewrite `cmd_checkout` (replacing `cmd_create`)

Replace the old `cmd_create` function with `cmd_checkout`. This is the core new command.

**Files:**
- Modify: `bin/git-ht` — replace `cmd_create` function (lines 381-527)

**Step 1: Replace `cmd_create` with `cmd_checkout`**

```sh
# Checkout subcommand — switch to or create a worktree
cmd_checkout() {
  local branch=""
  local base=""
  local exec_cmd=""
  local no_exec=0
  local skip_setup=0

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--skip-setup)
        skip_setup=1
        shift
        ;;
      -e|--exec)
        exec_cmd="$2"
        shift 2
        ;;
      -E|--no-exec)
        no_exec=1
        shift
        ;;
      -*)
        printf "Error: Unknown option: %s\n" "$1" >&2
        exit 1
        ;;
      *)
        if [ -z "$branch" ]; then
          branch="$1"
        elif [ -z "$base" ]; then
          base="$1"
        else
          printf "Error: Too many arguments\n" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  # Interactive selection if no branch provided
  if [ -z "$branch" ]; then
    branch=$(select_branch_interactive)
  fi

  # Check if a worktree already exists for this branch
  local existing_wt_path=$(get_worktree_path_for_branch "$branch" || true)
  if [ -n "$existing_wt_path" ]; then
    # Worktree exists — validate directory and run exec
    validate_worktree_dir "$branch"

    if [ -n "$base" ]; then
      printf "Error: [base] argument is not valid when worktree already exists for '%s'\n" "$branch" >&2
      exit 1
    fi

    printf "Worktree already exists: %s\n" "$existing_wt_path"
    run_exec "$existing_wt_path" "$exec_cmd" "$no_exec"
    return
  fi

  # No existing worktree — need to create one
  local worktrees_dir=$(get_worktrees_dir)
  local worktree_path="$worktrees_dir/$branch"

  # Check if worktree directory already exists (stale?)
  if [ -e "$worktree_path" ]; then
    printf "Error: Directory already exists but is not a registered worktree: %s\n" "$worktree_path" >&2
    printf "Remove it manually if it is stale.\n" >&2
    exit 1
  fi

  mkdir -p "$worktrees_dir"

  # Determine if this is an existing branch or a new one
  if branch_exists_local "$branch" || branch_exists_remote "$branch"; then
    # Existing branch
    if [ -n "$base" ]; then
      printf "Error: [base] argument is not valid when branch '%s' already exists\n" "$branch" >&2
      exit 1
    fi
    git worktree add "$worktree_path" "$branch"
  else
    # New branch — create from base or remote default
    local start_point="${base:-$(get_remote_default_branch)}"
    git worktree add -b "$branch" "$worktree_path" "$start_point"
  fi

  printf "Created worktree at: %s\n" "$worktree_path"

  # Run setup unless skipped
  if [ $skip_setup -eq 0 ]; then
    local setup_location=$(get_config "happy-trees.setupLocation" "")
    if [ -n "$setup_location" ]; then
      local repo_root=$(get_repo_root)
      local setup_script=$(expand_path_tokens "$setup_location" "$worktree_path")

      if [ -f "$setup_script" ] && [ -x "$setup_script" ]; then
        printf "\nRunning setup script...\n"
        if "$setup_script" "$repo_root" "$worktree_path"; then
          printf "Setup completed successfully\n"
        else
          printf "Warning: Setup script failed (worktree was still created)\n" >&2
        fi
      fi
    fi
  fi

  # Run exec
  run_exec "$worktree_path" "$exec_cmd" "$no_exec"
}
```

**Step 2: Commit**

```bash
git add bin/git-ht
git commit -m "feat(git-ht): add cmd_checkout replacing cmd_create"
```

---

### Task 6: Rewrite `cmd_remove`

Replace the old `cmd_remove` with the simplified version — only `--force` flag, auto-deletes local branch if remote SHA matches, interactive selector.

**Files:**
- Modify: `bin/git-ht` — replace `cmd_remove` function

**Step 1: Replace `cmd_remove`**

```sh
# Remove subcommand — remove worktree, conditionally delete local branch
cmd_remove() {
  local name=""
  local force=0

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      -*)
        printf "Error: Unknown option: %s\n" "$1" >&2
        exit 1
        ;;
      *)
        if [ -z "$name" ]; then
          name="$1"
        else
          printf "Error: Too many arguments\n" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  # Interactive selection if no branch provided
  if [ -z "$name" ]; then
    name=$(select_worktree_interactive 0)
  fi

  # Validate worktree directory
  validate_worktree_dir "$name"

  local worktrees_dir=$(get_worktrees_dir)
  local worktree_path="$worktrees_dir/$name"

  # Remove the worktree
  if [ $force -eq 1 ]; then
    git worktree remove --force "$worktree_path"
  else
    git worktree remove "$worktree_path"
  fi

  printf "Removed worktree: %s\n" "$worktree_path"

  # Auto-delete local branch if remote branch exists at same commit
  if branch_exists_local "$name" && branch_exists_remote "$name"; then
    local local_sha=$(git rev-parse "refs/heads/$name")
    local remote_sha=$(git rev-parse "refs/remotes/origin/$name" 2>/dev/null || true)

    if [ -n "$remote_sha" ] && [ "$local_sha" = "$remote_sha" ]; then
      git branch -D "$name"
      printf "Deleted local branch '%s' (matches remote)\n" "$name"
    fi
  fi
}
```

**Step 2: Commit**

```bash
git add bin/git-ht
git commit -m "feat(git-ht): rewrite cmd_remove with auto branch cleanup and interactive selector"
```

---

### Task 7: Add `cmd_destroy`

New command that removes worktree + deletes local and remote branches. Default branch protection.

**Files:**
- Modify: `bin/git-ht` — add after `cmd_remove`

**Step 1: Add `cmd_destroy`**

```sh
# Destroy subcommand — remove worktree + delete local and remote branches
cmd_destroy() {
  local name=""
  local force=0

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      -*)
        printf "Error: Unknown option: %s\n" "$1" >&2
        exit 1
        ;;
      *)
        if [ -z "$name" ]; then
          name="$1"
        else
          printf "Error: Too many arguments\n" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  # Interactive selection if no branch provided (exclude default branch)
  if [ -z "$name" ]; then
    name=$(select_worktree_interactive 1)
  fi

  # Check default branch protection
  if is_default_branch "$name"; then
    printf "Error: Cannot destroy the default branch '%s'\n" "$name" >&2
    exit 1
  fi

  # Validate worktree directory
  validate_worktree_dir "$name"

  local worktrees_dir=$(get_worktrees_dir)
  local worktree_path="$worktrees_dir/$name"

  # Remove the worktree
  if [ $force -eq 1 ]; then
    git worktree remove --force "$worktree_path"
  else
    git worktree remove "$worktree_path"
  fi

  printf "Removed worktree: %s\n" "$worktree_path"

  # Delete local branch
  if branch_exists_local "$name"; then
    git branch -D "$name"
    printf "Deleted local branch: %s\n" "$name"
  fi

  # Delete remote branch
  if branch_exists_remote "$name"; then
    git push origin --delete "$name"
    printf "Deleted remote branch: %s\n" "$name"
  fi
}
```

**Step 2: Commit**

```bash
git add bin/git-ht
git commit -m "feat(git-ht): add cmd_destroy for worktree + branch cleanup"
```

---

### Task 8: Update dispatcher and config

Update the `main()` dispatcher to route the new commands and remove `create`. Update gitconfig to rename `openWith` to `exec`.

**Files:**
- Modify: `bin/git-ht` — `main()` function
- Modify: `gitconfig:56-57`

**Step 1: Update dispatcher**

Replace the case statement in `main()`:

```sh
  case "$subcommand" in
    checkout|co)
      cmd_checkout "$@"
      ;;
    remove)
      cmd_remove "$@"
      ;;
    destroy)
      cmd_destroy "$@"
      ;;
    setup)
      cmd_setup "$@"
      ;;
    *)
      printf "Error: Unknown subcommand: %s\n" "$subcommand" >&2
      printf "Run 'git ht help' for usage information\n" >&2
      exit 1
      ;;
  esac
```

**Step 2: Update gitconfig**

Change line 57 of `gitconfig` from:

```
	openWith = code
```

to:

```
	exec = code
```

**Step 3: Commit**

```bash
git add bin/git-ht gitconfig
git commit -m "feat(git-ht): update dispatcher for checkout/destroy, rename openWith to exec"
```

---

### Task 9: Final review and cleanup

Verify the full script is consistent — no stale references to old commands/flags, no dead code.

**Step 1: Check for stale references**

Run: `grep -n 'openWith\|open_with\|cmd_create\|--existing-branch\|--initial-ref\|--worktrees-dir\|--delete-branch\|--delete-remote' bin/git-ht`
Expected: No matches.

Run: `grep -n 'openWith' gitconfig`
Expected: No matches.

**Step 2: Test help output**

Run: `bin/git-ht help`
Expected: Clean help output with checkout/co, remove, destroy, setup commands.

**Step 3: Commit any cleanup if needed**

```bash
git add bin/git-ht
git commit -m "chore(git-ht): final cleanup of stale references"
```
