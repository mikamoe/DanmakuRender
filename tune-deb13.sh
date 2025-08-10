#!/bin/bash
set -e

# 显示确认提示
read -p "是否要执行系统性能优化脚本？(Debian 13)[y/N] " confirm
confirm=${confirm:-N}
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消执行脚本。"
    exit 0
fi

# 性能优化函数
function optimize_system() {
    BACKUP_DIR=/root/perf-tune-backups-$(date +%Y%m%d%H%M%S)
    mkdir -p "$BACKUP_DIR"
    echo "备份关键配置到 $BACKUP_DIR"

    # 备份
    for f in /etc/sysctl.d/99-performance.conf /etc/security/limits.d/99-nofile.conf /etc/systemd/system.conf /etc/default/grub; do
        [ -f "$f" ] && cp -a "$f" "$BACKUP_DIR/"
    done

    # 1) sysctl - VM 和文件描述符
    cat > /etc/sysctl.d/99-performance.conf <<'EOF'
# Debian 13 性能优化（无网络内核调优）
# 文件描述符总数
fs.file-max = 2097152
# 虚拟内存与缓存管理
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.max_map_count = 262144
EOF
    sysctl --system

    # 2) ulimit / PAM limits
    cat > /etc/security/limits.d/99-nofile.conf <<'EOF'
*  soft  nofile  1048576
*  hard  nofile  1048576
root soft  nofile  1048576
root hard  nofile  1048576
EOF

    # 3) systemd 限制
    cp -a /etc/systemd/system.conf "$BACKUP_DIR/system.conf.bak" || true
    cat > /etc/systemd/system.conf <<'EOF'
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
DefaultLimitCORE=infinity
EOF
    systemctl daemon-reload

    # 4) 安装工具
    if command -v apt >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt update
        DEBIAN_FRONTEND=noninteractive apt install -y irqbalance || true
        systemctl enable --now irqbalance || true
    fi

    # 5) 禁用 THP
    GRUB_FILE=/etc/default/grub
    cp -a "$GRUB_FILE" "$BACKUP_DIR/grub.bak" || true
    if grep -q "transparent_hugepage=" "$GRUB_FILE"; then
        sed -i "s/transparent_hugepage=[^ ]*//g" "$GRUB_FILE"
    fi
    if ! grep -q "transparent_hugepage=never" "$GRUB_FILE"; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 transparent_hugepage=never\"/" "$GRUB_FILE"
    fi
    update-grub || true

    echo "优化完成，配置备份在 $BACKUP_DIR"
}

# 检测函数（已移除CPU相关检测）
function check_status() {
    echo -e "\n====== Debian 13 性能优化状态检测 ======"

    # 文件描述符
    echo -e "\n[1] 文件描述符限制"
    sysctl fs.file-max
    echo "当前 shell ulimit -n: $(ulimit -n)"
    # 检查 systemd 服务限制
    for svc in ssh sshd; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            systemctl show --property=LimitNOFILE $svc
        fi
    done

    # 虚拟内存
    echo -e "\n[2] 虚拟内存参数"
    sysctl vm.swappiness
    sysctl vm.dirty_ratio
    sysctl vm.dirty_background_ratio
    sysctl vm.vfs_cache_pressure
    sysctl vm.max_map_count

    # THP 状态
    echo -e "\n[3] Transparent HugePages 状态"
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "THP 状态不可检测"

    echo -e "\n====== 检测完成 ======"
}

# 执行优化
optimize_system

# 执行检测
check_status

# 最终提示
echo -e "\n所有优化和检测已完成。"
echo "强烈建议重启系统使所有设置生效！"
echo "请执行以下命令重启系统："
echo "  sudo reboot"
