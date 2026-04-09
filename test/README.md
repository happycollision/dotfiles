# Tests for dotfiles

This directory contains test suites for custom git extensions and other dotfiles utilities.

## git-ht Tests

The `git-ht-test.sh` script provides comprehensive regression testing for the `git ht` worktree plugin.

### Running the Tests

From the dotfiles repository root:

```sh
./test/git-ht-test.sh
```

### What's Tested

The test suite covers:

1. **Help and Basic Commands**
   - Help text display, subcommand routing, error on unknown commands

2. **Checkout (`co`)**
   - New branch creation (from default, from specific base ref)
   - Existing branch detection (auto-creates worktree)
   - Existing worktree detection (runs exec only)
   - Base argument error handling
   - `--exec` / `--no-exec` flags and config default
   - `--skip-setup` flag
   - Automatic setup execution on create

3. **Remove**
   - Basic worktree removal
   - Auto-deletion of local branch when remote SHA matches
   - Preservation of local branch when SHAs differ or no remote exists
   - `--force` flag for dirty worktrees

4. **Destroy**
   - Worktree + local + remote branch deletion
   - Default branch protection
   - `--force` flag for dirty worktrees

5. **Cross-worktree Commands**
   - Checkout, remove, and destroy from inside a worktree (not just the main repo)

6. **Setup**
   - `--init` mode (default path, relative path, absolute path, non-.sh extension, nested directories, safety checks)
   - Run mode from inside a worktree
   - Token expansion (`<repo_root>`, `<repo_name>`, `<worktree_root>`)
   - Error handling (not configured, not in worktree, script not found, not executable, failing script)

### Repository Configurations

All tests run in four configurations to ensure git-ht works across different setups:

| Mode | Description |
|------|-------------|
| `normal` | Non-bare repo with a remote |
| `bare` | Bare local clone with a remote (worktree-only workflow) |
| `normal-noremote` | Non-bare repo with no remote |
| `bare-noremote` | Bare repo with no remote |

Remote-dependent tests (SHA matching in remove, remote branch deletion in destroy) are automatically skipped when no remote is configured.

### Test Output

The test suite provides colored output:
- Green: Passing tests
- Red: Failing tests
- Yellow: Section headers and summary

Example output:
```
=== Test Summary ===
Tests run:    570
Tests passed: 570
Tests failed: 0

All tests passed!
```

### Cleanup

The test suite automatically cleans up after itself:
- Removes all test worktrees
- Deletes all test branches
- Cleans up temporary directories

Cleanup runs automatically on:
- Normal completion
- Test failure
- Script interruption (Ctrl-C)

### CI/CD Integration

To run tests in CI/CD:

```sh
cd /path/to/dotfiles
./test/git-ht-test.sh
```

The script exits with status 0 on success, 1 on failure.
