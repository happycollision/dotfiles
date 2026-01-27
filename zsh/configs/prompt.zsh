# Git-aware prompt showing branch and path from repo root
# Prints on separate line before the main prompt
# Output examples:
#   In git repo:     "[master] dotfiles/zsh/configs"
#   With changes:    "[master*] dotfiles/zsh/configs"
#   Ahead of remote: "[master↑3] dotfiles"
#   In worktree:     "[my-branch] dotfiles/../dotfiles.worktrees/my-branch/zsh"
#   Not in git:      "Documents/projects" (uses %2c)
# Status indicators:
#   *   - Uncommitted changes (modified, staged, or untracked files)
#   ↑N  - N commits ahead of remote
#   ↓N  - N commits behind remote
# Colors:
#   Branch name:       green
#   Repo location:     cyan
#   Path from root:    blue
_print_git_and_path() {
  local repo_root=$(git rev-parse --show-toplevel 2> /dev/null)

  if [[ -z $repo_root ]]; then
    # Not in a git repo, show regular path
    print -P "%F{blue}%B%2c%b%f"
    return
  fi

  # Get branch name
  local current_branch=$(git symbolic-ref --short HEAD 2> /dev/null || git rev-parse --short HEAD 2> /dev/null)

  # Get git status indicators
  local git_status=""

  # Check for uncommitted changes (modified, deleted, or untracked files)
  if ! git diff --quiet 2> /dev/null || ! git diff --cached --quiet 2> /dev/null || [[ -n $(git ls-files --others --exclude-standard 2> /dev/null) ]]; then
    git_status="${git_status}*"
  fi

  # Check ahead/behind remote
  local upstream=$(git rev-parse --abbrev-ref @{upstream} 2> /dev/null)
  if [[ -n $upstream ]]; then
    local ahead_behind=$(git rev-list --left-right --count HEAD...@{upstream} 2> /dev/null)
    local ahead=$(echo $ahead_behind | awk '{print $1}')
    local behind=$(echo $ahead_behind | awk '{print $2}')

    [[ $ahead -gt 0 ]] && git_status="${git_status}↑${ahead}"
    [[ $behind -gt 0 ]] && git_status="${git_status}↓${behind}"
  fi

  # Get current directory relative to repo root
  local current_dir=$(pwd)
  local path_from_root="${current_dir#$repo_root}"
  path_from_root="${path_from_root#/}"  # Remove leading slash

  # Get repo location (relative path to repo root or basename)
  local git_dir=$(git rev-parse --git-dir 2> /dev/null)
  local repo_location=""

  # Check if we're in a worktree
  if [[ -f "$git_dir/gitdir" ]]; then
    # We're in a worktree - show path relative to main worktree
    local main_worktree=$(git worktree list --porcelain 2> /dev/null | grep -m1 "^worktree " | cut -d' ' -f2)
    if [[ -n $main_worktree ]]; then
      local main_basename=$(basename "$main_worktree")
      local rel_path=$(python3 -c "import os.path; print(os.path.relpath('$repo_root', '$main_worktree'))" 2>/dev/null)
      if [[ -z $rel_path ]]; then
        rel_path=$(realpath --relative-to="$main_worktree" "$repo_root" 2>/dev/null)
      fi
      repo_location="$main_basename/$rel_path"
    else
      repo_location=$(basename "$repo_root")
    fi
  else
    # Regular repo - just show basename
    repo_location=$(basename "$repo_root")
  fi

  # Build and print the prompt
  if [[ -n $path_from_root ]]; then
    # We're in a subdirectory - repo location in cyan, path from root in blue
    print -P "%F{green}%B[${current_branch}${git_status}]%b%f %F{cyan}%B${repo_location}%b%f%F{blue}%B/${path_from_root}%b%f"
  else
    # At repo root - just show repo location in cyan
    print -P "%F{green}%B[${current_branch}${git_status}]%b%f %F{cyan}%B${repo_location}%b%f"
  fi
}

# Claude status indicators (for inline prompt)
# Output examples:
#   Both issues:     "🤖❗🤖⚠️"
#   Not configured:  "🤖❗"
#   Exclude conflict: "🤖⚠️"
#   No issues:       "" (empty)
claude_status() {
  claude_not_configured && echo -n "🤖❗"
  claude_exclude_conflict && echo -n "🤖⚠️"
}

# SSH connection info (for inline prompt)
# Output examples:
#   Via SSH:     "user@hostname:"
#   Local:       "" (empty)
ssh_info() {
  if [[ -n $SSH_CONNECTION ]]; then
    echo "%{$fg_bold[green]%}%n@%m:%{$reset_color%}"
  fi
}

# Register hooks (allows multiple hooks without conflicts)
# Hooks execute in registration order
autoload -Uz add-zsh-hook
add-zsh-hook precmd _print_git_and_path

setopt promptsubst

# Allow exported PS1 variable to override default prompt.
if ! env | grep -q '^PS1='; then
  PS1='$(claude_status)$(ssh_info)❯ '
fi
