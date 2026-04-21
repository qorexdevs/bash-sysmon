#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-healthcheck.conf}"
TIMEOUT="${TIMEOUT:-5}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_notify() {
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$1" -d parse_mode="Markdown" > /dev/null 2>&1 || true
}

show_help() {
    echo "healthcheck.sh — HTTP service health checker"
    echo ""
    echo "Usage:"
    echo "  ./healthcheck.sh [config_file]"
    echo ""
    echo "Config file format (one service per line):"
    echo "  service_name url [timeout_seconds]"
    echo "  Lines starting with # are ignored."
    echo ""
    echo "Environment variables:"
    echo "  TIMEOUT              Default timeout per request in seconds (default: 5)"
    echo "  TELEGRAM_BOT_TOKEN   Bot token for Telegram alerts on failures"
    echo "  TELEGRAM_CHAT_ID     Chat ID for Telegram alerts"
    echo ""
    echo "Examples:"
    echo "  ./healthcheck.sh"
    echo "  ./healthcheck.sh /etc/healthcheck.conf"
    echo "  TIMEOUT=10 ./healthcheck.sh endpoints.conf"
    echo "  # Cron every 2 minutes:"
    echo "  */2 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/healthcheck.sh /path/to/healthcheck.conf"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    echo "Run with --help for usage info." >&2
    exit 2
fi

down=0
total=0
hostname=$(hostname)

echo -e "\n${BOLD}${CYAN}=== Health Check ===${NC}"
echo -e "${BOLD}Host:${NC}   $hostname"
echo -e "${BOLD}Config:${NC} $CONFIG_FILE"
echo ""

printf "  ${BOLD}%-24s %-8s %s${NC}\n" "SERVICE" "STATUS" "TIME"

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line=$(echo "$line" | xargs) 2>/dev/null || continue
    [[ -z "$line" ]] && continue

    read -r name url svc_timeout <<< "$line"
    t="${svc_timeout:-$TIMEOUT}"

    start=$(date +%s%N)
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$t" "$url" 2>/dev/null) || code="000"
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    total=$((total + 1))

    if [[ "$code" == "200" ]]; then
        printf "  ${GREEN}●${NC} %-24s ${GREEN}%-8s${NC} %s\n" "$name" "$code" "${ms}ms"
    else
        printf "  ${RED}●${NC} %-24s ${RED}%-8s${NC} %s\n" "$name" "$code" "${ms}ms"
        down=$((down + 1))
        _notify "🔴 *Service down* on \`${hostname}\`: *${name}* — HTTP ${code} (${url})"
    fi
done < "$CONFIG_FILE"

echo ""
if (( down > 0 )); then
    echo -e "${RED}${down}/${total} service(s) down${NC}"
else
    echo -e "${GREEN}All ${total} service(s) healthy${NC}"
fi
echo ""

exit $((down > 0 ? 1 : 0))
