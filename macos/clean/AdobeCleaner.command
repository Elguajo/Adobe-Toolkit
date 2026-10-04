#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${1:-}" == "--ui-json" ]]; then
    exec /bin/bash "${SCRIPT_DIR}/../ui-json/adobe-toolkit-backend-v1" "$@"
fi
# shellcheck source=lib/adobe-cleaner-macos.sh
source "${SCRIPT_DIR}/lib/adobe-cleaner-macos.sh"
adobe_cleaner_main "$@"
