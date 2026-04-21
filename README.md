# bash-sysmon

Bash-инструментарий для мониторинга Linux-серверов, бэкапов и начальной настройки. Без зависимостей — только bash и стандартные утилиты.

A collection of Bash scripts for Linux server monitoring, automated backups, and initial server hardening. Zero dependencies beyond standard Linux utilities.

## Scripts

| Script | Description |
|:---|:---|
| `sysmon.sh` | Real-time CPU/RAM/disk monitoring with Telegram alerts |
| `backup.sh` | Automated backups for directories and databases (PostgreSQL, MySQL) |
| `disk-alert.sh` | Disk usage alerts per partition with configurable threshold and Telegram notifications |
| `logrotate.sh` | Log rotation by size with gzip compression and age-based cleanup |
| `netmon.sh` | Network latency and packet loss monitor with Telegram alerts |
| `healthcheck.sh` | HTTP endpoint health checker with response times and Telegram alerts |
| `ssl-check.sh` | SSL certificate expiry checker with configurable warning threshold |
| `server-setup.sh` | Ubuntu server initial setup: UFW, fail2ban, deploy user, SSH hardening, Docker |

## Quick Start

```bash
git clone https://github.com/qorexdev/bash-sysmon
cd bash-sysmon
chmod +x *.sh
```

## sysmon.sh

```bash
# Show current system status
./sysmon.sh status

# Continuous monitoring (60s interval)
./sysmon.sh watch

# Single check — outputs only if thresholds exceeded
./sysmon.sh check

# Top 10 processes by CPU/RAM
./sysmon.sh top

# Check service status
./sysmon.sh services

# Show listening ports
./sysmon.sh net
```

**Telegram alerts:**
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
./sysmon.sh watch
```

**Cron (every 5 minutes):**
```bash
echo '*/5 * * * * CPU_THRESHOLD=80 /path/to/sysmon.sh check' | crontab -
```

**Custom thresholds:**
```bash
CPU_THRESHOLD=70 RAM_THRESHOLD=85 DISK_THRESHOLD=80 ./sysmon.sh watch
```

## backup.sh

```bash
# Backup a directory
./backup.sh dir /var/www/html mysite

# Backup PostgreSQL database
PGPASSWORD=secret ./backup.sh postgres mydb

# Backup MySQL database
MYSQL_PASSWORD=secret ./backup.sh mysql mydb

# Clean up backups older than 7 days
RETENTION_DAYS=7 ./backup.sh cleanup
```

**Daily cron:**
```bash
0 3 * * * BACKUP_DIR=/backups PGPASSWORD=pass /path/to/backup.sh postgres mydb
0 4 * * * BACKUP_DIR=/backups /path/to/backup.sh cleanup
```

## disk-alert.sh

```bash
# Check all partitions (default threshold: 80%)
./disk-alert.sh

# Custom threshold
./disk-alert.sh --threshold 90

# Only check root partition
./disk-alert.sh --mount /

# Preview mode — shows what would alert without sending notifications
./disk-alert.sh --dry-run

# Combine options
./disk-alert.sh --threshold 75 --mount /home --dry-run
```

**Hourly cron with Telegram:**
```bash
0 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/disk-alert.sh --threshold 85
```

## logrotate.sh

```bash
# Check current log sizes
./logrotate.sh status

# Rotate logs bigger than 10M (default)
./logrotate.sh rotate

# Remove rotated logs older than 30 days
./logrotate.sh clean

# Both rotate + clean in one go
./logrotate.sh all

# Preview what would happen without changing anything
DRY_RUN=true ./logrotate.sh all

# Custom size threshold and retention
MAX_SIZE=5M MAX_FILES=3 ./logrotate.sh rotate

# Use with any log directory
LOG_DIR=/var/log/myapp ./logrotate.sh rotate
```

**Daily cron:**
```bash
0 2 * * * /path/to/logrotate.sh all
```

## netmon.sh

```bash
# Check latency and packet loss for default targets (8.8.8.8, 1.1.1.1, google.com)
./netmon.sh

# 10 pings per target
./netmon.sh -c 10

# Custom targets and loss threshold
./netmon.sh --targets "8.8.8.8 cloudflare.com" --loss 10

# Set latency alert threshold (ms)
./netmon.sh --latency 100
```

**Telegram alerts:**
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
./netmon.sh
```

**Cron (every 10 minutes):**
```bash
*/10 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/netmon.sh
```

## healthcheck.sh

Checks HTTP endpoints from a config file and reports status + response time. Exits with code 1 if any service is down.

```bash
# Check endpoints from config file
./healthcheck.sh healthcheck.conf

# Custom timeout (default: 5s)
TIMEOUT=10 ./healthcheck.sh healthcheck.conf

# With Telegram alerts
TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy ./healthcheck.sh healthcheck.conf
```

**Config file format** (`healthcheck.conf`):
```
# name            url                       [timeout]
google            https://www.google.com
my-api            https://api.example.com   10
```

**Cron (every 2 minutes):**
```bash
*/2 * * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/healthcheck.sh /path/to/healthcheck.conf
```

## ssl-check.sh

```bash
# Check one or more domains
./ssl-check.sh example.com google.com

# Read domains from a file
./ssl-check.sh --file domains.txt

# Custom warning threshold (default: 30 days)
./ssl-check.sh --warn-days 14 example.com

# Preview without Telegram alerts
./ssl-check.sh --dry-run example.com
```

**Daily cron:**
```bash
0 8 * * * TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /path/to/ssl-check.sh --file /path/to/domains.txt
```

## server-setup.sh

```bash
# Full setup (run on a fresh Ubuntu 22.04/24.04 server)
sudo DEPLOY_USER=app TIMEZONE=Europe/Moscow ./server-setup.sh all

# Individual steps
sudo ./server-setup.sh update     # Update packages
sudo ./server-setup.sh ufw        # Configure firewall
sudo ./server-setup.sh docker     # Install Docker
sudo ./server-setup.sh swap 4096  # Create 4GB swap
```

## Configuration

Scripts read environment variables or an optional config file at `~/.config/sysmon/config`:

```bash
# ~/.config/sysmon/config
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=85
TELEGRAM_BOT_TOKEN=xxxxx
TELEGRAM_CHAT_ID=yyyyy
CHECK_INTERVAL=300
```

## Requirements

- Linux (tested on Ubuntu 20.04/22.04/24.04, Debian 11/12, CentOS 7/8)
- bash 4.0+
- Standard utilities: `awk`, `sed`, `df`, `ps`, `ss`, `ping`
- `curl` — for Telegram alerts (optional)
- `pg_dump` — for PostgreSQL backups (optional)
- `mysqldump` — for MySQL backups (optional)
- `systemctl` — for service checks and server-setup.sh

---

<p align="center">
  <sub>developed by qorex &nbsp;
    <a href="https://github.com/qorexdev">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" style="vertical-align:middle;opacity:0.6">
        <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12z"/>
      </svg>
    </a>
    &nbsp;
    <a href="https://t.me/qorexdev">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" style="vertical-align:middle;opacity:0.6">
        <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.894 8.221-1.97 9.28c-.145.658-.537.818-1.084.508l-3-2.21-1.447 1.394c-.16.16-.295.295-.605.295l.213-3.053 5.56-5.023c.242-.213-.054-.333-.373-.12l-6.871 4.326-2.962-.924c-.643-.204-.657-.643.136-.953l11.57-4.461c.537-.194 1.006.131.833.941z"/>
      </svg>
    </a>
  </sub>
</p>
