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
   - Help text display
   - Default behavior

2. **Basic Worktree Creation**
   - Creating worktrees in default location
   - Branch creation
   - Directory structure

3. **Safety Checks**
   - Refusing duplicate branch names
   - Refusing currently checked out branches
   - Worktree directory conflicts

4. **Existing Branch Flag (`-e`)**
   - Using existing branches
   - Error handling for non-existent branches

5. **Worktree Removal**
   - Basic removal
   - Removal with `--delete-branch`
   - Removal with custom directories

6. **Custom Starting Points**
   - Creating from specific commits with `-i`
   - Verification of correct HEAD position

7. **Flag Validation**
   - Mutually exclusive flags
   - Required arguments

8. **Custom Directories**
   - Using `-d` with absolute paths
   - Creation and removal in custom locations

9. **Error Handling**
   - Non-existent worktrees
   - Missing required arguments

### Test Output

The test suite provides colored output:
- ✓ Green: Passing tests
- ✗ Red: Failing tests
- Yellow: Section headers and summary

Example output:
```
=== Test Summary ===
Tests run:    28
Tests passed: 28
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
