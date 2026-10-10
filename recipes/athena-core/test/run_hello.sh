#!/bin/bash
# Run ATLAS's HelloWorld example with athena.py; extra arguments go to athena.py.
set -euo pipefail
log=hello$(printf '%s' "$*" | tr -c 'a-zA-Z0-9' '_').log
if ! athena.py "$@" AthExHelloWorld/HelloWorldConfig.py > "${log}" 2>&1; then
  cat "${log}"
  exit 1
fi
grep "HelloWorld.HelloTool .*Hello World!" "${log}"
grep "leaving with code 0" "${log}"
