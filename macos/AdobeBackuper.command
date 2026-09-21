#!/bin/bash

# Adobe Environment Toolkit — Backup and Restore
TOOL_VERSION="1"

# ==========================================
# CONFIGURATION
# ==========================================
BACKUP_ROOT="$HOME/Desktop/Backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
CURRENT_BACKUP_FOLDER="$BACKUP_ROOT/Adobe_Backup_$TIMESTAMP"

# Standard exclusions: regenerated caches, recovery data, and Adobe-delivered modules.
# Keep user preferences, presets, and third-party extensions; the excluded items are
# recreated by Adobe or downloaded again after the application is installed.
RSYNC_EXCLUDES=(
    --exclude="*Cache*" 
    --exclude="*Caches*" 
    --exclude="*cache*"
    --exclude="*.tmp" 
    --exclude="*.lock" 
    --exclude="*.log" 
    --exclude="*Log*" 
    --exclude="*Logs*" 
    --exclude=".DS_Store" 
    --exclude="Creative Cloud Libraries" 
    --exclude="OOBE" 
    --exclude="Team Projects Local Hub" 
    --exclude="CC_LIBRARIES_PANEL_EXTENSION*" 
    --exclude="ACPLocal*"
    --exclude="AddonModules"
    --exclude="AutoRecover"
)

# Plugins Exclusions (Standard Adobe Plugins)
PLUGIN_EXCLUDES=(
    --exclude="(AdobePSL)"
    --exclude="Cineware by Maxon"
    --exclude="Effects"
    --exclude="Extensions"
    --exclude="Format"
    --exclude="Keyframe"
)

# ==========================================
# GUI HELPER FUNCTIONS
# ==========================================

# Runs rsync and records failures instead of letting them pass silently.
# Sets BACKUP_HAD_ERRORS/RESTORE_HAD_ERRORS (whichever the caller uses) to 1 on failure.
function run_rsync() {
    local rc
    rsync "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: rsync failed (exit $rc): rsync $*" >&2
        return 1
    fi
    return 0
}

function show_menu() {
    osascript <<EOD
    set question to display dialog "Adobe Environment Toolkit\n\nBackup/Restore:\n- User preferences and Adobe documents\n- Custom plug-ins and scripts for After Effects, Illustrator, and Photoshop\n\n(Shared Adobe system data is excluded)" buttons {"Cancel", "Restore", "Backup"} default button "Backup" with icon note
    return button returned of question
EOD
}

function show_notification() {
    osascript -e "display notification \"$1\" with title \"Adobe Environment Toolkit\""
}

function show_alert() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with icon caution"
}

function show_success() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with icon note"
}

function format_bytes() {
    local bytes="$1"
    awk -v bytes="$bytes" 'BEGIN {
        split("B KB MB GB TB", units, " ")
        size = bytes + 0
        unit = 1
        while (size >= 1024 && unit < 5) {
            size = size / 1024
            unit++
        }
        if (unit == 1) {
            printf "%d %s", size, units[unit]
        } else {
            printf "%.1f %s", size, units[unit]
        }
    }'
}

function scan_path_stats() {
    local path="$1"
    shift
    local excludes=("$@")
    local find_args=("$path")
    local exclude

    for exclude in "${excludes[@]}"; do
        local pattern="${exclude#--exclude=}"
        pattern="${pattern%\"}"
        pattern="${pattern#\"}"
        find_args+=( -name "$pattern" -prune -o )
    done

    # NOTE: macOS ships BWK awk (not gawk), which does not honor RS='\0' as a real NUL
    # separator - it silently stops after the first record. That previously made this
    # function undercount every multi-file folder down to "1 file". Batch stat via
    # find's own -exec ... + instead, which needs no NUL-splitting at all.
    local files=0 bytes=0 size
    while IFS= read -r size; do
        files=$((files + 1))
        bytes=$((bytes + size))
    done < <(find "${find_args[@]}" -type f -exec stat -f '%z' '{}' + 2>/dev/null)

    printf '%d\t%d\n' "$files" "$bytes"
}

function scan_add_item() {
    local category="$1"
    local source="$2"
    local destination="$3"
    shift 3

    if [ ! -e "$source" ]; then
        return
    fi

    local stats files bytes
    stats=$(scan_path_stats "$source" "$@")
    files=${stats%%$'\t'*}
    bytes=${stats##*$'\t'}

    if [ "${files:-0}" -eq 0 ]; then
        return
    fi

    SCAN_TOTAL_FILES=$((SCAN_TOTAL_FILES + files))
    SCAN_TOTAL_BYTES=$((SCAN_TOTAL_BYTES + bytes))
    SCAN_ITEM_COUNT=$((SCAN_ITEM_COUNT + 1))

    printf '%s\t%s\t%s\t%s\t%s\n' "$category" "$source" "$destination" "$files" "$bytes" >> "$SCAN_REPORT_FILE"
}

# Single source of truth for "what gets backed up": walks every candidate item exactly
# once and hands it to $callback as (category, source, destination, restore_parent, admin,
# exclude_kind). Both the preflight scan and the real backup consume this so they can never
# drift apart on which paths/excludes/selection-filter rules apply.
function enumerate_backup_items() {
    local callback="$1"

    local APP_SUPPORT="$HOME/Library/Application Support/Adobe"
    local PREFS="$HOME/Library/Preferences"
    local DEST_USER="$CURRENT_BACKUP_FOLDER/User_Library"
    local DEST_APP_CUSTOMIZATIONS="$CURRENT_BACKUP_FOLDER/App_Customizations"
    local INSTALLED_ADOBE_PREF_KEYS
    IFS=$'\n' read -r -d '' -a INSTALLED_ADOBE_PREF_KEYS < <(installed_adobe_preference_keys && printf '\0')

    if [ -e "$APP_SUPPORT" ] && should_include_backup_source "$APP_SUPPORT"; then
        "$callback" "User Application Support" "$APP_SUPPORT" "$DEST_USER/Application Support/Adobe" "$HOME/Library/Application Support/" false standard
    fi

    while IFS= read -r -d '' f; do
        if ! should_backup_adobe_preference "$f"; then
            echo "Skipping noise/stale preference: $f"
        elif should_include_backup_source "$f"; then
            "$callback" "User Preferences" "$f" "$DEST_USER/Preferences/$(basename "$f")" "$HOME/Library/Preferences/" false standard
        fi
    done < <(find "$PREFS" -maxdepth 1 -name "*Adobe*" -print0 2>/dev/null)

    # ~/Documents/Adobe holds per-app workspace/layout data that lives outside
    # ~/Library entirely (After Effects custom presets, Premiere Pro saved Layouts).
    local DOCS_ADOBE="$HOME/Documents/Adobe"
    local DEST_DOCS="$CURRENT_BACKUP_FOLDER/User_Documents"

    while IFS= read -r -d '' ae_dir; do
        if [ -d "$ae_dir/User Presets" ] && should_include_backup_source "$ae_dir/User Presets"; then
            local ae_rel="${ae_dir#"$HOME/Documents/"}"
            "$callback" "AE User Presets" "$ae_dir/User Presets" "$DEST_DOCS/$ae_rel/User Presets" "$ae_dir/" false standard
        fi
    done < <(find "$DOCS_ADOBE" -maxdepth 1 -type d -name "After Effects*" -print0 2>/dev/null)

    while IFS= read -r -d '' profile_dir; do
        local profile_rel="${profile_dir#"$HOME/Documents/"}"
        local layout_sub
        for layout_sub in Layouts ArchivedLayouts Mac Win; do
            if [ -d "$profile_dir/$layout_sub" ] && should_include_backup_source "$profile_dir/$layout_sub"; then
                "$callback" "Premiere Workspace ($layout_sub)" "$profile_dir/$layout_sub" "$DEST_DOCS/$profile_rel/$layout_sub" "$profile_dir/" false standard
            fi
        done
    done < <(find "$DOCS_ADOBE/Premiere Pro" -mindepth 2 -maxdepth 2 -type d -name "Profile-*" -print0 2>/dev/null)

    while IFS= read -r -d '' app_path; do
        local app_name
        app_name=$(basename "$app_path")
        if [ -d "$app_path/Plug-ins" ] && should_include_backup_source "$app_path/Plug-ins"; then
            "$callback" "$app_name Plug-ins" "$app_path/Plug-ins" "$DEST_APP_CUSTOMIZATIONS/$app_name/Plug-ins" "$app_path/" false plugins
        fi

        if [ -d "$app_path/Scripts/ScriptUI Panels" ] && should_include_backup_source "$app_path/Scripts/ScriptUI Panels"; then
            "$callback" "$app_name ScriptUI Panels" "$app_path/Scripts/ScriptUI Panels" "$DEST_APP_CUSTOMIZATIONS/$app_name/Scripts/ScriptUI Panels" "$app_path/Scripts/" false standard
        fi

        while IFS= read -r -d '' scripts_path; do
            local scripts_relative="${scripts_path#"$app_path"/}"
            if should_include_backup_source "$scripts_path"; then
                "$callback" "$app_name Preset Scripts" "$scripts_path" "$DEST_APP_CUSTOMIZATIONS/$app_name/$scripts_relative" "$(dirname "$scripts_path")/" false standard
            fi
        done < <(find "$app_path/Presets" -type d -name Scripts -print0 2>/dev/null)
    done < <(find /Applications -maxdepth 1 -type d \( -name "Adobe After Effects *" -o -name "Adobe Illustrator *" -o -name "Adobe Photoshop *" \) -print0 2>/dev/null)
}

function item_excludes() {
    local exclude_kind="$1"
    ITEM_EXCLUDES=("${RSYNC_EXCLUDES[@]}")
    if [ "$exclude_kind" = "plugins" ]; then
        ITEM_EXCLUDES+=("${PLUGIN_EXCLUDES[@]}")
    fi
}

function scan_item_callback() {
    local category="$1" source="$2" destination="$3"
    local exclude_kind="$6"
    local ITEM_EXCLUDES
    item_excludes "$exclude_kind"
    scan_add_item "$category" "$source" "$destination" "${ITEM_EXCLUDES[@]}"
}

function backup_item_callback() {
    local category="$1" source="$2" destination="$3" restore_parent="$4" admin="$5" exclude_kind="$6"
    local ITEM_EXCLUDES
    item_excludes "$exclude_kind"

    echo "Backing up $category: $source"
    mkdir -p "$(dirname "$destination")"
    if run_rsync -a -v "${ITEM_EXCLUDES[@]}" "$source" "$(dirname "$destination")/" \
        && manifest_add "$destination" "$restore_parent" "$admin"; then
        :
    else
        BACKUP_HAD_ERRORS=1
    fi
}

function build_backup_scan() {
    SCAN_REPORT_FILE=$(mktemp "${TMPDIR:-/tmp}/adobe-backup-scan.XXXXXX")
    SCAN_TOTAL_FILES=0
    SCAN_TOTAL_BYTES=0
    SCAN_ITEM_COUNT=0

    enumerate_backup_items scan_item_callback
}

function show_backup_preview() {
    local total_size
    total_size=$(format_bytes "$SCAN_TOTAL_BYTES")

    local preview line shown=0
    printf -v preview 'Preflight scan complete.\n\nWill backup: %s locations\nFiles: %s\nEstimated size: %s\nDestination:\n%s\n' \
        "$SCAN_ITEM_COUNT" "$SCAN_TOTAL_FILES" "$total_size" "$CURRENT_BACKUP_FOLDER"

    while IFS=$'\t' read -r category source destination files bytes; do
        if [ "$shown" -ge 5 ]; then
            preview="${preview}"$'\n'"...and more locations in Terminal output."
            break
        fi

        printf -v line '\n%s (%s / %s files)\n%s\n' \
            "$category" "$(format_bytes "$bytes")" "$files" "$source"
        preview="${preview}${line}"
        shown=$((shown + 1))
    done < "$SCAN_REPORT_FILE"

    osascript <<'APPLESCRIPT' - "$preview"
on run argv
  set previewText to item 1 of argv
  set answer to display dialog previewText buttons {"Cancel", "Backup"} default button "Backup" with icon note
  return button returned of answer
end run
APPLESCRIPT
}

function print_backup_scan_tsv() {
    build_backup_scan
    printf 'category\tsource\tdestination\tfiles\tbytes\n'
    cat "$SCAN_REPORT_FILE"
    rm -f "$SCAN_REPORT_FILE"
}

function should_include_backup_source() {
    local source="$1"

    if [ -z "${ADOBE_BACKUP_SELECTION_FILE:-}" ]; then
        return 0
    fi

    grep -Fxq "$source" "$ADOBE_BACKUP_SELECTION_FILE"
}

function is_noise_preference() {
    local name
    name=$(basename "$1")

    case "$name" in
        com.adobe.*.plist|\
        *"Creative Cloud"*|*"CoreSync"*|*"CCXProcess"*|*"AdobeGCClient"*|\
        *"Updater"*|*"Update"*|*"Sync"*|*"MRU"*|*"Recent"*)
            return 0
            ;;
    esac

    return 1
}

function installed_adobe_preference_keys() {
    find /Applications -maxdepth 3 \( -type d -name "Adobe *.app" -o -type d -name "Adobe *" \) -print0 2>/dev/null | \
    while IFS= read -r -d '' item; do
        local name
        name=$(basename "$item" .app)

        case "$name" in
            *"Creative Cloud"*|*"Updater"*|*"Update"*|*"CoreSync"*|*"CCXProcess"*)
                continue
                ;;
        esac

        printf '%s\n' "$name"

        local info_plist="$item/Contents/Info.plist"
        if [ -f "$info_plist" ]; then
            local major_version product_key
            major_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist" 2>/dev/null | cut -d. -f1)
            product_key=$(printf '%s\n' "$name" | sed -E 's/[[:space:]][0-9]{4}$//')

            if [ -n "$major_version" ] && [ -n "$product_key" ]; then
                printf '%s %s\n' "$product_key" "$major_version"
            fi
        fi
    done | sort -u
}

function should_backup_adobe_preference() {
    local path="$1"
    local name
    name=$(basename "$path")

    if is_noise_preference "$path"; then
        return 1
    fi

    if [ -d "$path" ] && [[ "$name" == Adobe*" Settings" ]]; then
        local settings_key="${name% Settings}"
        if ! printf '%s\n' "${INSTALLED_ADOBE_PREF_KEYS[@]}" | grep -Fxq "$settings_key"; then
            return 1
        fi
    fi

    return 0
}

function select_folder() {
    if [ ! -d "$BACKUP_ROOT" ]; then mkdir -p "$BACKUP_ROOT"; fi
    osascript <<EOD
    set startPath to POSIX file "$BACKUP_ROOT"
    try
        set folderPath to choose folder with prompt "Select Backup to Restore:" default location startPath
        return POSIX path of folderPath
    on error
        return "UserCanceled"
    end try
EOD
}

function manifest_init() {
    MANIFEST_FILE="$CURRENT_BACKUP_FOLDER/manifest.tsv"
    META_FILE="$CURRENT_BACKUP_FOLDER/meta.tsv"

    mkdir -p "$CURRENT_BACKUP_FOLDER"
    printf 'backup_path\trestore_parent\tadmin\n' > "$MANIFEST_FILE"
    printf 'backup_format_version\t1\n' > "$META_FILE"
    printf 'tool_version\t%s\n' "$TOOL_VERSION" >> "$META_FILE"
    printf 'platform\tmacos\n' >> "$META_FILE"
    printf 'created\t%s\n' "$TIMESTAMP" >> "$META_FILE"
    printf 'host\t%s\n' "$(scutil --get ComputerName 2>/dev/null || hostname)" >> "$META_FILE"
}

function manifest_path() {
    local path="$1"
    path="${path%/}"
    case "$path" in
        "$CURRENT_BACKUP_FOLDER"/*) printf '%s' "${path#"$CURRENT_BACKUP_FOLDER"/}" ;;
        *) echo "ERROR: Backup item is outside the backup root: $path" >&2; return 1 ;;
    esac
}

function manifest_add() {
    local backup_path="$1"
    local restore_parent="$2"
    local admin="$3"

    local relative_path
    relative_path=$(manifest_path "$backup_path") || return 1
    printf '%s\t%s\t%s\n' "$relative_path" "$restore_parent" "$admin" >> "$MANIFEST_FILE"
}

function has_path_traversal() {
    local component
    local path="$1"
    [[ -z "$path" || "$path" == *"//"* ]] && return 0
    IFS='/' read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        [[ "$component" == "." || "$component" == ".." ]] && return 0
    done
    return 1
}

function canonicalize_restore_target() {
    python3 - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

function is_within_dir() {
    local path="${1%/}"
    local dir="${2%/}"
    case "$path" in
        "$dir"|"$dir"/*) return 0 ;;
    esac
    return 1
}

# A backup folder is untrusted input. Only user directories and the installed
# After Effects, Illustrator, or Photoshop application bundle may be restore
# targets; application restores are limited to custom plug-ins and scripts below.
function is_allowed_restore_target() {
    local restore_parent="$1"
    local admin="$2"
    local canonical_parent user_library user_documents

    [[ "$admin" == "true" || "$admin" == "false" ]] || return 1
    has_path_traversal "$restore_parent" && return 1
    canonical_parent=$(canonicalize_restore_target "$restore_parent") || return 1

    if [ "$admin" = "true" ]; then
        is_within_dir "$canonical_parent" "/Applications" && return 0
        is_within_dir "$canonical_parent" "/Library/Application Support/Adobe" && return 0
        return 1
    fi

    user_library=$(canonicalize_restore_target "$HOME/Library") || return 1
    user_documents=$(canonicalize_restore_target "$HOME/Documents/Adobe") || return 1
    is_within_dir "$canonical_parent" "$user_library" && return 0
    is_within_dir "$canonical_parent" "$user_documents" && return 0
    case "$canonical_parent" in
        /Applications/Adobe\ After\ Effects\ *|/Applications/Adobe\ Illustrator\ *|/Applications/Adobe\ Photoshop\ *) return 0 ;;
    esac
    return 1
}

function is_allowed_manifest_backup_path() {
    case "$1" in
        User_Library/*|User_Documents/*|\
        App_Customizations/Adobe\ After\ Effects\ */Plug-ins|App_Customizations/Adobe\ Illustrator\ */Plug-ins|App_Customizations/Adobe\ Photoshop\ */Plug-ins|\
        App_Customizations/Adobe\ After\ Effects\ */Scripts/ScriptUI\ Panels|App_Customizations/Adobe\ Illustrator\ */Scripts/ScriptUI\ Panels|App_Customizations/Adobe\ Photoshop\ */Scripts/ScriptUI\ Panels|\
        App_Customizations/Adobe\ After\ Effects\ */Presets/*/Scripts|App_Customizations/Adobe\ Illustrator\ */Presets/*/Scripts|App_Customizations/Adobe\ Photoshop\ */Presets/*/Scripts|\
        System_Apps_Data/Applications/*|System_Library_Adobe/*) return 0 ;;
    esac
    return 1
}

function is_allowed_customization_restore_pair() {
    local backup_path="$1"
    local canonical_parent="$2"
    local relative_path app_name item_path expected_parent

    case "$backup_path" in
        App_Customizations/*) ;;
        *) return 0 ;;
    esac

    relative_path="${backup_path#App_Customizations/}"
    app_name="${relative_path%%/*}"
    item_path="${relative_path#*/}"
    expected_parent="/Applications/$app_name"

    case "$item_path" in
        Plug-ins) ;;
        Scripts/ScriptUI\ Panels) expected_parent="$expected_parent/Scripts" ;;
        Presets/*/Scripts) expected_parent="$expected_parent/${item_path%/Scripts}" ;;
        *) return 1 ;;
    esac

    expected_parent=$(canonicalize_restore_target "$expected_parent") || return 1
    [ "$canonical_parent" = "$expected_parent" ]
}

function validate_backup_metadata() {
    local source_root="$1" meta="$1/meta.tsv"
    local key value version="" platform="" seen=""

    [[ -f "$meta" ]] || return 0 # Legacy backups predate metadata.
    while IFS=$'\t' read -r key value extra; do
        [[ -z "$key" ]] && continue
        if [[ -n "${extra:-}" || -z "$value" || "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
            echo "ERROR: Invalid backup metadata entry." >&2
            return 3
        fi
        case " $seen " in *" $key "*) echo "ERROR: Duplicate backup metadata key: $key" >&2; return 3 ;; esac
        seen="$seen $key"
        case "$key" in
            backup_format_version) version="$value" ;;
            platform) platform="$value" ;;
        esac
    done < "$meta"
    if [[ -n "$version" && "$version" != "1" ]]; then
        echo "ERROR: Unsupported backup format version: $version" >&2
        return 3
    fi
    if [[ -n "$platform" && "$platform" != "macos" ]]; then
        echo "ERROR: Backup platform must be macos, got: $platform" >&2
        return 3
    fi
    return 0
}

function validate_restore_manifest() {
    local source_root="$1" manifest="$1/manifest.tsv"
    local header backup_path restore_parent admin extra

    [[ -f "$manifest" ]] || return 1
    IFS= read -r header < "$manifest"
    if [[ "$header" != $'backup_path\trestore_parent\tadmin' ]]; then
        echo "ERROR: Invalid backup manifest header." >&2
        return 3
    fi
    while IFS=$'\t' read -r backup_path restore_parent admin extra; do
        [[ -z "$backup_path$restore_parent$admin$extra" ]] && continue
        if [[ -n "${extra:-}" || -z "$backup_path" || -z "$restore_parent" || -z "$admin" ]]; then
            echo "ERROR: Invalid backup manifest entry." >&2
            return 3
        fi
        if [[ "$backup_path" == /* ]] || has_path_traversal "$backup_path" || ! is_allowed_manifest_backup_path "$backup_path"; then
            echo "ERROR: Refusing manifest backup path: $backup_path" >&2
            return 3
        fi
        if ! is_allowed_restore_target "$restore_parent" "$admin"; then
            echo "ERROR: Refusing manifest restore target: $restore_parent (admin=$admin)" >&2
            return 3
        fi
        if ! is_allowed_customization_restore_pair "$backup_path" "$(canonicalize_restore_target "$restore_parent")"; then
            echo "ERROR: Refusing mismatched application customization restore target: $restore_parent" >&2
            return 3
        fi
    done < <(tail -n +2 "$manifest")
    return 0
}

function restore_manifest_item() {
    local source_root="$1"
    local backup_path="$2"
    local restore_parent="$3"
    local admin="$4"

    local source_path="$source_root/$backup_path"
    if [ ! -e "$source_path" ]; then
        echo "Skipping missing manifest item: $source_path"
        return
    fi

    case "$backup_path" in
        App_Customizations/Adobe\ After\ Effects\ */*|App_Customizations/Adobe\ Illustrator\ */*|App_Customizations/Adobe\ Photoshop\ */*|\
        System_Apps_Data/Applications/Adobe\ After\ Effects\ */Plug-ins|System_Apps_Data/Applications/Adobe\ After\ Effects\ */Scripts/ScriptUI\ Panels|\
        System_Apps_Data/Applications/Adobe\ Illustrator\ */Plug-ins|System_Apps_Data/Applications/Adobe\ Photoshop\ */Plug-ins)
            run_rsync -a -v "$source_path" "$restore_parent" || RESTORE_HAD_ERRORS=1
            ;;
        User_Library/*|User_Documents/*)
            run_rsync -a -v "$source_path" "$restore_parent" || RESTORE_HAD_ERRORS=1
            ;;
        *)
            echo "Skipping unsupported system restore item: $backup_path"
            ;;
    esac
}

function restore_from_manifest() {
    local source_root="$1"
    local manifest="$source_root/manifest.tsv"

    validate_backup_metadata "$source_root" || return $?
    validate_restore_manifest "$source_root" || return $?

    while IFS=$'\t' read -r backup_path restore_parent admin extra; do
        [[ -z "$backup_path$restore_parent$admin$extra" ]] && continue
        restore_manifest_item "$source_root" "$backup_path" "$restore_parent" "$admin"
    done < <(tail -n +2 "$manifest")

    return 0
}

# ==========================================
# BACKUP LOGIC
# ==========================================

function do_backup() {
    echo "--- Starting Backup ---"
    if [ "${ADOBE_BACKUP_HEADLESS:-false}" != "true" ]; then
        echo "Scanning backup candidates..."
        build_backup_scan

        if [ "$SCAN_ITEM_COUNT" -eq 0 ]; then
            show_alert "Nothing to backup.\nNo matching Adobe settings, custom plugins, or ScriptUI Panels were found."
            rm -f "$SCAN_REPORT_FILE"
            return
        fi

        echo "Preflight scan:"
        while IFS=$'\t' read -r category source destination files bytes; do
            echo "- $category: $(format_bytes "$bytes"), $files files"
            echo "  From: $source"
            echo "  To:   $destination"
        done < "$SCAN_REPORT_FILE"
        echo "Total: $(format_bytes "$SCAN_TOTAL_BYTES"), $SCAN_TOTAL_FILES files, $SCAN_ITEM_COUNT locations"

        if [[ "$(show_backup_preview)" != "Backup" ]]; then
            rm -f "$SCAN_REPORT_FILE"
            echo "Backup cancelled after preflight scan."
            exit 0
        fi

        rm -f "$SCAN_REPORT_FILE"
    fi
    manifest_init

    BACKUP_HAD_ERRORS=0
    enumerate_backup_items backup_item_callback

    if [ "${ADOBE_BACKUP_HEADLESS:-false}" != "true" ]; then
        if [ "$BACKUP_HAD_ERRORS" -eq 0 ]; then
            show_success "Backup Complete!\nUser data and selected application customizations saved."
            show_notification "Backup Successful"
        else
            show_alert "Backup finished with errors.\nSome items failed to copy - check the Terminal output.\nDestination:\n$CURRENT_BACKUP_FOLDER"
        fi
    else
        if [ "$BACKUP_HAD_ERRORS" -ne 0 ]; then
            echo "Backup finished with errors." >&2
        fi
    fi
}

# ==========================================
# RESTORE LOGIC
# ==========================================

function restore_legacy_application_items() {
    local source_root="$1"
    local source_apps="$source_root/System_Apps_Data/Applications"
    local source_app destination_app scripts_path scripts_relative

    [ -d "$source_apps" ] || return 0

    for source_app in "$source_apps"/Adobe\ After\ Effects\ * "$source_apps"/Adobe\ Illustrator\ * "$source_apps"/Adobe\ Photoshop\ *; do
        [ -d "$source_app" ] || continue
        destination_app="/Applications/$(basename "$source_app")"
        if [ ! -d "$destination_app" ]; then
            echo "Skipping custom application items; application is not installed: $destination_app" >&2
            RESTORE_HAD_ERRORS=1
            continue
        fi

        if [ -d "$source_app/Plug-ins" ]; then
            echo "Restoring $(basename "$source_app") Plug-ins..."
            run_rsync -a -v "$source_app/Plug-ins" "$destination_app/" || RESTORE_HAD_ERRORS=1
        fi
        if [ -d "$source_app/Scripts/ScriptUI Panels" ]; then
            echo "Restoring $(basename "$source_app") ScriptUI Panels..."
            run_rsync -a -v "$source_app/Scripts/ScriptUI Panels" "$destination_app/Scripts/" || RESTORE_HAD_ERRORS=1
        fi
        while IFS= read -r -d '' scripts_path; do
            scripts_relative="${scripts_path#"$source_app"/}"
            echo "Restoring $(basename "$source_app") Preset Scripts..."
            run_rsync -a -v "$scripts_path" "$destination_app/$(dirname "$scripts_relative")/" || RESTORE_HAD_ERRORS=1
        done < <(find "$source_app/Presets" -type d -name Scripts -print0 2>/dev/null)
    done
}

function do_restore_from_source() {
    local SOURCE="$1"
    if [[ "$SOURCE" == "UserCanceled" ]]; then exit 0; fi
    if [[ ! -d "$SOURCE" ]]; then
        echo "ERROR: Restore source is not a directory: $SOURCE" >&2
        RESTORE_HAD_ERRORS=1
        return 3
    fi

    echo "--- Starting Restore ---"

    RESTORE_HAD_ERRORS=0
    restore_from_manifest "$SOURCE"
    local manifest_status=$?
    if [ "$manifest_status" -eq 0 ]; then
        if [ "${ADOBE_BACKUP_HEADLESS:-false}" != "true" ]; then
            if [ "$RESTORE_HAD_ERRORS" -eq 0 ]; then
                show_success "Restore Complete!\nManifest-based restore completed."
                show_notification "Restore Successful"
            else
                show_alert "Restore finished with errors.\nSome items failed - check the Terminal output."
            fi
        fi
        return "$RESTORE_HAD_ERRORS"
    elif [ "$manifest_status" -eq 3 ]; then
        RESTORE_HAD_ERRORS=1
        return 3
    fi

    # --- 1. Restore User Data ---
    if [ -d "$SOURCE/User_Library/Application Support/Adobe" ]; then
        echo "Restoring User Settings..."
        run_rsync -a -v "${RSYNC_EXCLUDES[@]}" "$SOURCE/User_Library/Application Support/Adobe" "$HOME/Library/Application Support/" || RESTORE_HAD_ERRORS=1
    fi

    if [ -d "$SOURCE/User_Library/Preferences" ]; then
        echo "Restoring Preferences..."
        run_rsync -a -v "${RSYNC_EXCLUDES[@]}" "$SOURCE/User_Library/Preferences/" "$HOME/Library/Preferences/" || RESTORE_HAD_ERRORS=1
    fi

    if [ -d "$SOURCE/System_Apps_Data" ]; then
        restore_legacy_application_items "$SOURCE"
    fi

    if [ -d "$SOURCE/System_Library_Adobe" ]; then
        echo "Skipping shared /Library Adobe data."
    fi

    if [ "${ADOBE_BACKUP_HEADLESS:-false}" != "true" ]; then
        if [ "$RESTORE_HAD_ERRORS" -eq 0 ]; then
            show_success "Restore Complete!\nUser data and selected application customizations restored."
            show_notification "Restore Successful"
        else
            show_alert "Restore finished with errors.\nSome items failed - check the Terminal output."
        fi
    fi
    return "$RESTORE_HAD_ERRORS"
}

function do_restore() {
    local SOURCE=$(select_folder)
    do_restore_from_source "$SOURCE"
}

# ==========================================
# EXECUTION
# ==========================================

if [[ "${ADOBE_BACKUP_LIBRARY_ONLY:-false}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
fi

if ! command -v rsync &> /dev/null; then
    show_alert "Error: rsync not found."
    exit 1
fi

case "${1:-}" in
    --scan-backup-tsv)
        print_backup_scan_tsv
        exit 0
        ;;
    --backup-headless)
        if [ -n "${2:-}" ]; then
            ADOBE_BACKUP_SELECTION_FILE="$2"
        fi
        BACKUP_HAD_ERRORS=0
        ADOBE_BACKUP_HEADLESS=true do_backup
        [ "$BACKUP_HAD_ERRORS" -eq 0 ]
        exit $?
        ;;
    --restore-headless)
        if [ -z "${2:-}" ]; then
            echo "Restore source is required."
            exit 1
        fi
        RESTORE_HAD_ERRORS=0
        ADOBE_BACKUP_HEADLESS=true do_restore_from_source "$2"
        exit $?
        ;;
esac

SELECTION=$(show_menu)

if [[ "$SELECTION" == "Backup" ]]; then
    do_backup
elif [[ "$SELECTION" == "Restore" ]]; then
    do_restore
else
    exit 0
fi
