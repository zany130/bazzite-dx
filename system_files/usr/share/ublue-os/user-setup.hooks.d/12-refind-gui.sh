#!/usr/bin/bash
set -euo pipefail
# Also usable manually; no legacy setup-services library or version gate.
exec /usr/libexec/bazzite-dx-refind-seed "$@"
