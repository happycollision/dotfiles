# ensure dotfiles bin directory is loaded first
PATH="$HOME/.bin:/usr/local/sbin:$PATH"

# Load asdf
if [ -f "/usr/local/opt/asdf/asdf.sh" ]; then
  . "/usr/local/opt/asdf/asdf.sh"
elif which brew &>/dev/null; then
  . "$(brew --prefix asdf)/libexec/asdf.sh"
elif [ -f "$HOME/.asdf/asdf.sh" ]; then
  . "$HOME/.asdf/asdf.sh"
  . "$HOME/.asdf/completions/asdf.bash"
fi

# mkdir .git/safe in the root of repositories you trust
PATH=".git/safe/../../bin:$PATH"

export -U PATH
