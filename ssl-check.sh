#!/usr/bin/env bash
set -euo pipefail

WARN_DAYS="${WARN_DAYS:-30}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
DRY_RUN=false
DOMAINS=()

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
            --warn-days)  WARN_DAYS="${2:?--warn-days requires a value}"; shift 2 ;;
            --domain)     DOMAINS+=("${2:?--domain requires a value}"); shift 2 ;;
            --file)
                local f="${2:?--file requires a path}"
                [[ ! -f "$f" ]] && { echo "File not found: $f" >&2; exit 1; }
                while IFS= read -r line; do
                    line="${line%%#*}"
                    line="${line// /}"
                    [[ -n "$line" ]] && DOMAINS+=("$line")
                done < "$f"
                shift 2 ;;
            --dry-run)    DRY_RUN=true; shift ;;
            --help|-h)    _usage; exit 0 ;;
            *)
                # bare argument = domain
                DOMAINS+=("$1"); shift ;;
        esac
    done
}

_usage() {
    cat <<EOF
Usage: ssl-check.sh [options] [domain ...]

Check SSL certificate expiry for one or more domains.

Options:
  --domain DOMAIN    Domain to check (can be repeated)
  --file FILE        Read domains from file (one per line, # comments ok)
  --warn-days N      Warn if cert expires within N days (default: 30)
  --dry-run          Print results but don't send Telegram alerts
  -h, --help         Show this help

Environment:
  TELEGRAM_BOT_TOKEN   Bot token for alerts
  TELEGRAM_CHAT_ID     Chat ID for alerts
  WARN_DAYS            Same as --warn-days

Examples:
  ssl-check.sh example.com google.com
  ssl-check.sh --file domains.txt --warn-days 14
  ssl-check.sh --domain api.example.com --dry-run
EOF
}

check_domain() {
    local domain="$1"
    local port=443

    if [[ "$domain" == *:* ]]; then
        port="${domain##*:}"
        domain="${domain%%:*}"
    fi

    local expiry
    expiry=$(echo | openssl s_client -servername "$domain" -connect "${domain}:${port}" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2) || true

    if [[ -z "$expiry" ]]; then
        printf "${RED}%-30s UNREACHABLE${NC}\n" "$domain"
        if [[ "$DRY_RUN" == false ]]; then
            _notify "🔴 *SSL Check*: \`$domain\` — cannot connect or no certificate"
        fi
        return 1
    fi

    local exp_epoch now_epoch days_left
    exp_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    days_left=$(( (exp_epoch - now_epoch) / 86400 ))

    local color="$GREEN"
    local status="OK"
    if [[ $days_left -le 0 ]]; then
        color="$RED"
        status="EXPIRED"
    elif [[ $days_left -le $WARN_DAYS ]]; then
        color="$YELLOW"
        status="EXPIRING"
    fi

    printf "${color}%-30s %s (%d days left, expires %s)${NC}\n" \
        "$domain" "$status" "$days_left" "$expiry"

    if [[ "$status" != "OK" && "$DRY_RUN" == false ]]; then
        local emoji="⚠️"
        [[ "$status" == "EXPIRED" ]] && emoji="🔴"
        _notify "${emoji} *SSL Check*: \`$domain\` — ${status}, ${days_left} days left (expires ${expiry})"
    fi
}

main() {
    _parse_args "$@"

    if [[ ${#DOMAINS[@]} -eq 0 ]]; then
        echo "No domains specified. Use --help for usage." >&2
        exit 1
    fi

    echo "Checking ${#DOMAINS[@]} domain(s), warn threshold: ${WARN_DAYS} days"
    echo ""

    local failed=0
    for d in "${DOMAINS[@]}"; do
        check_domain "$d" || ((failed++))
    done

    echo ""
    echo "Done. ${#DOMAINS[@]} checked, ${failed} issues."
    return $failed
}

main "$@"
