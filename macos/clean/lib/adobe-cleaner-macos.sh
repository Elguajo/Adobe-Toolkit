# Adobe Environment Toolkit — macOS cleanup backend.

adobe_cleaner_log_line() {
    local msg="$1"
    local log_dir="${HOME}/Library/Logs"
    local log_file="${log_dir}/AdobeEnvironmentToolkit-cleaner.log"
    if [[ "${DRY_RUN:-0}" == "1" || "${UI_DIAGNOSTIC_ONLY:-}" == "1" ]]; then
        return 0
    fi
    mkdir -p "$log_dir" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >>"$log_file" 2>/dev/null || true
}

adobe_cleaner_manifest_array() {
    local key="$1"
    python3 "${CLEANER_DIR}/lib/json_array.py" "${MANIFEST}" "$key"
}

adobe_cleaner_init_results() {
    local category state
    for category in PROCESSES LAUNCHD FILESYSTEM UI POST_ACTIONS; do
        for state in SUCCESS FAILED SKIPPED NOT_FOUND; do
            eval "RESULT_${category}_${state}=0"
        done
    done
    CLEANER_FAILED_TARGETS=""
}

adobe_cleaner_record_result() {
    local category="$1" state="$2" detail="$3" counter
    case "$category" in
        processes) category="PROCESSES" ;;
        launchd) category="LAUNCHD" ;;
        filesystem) category="FILESYSTEM" ;;
        ui) category="UI" ;;
        post_actions) category="POST_ACTIONS" ;;
        *) return 1 ;;
    esac
    case "$state" in
        success) state="SUCCESS" ;;
        failed) state="FAILED" ;;
        skipped) state="SKIPPED" ;;
        not_found) state="NOT_FOUND" ;;
        *) return 1 ;;
    esac
    counter="RESULT_${category}_${state}"
    eval "$counter=\$(( $counter + 1 ))"
    adobe_cleaner_log_line "result category=${category} state=${state} target=${detail}"
    if [[ "$state" == "FAILED" ]]; then
        CLEANER_FAILED_TARGETS+="${category}: ${detail}"$'\n'
    fi
}

adobe_cleaner_print_result_category() {
    local label="$1" category="$2"
    local success failed skipped not_found
    eval "success=\${RESULT_${category}_SUCCESS}"
    eval "failed=\${RESULT_${category}_FAILED}"
    eval "skipped=\${RESULT_${category}_SKIPPED}"
    eval "not_found=\${RESULT_${category}_NOT_FOUND}"
    printf '%s:\n  success: %s\n  failed: %s\n  skipped: %s\n  not found: %s\n' \
        "$label" "$success" "$failed" "$skipped" "$not_found"
}

adobe_cleaner_print_report() {
    local failed_total
    failed_total=$((RESULT_PROCESSES_FAILED + RESULT_LAUNCHD_FAILED + RESULT_FILESYSTEM_FAILED + RESULT_UI_FAILED + RESULT_POST_ACTIONS_FAILED))
    echo ""
    if [[ "$failed_total" -eq 0 ]]; then
        echo "Cleanup completed successfully"
    else
        echo "Cleanup completed with warnings"
    fi
    adobe_cleaner_print_result_category "Processes" "PROCESSES"
    adobe_cleaner_print_result_category "Launchd" "LAUNCHD"
    adobe_cleaner_print_result_category "Filesystem" "FILESYSTEM"
    adobe_cleaner_print_result_category "UI reconciliation" "UI"
    adobe_cleaner_print_result_category "Post-actions" "POST_ACTIONS"
    if [[ "$failed_total" -ne 0 ]]; then
        echo "Failed targets:"
        printf '%s' "$CLEANER_FAILED_TARGETS"
        echo "Result: PARTIAL SUCCESS"
        return 1
    fi
    echo "Result: SUCCESS"
    return 0
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
            if [[ "$DRY_RUN" == "1" ]]; then
                echo "[dry-run] pkill -f $(printf '%q' "$pat")"
                adobe_cleaner_record_result processes skipped "$pat"
            elif pkill -f "$pat" 2>/dev/null; then
                adobe_cleaner_record_result processes success "$pat"
            else
                echo "Failed to stop matches: $pat" >&2
                adobe_cleaner_record_result processes failed "$pat"
            fi
        else
            case "$?" in
                1) adobe_cleaner_record_result processes not_found "$pat" ;;
                *) echo "Could not inspect process pattern: $pat" >&2; adobe_cleaner_record_result processes failed "$pat" ;;
            esac
        fi
    done < <(adobe_cleaner_manifest_array "macos.kill_patterns")
    echo "Done."
}

adobe_cleaner_bootout_plist() {
    local plist="$1"
    local kind="$2"
    if [[ ! -f "$plist" ]]; then
        adobe_cleaner_record_result launchd not_found "$plist"
        return 0
    fi
    adobe_cleaner_log_line "launchd: $plist ($kind)"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] bootout: $plist"
        adobe_cleaner_record_result launchd skipped "$plist"
        return 0
    fi
    if [[ "$kind" == "user" ]]; then
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null \
            || launchctl unload "$plist" 2>/dev/null
    else
        sudo launchctl bootout system "$plist" 2>/dev/null \
            || sudo launchctl unload "$plist" 2>/dev/null
    fi
    if [[ "$?" -eq 0 ]]; then
        adobe_cleaner_record_result launchd success "$plist"
    else
        echo "Failed to unload: $plist" >&2
        adobe_cleaner_record_result launchd failed "$plist"
    fi
}

adobe_cleaner_unload_launchd() {
    echo ""
    echo -e "${RED}Unloading LaunchAgents / LaunchDaemons (com.adobe.*)...${NC}"
    local file
    while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "system"
    done < <(find /Library/LaunchAgents -name "com.adobe.*" -print0 2>/dev/null)
    while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "system"
    done < <(find /Library/LaunchDaemons -name "com.adobe.*" -print0 2>/dev/null)
    while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "user"
    done < <(find "${HOME}/Library/LaunchAgents" -name "com.adobe.*" -print0 2>/dev/null)
    while IFS= read -r -d '' file; do
        echo "Unload: $file"
        adobe_cleaner_bootout_plist "$file" "user"
    done < <(find "${HOME}/Library/LaunchAgents" -name "com.Adobe.*" -print0 2>/dev/null)
    echo "Launchd pass done."
}

adobe_cleaner_remove_paths() {
    echo ""
    echo -e "${RED}Removing paths...${NC}"
    local status target
    while IFS=$'\t' read -r status target; do
        [[ -z "$target" ]] && continue
        if [[ "$status" == "NOT_FOUND" ]]; then
            echo "Not found: $target"
            adobe_cleaner_record_result filesystem not_found "$target"
            continue
        fi
        adobe_cleaner_capture_application_provenance "$target"
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "[dry-run] rm -rf $(printf '%q' "$target")"
            adobe_cleaner_log_line "dry-run rm: $target"
            adobe_cleaner_record_result filesystem skipped "$target"
            continue
        fi
        adobe_cleaner_log_line "rm -rf: $target"
        if [[ "$target" == "${HOME}/"* ]]; then
            rm -rf "$target" 2>/dev/null
        else
            sudo rm -rf "$target" 2>/dev/null
        fi
        if [[ "$?" -eq 0 ]]; then
            adobe_cleaner_record_result filesystem success "$target"
        else
            echo "Failed to remove: $target" >&2
            adobe_cleaner_record_result filesystem failed "$target"
        fi
    done < <(python3 "${CLEANER_DIR}/lib/expand_macos_paths.py" "${MANIFEST}" --plan)
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
        adobe_cleaner_record_result ui skipped "Launch Services (lsregister unavailable)"
        return 0
    fi

    echo ""
    echo -e "${RED}Removing stale application registrations...${NC}"

    if ! adobe_cleaner_collect_launch_services "$lsregister"; then
        echo "Launch Services refresh skipped (registration dump is unavailable)."
        adobe_cleaner_record_result ui skipped "Launch Services registration dump"
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
            adobe_cleaner_record_result ui skipped "Launch Services: $stale_path"
            continue
        fi
        if "$lsregister" -u "$stale_path" >/dev/null 2>&1; then
            result="success"
            ADOBE_UI_CHANGED="1"
            adobe_cleaner_record_result ui success "Launch Services: $stale_path"
        else
            result="failed"
            echo "Failed to unregister stale registration: $stale_path" >&2
            adobe_cleaner_record_result ui failed "Launch Services: $stale_path"
        fi
        adobe_cleaner_log_line "launch services: unregister result=$result bundle_id=${bundle_id:-$canonical_id} path=$stale_path"
    done <<< "$LAUNCH_SERVICES_STALE_RECORDS"

    if [[ "$stale_count" -eq 0 ]]; then
        echo "No stale Adobe Launch Services registrations found."
        adobe_cleaner_record_result ui not_found "Launch Services stale registrations"
        return 0
    fi

    # -gc cleans up auxiliary records after the targeted unregister pass.
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        echo "[$action_label] would run lsregister -gc."
        adobe_cleaner_log_line "launch services: would run garbage collection; stale apps=$stale_count"
        adobe_cleaner_record_result ui skipped "Launch Services garbage collection"
    else
        if "$lsregister" -gc >/dev/null 2>&1; then
            adobe_cleaner_log_line "launch services: garbage collection result=success; stale apps=$stale_count"
            adobe_cleaner_record_result ui success "Launch Services garbage collection"
        else
            adobe_cleaner_log_line "launch services: garbage collection result=failed; stale apps=$stale_count"
            echo "Launch Services garbage collection failed." >&2
            adobe_cleaner_record_result ui failed "Launch Services garbage collection"
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
        adobe_cleaner_record_result ui not_found "Launchpad database"
        return 0
    fi
    if ! command -v "$sqlite3_bin" >/dev/null 2>&1; then
        echo "Launchpad reconciliation skipped (sqlite3 is unavailable)."
        adobe_cleaner_log_line "launchpad: skipped; sqlite3 unavailable"
        adobe_cleaner_record_result ui skipped "Launchpad (sqlite3 unavailable)"
        return 0
    fi
    if [[ "$LAUNCH_SERVICES_AVAILABLE" != "1" ]]; then
        echo "Launchpad reconciliation skipped (cannot confirm live applications without lsregister)."
        adobe_cleaner_log_line "launchpad: skipped; Launch Services data unavailable"
        adobe_cleaner_record_result ui skipped "Launchpad (Launch Services unavailable)"
        return 0
    fi

    for live_id in "${LAUNCH_SERVICES_LIVE_IDS[@]}"; do
        live_args+=(--live-id "$live_id")
    done
    plan_output="$(printf '%s\n' "$CLEANUP_PROVENANCE" | python3 "${CLEANER_DIR}/lib/launchpad_reconcile.py" plan "$db" --provenance-stdin "${live_args[@]}")" || plan_status=$?
    if [[ "$plan_status" -ne 0 ]]; then
        echo "Launchpad reconciliation skipped (unsupported database schema)."
        adobe_cleaner_log_line "launchpad: skipped; schema validation failed: $plan_output"
        adobe_cleaner_record_result ui skipped "Launchpad database schema"
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
        adobe_cleaner_record_result ui not_found "Launchpad orphan records"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        action_label="dry-run"
        [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"
        echo "[$action_label] would back up the database, remove $remove_count Launchpad record(s) in one transaction, and restart Dock."
        adobe_cleaner_log_line "launchpad: would apply transaction; records=$remove_count"
        adobe_cleaner_record_result ui skipped "Launchpad transaction ($remove_count records)"
        ADOBE_UI_CHANGED="1"
        return 0
    fi
    if ! cp -p "$db" "$backup" 2>/dev/null || ! cmp -s "$db" "$backup"; then
        echo "Launchpad reconciliation skipped (database backup failed)."
        adobe_cleaner_log_line "launchpad: backup failed: $backup"
        adobe_cleaner_record_result ui failed "Launchpad database backup: $backup"
        return 0
    fi
    adobe_cleaner_log_line "launchpad: backup created: $backup"
    if plan_output="$(python3 "${CLEANER_DIR}/lib/launchpad_reconcile.py" apply "$db" "${item_args[@]}" 2>&1)"; then
        echo "Launchpad database transaction completed."
        adobe_cleaner_log_line "launchpad: transaction result=success details=$plan_output"
        ADOBE_UI_CHANGED="1"
        adobe_cleaner_record_result ui success "Launchpad transaction ($remove_count records)"
    else
        echo "Launchpad reconciliation failed; transaction was rolled back."
        adobe_cleaner_log_line "launchpad: transaction result=failed details=$plan_output"
        adobe_cleaner_record_result ui failed "Launchpad transaction ($remove_count records)"
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
            adobe_cleaner_record_result post_actions skipped "Dock restart (no UI changes planned)"
        fi
        return 0
    fi
    if [[ "$DRY_RUN" == "1" || "$UI_DIAGNOSTIC_ONLY" == "1" ]]; then
        action_label="dry-run"
        [[ "$UI_DIAGNOSTIC_ONLY" == "1" ]] && action_label="diagnose"
        echo "[$action_label] Dock would be restarted."
        adobe_cleaner_log_line "launchpad: Dock would be restarted"
        adobe_cleaner_record_result post_actions skipped "Dock restart"
        return 0
    fi
    if pgrep -x Dock >/dev/null 2>&1; then
        if killall Dock >/dev/null 2>&1; then
            echo "Launchpad refreshed."
            adobe_cleaner_log_line "launchpad: Dock restart result=success"
            adobe_cleaner_record_result post_actions success "Dock restart"
        else
            adobe_cleaner_log_line "launchpad: Dock restart result=failed"
            echo "Failed to restart Dock." >&2
            adobe_cleaner_record_result post_actions failed "Dock restart"
        fi
    else
        echo "Dock is not running; no restart was needed."
        adobe_cleaner_log_line "launchpad: Dock restart skipped; Dock not running"
        adobe_cleaner_record_result post_actions not_found "Dock"
    fi
}

adobe_cleaner_flush_dns() {
    echo ""
    echo -e "${RED}Flushing DNS cache...${NC}"
    adobe_cleaner_log_line "dns flush dry_run=${DRY_RUN}"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] dscacheutil -flushcache; killall -HUP mDNSResponder"
        adobe_cleaner_record_result post_actions skipped "DNS cache flush"
        return 0
    fi
    if sudo dscacheutil -flushcache 2>/dev/null && sudo killall -HUP mDNSResponder 2>/dev/null; then
        adobe_cleaner_record_result post_actions success "DNS cache flush"
        echo "Done."
    else
        echo "DNS cache flush failed." >&2
        adobe_cleaner_record_result post_actions failed "DNS cache flush"
    fi
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
        return 2
    fi
    return 0
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
        return 3
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Python 3 is required to validate the cleaner manifest." >&2
        return 4
    fi
    if ! python3 "${CLEANER_DIR}/../../shared/validate_cleaner_manifest.py" \
        "$MANIFEST" "${CLEANER_DIR}/../../shared/cleaner-manifest.schema.json"; then
        return 3
    fi

    adobe_cleaner_parse_args "$@"

    if [[ "$MODE" == "help" ]]; then
        adobe_cleaner_print_help
        return 0
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
    adobe_cleaner_init_results

    if [[ "$MODE" == "diagnose" ]]; then
        UI_DIAGNOSTIC_ONLY="1"
        adobe_cleaner_refresh_launch_services
        adobe_cleaner_reconcile_launchpad
        adobe_cleaner_restart_dock_if_needed
        adobe_cleaner_log_line "=== end diagnose ==="
        adobe_cleaner_print_report
        return $?
    fi

    if [[ "$MODE" == "repair-ui" ]]; then
        adobe_cleaner_refresh_launch_services
        adobe_cleaner_reconcile_launchpad
        adobe_cleaner_restart_dock_if_needed
        adobe_cleaner_log_line "=== end repair-ui ==="
        adobe_cleaner_print_report
        return $?
    fi

    if [[ "$MODE" == "full" ]]; then
        adobe_cleaner_confirm_full || return $?
    fi

    if [[ "$DRY_RUN" != "1" ]]; then
        echo "Administrator rights required for system paths."
        if ! sudo -v; then
            echo "Administrator authorization failed." >&2
            adobe_cleaner_record_result post_actions failed "administrator authorization"
            adobe_cleaner_print_report
            return 1
        fi
        adobe_cleaner_sudo_keep_alive
    fi

    adobe_cleaner_kill_processes

    if [[ "$MODE" == "kill" ]]; then
        adobe_cleaner_unload_launchd
        adobe_cleaner_log_line "=== end kill-only ==="
        adobe_cleaner_print_report
        local result=$?
        read -r -p "Press Enter to close..." _ || true
        return "$result"
    fi

    adobe_cleaner_unload_launchd
    adobe_cleaner_remove_paths
    adobe_cleaner_refresh_launch_services
    adobe_cleaner_reconcile_launchpad
    adobe_cleaner_restart_dock_if_needed
    adobe_cleaner_flush_dns

    adobe_cleaner_log_line "=== end full ==="
    adobe_cleaner_print_report
    local result=$?
    read -r -p "Press Enter to close..." _ || true
    return "$result"
}
