#!/usr/bin/env bash
# Portal Bridge launch wrapper for the "steam" method on Linux.
#
# Set the game's Steam Launch Options to (python -m portal_bridge linux-setup
# prints the exact line):
#     "/path/to/pb-wrap.sh" waw %command%
#
# Before asking Steam to start the game, the bridge writes that launch's game
# arguments (map, travel state, ...) one per line to next_args_<game> next to
# this script. They are appended to Steam's command here, so they never pass
# through the shell-built command line Steam uses for launch options, where a
# "|" in the travel state would turn into a pipe. The file is deleted after
# reading, so a normal launch from the Steam library starts the plain game.
set -u
game="${1:?usage: pb-wrap.sh <waw|bo1> %command%}"
shift
file="$(dirname "$(readlink -f "$0")")/next_args_${game}"
args=()
if [ -f "$file" ]; then
    mapfile -t args < "$file"
    rm -f "$file"
fi
exec "$@" ${args[@]+"${args[@]}"}
