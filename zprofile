eval "$(/opt/homebrew/bin/brew shellenv)"

# mise shims for non-interactive shells (IDEs, scripts, etc.)
# This must be in .zprofile so VSCode can access mise-managed tools
# when using automation profile with --login flag
eval "$(mise activate zsh --shims)"
