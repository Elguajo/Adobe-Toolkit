# Adobe Environment Toolkit — macOS cleanup backend.

adobe_cleaner_log_line() {
    local msg="$1"
    local log_dir="${HOME}/Library/Logs"
    local log_file="${log_dir}/AdobeEnvironmentToolkit-cleaner.log"
    mkdir -p "$log_dir" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >>"$log_file" 2>/dev/null || true
}

adobe_cleaner_manifest_array() {
    local key="$1"
    python3 "${CLEANER_DIR}/lib/json_array.py" "${MANIFEST}" "$key" 2>/dev/null
}

adobe_cleaner_kill_processes() {
    echo ""
    echo -e "${RED}Stopping processes (patterns from manifest)...${NC}"
    adobe_cleaner_log_line "kill: start dry_run=${DRY_RUN}"
    local pat
    while IFS= read -r pat; do
        [[ -z "$pat" ]] && continue
        if pgrep -f "$pat" >/dev/null 2>&1; then
            echo "Stopping matches: $pat"
            adobe_cleaner_log_line "kill pattern: $pat"
            if [[ "$DRY_RUN" != "1" ]]; then
                pkill -f "$pat" 2>/dev/null || true
            fi
        fi
    done < <(adobe_cleaner_manifest_array "macos.kill_patterns")
    echo "Done."
}

adobe_cleaner_bootout_plist() {
    local plist="$1"
    local kind="$2"
    if [[ ! -f "$plist" ]]; then
        return 0
    fi
    adobe_cleaner_log_line "launchd: $plist ($kind)"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] bootout: $plist"
        return 0
    fi
    if [[ "$kind" == "user" ]]; then
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null \
            || launchctl unload "$plist" 2>/dev/null \
            || true
    else
        sudo launchctl bootout system "$plist" 2>/dev/null \
            || sudo launchctl unload "$plist" 2>/dev/null \
            || true
    fi
}

adobe_cleaner_unload_launchd() {
    echo ""
    echo -e "${RED}Unloading LaunchAgents / LaunchDaemons (com.adobe.*)...${NC}"
    local file
    find /Library/LaunchAgents -name "com.adobe.*" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "system"
    done
    find /Library/LaunchDaemons -name "com.adobe.*" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "system"
    done
    find "${HOME}/Library/LaunchAgents" -name "com.adobe.*" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "user"
    done
    find "${HOME}/Library/LaunchAgents" -name "com.Adobe.*" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "user"
    done
    echo "Launchd pass done."
}

adobe_cleaner_remove_paths() {
    echo ""
    echo -e "${RED}Removing paths...${NC}"
    local target
    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        adobe_cleaner_capture_application_provenance "$target"
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "[dry-run] rm -rf $(printf '%q' "$target")"
            adobe_cleaner_log_line "dry-run rm: $target"
            continue
        fi
        adobe_cleaner_log_line "rm -rf: $target"
        if [[ "$target" == "${HOME}/"* ]]; then
            rm -rf "$target" 2>/dev/null || true
        else
            sudo rm -rf "$target" 2>/dev/null || true
        fi
    done < <(python3 "${CLEANER_DIR}/lib/expand_macos_paths.py" "${MANIFEST}")
    echo "Removal pass done."
}

adobe_cleaner_capture_application_provenance() {
    local target="$1"
    local captured
    captured="$(python3 "${CLEANER_DIR}/lib/launchpad_reconcile.py" capture "$target" 2>/dev/null)" || return 0
    [[ -z "$captured" ]] && return 0
    if [[ -n "$CLEANUP_PROVENANCE" ]]; then
        CLEANUP_PROVENANCE+=$'\n'
    fi
    CLEANUP_PROVENANCE+="$captured"
    adobe_cleaner_log_line "launchpad provenance: recorded application bundle(s) under $target"
}

adobe_cleaner_collect_launch_services() {
    local lsregister="$1"
    local scan_output dump_output
    local kind bundle_id canonical_id app_name app_path

    LAUNCH_SERVICES_AVAILABLE="0"
    LAUNCH_SERVICES_LIVE_IDS=()
    LAUNCH_SERVICES_STALE_RECORDS=""
    if ! dump_output="$("$lsregister" -dump 2>/dev/null)" || [[ -z "$dump_output" ]]; then
        adobe_cleaner_log_line "launch services: dump unavailable"
        return 1
    fi
    if ! scan_output="$(printf '%s\n' "$dump_output" | python3 "${CLEANER_DIR}/lib/launch_services_records.py" 2>/dev/null)"; then
        adobe_cleaner_log_line "launch services: dump parsing failed"
        return 1
    fi
    LAUNCH_SERVICES_AVAILABLE="1"

    while IFS=$'\t' read -r kind bundle_id canonical_id app_name app_path; do
        case "$kind" in
            LIVE)
                [[ -n "$bundle_id" ]] && LAUNCH_SERVICES_LIVE_IDS+=("$bundle_id")
                ;;
            STALE)
                [[ -z "$app_path" ]] && continue
                if [[ -n "$LAUNCH_SERVICES_STALE_RECORDS" ]]; then
                    LAUNCH_SERVICES_STALE_RECORDS+=$'\n'
                fi
                LAUNCH_SERVICES_STALE_RECORDS+="${bundle_id}"$'\t'"${canonical_id}"$'\t'"${app_name}"$'\t'"${app_path}"
                ;;
        esac
    done <<< "$scan_output"
}

adobe_cleaner_refresh_launch_services() {
    local lsregister
    local bundle_id canonical_id app_name stale_path
    local stale_count=0
    local result
    local action_label
    lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    if [[ ! -x "$lsregister" ]]; then
        echo "Launch Services refresh skipped (lsregister is unavailable)."
        adobe_cleaner_log_line "launch services: skipped; lsregister unavailable"
        return 0
    fi

    echo ""
    echo -e "${RED}Removing stale application registrations...${NC}"

    if ! adobe_cleaner_collect_launch_services "$lsregister"; then
        echo "Launch Services refresh skipped (registration dump is unavailable)."
        return 0
    fi
    action_label="dry-run"
    [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"

    # Missing paths are the primary safety boundary. Adobe identity is checked
    # by launch_services_records.py using bundle/canonical IDs before an entry
    # reaches this loop, so registrations from volumes and archive folders are
    # handled without touching live applications with Adobe in their names.
    while IFS=$'\t' read -r bundle_id canonical_id app_name stale_path; do
        [[ -z "$stale_path" ]] && continue
        stale_count=$((stale_count + 1))
        echo "Stale registration: ${bundle_id:-$canonical_id} — $stale_path"
        adobe_cleaner_log_line "launch services: stale bundle_id=${bundle_id:-$canonical_id} path=$stale_path"
        if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
            echo "[$action_label] would unregister: $stale_path"
            adobe_cleaner_log_line "launch services: would unregister bundle_id=${bundle_id:-$canonical_id} path=$stale_path"
            continue
        fi
        if "$lsregister" -u "$stale_path" >/dev/null 2>&1; then
            result="success"
            ADOBE_UI_CHANGED="1"
        else
            result="failed"
        fi
        adobe_cleaner_log_line "launch services: unregister result=$result bundle_id=${bundle_id:-$canonical_id} path=$stale_path"
    done <<< "$LAUNCH_SERVICES_STALE_RECORDS"

    if [[ "$stale_count" -eq 0 ]]; then
        echo "No stale Adobe Launch Services registrations found."
        return 0
    fi

    # -gc cleans up auxiliary records after the targeted unregister pass.
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        echo "[$action_label] would run lsregister -gc."
        adobe_cleaner_log_line "launch services: would run garbage collection; stale apps=$stale_count"
    else
        if "$lsregister" -gc >/dev/null 2>&1; then
            adobe_cleaner_log_line "launch services: garbage collection result=success; stale apps=$stale_count"
        else
            adobe_cleaner_log_line "launch services: garbage collection result=failed; stale apps=$stale_count"
        fi
    fi
}

adobe_cleaner_reconcile_launchpad() {
    local db sqlite3_bin backup plan_output line action item_id title bundle_id reason
    local -a live_args=() item_args=()
    local plan_status=0
    local remove_count=0
    local live_id
    local action_label

    db="${LAUNCHPAD_DB:-$(getconf DARWIN_USER_DIR 2>/dev/null)com.apple.dock.launchpad/db/db}"
    sqlite3_bin="${SQLITE3_BIN:-sqlite3}"
    if [[ ! -f "$db" ]]; then
        echo "Launchpad reconciliation skipped (database not found)."
        adobe_cleaner_log_line "launchpad: skipped; database not found: $db"
        return 0
    fi
    if ! command -v "$sqlite3_bin" >/dev/null 2>&1; then
        echo "Launchpad reconciliation skipped (sqlite3 is unavailable)."
        adobe_cleaner_log_line "launchpad: skipped; sqlite3 unavailable"
        return 0
    fi
    if [[ "$LAUNCH_SERVICES_AVAILABLE" != "1" ]]; then
        echo "Launchpad reconciliation skipped (cannot confirm live applications without lsregister)."
        adobe_cleaner_log_line "launchpad: skipped; Launch Services data unavailable"
        return 0
    fi

    for live_id in "${LAUNCH_SERVICES_LIVE_IDS[@]}"; do
        live_args+=(--live-id "$live_id")
    done
    plan_output="$(printf '%s\n' "$CLEANUP_PROVENANCE" | python3 "${CLEANER_DIR}/lib/launchpad_reconcile.py" plan "$db" --provenance-stdin "${live_args[@]}")" || plan_status=$?
    if [[ "$plan_status" -ne 0 ]]; then
        echo "Launchpad reconciliation skipped (unsupported database schema)."
        adobe_cleaner_log_line "launchpad: skipped; schema validation failed: $plan_output"
        return 0
    fi

    backup="${db}.AdobeEnvironmentToolkit-$(date '+%Y%m%d-%H%M%S')-$$.bak"
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        echo "Launchpad DB backup would be used: $backup"
        adobe_cleaner_log_line "launchpad: backup would be used: $backup"
    else
        echo "Launchpad DB backup to use: $backup"
        adobe_cleaner_log_line "launchpad: backup to use: $backup"
    fi
    while IFS=$'\t' read -r action item_id title bundle_id reason; do
        [[ -z "$action" ]] && continue
        echo "Launchpad $action: item=$item_id title=$title bundle_id=$bundle_id ($reason)"
        adobe_cleaner_log_line "launchpad: candidate item_id=$item_id title=$title bundle_id=$bundle_id reason=$reason action=$action"
        if [[ "$action" == "REMOVE" ]]; then
            item_args+=(--id "$item_id")
            remove_count=$((remove_count + 1))
        fi
    done <<< "$plan_output"

    if [[ "${#item_args[@]}" -eq 0 ]]; then
        echo "No Launchpad records require removal; Dock will not be restarted for Launchpad."
        return 0
    fi
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        action_label="dry-run"
        [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"
        echo "[$action_label] would back up the database, remove $remove_count Launchpad record(s) in one transaction, and restart Dock."
        adobe_cleaner_log_line "launchpad: would apply transaction; records=$remove_count"
        ADOBE_UI_CHANGED="1"
        return 0
    fi
    if ! cp -p "$db" "$backup" 2>/dev/null || ! cmp -s "$db" "$backup"; then
        echo "Launchpad reconciliation skipped (database backup failed)."
        adobe_cleaner_log_line "launchpad: backup failed: $backup"
        return 0
    fi
    adobe_cleaner_log_line "launchpad: backup created: $backup"
    if plan_output="$(python3 "${CLEANER_DIR}/lib/launchpad_reconcile.py" apply "$db" "${item_args[@]}" 2>&1)"; then
        echo "Launchpad database transaction completed."
        adobe_cleaner_log_line "launchpad: transaction result=success details=$plan_output"
        ADOBE_UI_CHANGED="1"
    else
        echo "Launchpad reconciliation failed; transaction was rolled back."
        adobe_cleaner_log_line "launchpad: transaction result=failed details=$plan_output"
    fi
}

adobe_cleaner_restart_dock_if_needed() {
    local action_label
    if [[ "$ADOBE_UI_CHANGED" != "1" ]]; then
        if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
            action_label="dry-run"
            [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"
            echo "[$action_label] Dock would not be restarted (no relevant UI changes planned)."
            adobe_cleaner_log_line "launchpad: Dock would not be restarted; no relevant UI changes"
        fi
        return 0
    fi
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        action_label="dry-run"
        [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"
        echo "[$action_label] Dock would be restarted."
        adobe_cleaner_log_line "launchpad: Dock would be restarted"
        return 0
    fi
    if pgrep -x Dock >/dev/null 2>&1; then
        if killall Dock >/dev/null 2>&1; then
            echo "Launchpad refreshed."
            adobe_cleaner_log_line "launchpad: Dock restart result=success"
        else
            adobe_cleaner_log_line "launchpad: Dock restart result=failed"
        fi
    else
        echo "Dock is not running; no restart was needed."
        adobe_cleaner_log_line "launchpad: Dock restart skipped; Dock not running"
    fi
}

adobe_cleaner_flush_dns() {
    echo ""
    echo -e "${RED}Flushing DNS cache...${NC}"
    adobe_cleaner_log_line "dns flush dry_run=${DRY_RUN}"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] dscacheutil -flushcache; killall -HUP mDNSResponder"
        return 0
    fi
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    echo "Done."
}

adobe_cleaner_sudo_keep_alive() {
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

adobe_cleaner_parse_args() {
    MODE="full"
    DRY_RUN="0"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN="1"
                shift
                ;;
            kill|kill-only)
                MODE="kill"
                shift
                ;;
            full)
                MODE="full"
                shift
                ;;
            diagnose)
                MODE="diagnose"
                shift
                ;;
            repair-ui)
                MODE="repair-ui"
                shift
                ;;
            -h|--help)
                MODE="help"
                shift
                ;;
            *)
                echo "Unknown arg: $1"
                MODE="help"
                shift
                ;;
        esac
    done
}

adobe_cleaner_print_help() {
    cat <<'EOF'
Usage: AdobeCleaner.command [options] [mode]

Modes:
  full       Full cleanup (default)
  kill       Kill processes and unload launchd only (no rm)
  diagnose   Inspect stale Launch Services and Launchpad records (no changes)
  repair-ui  Repair only stale Launch Services and confirmed Launchpad records

Options:
  --dry-run  Show actions without rm/pkill/sudo launchctl

Examples:
  ./AdobeCleaner.command --dry-run full
  ./AdobeCleaner.command kill
  ./AdobeCleaner.command diagnose
  ./AdobeCleaner.command --dry-run repair-ui
EOF
}

adobe_cleaner_confirm_full() {
    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi
    echo ""
    echo -e "${YELLOW}This will permanently delete Adobe data listed in shared/cleaner-manifest.json.${NC}"
    echo "Type exactly: YES DELETE ADOBE"
    read -r line
    if [[ "$line" != "YES DELETE ADOBE" ]]; then
        echo "Cancelled."
        adobe_cleaner_log_line "aborted: confirmation failed"
        exit 1
    fi
}

adobe_cleaner_main() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    CLEANER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    MANIFEST="${CLEANER_DIR}/../../shared/cleaner-manifest.json"

    if [[ ! -f "$MANIFEST" ]]; then
        echo "Missing cleaner manifest: $MANIFEST"
        exit 1
    fi

    adobe_cleaner_parse_args "$@"

    if [[ "$MODE" == "help" ]]; then
        adobe_cleaner_print_help
        exit 0
    fi

    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}   ADOBE ENVIRONMENT TOOLKIT — CLEANER           ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    if [[ "$DRY_RUN" == "1" ]]; then
        echo -e "${YELLOW}Dry-run: destructive commands are not executed.${NC}"
        echo ""
    fi
    echo "Mode: ${MODE}"
    echo ""

    adobe_cleaner_log_line "=== start mode=${MODE} dry_run=${DRY_RUN} ==="

    CLEANUP_PROVENANCE=""
    LAUNCH_SERVICES_AVAILABLE="0"
    LAUNCH_SERVICES_LIVE_IDS=()
    LAUNCH_SERVICES_STALE_RECORDS=""
    ADOBE_UI_CHANGED="0"
    UI_DIAGNOSTIC_ONLY=""

    if [[ "$MODE" == "diagnose" ]]; then
        UI_DIAGNOSTIC_ONLY="1"
        adobe_cleaner_refresh_launch_services
        adobe_cleaner_reconcile_launchpad
        adobe_cleaner_restart_dock_if_needed
        adobe_cleaner_log_line "=== end diagnose ==="
        return 0
    fi

    if [[ "$MODE" == "repair-ui" ]]; then
        adobe_cleaner_refresh_launch_services
        adobe_cleaner_reconcile_launchpad
        adobe_cleaner_restart_dock_if_needed
        adobe_cleaner_log_line "=== end repair-ui ==="
        return 0
    fi

    if [[ "$MODE" == "full" ]]; then
        adobe_cleaner_confirm_full
    fi

    if [[ "$DRY_RUN" != "1" ]]; then
        echo "Administrator rights required for system paths."
        sudo -v
        adobe_cleaner_sudo_keep_alive
    fi

    adobe_cleaner_kill_processes

    if [[ "$MODE" == "kill" ]]; then
        adobe_cleaner_unload_launchd
        adobe_cleaner_log_line "=== end kill-only ==="
        echo ""
        echo -e "${GREEN}Kill-only finished.${NC}"
        read -r -p "Press Enter to close..." _ || true
        exit 0
    fi

    adobe_cleaner_unload_launchd
    adobe_cleaner_remove_paths
    adobe_cleaner_refresh_launch_services
    adobe_cleaner_reconcile_launchpad
    adobe_cleaner_restart_dock_if_needed
    adobe_cleaner_flush_dns

    adobe_cleaner_log_line "=== end full ==="
    echo ""
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}   Done. Reboot recommended.                      ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    read -r -p "Press Enter to close..." _ || true
}
