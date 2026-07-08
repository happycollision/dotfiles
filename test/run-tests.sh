#!/bin/sh
# Run all dotfiles test suites from repository root.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

cd "$DOTFILES_ROOT"

./test/git-ht-test.sh
./test/killport-test.sh
