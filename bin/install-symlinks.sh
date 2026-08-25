#!/usr/bin/env sh
#
# install-symlinks.sh — link the magento-integration-* skills into an agent home.
#
# Per-folder symlinks: each skills/<name>/ becomes <dest>/<name>.
# Existing local entries are never overwritten — they win and are reported.
#
# Usage: bin/install-symlinks.sh [dest]
#   dest defaults to $CLAUDE_HOME/skills, else ~/.claude/skills
#
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$repo_root/skills"

if [ "$#" -ge 1 ]; then
    dest=$1
elif [ -n "${CLAUDE_HOME:-}" ]; then
    dest="$CLAUDE_HOME/skills"
else
    dest="$HOME/.claude/skills"
fi

[ -d "$src" ] || { printf 'error: no skills/ in %s\n' "$repo_root" >&2; exit 1; }
mkdir -p -- "$dest"

linked=0
skipped=0
for skill in "$src"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename -- "$skill")
    target="$dest/$name"

    if [ -L "$target" ]; then
        current=$(readlink -- "$target")
        if [ "$current" = "${skill%/}" ]; then
            printf '  ok       %s\n' "$name"
            linked=$((linked + 1))
            continue
        fi
        rm -f -- "$target"
    elif [ -e "$target" ]; then
        printf '  WARN     %s exists and is not a link — left alone\n' "$name"
        skipped=$((skipped + 1))
        continue
    fi

    ln -s -- "${skill%/}" "$target"
    printf '  linked   %s\n' "$name"
    linked=$((linked + 1))
done

printf '\n%s linked, %s skipped -> %s\n' "$linked" "$skipped" "$dest"
