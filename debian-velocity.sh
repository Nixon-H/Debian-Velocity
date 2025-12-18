#!/usr/bin/env bash
# Project: Debian-Velocity
# Description: Intelligent System Optimizer (RAM/Swap/Kernel)
# Author: Nixon-H
set -u
set -e
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
log_info() { echo "${BOLD}${GREEN}[+] $1${RESET}"; }
log_warn() { echo "${BOLD}${YELLOW}[!] $1${RESET}"; }
log_err() { echo "${BOLD}${RED}[X] $1${RESET}"; }
log_head() { echo "${BOLD}${CYAN}== $1 ==${RESET}"; }
if [[ $EUID -ne 0 ]]; then
    log_err "This script must be run as root."
    exit 1
fi
get_total_ram() {
    free -g | awk '/^Mem:/{print $2}'
}
setup_zram_service() {
    local size_gb=$1
    local size_mb=$((size_gb * 1024))
    log_info "Configuring ${size_gb}GB ZRAM Service..."
    bash -c "cat > /etc/systemd/system/zram-velocity.service" << EOF
[Unit]
Description=Debian-Velocity ZRAM (${size_gb}GB)
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/sbin/modprobe zram
ExecStartPre=/bin/sh -c 'if grep -q "^/dev/zram0" /proc/swaps; then /sbin/swapoff /dev/zram0; fi'
ExecStartPre=/bin/sh -c 'echo zstd > /sys/block/zram0/comp_algorithm'
ExecStartPre=/bin/sh -c 'echo ${size_mb}M > /sys/block/zram0/disksize'
ExecStartPre=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon -p 100 /dev/zram0
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now zram-velocity.service
}
setup_swapfile() {
    local swap_size=$1
    local swap_path="/swapfile"
    if [ -f "$swap_path" ]; then
        log_warn "Existing swapfile found. Removing..."
        swapoff "$swap_path" 2>/dev/null || true
        rm -f "$swap_path"
    fi
    log_info "Creating ${swap_size}G Swapfile (Backup)..."
    fallocate -l "${swap_size}G" "$swap_path"
    chmod 600 "$swap_path"
    mkswap "$swap_path"
    swapon "$swap_path"
    if ! grep -q "^$swap_path" /etc/fstab; then
        echo "$swap_path none swap sw 0 0" | tee -a /etc/fstab >/dev/null
    fi
}
apply_optimizations() {
    log_info "Applying Core Optimizations..."
    apt update -qq >/dev/null 2>&1
    apt install -y zram-tools nohang tlp tlp-rdw >/dev/null 2>&1
    systemctl disable --now zramswap.service 2>/dev/null || true
    if [ -f /sys/module/zswap/parameters/enabled ]; then
        echo N | tee /sys/module/zswap/parameters/enabled >/dev/null
    fi
    local grub_conf="/etc/default/grub"
    local perf_args="quiet splash zswap.enabled=0 nowatchdog nmi_watchdog=0"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_conf"; then
        if ! grep -q "zswap.enabled=0" "$grub_conf"; then
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${perf_args}\"|" "$grub_conf"
            update-grub >/dev/null 2>&1
        fi
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${perf_args}\"" | tee -a "$grub_conf" >/dev/null
        update-grub >/dev/null 2>&1
    fi
    local sysctl_conf="/etc/sysctl.conf"
    sed -i '/^vm.swappiness=/d' "$sysctl_conf"
    sed -i '/^vm.vfs_cache_pressure=/d' "$sysctl_conf"
    sed -i '/^vm.overcommit_memory=/d' "$sysctl_conf"
    sed -i '/^vm.page-cluster=/d' "$sysctl_conf"
    sed -i '/^net.ipv4.tcp_congestion_control=/d' "$sysctl_conf"
    sed -i '/^net.core.default_qdisc=/d' "$sysctl_conf"
    cat >> "$sysctl_conf" << EOF
vm.swappiness=180
vm.vfs_cache_pressure=50
vm.overcommit_memory=1
vm.page-cluster=0
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p >/dev/null
    mkdir -p /etc/nohang
    cat > /etc/nohang/nohang-desktop.conf << EOF
[thresholds]
main_threshold = 5
swap_threshold = 5
[killer]
enable_process_killer = false
EOF
    systemctl enable --now nohang-desktop.service >/dev/null 2>&1
    mount -o remount,noatime /
    if grep -q "errors=remount-ro" /etc/fstab && ! grep -q "noatime" /etc/fstab; then
        sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab
    fi
    cat > /etc/systemd/system/cpu-gov.service << EOF
[Unit]
Description=CPU Performance
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now cpu-gov.service >/dev/null 2>&1
    systemctl enable --now tlp.service >/dev/null 2>&1
    systemctl enable --now fstrim.timer >/dev/null 2>&1
    for svc in avahi-daemon cups cups-browsed ModemManager; do
        systemctl disable --now "${svc}.service" 2>/dev/null || true
    done
}
install_auto() {
    log_head "Automatic Detection Mode"
    local ram_gb=$(get_total_ram)
    log_info "Detected RAM: ${ram_gb}GB"
    if [[ $ram_gb -lt 2 ]]; then
        log_err "System RAM is below 2GB. Optimization aborted for safety."
        exit 1
    fi
    local zram_size=0
    local swap_size=10
    if [[ $ram_gb -ge 8 ]]; then
        zram_size=10
    elif [[ $ram_gb -ge 4 ]]; then
        zram_size=6
        swap_size=6
    elif [[ $ram_gb -ge 2 ]]; then
        zram_size=3
        swap_size=4
    fi
    log_info "Calculated Strategy: ZRAM=${zram_size}GB | Swapfile=${swap_size}GB"
    apply_optimizations
    setup_zram_service $zram_size
    setup_swapfile $swap_size
    log_info "Installation Complete. Please Reboot."
}
install_manual() {
    log_head "Manual Input Mode"
    read -p "Enter desired ZRAM size in GB (2-16): " zram_input
    if ! [[ "$zram_input" =~ ^[0-9]+$ ]] || [ "$zram_input" -lt 2 ] || [ "$zram_input" -gt 16 ]; then
        log_err "Invalid input. Must be an integer between 2 and 16."
        exit 1
    fi
    local swap_size=10
    log_info "Manual Strategy: ZRAM=${zram_input}GB | Swapfile=${swap_size}GB"
    apply_optimizations
    setup_zram_service $zram_input
    setup_swapfile $swap_size
    log_info "Installation Complete. Please Reboot."
}
uninstall_reverse() {
    log_head "Reversing Optimizations"
    if systemctl is-active --quiet zram-velocity.service; then
        systemctl disable --now zram-velocity.service
        rm -f /etc/systemd/system/zram-velocity.service
    fi
    if systemctl is-active --quiet cpu-gov.service; then
        systemctl disable --now cpu-gov.service
        rm -f /etc/systemd/system/cpu-gov.service
    fi
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    local grub_conf="/etc/default/grub"
    sed -i 's/zswap.enabled=0 nowatchdog nmi_watchdog=0//g' "$grub_conf"
    update-grub >/dev/null 2>&1
    local sysctl_conf="/etc/sysctl.conf"
    sed -i '/vm.swappiness=180/d' "$sysctl_conf"
    sed -i '/vm.vfs_cache_pressure=50/d' "$sysctl_conf"
    sed -i '/vm.overcommit_memory=1/d' "$sysctl_conf"
    sed -i '/net.ipv4.tcp_congestion_control = bbr/d' "$sysctl_conf"
    sysctl -p >/dev/null 2>&1
    sed -i 's/,noatime//g' /etc/fstab
    mount -o remount,atime /
    log_info "System Restored to Defaults. Please Reboot."
}
clear
echo "${BOLD}${CYAN}"
echo "    DEBIAN-VELOCITY    "
echo "    System Optimizer   "
echo "${RESET}"
echo "1. Install (Automatic Detection)"
echo "2. Install (Manual ZRAM Size)"
echo "3. Uninstall / Reverse All Changes"
echo "4. Exit"
echo
read -p "Select option [1-4]: " choice
case $choice in
    1) install_auto ;;
    2) install_manual ;;
    3) uninstall_reverse ;;
    4) exit 0 ;;
    *) log_err "Invalid Option"; exit 1 ;;
esac
