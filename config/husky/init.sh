# Sourced by husky before every git hook. 
#
# Some GUI git clients (GitKraken, in my
# case) don't inherit shell profiles, so mise-managed tools aren't on PATH.
# Ideally, we could fix this in the GUI client itself, but GK doesn't allow us
# to modify the PATH it uses.
eval "$(mise activate bash --shims)"
