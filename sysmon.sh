#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
CONFIG_FILE="${HOME}/.config/sysmon/config"
LOG_FILE="${HOME}/.local/share/sysmon/sysmon.log"

CPU_THRESHOLD=${CPU_THRESHOLD:-85}
RAM_THRESHOLD=${RAM_THRESHOLD:-90}
DISK_THRESHOLD=${DISK_THRESHOLD:-90}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-""}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-""}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

_telegram() {
    local msg="$1"
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$msg" \
        -d parse_mode="Markdown" > /dev/null 2>&1 || true
}

_alert() {
    local level="$1"
    local msg="$2"
    _log "$level" "$msg"
    _telegram "🚨 *[$level]* $msg"
    if [[ "$level" == "CRIT" ]]; then
        echo -e "${RED}[CRIT]${NC} $msg" >&2
    else
        echo -e "${YELLOW}[WARN]${NC} $msg"
    fi
}

get_cpu() {
    awk '/^cpu /{
        idle=$5; total=$2+$3+$4+$5+$6+$7+$8
        printf "%.1f", (1 - idle/total) * 100
    }' /proc/stat
}

get_ram() {
    awk '/MemTotal/{total=$2} /MemAvailable/{avail=$2}
        END{printf "%.1f", (1 - avail/total) * 100}' /proc/meminfo
}

get_disk() {
    df -h | awk 'NR>1 && /^\// {
        gsub(/%/, "", $5)
        if ($5+0 > max) { max=$5+0; mount=$6 }
    } END{ print max, mount }'
}

get_load() {
    awk '{print $1, $2, $3}' /proc/loadavg
}

get_uptime() {
    awk '{
        days=int($1/86400); hours=int(($1%86400)/3600)
        mins=int(($1%3600)/60)
        printf "%dd %dh %dm\n", days, hours, mins
    }' /proc/uptime
}

check_once() {
    local cpu ram disk_usage disk_mount load

    cpu=$(get_cpu)
    ram=$(get_ram)
    read -r disk_usage disk_mount <<< "$(get_disk)"
    load=$(get_load)

    if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )); then
        _alert "WARN" "High CPU: ${cpu}% (threshold: ${CPU_THRESHOLD}%) | load: $load"
    fi

    if (( $(echo "$ram > $RAM_THRESHOLD" | bc -l) )); then
        _alert "WARN" "High RAM: ${ram}% (threshold: ${RAM_THRESHOLD}%)"
    fi

    if [[ -n "$disk_usage" ]] && (( disk_usage > DISK_THRESHOLD )); then
        _alert "CRIT" "Disk usage critical: ${disk_usage}% on $disk_mount (threshold: ${DISK_THRESHOLD}%)"
    fi
}

cmd_status() {
    local cpu ram disk_info load uptime_val
    cpu=$(get_cpu)
    ram=$(get_ram)
    disk_info=$(get_disk)
    load=$(get_load)
    uptime_val=$(get_uptime)

    echo -e "\n${BOLD}${CYAN}=== System Monitor v${VERSION} ===${NC}"
    echo -e "${BOLD}Hostname:${NC}  $(hostname)"
    echo -e "${BOLD}Uptime:${NC}    $uptime_val"
    echo -e "${BOLD}Load avg:${NC}  $load"

    local cpu_color="$GREEN"
    (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )) && cpu_color="$RED" || \
    (( $(echo "$cpu > 70" | bc -l) )) && cpu_color="$YELLOW"
    echo -e "${BOLD}CPU:${NC}       ${cpu_color}${cpu}%${NC} (alert: ${CPU_THRESHOLD}%)"

    local ram_color="$GREEN"
    (( $(echo "$ram > $RAM_THRESHOLD" | bc -l) )) && ram_color="$RED" || \
    (( $(echo "$ram > 75" | bc -l) )) && ram_color="$YELLOW"
    echo -e "${BOLD}RAM:${NC}       ${ram_color}${ram}%${NC} (alert: ${RAM_THRESHOLD}%)"

    local disk_usage disk_mount
    read -r disk_usage disk_mount <<< "$disk_info"
    local disk_color="$GREEN"
    [[ -n "$disk_usage" ]] && {
        (( disk_usage > DISK_THRESHOLD )) && disk_color="$RED" || \
        (( disk_usage > 75 )) && disk_color="$YELLOW"
        echo -e "${BOLD}Disk:${NC}      ${disk_color}${disk_usage}%${NC} on $disk_mount (alert: ${DISK_THRESHOLD}%)"
    }

    echo ""
}

cmd_watch() {
    echo -e "${CYAN}Watching system metrics every ${CHECK_INTERVAL}s (Ctrl+C to stop)...${NC}"
    while true; do
        check_once
        sleep "$CHECK_INTERVAL"
    done
}

cmd_top_procs() {
    local n="${1:-10}"
    echo -e "\n${BOLD}${CYAN}=== Top $n Processes by CPU ===${NC}"
    ps aux --sort=-%cpu | head -n $(( n + 1 ))
    echo -e "\n${BOLD}${CYAN}=== Top $n Processes by RAM ===${NC}"
    ps aux --sort=-%mem | head -n $(( n + 1 ))
}

cmd_services() {
    local services=("nginx" "postgresql" "redis" "docker" "ssh")
    echo -e "\n${BOLD}${CYAN}=== Service Status ===${NC}"
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $svc"
        elif systemctl list-units --full -all 2>/dev/null | grep -q "$svc"; then
            echo -e "  ${RED}●${NC} $svc (inactive)"
        fi
    done
    echo ""
}

cmd_net() {
    echo -e "\n${BOLD}${CYAN}=== Network Connections ===${NC}"
    ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null || echo "ss/netstat not available"
    echo ""
}

cmd_help() {
    echo -e "${BOLD}sysmon v${VERSION}${NC} — Linux system monitoring toolkit"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  ./sysmon.sh <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  status          Show current CPU/RAM/disk/load"
    echo "  watch           Continuous monitoring (checks every \$CHECK_INTERVAL seconds)"
    echo "  check           Single check — alerts only if thresholds exceeded"
    echo "  top [n]         Show top N processes by CPU and RAM (default: 10)"
    echo "  services        Show status of common services (nginx, postgres, redis, docker)"
    echo "  net             Show listening ports and connections"
    echo "  help            Show this help"
    echo ""
    echo -e "${BOLD}Environment variables:${NC}"
    echo "  CPU_THRESHOLD       CPU alert threshold, default: 85"
    echo "  RAM_THRESHOLD       RAM alert threshold, default: 90"
    echo "  DISK_THRESHOLD      Disk alert threshold, default: 90"
    echo "  CHECK_INTERVAL      Watch interval in seconds, default: 60"
    echo "  TELEGRAM_BOT_TOKEN  Bot token for Telegram alerts"
    echo "  TELEGRAM_CHAT_ID    Chat ID for Telegram alerts"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./sysmon.sh status"
    echo "  ./sysmon.sh watch"
    echo "  CPU_THRESHOLD=70 ./sysmon.sh check"
    echo "  TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy ./sysmon.sh watch"
    echo "  # Cron every 5 minutes:"
    echo "  echo '*/5 * * * * /path/to/sysmon.sh check' | crontab -"
}

# shellcheck source=/dev/null
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
fi

case "${1:-help}" in
    status)   cmd_status ;;
    watch)    cmd_watch ;;
    check)    check_once ;;
    top)      cmd_top_procs "${2:-10}" ;;
    services) cmd_services ;;
    net)      cmd_net ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1" >&2
        cmd_help
        exit 1
        ;;
esac
