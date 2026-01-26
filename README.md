# Don's Dotfiles

Personal dotfiles based on [thoughtbot's dotfiles](https://github.com/thoughtbot/dotfiles).

## Requirements

- macOS
- [Homebrew](https://brew.sh/)
- [rcm](https://github.com/thoughtbot/rcm) for managing dotfiles

## Installation

Install Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

Install rcm:

```bash
brew tap thoughtbot/formulae
brew install rcm
```

Clone this repo:

```bash
git clone git@github.com:happycollision/dotfiles.git ~/dotfiles
```

Install the dotfiles:

```bash
env RCRC=$HOME/dotfiles/rcrc rcup
```

After initial installation, just run `rcup` to update.

## What's Included

### Custom Tools

- **git-ht** - Git worktree wrapper for easier branch management
- **addrev** - GitHub PR reviewer management tool
- **reviews** - List GitHub PRs awaiting your review

### Shell Configuration

- **Zsh** with custom configs for colors, history, keybindings
- **Aliases** for git operations and common tasks
- **Functions**: `g` (git shorthand), `mcd` (mkdir + cd), `envup` (load .env), `gr` (interactive rebase), `new` (open new terminal), `uncommit` (unstage commit)

### Version Management

- **mise** - Runtime version manager (replaces asdf)

### Editor

- VS Code (`code --wait`) set as default editor

## Customization

Create `~/dotfiles-local` for personal overrides:

```bash
mkdir ~/dotfiles-local
```

Add customizations in `.local` files:

- `~/dotfiles-local/aliases.local`
- `~/dotfiles-local/gitconfig.local`
- `~/dotfiles-local/zshrc.local`
- `~/dotfiles-local/zsh/configs/*`

### Example: Custom Aliases

```bash
# ~/dotfiles-local/aliases.local
alias myproject='cd ~/code/myproject'
```

### Example: Git Config

```bash
# ~/dotfiles-local/gitconfig.local
[user]
  name = Your Name
  email = you@example.com
```

## Updating

Pull the latest changes and run rcup:

```bash
cd ~/dotfiles
git pull
rcup
```

## License

See [LICENSE](LICENSE) file. Based on thoughtbot's dotfiles framework with additions by Don Denton.
