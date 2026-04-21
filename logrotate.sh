#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-${HOME}/.local/share/sysmon}"
MAX_SIZE="${MAX_SIZE:-10M}"
MAX_FILES="${MAX_FILES:-5}"
COMPRESS_LOGS="${COMPRESS_LOGS:-true}"
MAX_AGE="${MAX_AGE:-30}"
DRY_RUN="${DRY_RUN:-false}"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

parse_size() {
    local input="$1"
    local num unit
    num="${input//[^0-9]/}"
    unit="${input//[0-9]/}"
    unit="${unit^^}"
    case "$unit" in
        K|KB) echo $(( num * 1024 )) ;;
        M|MB) echo $(( num * 1024 * 1024 )) ;;
        G|GB) echo $(( num * 1024 * 1024 * 1024 )) ;;
        *)    echo "$num" ;;
    esac
}

human_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        awk "BEGIN{printf \"%.1fG\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN{printf \"%.1fM\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN{printf \"%.1fK\", $bytes/1024}"
    else
        echo "${bytes}B"
    fi
}

rotate_file() {
    local file="$1"
    local max_files="$MAX_FILES"

    local i=$max_files
    while (( i > 0 )); do
        local prev=$(( i - 1 ))
        local src dst

        if (( prev == 0 )); then
            src="$file"
        else
            src="${file}.${prev}"
            [[ ! -f "$src" && -f "${src}.gz" ]] && src="${src}.gz"
        fi

        if [[ "$src" == *.gz ]]; then
            dst="${file}.${i}.gz"
        else
            dst="${file}.${i}"
        fi

        if [[ -f "$src" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                _log "[dry-run] would move $src -> $dst"
            else
                mv "$src" "$dst"
            fi
        fi

        (( i-- ))
    done

    local overflow="${file}.$((max_files + 1))"
    for f in "$overflow" "${overflow}.gz"; do
        if [[ -f "$f" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                _log "[dry-run] would remove $f"
            else
                rm -f "$f"
                _log "Removed overflow: $f"
            fi
        fi
    done

    if [[ "$COMPRESS_LOGS" == "true" ]]; then
        local target="${file}.1"
        if [[ -f "$target" && "$target" != *.gz ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                _log "[dry-run] would compress $target"
            else
                gzip "$target"
                _log "Compressed: ${target}.gz"
            fi
        fi
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        touch "$file"
    fi
}

cmd_rotate() {
    local max_bytes
    max_bytes=$(parse_size "$MAX_SIZE")

    _log "Scanning $LOG_DIR for logs > $(human_size "$max_bytes")"

    local count=0
    while IFS= read -r -d '' logfile; do
        local size
        size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo 0)

        if (( size > max_bytes )); then
            _log "Rotating: $logfile ($(human_size "$size"))"
            rotate_file "$logfile"
            (( count++ ))
        fi
    done < <(find "$LOG_DIR" -maxdepth 2 -name "*.log" -type f -print0 2>/dev/null)

    if (( count == 0 )); then
        _log "No logs need rotation"
    else
        _log "Rotated $count file(s)"
    fi
}

cmd_clean() {
    _log "Removing rotated logs older than ${MAX_AGE} days"

    local count=0
    while IFS= read -r -d '' old; do
        if [[ "$DRY_RUN" == "true" ]]; then
            _log "[dry-run] would remove $old"
        else
            rm -f "$old"
            _log "Removed: $old"
        fi
        (( count++ ))
    done < <(find "$LOG_DIR" -maxdepth 2 \( -name "*.log.[0-9]" -o -name "*.log.[0-9].gz" \) -type f -mtime +"$MAX_AGE" -print0 2>/dev/null)

    if (( count == 0 )); then
        _log "No old logs to clean"
    else
        _log "Cleaned $count file(s)"
    fi
}

cmd_status() {
    echo "Log directory: $LOG_DIR"
    echo ""

    if [[ ! -d "$LOG_DIR" ]]; then
        echo "Directory does not exist."
        return
    fi

    local total=0
    while IFS= read -r -d '' f; do
        local s
        s=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
        (( total += s ))

        local name
        name="${f#"$LOG_DIR"/}"
        printf "  %-40s %s\n" "$name" "$(human_size "$s")"
    done < <(find "$LOG_DIR" -maxdepth 2 \( -name "*.log" -o -name "*.log.*" \) -type f -print0 2>/dev/null | sort -z)

    echo ""
    echo "Total: $(human_size "$total")"
}

cmd_help() {
    echo "logrotate.sh — log rotation for sysmon"
    echo ""
    echo "Usage:"
    echo "  ./logrotate.sh rotate    Rotate logs exceeding MAX_SIZE"
    echo "  ./logrotate.sh clean     Remove rotated logs older than MAX_AGE days"
    echo "  ./logrotate.sh status    Show log files and sizes"
    echo "  ./logrotate.sh all       Run rotate + clean"
    echo "  ./logrotate.sh help      Show this help"
    echo ""
    echo "Environment variables:"
    echo "  LOG_DIR         Directory to scan (default: ~/.local/share/sysmon)"
    echo "  MAX_SIZE        Max log size before rotation (default: 10M)"
    echo "  MAX_FILES       Number of rotated copies to keep (default: 5)"
    echo "  COMPRESS_LOGS   Gzip rotated files (default: true)"
    echo "  MAX_AGE         Days to keep rotated logs (default: 30)"
    echo "  DRY_RUN         Preview mode, no changes (default: false)"
    echo ""
    echo "Examples:"
    echo "  ./logrotate.sh rotate"
    echo "  MAX_SIZE=5M MAX_FILES=3 ./logrotate.sh rotate"
    echo "  DRY_RUN=true ./logrotate.sh all"
    echo "  LOG_DIR=/var/log/myapp ./logrotate.sh rotate"
    echo "  # Daily cron:"
    echo "  0 2 * * * /path/to/logrotate.sh all"
}

case "${1:-help}" in
    rotate) cmd_rotate ;;
    clean)  cmd_clean ;;
    status) cmd_status ;;
    all)    cmd_rotate; cmd_clean ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1" >&2
        cmd_help
        exit 1
        ;;
esac
