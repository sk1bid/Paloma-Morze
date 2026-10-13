#!/bin/bash
# Preserve command status and expose the failure tail in the Actions summary.
set -uo pipefail
log=${1:?Usage: ci-diagnostics.sh LOG COMMAND [ARGS...]}
shift
mkdir -p "$(dirname "$log")"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [[ "$status" -ne 0 ]]; then
  python3 - "$log" <<'PYLOG'
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
for line in lines[-30:]:
    print('::error::' + line[:1800].replace('%', '%25').replace('\r', '%0D'))
PYLOG
fi
exit "$status"
