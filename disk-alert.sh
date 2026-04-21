#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${THRESHOLD:-80}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
MOUNT_FILTER="${MOUNT_FILTER:-}"
DRY_RUN=false

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

_notify() {
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$1" -d parse_mode="Markdown" > /dev/null 2>&1 || true
}

_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --threshold)  THRESHOLD="${2:?--threshold requires a value}"; shift 2 ;;
            --mount)      MOUNT_FILTER="${2:?--mount requires a value}"; shift 2 ;;
            --dry-run)    DRY_RUN=true; shift ;;
            --help|-h)    show_help; exit 0 ;;
            *)            echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        esac
    done
}

_get_partitions() {
    df -P | awk 'NR>1 && /^\// {
        gsub(/%/, "", $5)
        print $5, $4, $6
    }'
}

_check_disk() {
    local alerts=0
    local hostname
    hostname=$(hostname)

    while read -r usage _avail mount; do
        [[ -z "$usage" ]] && continue

        if [[ -n "$MOUNT_FILTER" ]] && [[ "$mount" != "$MOUNT_FILTER" ]]; then
            continue
        fi

        if (( usage > THRESHOLD )); then
            alerts=$((alerts + 1))
            local avail_h
            avail_h=$(df -h "$mount" 2>/dev/null | awk 'NR==2{print $4}')

            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${YELLOW}[DRY-RUN]${NC} would alert: ${mount} at ${usage}% (${avail_h} free)"
            else
                echo -e "${RED}[ALERT]${NC} ${mount} — ${usage}% used (${avail_h} free, threshold: ${THRESHOLD}%)"
                _notify "🚨 *Disk alert* on \`${hostname}\`: \`${mount}\` at *${usage}%* (${avail_h} free, threshold: ${THRESHOLD}%)"
            fi
        else
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${GREEN}[OK]${NC} ${mount} at ${usage}% — below threshold"
            fi
        fi
    done < <(_get_partitions)

    if [[ "$DRY_RUN" == true ]] && (( alerts == 0 )); then
        echo -e "${GREEN}No partitions exceed ${THRESHOLD}% threshold${NC}"
    fi

    return 0
}

show_help() {
    echo "disk-alert.sh — disk usage alert with Telegram notifications"
    echo ""
    echo "Usage:"
    echo "  ./disk-alert.sh [options]"
    echo ""
    echo "Options:"
    echo "  --threshold N    Alert when usage exceeds N% (default: 80)"
    echo "  --mount /path    Only check a specific mount point"
    echo "  --dry-run        Preview alerts without sending notifications"
    echo "  --help, -h       Show this help"
    echo ""
    echo "Environment variables:"
    echo "  THRESHOLD            Same as --threshold"
    echo "  MOUNT_FILTER         Same as --mount"
    echo "  TELEGRAM_BOT_TOKEN   Bot token for Telegram alerts"
    echo "  TELEGRAM_CHAT_ID     Chat ID for Telegram alerts"
    echo ""
    echo "Examples:"
    echo "  ./disk-alert.sh"
    echo "  ./disk-alert.sh --threshold 90 --mount /"
    echo "  ./disk-alert.sh --dry-run"
    echo "  THRESHOLD=75 ./disk-alert.sh"
    echo "  # Cron every hour:"
    echo "  0 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/disk-alert.sh"
}

_parse_args "$@"
_check_disk
