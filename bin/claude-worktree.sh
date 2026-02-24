#!/bin/zsh

set -e

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	echo "Not inside a git repository."
	exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
worktree_base="$(dirname "$repo_root")"

name="temp"
dir="$worktree_base/$name"

if [ -d "$dir" ]; then
	nr=1
	while [ -d "$worktree_base/worktree_$nr" ]; do
		nr=$((nr + 1))
	done
	name="worktree_$nr"
	dir="$worktree_base/$name"
fi

echo "Creating worktree '$name' at $dir"
git worktree add "$dir"

echo "Starting Claude session in $dir"
cd "$dir" && claude
