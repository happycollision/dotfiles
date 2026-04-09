#!/bin/sh
# Test suite for git-ht (v2 API)
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
# Usage: setup_test_repo [bare]
#   bare - create local repo as a bare clone (worktree-only workflow)
setup_test_repo() {
  local mode="${1:-normal}"
  printf "${YELLOW}Setting up test repository (mode: %s)...${NC}\n" "$mode"

  # Remove any existing sandbox
  rm -rf "$SANDBOX"

  # Create bare origin repo
  mkdir -p "$SANDBOX/origin.git"
  git init -q --bare "$SANDBOX/origin.git"

  if [ "$mode" = "bare" ]; then
    # Seed the origin with commits so the bare clone has content
    local seed_dir="$SANDBOX/seed-repo"
    mkdir -p "$seed_dir"
    cd "$seed_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "# Test Repository" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    echo "Content 1" > file1.txt
    git add file1.txt
    git commit -q -m "Add file1"
    echo "Content 2" > file2.txt
    git add file2.txt
    git commit -q -m "Add file2"
    git branch -M master
    git remote add origin "$SANDBOX/origin.git"
    git push -q -u origin master
    cd "$SANDBOX"
    rm -rf "$seed_dir"

    # Bare clone from origin
    git clone -q --bare "$SANDBOX/origin.git" "$TEST_REPO_DIR"
    cd "$TEST_REPO_DIR"
    git config user.name "Test User"
    git config user.email "test@example.com"
  else
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

    # Set up default branch as master
    git branch -M master

    # Add the bare repo as origin and push
    git remote add origin "$SANDBOX/origin.git"
    git push -q -u origin master
  fi

  # Set worktreesDir explicitly to avoid path resolution issues with ../
  git config happy-trees.worktreesDir "$SANDBOX/test-repo.worktrees"

  # Override global exec config (e.g. "code") so no editor opens during tests
  git config happy-trees.exec ""

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

# ============================================================================
# Run all tests against the current test repo
# Usage: run_all_tests
# ============================================================================
run_all_tests() {

  # ============================================================================
  # Test Group 1: Help and Basic Commands
  # ============================================================================
  printf "${YELLOW}Test Group: Help and Basic Commands${NC}\n"
  assert_output_contains "git_ht --help" "Usage: git ht" "git ht --help shows usage information"
  assert_output_contains "git_ht -h" "Usage: git ht" "git ht -h shows usage information"
  assert_output_contains "git_ht" "Usage: git ht" "git ht without args shows help"
  assert_output_contains "git_ht help" "Usage: git ht" "git ht help shows usage information"
  assert_output_contains "git_ht --help" "checkout" "Help mentions checkout command"
  assert_output_contains "git_ht --help" "co" "Help mentions co alias"
  assert_output_contains "git_ht --help" "remove" "Help mentions remove command"
  assert_output_contains "git_ht --help" "destroy" "Help mentions destroy command"
  assert_output_contains "git_ht --help" "setup" "Help mentions setup command"
  assert_output_contains "git_ht bogus-command" "Unknown subcommand" "Unknown subcommand shows error"
  
  # ============================================================================
  # Test Group 2: Checkout - new branch
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - New Branch${NC}\n"
  assert_success "git_ht co new-branch-1" "Creates worktree with new branch from default"
  assert_file_exists "$SANDBOX/test-repo.worktrees/new-branch-1" "Worktree directory exists in correct location"
  assert_success "git worktree list | grep -q new-branch-1" "Worktree appears in git worktree list"
  assert_success "git branch --list new-branch-1 | grep -q new-branch-1" "Branch was created"
  
  # Verify it was created from master (default branch)
  wt_head=$(git -C "$SANDBOX/test-repo.worktrees/new-branch-1" rev-parse HEAD)
  master_head=$(git rev-parse master)
  if [ "$wt_head" = "$master_head" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} New branch starts from default branch (master)\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} New branch does not start from default branch\n"
  fi
  
  # Also test using the full 'checkout' command name
  assert_success "git_ht checkout new-branch-full" "Creates worktree with 'checkout' (full name)"
  assert_file_exists "$SANDBOX/test-repo.worktrees/new-branch-full" "Worktree exists for full checkout command"
  git worktree remove "$SANDBOX/test-repo.worktrees/new-branch-full"
  git branch -D new-branch-full
  
  # ============================================================================
  # Test Group 3: Checkout - new branch with base
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - New Branch with Base${NC}\n"
  assert_success "git_ht co new-branch-base HEAD~1" "Creates worktree from specific ref"
  assert_file_exists "$SANDBOX/test-repo.worktrees/new-branch-base" "Worktree created from specific ref"
  
  # Verify it's at the right commit
  commit_hash=$(git -C "$SANDBOX/test-repo.worktrees/new-branch-base" rev-parse HEAD)
  expected_hash=$(git rev-parse HEAD~1)
  if [ "$commit_hash" = "$expected_hash" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Worktree HEAD is at correct commit (HEAD~1)\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Worktree HEAD is at wrong commit\n"
  fi
  
  # Cleanup
  git worktree remove "$SANDBOX/test-repo.worktrees/new-branch-base"
  git branch -D new-branch-base
  
  # ============================================================================
  # Test Group 4: Checkout - existing branch (auto-detected)
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Existing Branch${NC}\n"
  
  # Create a branch without a worktree first
  git branch existing-branch HEAD~1
  
  assert_success "git_ht co existing-branch" "Creates worktree for existing branch (auto-detected)"
  assert_file_exists "$SANDBOX/test-repo.worktrees/existing-branch" "Worktree directory exists for existing branch"
  
  # Verify it's on the existing branch's commit (HEAD~1)
  existing_head=$(git -C "$SANDBOX/test-repo.worktrees/existing-branch" rev-parse HEAD)
  expected_existing=$(git rev-parse HEAD~1)
  if [ "$existing_head" = "$expected_existing" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Worktree is on existing branch's commit\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Worktree is not on existing branch's commit\n"
  fi
  
  # ============================================================================
  # Test Group 5: Checkout - existing worktree (already checked out)
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Existing Worktree${NC}\n"
  
  # existing-branch already has a worktree from above
  assert_output_contains "git_ht co existing-branch" "already exists" "Reports worktree already exists"
  
  # ============================================================================
  # Test Group 6: Checkout - base arg errors
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Base Arg Errors${NC}\n"
  
  # existing-branch already exists as a branch, so providing a base should error
  assert_output_contains "git_ht co existing-branch some-base" "not valid" "Errors when base given for existing branch with worktree"
  
  # Remove the worktree but keep the branch
  git worktree remove "$SANDBOX/test-repo.worktrees/existing-branch"
  
  # Try again without a worktree — branch still exists, base still invalid
  assert_output_contains "git_ht co existing-branch some-base" "not valid" "Errors when base given for existing branch without worktree"
  
  # Cleanup
  git branch -D existing-branch
  
  # ============================================================================
  # Test Group 7: Checkout - exec flag
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Exec Flag${NC}\n"
  
  # Create a test script that writes to a marker file when called
  mkdir -p "$SANDBOX/test-commands"
  cat > "$SANDBOX/test-commands/test-cmd" <<'TESTCMD'
  #!/bin/sh
  echo "$1" > "$TEST_MARKER_FILE"
TESTCMD
  chmod +x "$SANDBOX/test-commands/test-cmd"
  
  export TEST_MARKER_FILE="$SANDBOX/exec-test-marker.txt"
  export PATH="$SANDBOX/test-commands:$PATH"
  
  # Test -e flag on new worktree creation
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-test-1 -e test-cmd" "Creates worktree with -e test-cmd"
  assert_file_exists "$TEST_MARKER_FILE" "Exec command was executed (marker file exists)"
  
  # Verify command received correct path
  if [ -f "$TEST_MARKER_FILE" ]; then
    received_path=$(cd "$(cat "$TEST_MARKER_FILE")" && pwd)
    expected_path=$(cd "$SANDBOX/test-repo.worktrees/exec-test-1" && pwd)
    if [ "$received_path" = "$expected_path" ]; then
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}✓${NC} Exec command received correct worktree path\n"
    else
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "${RED}✗${NC} Exec command received wrong path\n"
      printf "  Expected: %s\n" "$expected_path"
      printf "  Received: %s\n" "$received_path"
    fi
  fi
  
  # Test -e flag on existing worktree checkout (re-visit)
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-test-1 -e test-cmd" "Re-checkout existing worktree with -e test-cmd"
  assert_file_exists "$TEST_MARKER_FILE" "Exec command ran on existing worktree checkout"
  
  # Test -E flag skips exec (even if -e is not provided, but config might be set)
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-test-1 -E" "Re-checkout with -E skips exec"
  assert_file_not_exists "$TEST_MARKER_FILE" "No exec command ran with -E flag"
  
  # Test with long forms
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-test-1 --exec test-cmd" "Re-checkout with --exec (long form)"
  assert_file_exists "$TEST_MARKER_FILE" "Exec command ran with --exec long form"
  
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-test-1 --no-exec" "Re-checkout with --no-exec (long form)"
  assert_file_not_exists "$TEST_MARKER_FILE" "No exec command ran with --no-exec long form"
  
  # Cleanup exec-test-1
  git worktree remove "$SANDBOX/test-repo.worktrees/exec-test-1"
  git branch -D exec-test-1
  
  # Test non-existent command (should warn but not fail)
  assert_output_contains "git_ht co exec-test-noexist -e nonexistent-command-xyz" "not found" "Warns when exec command not found"
  assert_file_exists "$SANDBOX/test-repo.worktrees/exec-test-noexist" "Worktree still created when exec command not found"
  git worktree remove "$SANDBOX/test-repo.worktrees/exec-test-noexist"
  git branch -D exec-test-noexist
  
  # Test failing command (should warn but not fail)
  cat > "$SANDBOX/test-commands/fail-cmd" <<'FAILCMD'
  #!/bin/sh
  exit 1
FAILCMD
  chmod +x "$SANDBOX/test-commands/fail-cmd"
  
  assert_output_contains "git_ht co exec-test-fail -e fail-cmd" "failed" "Warns when exec command fails"
  assert_file_exists "$SANDBOX/test-repo.worktrees/exec-test-fail" "Worktree still created when exec command fails"
  git worktree remove "$SANDBOX/test-repo.worktrees/exec-test-fail"
  git branch -D exec-test-fail
  
  rm -f "$TEST_MARKER_FILE"
  
  # ============================================================================
  # Test Group 8: Checkout - exec config default
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Exec Config Default${NC}\n"
  
  git config happy-trees.exec test-cmd
  
  # Test that config default is used on create
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-config-1" "Creates worktree using default exec from config"
  assert_file_exists "$TEST_MARKER_FILE" "Default exec command was executed on create"
  
  # Test that config default is used on existing worktree checkout
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-config-1" "Re-checkout triggers default exec"
  assert_file_exists "$TEST_MARKER_FILE" "Default exec command was executed on existing worktree"
  
  # Test that -E skips the config default
  rm -f "$TEST_MARKER_FILE"
  assert_success "git_ht co exec-config-1 -E" "Re-checkout with -E skips config default"
  assert_file_not_exists "$TEST_MARKER_FILE" "Config default exec skipped with -E"
  
  # Test that explicit -e overrides the config default
  rm -f "$TEST_MARKER_FILE"
  cat > "$SANDBOX/test-commands/other-cmd" <<'OTHERCMD'
  #!/bin/sh
  echo "other:$1" > "$TEST_MARKER_FILE"
OTHERCMD
  chmod +x "$SANDBOX/test-commands/other-cmd"
  
  assert_success "git_ht co exec-config-1 -e other-cmd" "Re-checkout with explicit -e overrides config"
  if [ -f "$TEST_MARKER_FILE" ]; then
    if grep -q "^other:" "$TEST_MARKER_FILE"; then
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}✓${NC} Explicit -e flag overrides config default\n"
    else
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "${RED}✗${NC} Config default was used instead of explicit -e\n"
    fi
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} No command was executed\n"
  fi
  
  # Cleanup - restore empty exec to prevent global config leaking
  git config happy-trees.exec ""
  git worktree remove "$SANDBOX/test-repo.worktrees/exec-config-1"
  git branch -D exec-config-1
  rm -f "$TEST_MARKER_FILE"
  
  # ============================================================================
  # Test Group 9: Checkout - skip setup
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Skip Setup${NC}\n"
  
  # Set up a setup script that creates a marker file
  git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"
  cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'SETUPSCRIPT'
  #!/usr/bin/env bash
  REPO_ROOT="$1"
  WORKTREE_ROOT="$2"
  touch "$WORKTREE_ROOT/.setup-ran"
SETUPSCRIPT
  chmod +x "$TEST_REPO_DIR/setup-worktree.sh"
  
  # Test -s skips setup
  assert_success "git_ht co skip-setup-1 -s" "Creates worktree with -s (skip setup)"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/skip-setup-1/.setup-ran" "Setup was skipped with -s flag"
  git worktree remove "$SANDBOX/test-repo.worktrees/skip-setup-1"
  git branch -D skip-setup-1
  
  # Test --skip-setup
  assert_success "git_ht co skip-setup-2 --skip-setup" "Creates worktree with --skip-setup"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/skip-setup-2/.setup-ran" "Setup was skipped with --skip-setup flag"
  git worktree remove "$SANDBOX/test-repo.worktrees/skip-setup-2"
  git branch -D skip-setup-2
  
  # Cleanup config
  git config --unset happy-trees.setupLocation
  rm -f "$TEST_REPO_DIR/setup-worktree.sh"
  
  # ============================================================================
  # Test Group 10: Checkout - auto setup
  # ============================================================================
  printf "\n${YELLOW}Test Group: Checkout - Auto Setup${NC}\n"
  
  # Set up a setup script
  git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"
  cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'AUTOSETUPSCRIPT'
  #!/usr/bin/env bash
  REPO_ROOT="$1"
  WORKTREE_ROOT="$2"
  touch "$WORKTREE_ROOT/.auto-setup-complete"
AUTOSETUPSCRIPT
  chmod +x "$TEST_REPO_DIR/setup-worktree.sh"
  
  # Test that create automatically runs setup
  assert_success "git_ht co auto-setup-1" "Creates worktree with automatic setup"
  assert_file_exists "$SANDBOX/test-repo.worktrees/auto-setup-1/.auto-setup-complete" "Setup ran automatically after create"
  git worktree remove --force "$SANDBOX/test-repo.worktrees/auto-setup-1"
  git branch -D auto-setup-1
  
  # Test without setup configured (should still create worktree)
  git config --unset happy-trees.setupLocation
  assert_success "git_ht co auto-setup-2" "Creates worktree when setup not configured"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/auto-setup-2/.auto-setup-complete" "Setup silently skipped when not configured"
  git worktree remove "$SANDBOX/test-repo.worktrees/auto-setup-2"
  git branch -D auto-setup-2
  
  # Test with non-existent setup script (should still create worktree)
  git config happy-trees.setupLocation "<repo_root>/nonexistent.sh"
  assert_success "git_ht co auto-setup-3" "Creates worktree when setup script missing"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/auto-setup-3/.auto-setup-complete" "Setup silently skipped when script missing"
  git worktree remove "$SANDBOX/test-repo.worktrees/auto-setup-3"
  git branch -D auto-setup-3
  
  # Test with non-executable setup script (should still create worktree)
  echo "#!/bin/sh" > "$TEST_REPO_DIR/non-exec.sh"
  git config happy-trees.setupLocation "<repo_root>/non-exec.sh"
  assert_success "git_ht co auto-setup-4" "Creates worktree when setup script not executable"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/auto-setup-4/.auto-setup-complete" "Setup silently skipped when script not executable"
  git worktree remove "$SANDBOX/test-repo.worktrees/auto-setup-4"
  git branch -D auto-setup-4
  
  # Test that setup failure doesn't prevent worktree creation
  cat > "$TEST_REPO_DIR/failing-setup.sh" <<'FAILSETUPSCRIPT'
  #!/usr/bin/env bash
  exit 1
FAILSETUPSCRIPT
  chmod +x "$TEST_REPO_DIR/failing-setup.sh"
  git config happy-trees.setupLocation "<repo_root>/failing-setup.sh"
  assert_success "git_ht co auto-setup-5" "Creates worktree even when setup fails"
  assert_file_exists "$SANDBOX/test-repo.worktrees/auto-setup-5" "Worktree created despite setup failure"
  git worktree remove "$SANDBOX/test-repo.worktrees/auto-setup-5"
  git branch -D auto-setup-5
  
  # Cleanup
  git config --unset happy-trees.setupLocation || true
  rm -f "$TEST_REPO_DIR/setup-worktree.sh" "$TEST_REPO_DIR/non-exec.sh" "$TEST_REPO_DIR/failing-setup.sh"
  
  # ============================================================================
  # Test Group 11: Remove - basic
  # ============================================================================
  printf "\n${YELLOW}Test Group: Remove - Basic${NC}\n"
  
  assert_success "git_ht co remove-test-1" "Creates worktree for remove test"
  assert_file_exists "$SANDBOX/test-repo.worktrees/remove-test-1" "Worktree exists before remove"
  assert_success "git_ht remove remove-test-1" "Removes worktree"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/remove-test-1" "Worktree directory removed"
  # Branch should still exist (no remote branch, so no auto-cleanup)
  assert_success "git branch --list remove-test-1 | grep -q remove-test-1" "Local branch still exists after remove"
  git branch -D remove-test-1
  
  # Test removing non-existent worktree
  assert_output_contains "git_ht remove nonexistent-wt" "No worktree found" "Fails gracefully when removing non-existent worktree"
  
  # ============================================================================
  # Test Group 12: Remove - auto branch cleanup (SHA matching)
  # ============================================================================
  printf "\n${YELLOW}Test Group: Remove - Auto Branch Cleanup${NC}\n"
  
  # Scenario 1: Local and remote SHA match -> branch auto-deleted
  assert_success "git_ht co cleanup-match" "Creates worktree for SHA-match test"
  # Push the branch to origin so local and remote match
  git push -q origin cleanup-match
  # Fetch so we have the remote tracking ref
  git fetch -q origin
  assert_success "git_ht remove cleanup-match" "Removes worktree (SHA match scenario)"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/cleanup-match" "Worktree directory removed"
  # Local branch should be auto-deleted since SHAs match
  assert_failure "git branch --list cleanup-match | grep -q cleanup-match" "Local branch auto-deleted when SHA matches remote"
  # Cleanup remote branch
  git push -q origin --delete cleanup-match || true
  
  # Scenario 2: Local and remote SHA don't match -> branch preserved
  assert_success "git_ht co cleanup-nomatch" "Creates worktree for SHA-nomatch test"
  git push -q origin cleanup-nomatch
  git fetch -q origin
  # Make a local commit so SHAs diverge
  git -C "$SANDBOX/test-repo.worktrees/cleanup-nomatch" commit -q --allow-empty -m "local diverge"
  assert_success "git_ht remove cleanup-nomatch" "Removes worktree (SHA mismatch scenario)"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/cleanup-nomatch" "Worktree directory removed"
  # Local branch should still exist since SHAs differ
  assert_success "git branch --list cleanup-nomatch | grep -q cleanup-nomatch" "Local branch preserved when SHA differs from remote"
  # Cleanup
  git branch -D cleanup-nomatch
  git push -q origin --delete cleanup-nomatch || true
  
  # Scenario 3: No remote branch -> branch preserved
  assert_success "git_ht co cleanup-noremote" "Creates worktree for no-remote test"
  # Don't push to origin
  assert_success "git_ht remove cleanup-noremote" "Removes worktree (no remote scenario)"
  # Local branch should still exist
  assert_success "git branch --list cleanup-noremote | grep -q cleanup-noremote" "Local branch preserved when no remote branch exists"
  git branch -D cleanup-noremote
  
  # ============================================================================
  # Test Group 13: Remove - force
  # ============================================================================
  printf "\n${YELLOW}Test Group: Remove - Force${NC}\n"
  
  assert_success "git_ht co force-remove-test" "Creates worktree for force remove test"
  
  # Make the worktree dirty (uncommitted changes)
  echo "dirty content" > "$SANDBOX/test-repo.worktrees/force-remove-test/dirty-file.txt"
  git -C "$SANDBOX/test-repo.worktrees/force-remove-test" add dirty-file.txt
  
  # Regular remove should fail
  assert_failure "git_ht remove force-remove-test" "Regular remove fails on dirty worktree"
  assert_file_exists "$SANDBOX/test-repo.worktrees/force-remove-test" "Dirty worktree still exists after failed remove"
  
  # Force remove should succeed
  assert_success "git_ht remove force-remove-test --force" "Force remove succeeds on dirty worktree"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/force-remove-test" "Dirty worktree removed with --force"
  git branch -D force-remove-test
  
  # ============================================================================
  # Test Group 14: Destroy - basic
  # ============================================================================
  printf "\n${YELLOW}Test Group: Destroy - Basic${NC}\n"
  
  assert_success "git_ht co destroy-test-1" "Creates worktree for destroy test"
  # Push to remote so destroy can delete both
  git push -q origin destroy-test-1
  git fetch -q origin
  
  assert_success "git_ht destroy destroy-test-1" "Destroys worktree + branches"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/destroy-test-1" "Worktree directory removed by destroy"
  assert_failure "git branch --list destroy-test-1 | grep -q destroy-test-1" "Local branch deleted by destroy"
  # Verify remote branch is gone
  assert_failure "git ls-remote --heads origin destroy-test-1 | grep -q destroy-test-1" "Remote branch deleted by destroy"
  
  # Test destroy with --force on dirty worktree
  assert_success "git_ht co destroy-test-2" "Creates worktree for force destroy test"
  echo "dirty" > "$SANDBOX/test-repo.worktrees/destroy-test-2/dirty.txt"
  git -C "$SANDBOX/test-repo.worktrees/destroy-test-2" add dirty.txt
  assert_failure "git_ht destroy destroy-test-2" "Regular destroy fails on dirty worktree"
  assert_success "git_ht destroy destroy-test-2 --force" "Force destroy succeeds on dirty worktree"
  assert_file_not_exists "$SANDBOX/test-repo.worktrees/destroy-test-2" "Dirty worktree removed by force destroy"
  assert_failure "git branch --list destroy-test-2 | grep -q destroy-test-2" "Local branch deleted by force destroy"
  
  # ============================================================================
  # Test Group 15: Destroy - default branch protection
  # ============================================================================
  printf "\n${YELLOW}Test Group: Destroy - Default Branch Protection${NC}\n"
  
  # Trying to destroy master (the default branch) should fail.
  # We need a worktree for master first. But master is the current branch in the
  # main repo, so we can't create a worktree for it directly. Instead, test the
  # error message by just calling destroy with the branch name.
  assert_output_contains "git_ht destroy master" "Cannot destroy the default branch" "Errors when trying to destroy default branch"
  
  # ============================================================================
  # Test Group 16: Setup - init
  # ============================================================================
  printf "\n${YELLOW}Test Group: Setup - Init Mode${NC}\n"
  
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
  
  # Cleanup init test
  rm -f "$TEST_REPO_DIR/setup-worktree.sh"
  git config --unset happy-trees.setupLocation
  
  # Test --init with custom relative path
  assert_success "git_ht setup --init scripts/initWorktree.sh" "Creates setup script at relative path"
  assert_file_exists "$TEST_REPO_DIR/scripts/initWorktree.sh" "Script created at relative path"
  
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
  
  rm -rf "$TEST_REPO_DIR/scripts"
  git config --unset happy-trees.setupLocation
  
  # Test --init with absolute path
  assert_success "git_ht setup --init '$SANDBOX/absolute-setup.sh'" "Creates setup script at absolute path"
  assert_file_exists "$SANDBOX/absolute-setup.sh" "Script created at absolute path"
  
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
  
  rm -f "$SANDBOX/absolute-setup.sh"
  git config --unset happy-trees.setupLocation
  
  # Test --init with non-.sh extension
  assert_success "git_ht setup --init scripts/initWorktree.js" "Creates setup script with .js extension"
  assert_file_exists "$TEST_REPO_DIR/scripts/initWorktree.js" "Script created with .js extension"
  
  if [ ! -x "$TEST_REPO_DIR/scripts/initWorktree.js" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}✓${NC} Non-.sh script is not auto-executable\n"
  else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}✗${NC} Non-.sh script was made executable\n"
  fi
  
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
  
  rm -rf "$TEST_REPO_DIR/scripts"
  git config --unset happy-trees.setupLocation
  
  # Test --init creates nested parent directories
  assert_success "git_ht setup --init deeply/nested/path/setup.sh" "Creates setup script with nested directories"
  assert_file_exists "$TEST_REPO_DIR/deeply/nested/path/setup.sh" "Script created in nested directory"
  rm -rf "$TEST_REPO_DIR/deeply"
  git config --unset happy-trees.setupLocation
  
  # Test --init safety: fails if config already exists
  git config happy-trees.setupLocation "<repo_root>/existing-setup.sh"
  assert_output_contains "git_ht setup --init" "already configured" "Fails when setupLocation config already exists"
  assert_file_not_exists "$TEST_REPO_DIR/setup-worktree.sh" "No file created when config exists"
  git config --unset happy-trees.setupLocation
  
  # Test --init safety: fails if file already exists
  echo "existing content" > "$TEST_REPO_DIR/setup-worktree.sh"
  assert_output_contains "git_ht setup --init" "already exists" "Fails when destination file already exists"
  rm -f "$TEST_REPO_DIR/setup-worktree.sh"
  git config --unset happy-trees.setupLocation || true
  
  # ============================================================================
  # Test Group 17: Setup - run from worktree
  # ============================================================================
  printf "\n${YELLOW}Test Group: Setup - Run from Worktree${NC}\n"
  
  # Set up a working setup script and config
  git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"
  cat > "$TEST_REPO_DIR/setup-worktree.sh" <<'SETUPSCRIPT'
  #!/usr/bin/env bash
  REPO_ROOT="$1"
  WORKTREE_ROOT="$2"
  echo "repo_root=$REPO_ROOT" > "$WORKTREE_ROOT/.setup-marker"
  echo "worktree_root=$WORKTREE_ROOT" >> "$WORKTREE_ROOT/.setup-marker"
  echo "Setup complete" > "$WORKTREE_ROOT/.setup-complete"
SETUPSCRIPT
  chmod +x "$TEST_REPO_DIR/setup-worktree.sh"
  
  # Create a worktree for testing setup
  assert_success "git_ht co setup-run-test -s" "Creates worktree for setup run test (skip auto-setup)"
  
  # Run setup from inside the worktree
  cd "$SANDBOX/test-repo.worktrees/setup-run-test"
  assert_success "git_ht setup" "Runs setup from inside worktree"
  assert_file_exists "$SANDBOX/test-repo.worktrees/setup-run-test/.setup-marker" "Setup script created marker file"
  assert_file_exists "$SANDBOX/test-repo.worktrees/setup-run-test/.setup-complete" "Setup script completed successfully"
  
  # Verify arguments were passed correctly
  if [ -f "$SANDBOX/test-repo.worktrees/setup-run-test/.setup-marker" ]; then
    marker_content=$(cat "$SANDBOX/test-repo.worktrees/setup-run-test/.setup-marker")
    expected_repo_root=$(cd "$TEST_REPO_DIR" && pwd)
    expected_worktree_root=$(cd "$SANDBOX/test-repo.worktrees/setup-run-test" && pwd)
  
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
  
  # Cleanup
  git worktree remove --force "$SANDBOX/test-repo.worktrees/setup-run-test"
  git branch -D setup-run-test
  
  # Cleanup setup script and config from prior group
  rm -f "$TEST_REPO_DIR/setup-worktree.sh"
  git config --unset happy-trees.setupLocation
  
  # ============================================================================
  # Test Group: Setup - Token Expansion
  # ============================================================================
  printf "\n${YELLOW}Test Group: Setup - Token Expansion${NC}\n"
  
  # Create a setup script that records the arguments it receives
  cat > "$TEST_REPO_DIR/token-test-setup.sh" <<'TOKENSCRIPT'
  #!/usr/bin/env bash
  REPO_ROOT="$1"
  WORKTREE_ROOT="$2"
  echo "repo_root=$REPO_ROOT" > "$WORKTREE_ROOT/.token-marker"
  echo "worktree_root=$WORKTREE_ROOT" >> "$WORKTREE_ROOT/.token-marker"
TOKENSCRIPT
  chmod +x "$TEST_REPO_DIR/token-test-setup.sh"
  
  # Test <repo_root> token in setupLocation
  git config happy-trees.setupLocation "<repo_root>/token-test-setup.sh"
  assert_success "git_ht co token-test-1 -s" "Creates worktree for token expansion test"
  cd "$SANDBOX/test-repo.worktrees/token-test-1"
  assert_success "git_ht setup" "Runs setup with <repo_root> token in setupLocation"
  assert_file_exists "$SANDBOX/test-repo.worktrees/token-test-1/.token-marker" "Setup script ran with <repo_root> token"
  
  # Verify <repo_root> expanded correctly (script received correct repo root)
  if [ -f "$SANDBOX/test-repo.worktrees/token-test-1/.token-marker" ]; then
    expected_repo_root=$(cd "$TEST_REPO_DIR" && pwd)
    if grep -q "repo_root=$expected_repo_root" "$SANDBOX/test-repo.worktrees/token-test-1/.token-marker"; then
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}✓${NC} <repo_root> token expanded correctly in setupLocation\n"
    else
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "${RED}✗${NC} <repo_root> token did not expand correctly\n"
    fi
  fi
  
  # Verify <worktree_root> was passed correctly as argument to setup script
  if [ -f "$SANDBOX/test-repo.worktrees/token-test-1/.token-marker" ]; then
    expected_wt_root=$(cd "$SANDBOX/test-repo.worktrees/token-test-1" && pwd)
    if grep -q "worktree_root=$expected_wt_root" "$SANDBOX/test-repo.worktrees/token-test-1/.token-marker"; then
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}✓${NC} Worktree root passed correctly to setup script\n"
    else
      TESTS_RUN=$((TESTS_RUN + 1))
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "${RED}✗${NC} Worktree root not passed correctly\n"
    fi
  fi
  
  cd "$TEST_REPO_DIR"
  git worktree remove --force "$SANDBOX/test-repo.worktrees/token-test-1"
  git branch -D token-test-1
  
  # Test <repo_name> token in worktreesDir
  # Save original worktreesDir and set one using <repo_name>
  original_wt_dir=$(git config happy-trees.worktreesDir)
  git config happy-trees.worktreesDir "$SANDBOX/<repo_name>.trees"
  assert_success "git_ht co token-test-2 -s" "Creates worktree with <repo_name> token in worktreesDir"
  assert_file_exists "$SANDBOX/test-repo.trees/token-test-2" "Worktree created in directory with expanded <repo_name>"
  
  # Cleanup
  git worktree remove --force "$SANDBOX/test-repo.trees/token-test-2"
  git branch -D token-test-2
  rm -rf "$SANDBOX/test-repo.trees"
  git config happy-trees.worktreesDir "$original_wt_dir"
  
  # Test <worktree_root> token in setupLocation
  cat > "$TEST_REPO_DIR/wt-token-setup.sh" <<'WTTOKENSCRIPT'
  #!/usr/bin/env bash
  echo "ran" > "$2/.wt-token-ran"
WTTOKENSCRIPT
  chmod +x "$TEST_REPO_DIR/wt-token-setup.sh"
  
  # Use a setupLocation that uses <repo_root> to point to the script
  git config happy-trees.setupLocation "<repo_root>/wt-token-setup.sh"
  assert_success "git_ht co token-test-3 -s" "Creates worktree for <worktree_root> token test"
  cd "$SANDBOX/test-repo.worktrees/token-test-3"
  assert_success "git_ht setup" "Runs setup script located via <repo_root> token"
  assert_file_exists "$SANDBOX/test-repo.worktrees/token-test-3/.wt-token-ran" "Setup script ran in worktree context"
  
  cd "$TEST_REPO_DIR"
  git worktree remove --force "$SANDBOX/test-repo.worktrees/token-test-3"
  git branch -D token-test-3
  
  # Cleanup
  rm -f "$TEST_REPO_DIR/token-test-setup.sh" "$TEST_REPO_DIR/wt-token-setup.sh"
  git config --unset happy-trees.setupLocation
  
  # ============================================================================
  # Test Group: Setup - Errors
  # ============================================================================
  printf "\n${YELLOW}Test Group: Setup - Errors${NC}\n"
  
  # Test: not configured
  git config --unset happy-trees.setupLocation || true
  assert_output_contains "git_ht setup" "not configured" "Fails gracefully when setupLocation not configured"
  
  # Test: not in a linked worktree (running from main repo)
  git config happy-trees.setupLocation "<repo_root>/setup-worktree.sh"
  assert_output_contains "git_ht setup" "linked worktree" "Fails when run from main worktree"
  
  # Test: script not found
  assert_success "git_ht co setup-err-test -s" "Creates worktree for setup error test"
  cd "$SANDBOX/test-repo.worktrees/setup-err-test"
  git config happy-trees.setupLocation "<repo_root>/nonexistent-setup.sh"
  assert_output_contains "git_ht setup" "not found" "Fails when script doesn't exist"
  
  # Test: script not executable
  echo "#!/bin/sh" > "$TEST_REPO_DIR/non-exec-setup.sh"
  git config happy-trees.setupLocation "<repo_root>/non-exec-setup.sh"
  assert_output_contains "git_ht setup" "not executable" "Fails when script is not executable"
  
  # Test: script fails
  cat > "$TEST_REPO_DIR/fail-setup.sh" <<'FAILSCRIPT'
  #!/usr/bin/env bash
  exit 1
FAILSCRIPT
  chmod +x "$TEST_REPO_DIR/fail-setup.sh"
  git config happy-trees.setupLocation "<repo_root>/fail-setup.sh"
  assert_output_contains "git_ht setup" "failed" "Reports when setup script fails"
  
  # Return to test repo and cleanup
  cd "$TEST_REPO_DIR"
  git worktree remove --force "$SANDBOX/test-repo.worktrees/setup-err-test"
  git branch -D setup-err-test
  rm -f "$TEST_REPO_DIR/setup-worktree.sh" "$TEST_REPO_DIR/non-exec-setup.sh" "$TEST_REPO_DIR/fail-setup.sh"
  git config --unset happy-trees.setupLocation || true
  
  # Cleanup remaining worktree from group 2
  git worktree remove "$SANDBOX/test-repo.worktrees/new-branch-1" 2>/dev/null || true
  git branch -D new-branch-1 2>/dev/null || true
  
  # Cleanup test commands
  rm -rf "$SANDBOX/test-commands"
  rm -f "$TEST_MARKER_FILE"
  
} # end run_all_tests

# ============================================================================
# Run both passes
# ============================================================================

# Pass 1: Normal (non-bare) local repo
setup_test_repo normal
printf "\n${YELLOW}=== Testing git-ht (normal repo) ===${NC}\n\n"
run_all_tests
cleanup

# Pass 2: Bare local repo
setup_test_repo bare
printf "\n${YELLOW}=== Testing git-ht (bare repo) ===${NC}\n\n"
run_all_tests

# ============================================================================
# Print summary
# ============================================================================
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
