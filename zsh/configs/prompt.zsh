# Git-aware prompt showing branch and path from repo root
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
git_prompt_info() {
  local repo_root=$(git rev-parse --show-toplevel 2> /dev/null)

  if [[ -z $repo_root ]]; then
    # Not in a git repo, show regular path
    echo "%{$fg_bold[blue]%}%2c%{$reset_color%}"
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

  # Build the prompt
  local branch_part="%{$fg_bold[green]%}[$current_branch$git_status]%{$reset_color%}"
  local location_part="%{$fg_bold[cyan]%}$repo_location%{$reset_color%}"

  if [[ -n $path_from_root ]]; then
    # We're in a subdirectory
    location_part="$location_part%{$fg_bold[blue]%}/$path_from_root%{$reset_color%}"
  fi

  echo "$branch_part $location_part"
}

# Claude status indicators
# Output examples:
#   Both issues:     "🤖❗🤖⚠️"
#   Not configured:  "🤖❗"
#   Exclude conflict: "🤖⚠️"
#   No issues:       "" (empty)
claude_status() {
  claude_not_configured && echo "🤖❗"
  claude_exclude_conflict && echo "🤖⚠️"
}

# SSH connection info
# Output examples:
#   Via SSH:     "user@hostname:"
#   Local:       "" (empty)
ssh_info() {
  if [[ -n $SSH_CONNECTION ]]; then
    echo "%{$fg_bold[green]%}%n@%m:%{$reset_color%}"
  fi
}

setopt promptsubst

# Allow exported PS1 variable to override default prompt.
if ! env | grep -q '^PS1='; then
  PS1='$(claude_status)$(ssh_info)$(git_prompt_info)
❯ '
fi
