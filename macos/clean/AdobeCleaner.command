#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/adobe-cleaner-macos.sh
source "${SCRIPT_DIR}/lib/adobe-cleaner-macos.sh"
adobe_cleaner_main "$@"
