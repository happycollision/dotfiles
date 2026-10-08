# Tests for dotfiles

This directory contains test suites for custom git extensions and other dotfiles utilities.

## Run All Tests

Run all test suites with one command:

```sh
./test/run-tests.sh
```

## killport Tests

The `killport-test.sh` script validates the `killport` zsh function in isolation.

### Running the Tests

From the dotfiles repository root:

```sh
./test/killport-test.sh
```

### What's Tested

The test suite covers:

1. **Usage handling**
   - Missing argument prints usage and exits non-zero

2. **No-process behavior**
   - Unused port returns success with a clear message

3. **Process termination**
   - Starts a local test listener, runs `killport <port>`, and verifies the listener is terminated and port is freed
