#!/bin/sh
# Test suite for git-ht
# Run from the dotfiles repository root

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get the absolute path to the script's directory (test/)
# and derive the dotfiles root from there
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SANDBOX="$DOTFILES_ROOT/tmp"
GIT_HT_PATH="$DOTFILES_ROOT/bin/git-ht"
TEST_REPO_DIR="$SANDBOX/test-repo"

# Test helper functions
assert_success() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if eval "$1" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} %s\n" "$2"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} %s\n" "$2"
    return 1
  fi
}

assert_failure() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! eval "$1" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} %s\n" "$2"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} %s\n" "$2"
    return 1
  fi
}

assert_output_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  output=$(eval "$1" 2>&1 || true)
  if echo "$output" | grep -q "$2"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} %s\n" "$3"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} %s\n" "$3"
    printf "  Expected output to contain: %s\n" "$2"
    printf "  Actual output: %s\n" "$output"
    return 1
  fi
}

assert_file_exists() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -e "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} %s\n" "$2"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} %s\n" "$2"
    return 1
  fi
}

assert_file_not_exists() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} %s\n" "$2"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} %s\n" "$2"
    return 1
  fi
}

# Setup test repository
setup_test_repo() {
  printf "${YELLOW}Setting up test repository...${NC}\n"

  # Remove any existing test repo
  rm -rf "$TEST_REPO_DIR"

  # Create test repo directory
  mkdir -p "$TEST_REPO_DIR"
  cd "$TEST_REPO_DIR"

  # Initialize git repo
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Create initial commit
  echo "# Test Repository" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  # Create a few more commits for testing HEAD~N
  echo "Content 1" > file1.txt
  git add file1.txt
  git commit -q -m "Add file1"

  echo "Content 2" > file2.txt
  git add file2.txt
  git commit -q -m "Add file2"

  # Set up a fake origin (for testing origin/master detection)
  git branch -M master

  printf "${GREEN}Test repository created at: %s${NC}\n\n" "$TEST_REPO_DIR"
}

# Cleanup function
cleanup() {
  printf "\n${YELLOW}Cleaning up...${NC}\n"

  # Return to dotfiles root
  cd "$DOTFILES_ROOT"

  # Remove entire sandbox directory (test repo and all worktrees)
  rm -rf "$SANDBOX"

  printf "${GREEN}Cleanup complete${NC}\n\n"
}

# Wrapper to call git-ht from test repo
git_ht() {
  "$GIT_HT_PATH" "$@"
}

# Trap to ensure cleanup runs on exit
trap cleanup EXIT INT TERM

# Setup test environment
setup_test_repo

printf "\n${YELLOW}=== Testing git-ht ===${NC}\n\n"

# Test 1: Help options
printf "${YELLOW}Test Group: Help and Basic Commands${NC}\n"
assert_output_contains "git_ht --help" "Usage: git ht" "git ht --help shows usage information"
assert_output_contains "git_ht -h" "Usage: git ht" "git ht -h shows usage information"
assert_output_contains "git_ht" "Usage: git ht" "git ht without args shows help"

# Test 2: Create basic worktree
printf "\n${YELLOW}Test Group: Basic Worktree Creation${NC}\n"
assert_success "git_ht create test-wt-1" "Creates basic worktree"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-wt-1" "Worktree directory exists in correct location"
assert_success "git worktree list | grep -q test-wt-1" "Worktree appears in git worktree list"
assert_success "git branch --list test-wt-1 | grep -q test-wt-1" "Branch was created"

# Test 3: Safety checks - duplicate branch name
printf "\n${YELLOW}Test Group: Safety Checks${NC}\n"
assert_output_contains "git_ht create test-wt-1" "Refusing to create test-wt-1 for an existing branch name" "Refuses to create worktree for existing branch"

# Test 4: Safety checks - current branch
current_branch=$(git branch --show-current)
assert_output_contains "git_ht create $current_branch" "Cannot create worktree for currently checked out branch" "Refuses to create worktree for current branch"

# Test 5: Remove worktree (so we can test -e flag)
assert_success "git_ht remove test-wt-1" "Removes worktree (preparing for -e test)"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-wt-1" "Worktree directory removed"
assert_success "git branch --list test-wt-1 | grep -q test-wt-1" "Branch still exists after removal"

# Test 6: Create with existing branch flag
printf "\n${YELLOW}Test Group: Existing Branch Flag${NC}\n"
assert_success "git_ht create test-wt-1 -e" "Creates worktree with existing branch using -e"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-wt-1" "Worktree directory exists"

# Test 7: Existing branch flag with non-existent branch
assert_output_contains "git_ht create test-wt-nonexistent -e" "does not exist" "Fails when using -e with non-existent branch"

# Test 8: Remove worktree again
assert_success "git_ht remove test-wt-1" "Removes worktree again"

# Test 9: Remove with --delete-branch
printf "\n${YELLOW}Test Group: Remove with Branch Deletion${NC}\n"
assert_success "git_ht create test-wt-2" "Creates worktree for delete-branch test"
assert_success "git_ht remove test-wt-2 --delete-branch" "Removes worktree with --delete-branch"
assert_failure "git branch --list test-wt-2 | grep -q test-wt-2" "Branch deleted with --delete-branch"

# Test 10: Create from specific commit
printf "\n${YELLOW}Test Group: Custom Starting Point${NC}\n"
assert_success "git_ht create test-wt-commit -i HEAD~1" "Creates worktree from specific commit"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-wt-commit" "Worktree created from commit exists"

# Verify it's at the right commit
commit_hash=$(git -C "$SANDBOX/test-repo.worktrees/test-wt-commit" rev-parse HEAD)
expected_hash=$(git rev-parse HEAD~1)
if [ "$commit_hash" = "$expected_hash" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Worktree HEAD is at correct commit\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Worktree HEAD is at wrong commit\n"
fi

assert_success "git_ht remove test-wt-commit --delete-branch" "Cleans up commit test worktree"

# Test 11: Mutually exclusive flags
printf "\n${YELLOW}Test Group: Flag Validation${NC}\n"
assert_output_contains "git_ht create test-conflict -e -i HEAD" "mutually exclusive" "Rejects both -e and -i flags together"

# Test 12: Custom worktrees directory
printf "\n${YELLOW}Test Group: Custom Directory${NC}\n"
assert_success "git_ht create test-wt-custom -d '$SANDBOX/custom-wt'" "Creates worktree in custom directory"
assert_file_exists "$SANDBOX/custom-wt/test-wt-custom" "Worktree exists in custom location"
assert_success "git_ht remove test-wt-custom -d '$SANDBOX/custom-wt' --delete-branch" "Removes worktree from custom directory"

# Test 13: Token expansion with -d flag
printf "\n${YELLOW}Test Group: Token Expansion${NC}\n"
repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")

assert_success "git_ht create test-wt-tokens -d '<repo_root>/wt-custom'" "Creates worktree with <repo_root> token in -d flag"
assert_file_exists "$repo_root/wt-custom/test-wt-tokens" "Worktree exists at expanded <repo_root> path"

# Verify the path was correctly expanded
if [ -d "$repo_root/wt-custom/test-wt-tokens" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Token <repo_root> was correctly expanded\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Token <repo_root> was not expanded correctly\n"
fi

assert_success "git_ht remove test-wt-tokens -d '<repo_root>/wt-custom' --delete-branch" "Removes worktree with token in -d flag"

# Test 14: Token expansion with git config
assert_success "git config happy-trees.worktreesDir '<repo_root>/wt-test'" "Sets config with <repo_root> token"
assert_success "git_ht create test-wt-config-tokens" "Creates worktree using config with tokens"
assert_file_exists "$repo_root/wt-test/test-wt-config-tokens" "Worktree exists at config-specified token path"

# Verify <repo_name> token would work (checking the repo name is correct)
if [ "$repo_name" = "test-repo" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Token <repo_name> correctly identifies 'test-repo'\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Token <repo_name> returned unexpected value: %s\n" "$repo_name"
fi

assert_success "git_ht remove test-wt-config-tokens --delete-branch" "Removes worktree created with config tokens"
assert_success "git config --unset happy-trees.worktreesDir" "Unsets test config"

# Test 15: Remove non-existent worktree
printf "\n${YELLOW}Test Group: Error Handling${NC}\n"
assert_output_contains "git_ht remove nonexistent-wt" "Worktree not found" "Fails gracefully when removing non-existent worktree"

# Test 16: Create without name
assert_output_contains "git_ht create" "worktree name is required" "Requires worktree name"

# Test 17: --open-with option
printf "\n${YELLOW}Test Group: --open-with Option${NC}\n"

# Create a test script that writes to a file when called
mkdir -p "$SANDBOX/test-commands"
cat > "$SANDBOX/test-commands/test-cmd" <<'TESTCMD'
#!/bin/sh
echo "$1" > "$TEST_MARKER_FILE"
TESTCMD
chmod +x "$SANDBOX/test-commands/test-cmd"

# Test with long form --open-with
export TEST_MARKER_FILE="$SANDBOX/open-with-test-marker.txt"
export PATH="$SANDBOX/test-commands:$PATH"

assert_success "git_ht create test-wt-open --open-with test-cmd" "Creates worktree with --open-with test-cmd"
assert_file_exists "$TEST_MARKER_FILE" "Command was executed (marker file exists)"

# Verify command received correct path (normalize both paths for comparison)
if [ -f "$TEST_MARKER_FILE" ]; then
  received_path=$(cd "$(cat "$TEST_MARKER_FILE")" && pwd)
  expected_path=$(cd "$SANDBOX/test-repo.worktrees/test-wt-open" && pwd)
  if [ "$received_path" = "$expected_path" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Command received correct worktree path\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Command received wrong path\n"
    printf "  Expected: %s\n" "$expected_path"
    printf "  Received: %s\n" "$received_path"
  fi
fi

assert_success "git_ht remove test-wt-open --delete-branch" "Removes test-wt-open"
rm -f "$TEST_MARKER_FILE"

# Test with short form -o
assert_success "git_ht create test-wt-open-short -o test-cmd" "Creates worktree with -o test-cmd (short form)"
assert_file_exists "$TEST_MARKER_FILE" "Command executed with short form -o"

# Verify path again for short form (normalize both paths for comparison)
if [ -f "$TEST_MARKER_FILE" ]; then
  received_path=$(cd "$(cat "$TEST_MARKER_FILE")" && pwd)
  expected_path=$(cd "$SANDBOX/test-repo.worktrees/test-wt-open-short" && pwd)
  if [ "$received_path" = "$expected_path" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Short form -o passes correct path\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Short form -o passed wrong path\n"
  fi
fi

assert_success "git_ht remove test-wt-open-short --delete-branch" "Removes test-wt-open-short"
rm -f "$TEST_MARKER_FILE"

# Test with non-existent command (should warn but not fail)
assert_output_contains "git_ht create test-wt-noexist-cmd --open-with nonexistent-command-xyz" "Warning.*not found" "Warns when command not found"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-wt-noexist-cmd" "Worktree still created when command not found"
assert_success "git_ht remove test-wt-noexist-cmd --delete-branch" "Removes test-wt-noexist-cmd"

# Test with failing command (should warn but not fail worktree creation)
cat > "$SANDBOX/test-commands/fail-cmd" <<'FAILCMD'
#!/bin/sh
exit 1
FAILCMD
chmod +x "$SANDBOX/test-commands/fail-cmd"

assert_output_contains "git_ht create test-wt-fail-cmd --open-with fail-cmd" "Warning.*command failed" "Warns when command fails"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-wt-fail-cmd" "Worktree still created when command fails"
assert_success "git_ht remove test-wt-fail-cmd --delete-branch" "Removes test-wt-fail-cmd"

# Test interaction with -i flag
rm -f "$TEST_MARKER_FILE"
assert_success "git_ht create test-wt-with-commit -i HEAD~1 -o test-cmd" "Creates worktree with both -i and -o flags"
assert_file_exists "$TEST_MARKER_FILE" "Command executed when combined with -i flag"
assert_success "git_ht remove test-wt-with-commit --delete-branch" "Removes test-wt-with-commit"
rm -f "$TEST_MARKER_FILE"

# Test with custom directory
assert_success "git_ht create test-wt-custom-open -d '$SANDBOX/custom-open' -o test-cmd" "Creates worktree with -d and -o flags"
if [ -f "$TEST_MARKER_FILE" ]; then
  received_path=$(cd "$(cat "$TEST_MARKER_FILE")" && pwd)
  expected_path=$(cd "$SANDBOX/custom-open/test-wt-custom-open" && pwd)
  if [ "$received_path" = "$expected_path" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Command receives custom directory path\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Command received wrong custom path\n"
  fi
fi
assert_success "git_ht remove test-wt-custom-open -d '$SANDBOX/custom-open' --delete-branch" "Removes test-wt-custom-open"

# Test 18: Default --open-with via config
printf "\n${YELLOW}Test Group: Default --open-with via Config${NC}\n"

# Set default open-with config
git config happy-trees.openWith test-cmd

# Test that config default is used
rm -f "$TEST_MARKER_FILE"
assert_success "git_ht create test-wt-default-open" "Creates worktree using default openWith from config"
assert_file_exists "$TEST_MARKER_FILE" "Default openWith command was executed"

# Verify path is correct
if [ -f "$TEST_MARKER_FILE" ]; then
  received_path=$(cd "$(cat "$TEST_MARKER_FILE")" && pwd)
  expected_path=$(cd "$SANDBOX/test-repo.worktrees/test-wt-default-open" && pwd)
  if [ "$received_path" = "$expected_path" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Default openWith received correct worktree path\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Default openWith received wrong path\n"
  fi
fi
assert_success "git_ht remove test-wt-default-open --delete-branch" "Removes test-wt-default-open"

# Test that --no-open-with skips the default
rm -f "$TEST_MARKER_FILE"
assert_success "git_ht create test-wt-no-open --no-open-with" "Creates worktree with --no-open-with flag"
assert_file_not_exists "$TEST_MARKER_FILE" "Default openWith was skipped with --no-open-with"
assert_success "git_ht remove test-wt-no-open --delete-branch" "Removes test-wt-no-open"

# Test that -O (short form) also skips the default
rm -f "$TEST_MARKER_FILE"
assert_success "git_ht create test-wt-no-open-short -O" "Creates worktree with -O flag (short form)"
assert_file_not_exists "$TEST_MARKER_FILE" "Default openWith was skipped with -O"
assert_success "git_ht remove test-wt-no-open-short --delete-branch" "Removes test-wt-no-open-short"

# Test that explicit -o overrides the default
rm -f "$TEST_MARKER_FILE"
cat > "$SANDBOX/test-commands/other-cmd" <<'OTHERCMD'
#!/bin/sh
echo "other:$1" > "$TEST_MARKER_FILE"
OTHERCMD
chmod +x "$SANDBOX/test-commands/other-cmd"

assert_success "git_ht create test-wt-override-open -o other-cmd" "Creates worktree with explicit -o overriding config"
if [ -f "$TEST_MARKER_FILE" ]; then
  if grep -q "^other:" "$TEST_MARKER_FILE"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Explicit -o flag overrides config default\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Config default was used instead of explicit -o\n"
  fi
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} No command was executed\n"
fi
assert_success "git_ht remove test-wt-override-open --delete-branch" "Removes test-wt-override-open"

# Unset the config
git config --unset happy-trees.openWith

# Cleanup test commands
rm -rf "$SANDBOX/test-commands"
rm -f "$TEST_MARKER_FILE"

# Test 19: Setup command - Init mode
printf "\n${YELLOW}Test Group: Setup Command - Init Mode${NC}\n"

assert_success "git_ht setup --init" "Creates setup script with --init"
assert_file_exists "$TEST_REPO_DIR/setup-worktree.sh" "Setup script exists in repo root"

# Verify script is executable
if [ -x "$TEST_REPO_DIR/setup-worktree.sh" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Setup script is executable\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Setup script is not executable\n"
fi

# Verify git config was set
setup_location=$(git config happy-trees.setupLocation)
if [ -n "$setup_location" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Git config happy-trees.setupLocation is set\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Git config happy-trees.setupLocation is not set\n"
fi

# Verify script contains expected content
if grep -q "#!/usr/bin/env bash" "$TEST_REPO_DIR/setup-worktree.sh" && \
   grep -q "REPO_ROOT=\"\$1\"" "$TEST_REPO_DIR/setup-worktree.sh" && \
   grep -q "WORKTREE_ROOT=\"\$2\"" "$TEST_REPO_DIR/setup-worktree.sh"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Setup script contains expected template content\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Setup script missing expected template content\n"
fi

# Test 19: Setup command - Run mode prerequisites
printf "\n${YELLOW}Test Group: Setup Command - Run Mode Prerequisites${NC}\n"

# Unset config to test failure case
git config --unset happy-trees.setupLocation
assert_output_contains "git_ht setup" "not configured" "Fails gracefully when setupLocation not configured"

# Restore config for remaining tests
git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"

# Test running from main worktree without branch argument should fail
assert_output_contains "git_ht setup" "linked worktree" "Fails when run from main worktree without branch argument"

# Test 20: Setup command - Run mode with actual execution
printf "\n${YELLOW}Test Group: Setup Command - Run Mode Execution${NC}\n"

# Create a worktree for testing setup
assert_success "git_ht create test-setup-wt" "Creates worktree for setup testing"

# Modify the setup script to write a marker file so we can verify it ran
cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'SETUPSCRIPT'
#!/usr/bin/env bash
REPO_ROOT="$1"
WORKTREE_ROOT="$2"

# Write marker file to prove script ran with correct arguments
echo "repo_root=$REPO_ROOT" > "$WORKTREE_ROOT/.setup-marker"
echo "worktree_root=$WORKTREE_ROOT" >> "$WORKTREE_ROOT/.setup-marker"

# Create a test file
echo "Setup complete" > "$WORKTREE_ROOT/.setup-complete"
SETUPSCRIPT
chmod +x "$TEST_REPO_DIR/setup-worktree.sh"

# Test setup from inside the worktree
cd "$SANDBOX/test-repo.worktrees/test-setup-wt"
assert_success "git_ht setup" "Runs setup from inside worktree"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker" "Setup script created marker file"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-complete" "Setup script completed successfully"

# Verify arguments were passed correctly
if [ -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker" ]; then
  marker_content=$(cat "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker")
  expected_repo_root=$(cd "$TEST_REPO_DIR" && pwd)
  expected_worktree_root=$(cd "$SANDBOX/test-repo.worktrees/test-setup-wt" && pwd)

  if echo "$marker_content" | grep -q "repo_root=$expected_repo_root" && \
     echo "$marker_content" | grep -q "worktree_root=$expected_worktree_root"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Setup script received correct arguments\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Setup script received wrong arguments\n"
    printf "  Marker content: %s\n" "$marker_content"
  fi
fi

# Return to test repo
cd "$TEST_REPO_DIR"

# Test 21: Setup command - Run mode with branch argument
printf "\n${YELLOW}Test Group: Setup Command - Run Mode with Branch Argument${NC}\n"

# Clean up marker files
rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker"
rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-complete"

# Test setup from main repo with branch argument
assert_success "git_ht setup test-setup-wt" "Runs setup with branch argument from main repo"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker" "Setup script ran with branch argument"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-complete" "Setup completed with branch argument"

# Test setup with non-existent branch
assert_output_contains "git_ht setup nonexistent-branch" "not found" "Fails when branch doesn't exist"

# Create another worktree and test setup from different worktree
assert_success "git_ht create test-setup-wt-2" "Creates second worktree for cross-worktree testing"
cd "$SANDBOX/test-repo.worktrees/test-setup-wt-2"
rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker"
rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-complete"
assert_success "git_ht setup test-setup-wt" "Runs setup for different worktree from inside another worktree"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker" "Setup ran for correct worktree"

# Return to test repo
cd "$TEST_REPO_DIR"

# Test 22: Setup command - Token expansion in setupLocation
printf "\n${YELLOW}Test Group: Setup Command - Token Expansion${NC}\n"

# Test <repo_root> token (already tested implicitly above, but let's be explicit)
setup_location=$(git config happy-trees.setupLocation)
if echo "$setup_location" | grep -q "<repo_root>"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config uses <repo_root> token\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config doesn't use <repo_root> token\n"
fi

# Test <repo_name> token - change config to use it
git config happy-trees.setupLocation "<repo_root>/<repo_name>-setup.sh"
cp "$TEST_REPO_DIR/setup-worktree.sh" "$TEST_REPO_DIR/test-repo-setup.sh"
chmod +x "$TEST_REPO_DIR/test-repo-setup.sh"

rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker"
assert_success "git_ht setup test-setup-wt" "Works with <repo_name> token in config"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker" "Setup script found via <repo_name> token"

# Test <worktree_root> token - useful for storing script in worktree itself
git config happy-trees.setupLocation "<worktree_root>/local-setup.sh"
cat > "$SANDBOX/test-repo.worktrees/test-setup-wt/local-setup.sh" <<'LOCALSETUP'
#!/usr/bin/env bash
REPO_ROOT="$1"
WORKTREE_ROOT="$2"
echo "local_setup_ran=yes" > "$WORKTREE_ROOT/.local-setup-marker"
LOCALSETUP
chmod +x "$SANDBOX/test-repo.worktrees/test-setup-wt/local-setup.sh"

rm -f "$SANDBOX/test-repo.worktrees/test-setup-wt/.setup-marker"
assert_success "git_ht setup test-setup-wt" "Works with <worktree_root> token in config"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-setup-wt/.local-setup-marker" "Setup script found via <worktree_root> token"

# Restore original config
git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"

# Test 23: Setup command - Error handling
printf "\n${YELLOW}Test Group: Setup Command - Error Handling${NC}\n"

# Test with non-existent script path
git config happy-trees.setupLocation "<repo_root>/nonexistent-setup.sh"
assert_output_contains "git_ht setup test-setup-wt" "not found" "Fails when script doesn't exist"

# Test with non-executable script
echo "#!/bin/sh" > "$TEST_REPO_DIR/non-exec-setup.sh"
git config happy-trees.setupLocation "<repo_root>/non-exec-setup.sh"
assert_output_contains "git_ht setup test-setup-wt" "not executable" "Fails when script is not executable"

# Restore config
git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"

# Test with script that fails (should report but not crash)
cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'FAILSCRIPT'
#!/usr/bin/env bash
exit 1
FAILSCRIPT
chmod +x "$TEST_REPO_DIR/setup-worktree.sh"

assert_output_contains "git_ht setup test-setup-wt" "failed" "Reports when setup script fails"

# Restore working script
cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'SETUPSCRIPT'
#!/usr/bin/env bash
REPO_ROOT="$1"
WORKTREE_ROOT="$2"
echo "Setup complete for worktree: $WORKTREE_ROOT"
SETUPSCRIPT
chmod +x "$TEST_REPO_DIR/setup-worktree.sh"

# Cleanup test worktrees
cd "$TEST_REPO_DIR"
assert_success "git_ht remove test-setup-wt --delete-branch --force" "Removes test-setup-wt"
assert_success "git_ht remove test-setup-wt-2 --delete-branch --force" "Removes test-setup-wt-2"

# Test 24: Automatic setup after create
printf "\n${YELLOW}Test Group: Automatic Setup After Create${NC}\n"

# Ensure we have setup configured
git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"

# Create a setup script that creates a marker file
cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'AUTOSETUPSCRIPT'
#!/usr/bin/env bash
REPO_ROOT="$1"
WORKTREE_ROOT="$2"
touch "$WORKTREE_ROOT/.auto-setup-complete"
echo "Auto-setup complete for: $WORKTREE_ROOT"
AUTOSETUPSCRIPT
chmod +x "$TEST_REPO_DIR/setup-worktree.sh"

# Test that create automatically runs setup
assert_success "git_ht create test-auto-setup" "Creates worktree with automatic setup"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-auto-setup/.auto-setup-complete" "Setup ran automatically after create"

# Test that --skip-setup prevents automatic setup
assert_success "git_ht create test-skip-setup --skip-setup" "Creates worktree with --skip-setup"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-skip-setup/.auto-setup-complete" "Setup was skipped with --skip-setup flag"

# Test that -s (short form) also skips setup
assert_success "git_ht create test-skip-setup-short -s" "Creates worktree with -s flag"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-skip-setup-short/.auto-setup-complete" "Setup was skipped with -s flag"

# Test automatic setup when setup config is not set
git config --unset happy-trees.setupLocation
assert_success "git_ht create test-no-setup-config" "Creates worktree when setup not configured"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-no-setup-config/.auto-setup-complete" "Setup silently skipped when not configured"

# Test automatic setup when setup script doesn't exist
git config happy-trees.setupLocation "<repo_root>/nonexistent.sh"
assert_success "git_ht create test-missing-script" "Creates worktree when setup script missing"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-missing-script/.auto-setup-complete" "Setup silently skipped when script missing"

# Test automatic setup when setup script is not executable
echo "#!/bin/sh" > "$TEST_REPO_DIR/non-exec.sh"
git config happy-trees.setupLocation "<repo_root>/non-exec.sh"
assert_success "git_ht create test-non-exec" "Creates worktree when setup script not executable"
assert_file_not_exists "$SANDBOX/test-repo.worktrees/test-non-exec/.auto-setup-complete" "Setup silently skipped when script not executable"

# Test that setup failure doesn't prevent worktree creation
cat > "$TEST_REPO_DIR/failing-setup.sh" <<'FAILSETUPSCRIPT'
#!/usr/bin/env bash
exit 1
FAILSETUPSCRIPT
chmod +x "$TEST_REPO_DIR/failing-setup.sh"
git config happy-trees.setupLocation "<repo_root>/failing-setup.sh"
assert_success "git_ht create test-failing-setup" "Creates worktree even when setup fails"
assert_file_exists "$SANDBOX/test-repo.worktrees/test-failing-setup" "Worktree created despite setup failure"

# Cleanup automatic setup test worktrees
assert_success "git_ht remove test-auto-setup --delete-branch --force" "Removes test-auto-setup"
assert_success "git_ht remove test-skip-setup --delete-branch --force" "Removes test-skip-setup"
assert_success "git_ht remove test-skip-setup-short --delete-branch --force" "Removes test-skip-setup-short"
assert_success "git_ht remove test-no-setup-config --delete-branch --force" "Removes test-no-setup-config"
assert_success "git_ht remove test-missing-script --delete-branch --force" "Removes test-missing-script"
assert_success "git_ht remove test-non-exec --delete-branch --force" "Removes test-non-exec"
assert_success "git_ht remove test-failing-setup --delete-branch --force" "Removes test-failing-setup"

# Cleanup test files
rm -f "$TEST_REPO_DIR/test-repo-setup.sh"
rm -f "$TEST_REPO_DIR/non-exec-setup.sh"
rm -f "$TEST_REPO_DIR/non-exec.sh"
rm -f "$TEST_REPO_DIR/failing-setup.sh"

# Cleanup config
git config --unset happy-trees.setupLocation || true

# Test 25: Setup --init with custom relative path
printf "\n${YELLOW}Test Group: Setup --init with Custom Path${NC}\n"

# Test relative path (should use <repo_root> token)
assert_success "git_ht setup --init scripts/initWorktree.sh" "Creates setup script at relative path"
assert_file_exists "$TEST_REPO_DIR/scripts/initWorktree.sh" "Script created at relative path"

# Verify script is executable
if [ -x "$TEST_REPO_DIR/scripts/initWorktree.sh" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Script at relative path is executable\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Script at relative path is not executable\n"
fi

# Verify config uses <repo_root> token
config_value=$(git config happy-trees.setupLocation)
if echo "$config_value" | grep -q "^<repo_root>/scripts/initWorktree.sh$"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config uses <repo_root> token for relative path\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config doesn't use <repo_root> token: %s\n" "$config_value"
fi

# Verify script contains shell template
if grep -q "#!/usr/bin/env bash" "$TEST_REPO_DIR/scripts/initWorktree.sh"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Shell script has bash shebang\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Shell script missing bash shebang\n"
fi

# Cleanup
rm -rf "$TEST_REPO_DIR/scripts"
git config --unset happy-trees.setupLocation || true

# Test 26: Setup --init with non-.sh extension
printf "\n${YELLOW}Test Group: Setup --init with Non-.sh Extension${NC}\n"

assert_success "git_ht setup --init scripts/initWorktree.js" "Creates setup script with .js extension"
assert_file_exists "$TEST_REPO_DIR/scripts/initWorktree.js" "Script created with .js extension"

# Verify script is NOT executable (non-shell scripts need manual chmod)
if [ ! -x "$TEST_REPO_DIR/scripts/initWorktree.js" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Non-.sh script is not auto-executable\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Non-.sh script was made executable\n"
fi

# Verify config is set correctly
config_value=$(git config happy-trees.setupLocation)
if echo "$config_value" | grep -q "^<repo_root>/scripts/initWorktree.js$"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config set correctly for .js file\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config incorrect for .js file: %s\n" "$config_value"
fi

# Verify script contains non-shell template with warning
if grep -q "non-.sh extension" "$TEST_REPO_DIR/scripts/initWorktree.js" && \
   grep -q "argv\[1\]" "$TEST_REPO_DIR/scripts/initWorktree.js"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Non-.sh script contains appropriate template\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Non-.sh script missing expected template content\n"
fi

# Cleanup
rm -rf "$TEST_REPO_DIR/scripts"
git config --unset happy-trees.setupLocation || true

# Test 27: Setup --init with absolute path (using ~)
printf "\n${YELLOW}Test Group: Setup --init with Absolute Path${NC}\n"

# Use sandbox for absolute path test to avoid polluting user's home
assert_success "git_ht setup --init '$SANDBOX/absolute-setup.sh'" "Creates setup script at absolute path"
assert_file_exists "$SANDBOX/absolute-setup.sh" "Script created at absolute path"

# Verify config uses literal path (not token)
config_value=$(git config happy-trees.setupLocation)
if [ "$config_value" = "$SANDBOX/absolute-setup.sh" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config uses literal absolute path\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config doesn't use literal path: %s\n" "$config_value"
fi

# Cleanup
rm -f "$SANDBOX/absolute-setup.sh"
git config --unset happy-trees.setupLocation || true

# Test 28: Setup --init creates parent directories
printf "\n${YELLOW}Test Group: Setup --init Creates Parent Directories${NC}\n"

assert_success "git_ht setup --init deeply/nested/path/setup.sh" "Creates setup script with nested directories"
assert_file_exists "$TEST_REPO_DIR/deeply/nested/path/setup.sh" "Script created in nested directory"

# Cleanup
rm -rf "$TEST_REPO_DIR/deeply"
git config --unset happy-trees.setupLocation || true

# Test 29: Setup --init with tilde path
printf "\n${YELLOW}Test Group: Setup --init with Tilde Path${NC}\n"

# Create a test directory in sandbox that we can reference with a path
# We'll test that ~ gets preserved in config but expanded for file creation
mkdir -p "$SANDBOX/home-test"
# We can't actually use ~ in tests easily, so we'll test the / prefix detection
assert_success "git_ht setup --init /tmp/git-ht-test-setup.sh" "Creates setup script at /tmp path"
assert_file_exists "/tmp/git-ht-test-setup.sh" "Script created at /tmp path"

config_value=$(git config happy-trees.setupLocation)
if [ "$config_value" = "/tmp/git-ht-test-setup.sh" ]; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config preserves absolute path with /\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config didn't preserve absolute path: %s\n" "$config_value"
fi

# Cleanup
rm -f "/tmp/git-ht-test-setup.sh"
git config --unset happy-trees.setupLocation || true

# Test 30: Setup --init safety checks
printf "\n${YELLOW}Test Group: Setup --init Safety Checks${NC}\n"

# Ensure clean state - remove any leftover setup script from previous tests
rm -f "$TEST_REPO_DIR/setup-worktree.sh"

# Test: --init fails if config already exists
git config happy-trees.setupLocation "<repo_root>/existing-setup.sh"
assert_output_contains "git_ht setup --init" "already configured" "Fails when setupLocation config already exists"
assert_output_contains "git_ht setup --init" "git config --unset" "Error message includes unset instruction"

# Verify no file was created
assert_file_not_exists "$TEST_REPO_DIR/setup-worktree.sh" "No file created when config exists"

git config --unset happy-trees.setupLocation

# Test: --init fails if destination file already exists
echo "existing content" > "$TEST_REPO_DIR/setup-worktree.sh"
assert_output_contains "git_ht setup --init" "already exists" "Fails when destination file already exists"
assert_output_contains "git_ht setup --init" "Choose a different path" "Error message suggests different path"

# Verify config was not set
if git config happy-trees.setupLocation >/dev/null 2>&1; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Config was set despite file existing\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Config was not set when file exists\n"
fi

# Verify original file was not modified
if grep -q "existing content" "$TEST_REPO_DIR/setup-worktree.sh"; then
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}✓${NC} Existing file was not modified\n"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}✗${NC} Existing file was modified\n"
fi

rm -f "$TEST_REPO_DIR/setup-worktree.sh"

# Test: --init with custom path fails if that file exists
mkdir -p "$TEST_REPO_DIR/scripts"
echo "existing script" > "$TEST_REPO_DIR/scripts/init.sh"
assert_output_contains "git_ht setup --init scripts/init.sh" "already exists" "Fails when custom path file exists"

# Cleanup
rm -rf "$TEST_REPO_DIR/scripts"
git config --unset happy-trees.setupLocation || true

# Test: Both checks - config exists AND file exists (config check should come first)
git config happy-trees.setupLocation "<repo_root>/some-other-path.sh"
echo "existing" > "$TEST_REPO_DIR/setup-worktree.sh"
assert_output_contains "git_ht setup --init" "already configured" "Config check happens before file check"

# Cleanup
rm -f "$TEST_REPO_DIR/setup-worktree.sh"
git config --unset happy-trees.setupLocation || true

# Print summary
printf "\n${YELLOW}=== Test Summary ===${NC}\n"
printf "Tests run:    %d\n" "$TESTS_RUN"
printf "Tests passed: ${GREEN}%d${NC}\n" "$TESTS_PASSED"
printf "Tests failed: ${RED}%d${NC}\n" "$TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
  printf "\n${GREEN}All tests passed!${NC}\n"
  exit 0
else
  printf "\n${RED}Some tests failed!${NC}\n"
  exit 1
fi
