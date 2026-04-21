#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
TIMEZONE="${TIMEZONE:-UTC}"
SSH_PORT="${SSH_PORT:-22}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

_step() { echo -e "\n${GREEN}==>${NC} $*"; }
_info() { echo -e "  ${YELLOW}→${NC} $*"; }

require_root() {
    [[ "$EUID" -ne 0 ]] && { echo "Run as root"; exit 1; }
}

setup_locale_tz() {
    _step "Setting timezone to $TIMEZONE"
    timedatectl set-timezone "$TIMEZONE"
    _info "Timezone: $(timedatectl | grep 'Time zone')"
}

update_system() {
    _step "Updating system packages"
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git vim htop unzip \
        build-essential software-properties-common \
        ufw fail2ban \
        ca-certificates gnupg lsb-release
}

setup_ufw() {
    _step "Configuring UFW firewall"
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    _info "UFW status:"
    ufw status verbose
}

setup_fail2ban() {
    _step "Configuring fail2ban"
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(syslog_backend)s
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    _info "fail2ban enabled"
}

setup_deploy_user() {
    _step "Creating deploy user: $DEPLOY_USER"
    if id "$DEPLOY_USER" &>/dev/null; then
        _info "User $DEPLOY_USER already exists, skipping"
    else
        useradd -m -s /bin/bash "$DEPLOY_USER"
        usermod -aG sudo "$DEPLOY_USER"
        mkdir -p "/home/$DEPLOY_USER/.ssh"
        chmod 700 "/home/$DEPLOY_USER/.ssh"
        chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
        _info "User $DEPLOY_USER created (no password — add SSH key manually)"
    fi
}

harden_ssh() {
    _step "Hardening SSH configuration"
    local sshd_conf="/etc/ssh/sshd_config"
    cp "$sshd_conf" "${sshd_conf}.bak"
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$sshd_conf"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_conf"
    sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$sshd_conf"
    sed -i "s/^#\?Port.*/Port $SSH_PORT/" "$sshd_conf"
    systemctl reload sshd
    _info "SSH: root login disabled, password auth disabled, port $SSH_PORT"
}

install_docker() {
    _step "Installing Docker"
    if command -v docker &>/dev/null; then
        _info "Docker already installed: $(docker --version)"
        return
    fi
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$DEPLOY_USER" 2>/dev/null || true
    systemctl enable docker
    _info "Docker installed: $(docker --version)"
}

setup_swap() {
    local size_mb="${1:-2048}"
    _step "Setting up ${size_mb}MB swap"
    if swapon --show | grep -q '/swapfile'; then
        _info "Swap already configured"
        return
    fi
    fallocate -l "${size_mb}M" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    _info "Swap: ${size_mb}MB configured"
}

show_help() {
    echo "server-setup.sh — Ubuntu server initial configuration"
    echo ""
    echo "Usage: sudo ./server-setup.sh <command>"
    echo ""
    echo "Commands:"
    echo "  all        Run full setup (update + ufw + fail2ban + user + ssh + docker + swap)"
    echo "  update     Update system packages"
    echo "  ufw        Configure UFW firewall"
    echo "  fail2ban   Configure fail2ban"
    echo "  user       Create deploy user"
    echo "  ssh        Harden SSH config"
    echo "  docker     Install Docker"
    echo "  swap [mb]  Create swap file (default: 2048MB)"
    echo ""
    echo "Environment variables:"
    echo "  DEPLOY_USER   Username for deploy user (default: deploy)"
    echo "  TIMEZONE      System timezone (default: UTC)"
    echo "  SSH_PORT      SSH port (default: 22)"
    echo ""
    echo "Example:"
    echo "  sudo DEPLOY_USER=app TIMEZONE=Europe/Moscow ./server-setup.sh all"
}

require_root

case "${1:-help}" in
    all)
        update_system
        setup_locale_tz
        setup_ufw
        setup_fail2ban
        setup_deploy_user
        harden_ssh
        install_docker
        setup_swap "${2:-2048}"
        echo -e "\n${GREEN}Server setup complete!${NC}"
        ;;
    update)   update_system ;;
    tz)       setup_locale_tz ;;
    ufw)      setup_ufw ;;
    fail2ban) setup_fail2ban ;;
    user)     setup_deploy_user ;;
    ssh)      harden_ssh ;;
    docker)   install_docker ;;
    swap)     setup_swap "${2:-2048}" ;;
    help|--help|-h) show_help ;;
    *)
        echo "Unknown command: $1" >&2
        show_help
        exit 1
        ;;
esac
