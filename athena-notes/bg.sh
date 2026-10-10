#!/bin/bash
# bg.sh <dir> <name> <command...>: run a command in <dir>, output to <name>.out, exit code to <name>.rc
dir=$1 name=$2
shift 2
cd "$dir" || exit 1
rm -f "$name.rc"
"$@" > "$name.out" 2>&1 < /dev/null
echo $? > "$name.rc"
