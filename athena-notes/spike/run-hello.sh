#!/bin/bash
# Run AthExHelloWorld with athena.py from the installed spike layers.
# usage: run-hello.sh [athena.py arguments]
set +eu
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh > /dev/null 2>&1
# shellcheck disable=SC1091
source /work/spike-env/opt/athena/Athena/25.0.73/InstallArea/aarch64-cf-gcc15-opt/setup.sh
set -eu
mkdir -p /work/run && cd /work/run
# athena.py is a "#!/bin/sh" script that needs bash (arrays).
bash "$(command -v athena.py)" "$@" AthExHelloWorld/HelloWorldConfig.py
