# Claude ignore/tracked mismatch detection
# Warns when .claude/ is ignored but has tracked files

typeset -gA _claude_ignore_warned_repos

_check_claude_ignore_mismatch() {
  # Only run in git repos
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return

  # Get repo root for deduplication
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return

  # Skip if already warned for this repo this session
  [[ -n "${_claude_ignore_warned_repos[$repo_root]}" ]] && return

  # Gather state
  local has_exclude=false
  grep -q "^\.claude" "$git_dir/info/exclude" 2>/dev/null && has_exclude=true

  local has_gitignore=false
  grep -q "\.claude" "$repo_root/.gitignore" 2>/dev/null && has_gitignore=true

  local tracked_files=$(git ls-files .claude/ 2>/dev/null)

  # Case: Tracked files exist without .gitignore rules (regardless of exclude)
  # Suggest adding proper ignore rules to .gitignore
  if [[ -n "$tracked_files" ]] && ! $has_gitignore; then
    echo "⚠️  .claude/ files are tracked without explicit .gitignore rules"
    echo "   Tracked files:"
    echo "$tracked_files" | sed 's/^/     /'
    echo "   Run 'create-claude-ignores' to add proper ignore rules to .gitignore"
    _claude_ignore_warned_repos[$repo_root]=1
  # Case: Exclude is set AND .gitignore has rules (conflict - our exclude overrides project rules)
  # Suggest running unignore-claude. Prompt: 🤖⚠️
  elif $has_exclude && $has_gitignore; then
    echo "🤖⚠️  .claude/ is in personal exclude but repo has .gitignore rules for .claude"
    echo "   Run 'unignore-claude' to remove your personal exclude and use repo's rules"
    _claude_ignore_warned_repos[$repo_root]=1
  # Case: No exclude, no .gitignore, but .claude dir exists (danger - untracked files with no rules)
  # Suggest ignore-claude or adding .gitignore rules. Prompt: 🤖❗
  elif ! $has_exclude && ! $has_gitignore && [[ -d "$repo_root/.claude" ]]; then
    echo "🤖❗ .claude/ exists but repo has no claude ignore patterns"
    echo "   Run 'ignore-claude' to add personal ignore, or 'create-claude-ignores' for shared settings"
    _claude_ignore_warned_repos[$repo_root]=1
  fi
}

ignore-claude() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || {
    echo "Not in a git repository"
    return 1
  }

  local exclude_file="$git_dir/info/exclude"

  # Create info directory if it doesn't exist
  mkdir -p "$git_dir/info"

  # If exclude file is a symlink, replace with a local copy
  if [[ -L "$exclude_file" ]]; then
    local target=$(readlink "$exclude_file")
    rm "$exclude_file"
    cp "$target" "$exclude_file"
    echo "✓ Converted symlink to local file"
  fi

  if grep -q "^\.claude" "$exclude_file" 2>/dev/null; then
    echo ".claude is already in $exclude_file"
    return 0
  fi

  echo ".claude" >> "$exclude_file"
  echo "✓ Added .claude to $exclude_file"
}

create-claude-ignores() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Not in a git repository"
    return 1
  }

  local gitignore_file="$repo_root/.gitignore"

  if grep -q "\.claude" "$gitignore_file" 2>/dev/null; then
    echo ".claude patterns already exist in $gitignore_file"
    return 0
  fi

  cat >> "$gitignore_file" << 'EOF'

# Claude Code - ignore local settings, keep shared settings
.claude/settings.local.json
EOF

  echo "✓ Added claude ignore patterns to $gitignore_file"
}

unignore-claude() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || {
    echo "Not in a git repository"
    return 1
  }

  local exclude_file="$git_dir/info/exclude"

  if [[ ! -e "$exclude_file" ]]; then
    echo "No .git/info/exclude file exists"
    return 0
  fi

  # If exclude file is a symlink, replace with a local copy (minus .claude)
  if [[ -L "$exclude_file" ]]; then
    local target=$(readlink "$exclude_file")
    rm "$exclude_file"
    grep -v "^\.claude" "$target" > "$exclude_file"
    echo "✓ Converted symlink to local file and removed .claude"

    # Clear the warning flag for this repo
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    unset "_claude_ignore_warned_repos[$repo_root]"
    return 0
  fi

  if grep -q "^\.claude" "$exclude_file" 2>/dev/null; then
    # Remove lines starting with .claude (handles .claude, .claude/, .claude/*)
    sed -i '' '/^\.claude/d' "$exclude_file"
    echo "✓ Removed .claude from $exclude_file"

    # Clear the warning flag for this repo
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    unset "_claude_ignore_warned_repos[$repo_root]"
  else
    echo ".claude is not in $exclude_file (may be in global gitignore)"
  fi
}

# Prompt integration: returns 0 if personal exclude conflicts with repo's .gitignore rules
# Usage: $(claude_exclude_conflict && echo "🤖⚠️")
claude_exclude_conflict() {
  local git_dir repo_root
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  grep -q "^\.claude" "$git_dir/info/exclude" 2>/dev/null || return 1
  grep -q "\.claude" "$repo_root/.gitignore" 2>/dev/null || return 1
  return 0
}

# Prompt integration: returns 0 if .claude exists but repo has no ignore patterns
# Usage: $(claude_not_configured && echo "🤖❗")
claude_not_configured() {
  local git_dir repo_root
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ -d "$repo_root/.claude" ]] || return 1
  grep -q "^\.claude" "$git_dir/info/exclude" 2>/dev/null && return 1
  grep -q "\.claude" "$repo_root/.gitignore" 2>/dev/null && return 1
  return 0
}

# Hook into directory changes
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _check_claude_ignore_mismatch

# Run on shell start for initial directory
_check_claude_ignore_mismatch
