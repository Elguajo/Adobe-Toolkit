#!/bin/bash
# Internal bridge: static functions only, positional inputs, NUL-delimited records.
ADOBE_BACKUP_LIBRARY_ONLY=true
unset ADOBE_BACKUP_SELECTION_FILE
source "$(dirname "$0")/../AdobeBackuper.command"
case "$1" in
    scan)
        CURRENT_BACKUP_FOLDER=/__v1_backup__
        ui_item() {
            local ITEM_EXCLUDES
            item_excludes "$6"
            printf '%s\0' "$@" "${ITEM_EXCLUDES[@]}" '' >&3
        }
        enumerate_backup_items ui_item 3>&1 1>&2
        ;;
    validate)
        validate_backup_metadata "$2" && validate_restore_manifest "$2"
        ;;
    *) exit 3 ;;
esac
