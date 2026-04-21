#!/usr/bin/env bash
set -euo pipefail

TARGETS="${TARGETS:-8.8.8.8 1.1.1.1 google.com}"
PING_COUNT="${PING_COUNT:-5}"
LOSS_THRESHOLD="${LOSS_THRESHOLD:-20}"
LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-200}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_notify() {
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$1" -d parse_mode="Markdown" > /dev/null 2>&1 || true
}

_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--count)    PING_COUNT="${2:?--count requires a value}"; shift 2 ;;
            --targets)     TARGETS="${2:?--targets requires a value}"; shift 2 ;;
            --loss)        LOSS_THRESHOLD="${2:?--loss requires a value}"; shift 2 ;;
            --latency)     LATENCY_THRESHOLD="${2:?--latency requires a value}"; shift 2 ;;
            --help|-h)     show_help; exit 0 ;;
            *)             echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        esac
    done
}

_ping_target() {
    local target="$1"
    local result
    result=$(ping -c "$PING_COUNT" -W 3 "$target" 2>&1) || true

    local loss
    loss=$(echo "$result" | awk -F'[,%]' '/packet loss/{for(i=1;i<=NF;i++) if($i ~ /packet loss/) print $(i-1)}' | tr -d ' ')

    local min avg max
    min=$(echo "$result" | awk -F'[/ =]+' '/min\/avg\/max/{print $(NF-3)}')
    avg=$(echo "$result" | awk -F'[/ =]+' '/min\/avg\/max/{print $(NF-2)}')
    max=$(echo "$result" | awk -F'[/ =]+' '/min\/avg\/max/{print $(NF-1)}')

    if [[ -z "$loss" ]]; then
        loss="100"
    fi

    echo "$loss ${min:-0} ${avg:-0} ${max:-0}"
}

_color_for_loss() {
    local loss="$1"
    if (( loss == 0 )); then
        echo -e "$GREEN"
    elif (( loss < LOSS_THRESHOLD )); then
        echo -e "$YELLOW"
    else
        echo -e "$RED"
    fi
}

_color_for_latency() {
    local avg="$1"
    local avg_int
    avg_int=$(printf '%.0f' "$avg" 2>/dev/null) || avg_int=0
    if (( avg_int < 50 )); then
        echo -e "$GREEN"
    elif (( avg_int < LATENCY_THRESHOLD )); then
        echo -e "$YELLOW"
    else
        echo -e "$RED"
    fi
}

check_targets() {
    local hostname
    hostname=$(hostname)
    local alerts=0

    echo -e "\n${BOLD}${CYAN}=== Network Monitor ===${NC}"
    echo -e "${BOLD}Host:${NC}    $hostname"
    echo -e "${BOLD}Pings:${NC}   $PING_COUNT per target"
    echo ""

    local target
    for target in $TARGETS; do
        local loss min avg max
        read -r loss min avg max <<< "$(_ping_target "$target")"

        local loss_color latency_color
        loss_color=$(_color_for_loss "$loss")
        latency_color=$(_color_for_latency "$avg")

        if [[ "$avg" == "0" && "$loss" == "100" ]]; then
            echo -e "  ${RED}✗${NC} ${BOLD}${target}${NC} — ${RED}unreachable${NC} (100% loss)"
        else
            echo -e "  ${loss_color}●${NC} ${BOLD}${target}${NC} — latency: ${latency_color}${min}/${avg}/${max}ms${NC} — loss: ${loss_color}${loss}%${NC}"
        fi

        if (( loss >= LOSS_THRESHOLD )); then
            alerts=$((alerts + 1))
            _notify "🌐 *Network alert* on \`${hostname}\`: \`${target}\` — *${loss}%* packet loss (threshold: ${LOSS_THRESHOLD}%)"
        fi

        local avg_int
        avg_int=$(printf '%.0f' "$avg" 2>/dev/null) || avg_int=0
        if (( avg_int >= LATENCY_THRESHOLD && loss < 100 )); then
            alerts=$((alerts + 1))
            _notify "🌐 *Latency alert* on \`${hostname}\`: \`${target}\` — avg *${avg}ms* (threshold: ${LATENCY_THRESHOLD}ms)"
        fi
    done

    echo ""
    if (( alerts > 0 )); then
        echo -e "${YELLOW}${alerts} alert(s) triggered${NC}"
    else
        echo -e "${GREEN}All targets within thresholds${NC}"
    fi
    echo ""
}

show_help() {
    echo "netmon.sh — network latency and packet loss monitor"
    echo ""
    echo "Usage:"
    echo "  ./netmon.sh [options]"
    echo ""
    echo "Options:"
    echo "  -c, --count N      Number of pings per target (default: 5)"
    echo "  --targets \"list\"    Space-separated list of hosts to ping"
    echo "  --loss N            Packet loss alert threshold in % (default: 20)"
    echo "  --latency N         Average latency alert threshold in ms (default: 200)"
    echo "  --help, -h          Show this help"
    echo ""
    echo "Environment variables:"
    echo "  TARGETS              Hosts to ping (default: 8.8.8.8 1.1.1.1 google.com)"
    echo "  PING_COUNT           Same as --count"
    echo "  LOSS_THRESHOLD       Same as --loss"
    echo "  LATENCY_THRESHOLD    Same as --latency"
    echo "  TELEGRAM_BOT_TOKEN   Bot token for Telegram alerts"
    echo "  TELEGRAM_CHAT_ID     Chat ID for Telegram alerts"
    echo ""
    echo "Examples:"
    echo "  ./netmon.sh"
    echo "  ./netmon.sh -c 10"
    echo "  ./netmon.sh --targets \"8.8.8.8 cloudflare.com\" --loss 10"
    echo "  TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy ./netmon.sh"
    echo "  # Cron every 10 minutes:"
    echo "  */10 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/netmon.sh"
}

_parse_args "$@"
check_targets
