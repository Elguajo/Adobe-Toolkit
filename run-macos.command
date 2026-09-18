#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"

launch() {
    local target="$1"
    chmod +x "$target" || true
    open "$target"
}

run_clean() {
    local target="$script_dir/macos/clean/AdobeCleaner.command"
    chmod +x "$target" || true

    echo "1) Preview full cleanup (recommended)"
    echo "2) Stop Adobe processes and services"
    echo "3) Full cleanup"
    echo
    read -r -p "Select (1/2/3): " clean_choice

    case "$clean_choice" in
        1) "$target" --dry-run full ;;
        2) "$target" kill ;;
        3) "$target" full ;;
        *) echo "Invalid choice."; exit 2 ;;
    esac
}

case "${1:-}" in
    backup)
        launch "$script_dir/macos/AdobeBackuper.command"
        exit 0
        ;;
    clean)
        run_clean
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Usage: $0 [backup|clean]"
        exit 2
        ;;
esac

echo "Adobe Environment Toolkit"
echo
echo "1) Back up or restore settings"
echo "2) Clean Adobe processes and leftovers"
echo
read -r -p "Select (1/2): " choice

case "$choice" in
    1) launch "$script_dir/macos/AdobeBackuper.command" ;;
    2) run_clean ;;
    *) echo "Invalid choice."; exit 2 ;;
esac
