#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/sysmon}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
COMPRESS="${COMPRESS:-true}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

_ts() { date '+%Y%m%d_%H%M%S'; }
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

_notify() {
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$1" -d parse_mode="Markdown" > /dev/null 2>&1 || true
}

backup_dir() {
    local src="$1"
    local name="${2:-$(basename "$src")}"
    local dst
    dst="${BACKUP_DIR}/${name}_$(_ts)"
    mkdir -p "$BACKUP_DIR"

    _log "Backing up directory: $src"
    if [[ "$COMPRESS" == "true" ]]; then
        dst="${dst}.tar.gz"
        tar -czf "$dst" -C "$(dirname "$src")" "$(basename "$src")"
    else
        cp -r "$src" "$dst"
    fi

    local size
    size=$(du -sh "$dst" | cut -f1)
    _log "Done: $dst ($size)"
    _notify "✅ *Backup complete*: \`$name\` → \`$dst\` ($size)"
}

backup_postgres() {
    local db="$1"
    local user="${PGUSER:-postgres}"
    local dst
    dst="${BACKUP_DIR}/pg_${db}_$(_ts).sql"
    mkdir -p "$BACKUP_DIR"

    _log "Dumping PostgreSQL database: $db"
    PGPASSWORD="${PGPASSWORD:-}" pg_dump -U "$user" "$db" > "$dst"

    if [[ "$COMPRESS" == "true" ]]; then
        gzip "$dst"
        dst="${dst}.gz"
    fi

    local size
    size=$(du -sh "$dst" | cut -f1)
    _log "Done: $dst ($size)"
    _notify "✅ *DB backup complete*: \`$db\` → \`$dst\` ($size)"
}

backup_mysql() {
    local db="$1"
    local user="${MYSQL_USER:-root}"
    local dst
    dst="${BACKUP_DIR}/mysql_${db}_$(_ts).sql"
    mkdir -p "$BACKUP_DIR"

    _log "Dumping MySQL database: $db"
    mysqldump -u "$user" ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} "$db" > "$dst"

    if [[ "$COMPRESS" == "true" ]]; then
        gzip "$dst"
        dst="${dst}.gz"
    fi

    local size
    size=$(du -sh "$dst" | cut -f1)
    _log "Done: $dst ($size)"
    _notify "✅ *MySQL backup complete*: \`$db\` → \`$dst\` ($size)"
}

cleanup_old() {
    _log "Removing backups older than ${RETENTION_DAYS} days from $BACKUP_DIR"
    find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
    _log "Cleanup done"
}

show_help() {
    echo "backup.sh — automated backup utility"
    echo ""
    echo "Usage:"
    echo "  ./backup.sh dir <path> [name]    Backup a directory"
    echo "  ./backup.sh postgres <dbname>    Backup a PostgreSQL database"
    echo "  ./backup.sh mysql <dbname>       Backup a MySQL/MariaDB database"
    echo "  ./backup.sh cleanup              Remove backups older than RETENTION_DAYS"
    echo ""
    echo "Environment variables:"
    echo "  BACKUP_DIR         Where to store backups (default: /var/backups/sysmon)"
    echo "  RETENTION_DAYS     Days to keep backups (default: 7)"
    echo "  COMPRESS           Enable gzip compression (default: true)"
    echo "  TELEGRAM_BOT_TOKEN Bot token for completion alerts"
    echo "  TELEGRAM_CHAT_ID   Chat ID for completion alerts"
    echo "  PGUSER / PGPASSWORD  PostgreSQL credentials"
    echo "  MYSQL_USER / MYSQL_PASSWORD  MySQL credentials"
    echo ""
    echo "Examples:"
    echo "  ./backup.sh dir /var/www/html mysite"
    echo "  PGPASSWORD=secret ./backup.sh postgres mydb"
    echo "  BACKUP_DIR=/mnt/nas ./backup.sh cleanup"
    echo "  # Daily cron:"
    echo "  0 3 * * * BACKUP_DIR=/backups /path/to/backup.sh dir /var/www/html"
}

case "${1:-help}" in
    dir)     backup_dir "${2:?Usage: backup.sh dir <path> [name]}" "${3:-}" ;;
    postgres) backup_postgres "${2:?Usage: backup.sh postgres <dbname>}" ;;
    mysql)   backup_mysql "${2:?Usage: backup.sh mysql <dbname>}" ;;
    cleanup) cleanup_old ;;
    help|--help|-h) show_help ;;
    *)
        echo "Unknown command: $1" >&2
        show_help
        exit 1
        ;;
esac
