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

adobe_cleaner_refresh_launch_services() {
    local lsregister
    local stale_path
    local stale_count=0
    lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    if [[ ! -x "$lsregister" ]]; then
        echo "Launch Services refresh skipped (lsregister is unavailable)."
        adobe_cleaner_log_line "launch services: skipped; lsregister unavailable"
        return 0
    fi

    echo ""
    echo -e "${RED}Removing stale application registrations...${NC}"

    # -gc alone does not remove every missing bundle on current macOS releases.
    # Explicitly unregister only missing app bundles in the Adobe paths covered
    # by the manifest. This leaves live applications (including non-Adobe ones)
    # and the user's Launchpad layout untouched.
    while IFS= read -r stale_path; do
        [[ -z "$stale_path" ]] && continue
        stale_count=$((stale_count + 1))
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "[dry-run] unregister stale app: $stale_path"
            continue
        fi
        "$lsregister" -u "$stale_path" >/dev/null 2>&1 || true
        adobe_cleaner_log_line "launch services: unregistered stale app: $stale_path"
    done < <(
        "$lsregister" -dump 2>/dev/null | awk '
            function is_adobe_path(value) {
                return value ~ /^\/Applications\/Adobe/ || value ~ /^\/Applications\/Utilities\/Adobe/ || value ~ /^\/Applications\/Utilities\/Creative Cloud/ || value ~ /^\/Library\/Application Support\/Adobe/
            }
            function emit_path() { return missing && is_adobe_path(path) }
            /^-+$/ {
                if (emit_path()) print path
                missing = 0
                path = ""
                next
            }
            /Bundle node not found on disk/ { missing = 1 }
            /^[[:space:]]*path:[[:space:]]/ {
                path = $0
                sub(/^[[:space:]]*path:[[:space:]]*/, "", path)
                sub(/[[:space:]]+\(0x[[:xdigit:]]+\)$/, "", path)
            }
            END { if (emit_path()) print path }
        ' | sort -u
    )

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] lsregister -gc; restart Dock (stale Adobe apps found: $stale_count)"
        adobe_cleaner_log_line "dry-run launch services garbage collection"
        return 0
    fi

    # -gc cleans up auxiliary records after the targeted unregister pass.
    "$lsregister" -gc >/dev/null 2>&1 || true
    adobe_cleaner_log_line "launch services: garbage collection requested; stale apps=$stale_count"

    # Dock owns Launchpad's visible cache. Restarting it makes the cleaned
    # registrations take effect without resetting the user's Launchpad layout.
    if pgrep -x Dock >/dev/null 2>&1; then
        killall Dock >/dev/null 2>&1 || true
        echo "Launchpad refreshed."
        adobe_cleaner_log_line "launch services: Dock restarted"
    else
        echo "Launch Services refreshed."
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

Options:
  --dry-run  Show actions without rm/pkill/sudo launchctl

Examples:
  ./AdobeCleaner.command --dry-run full
  ./AdobeCleaner.command kill
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
    adobe_cleaner_flush_dns

    adobe_cleaner_log_line "=== end full ==="
    echo ""
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}   Done. Reboot recommended.                      ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    read -r -p "Press Enter to close..." _ || true
}
