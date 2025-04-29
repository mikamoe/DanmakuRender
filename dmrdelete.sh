#!/bin/bash
# dmrdelete.sh v2.1 —— 集成交互式菜单 + systemd 的磁盘清理服务
# 功能：
#   （无参）   —— 交互式菜单操作：安装、卸载、启动、停止、状态、立即清理、退出
#   install   —— 安装并启动 systemd 服务
#   uninstall —— 停止服务并删除 systemd 单元及残留文件
#   --daemon  —— 守护进程模式循环清理，供 systemd 调用
#
# 用法：
#   sudo ./dmrdelete.sh           # 进入交互式菜单
#   sudo ./dmrdelete.sh install   # 安装并启动服务
#   sudo ./dmrdelete.sh uninstall # 卸载服务
#   sudo systemctl {start,stop,status} dmrdelete
#   sudo systemctl restart dmrdelete
#   sudo ./dmrdelete.sh --daemon  # 由 systemd 调用

# ======================= 配置区域 =======================
CONFIG_FILE="/opt/DanmakuRender-5/dmrdeletetokenchatid"
NOTIFY_TITLE="$(hostname)"
THRESHOLD=94
DIRECTORIES=(
    "/opt/DanmakuRender-5/直播回放"
    "/opt/DanmakuRender-5/直播回放（弹幕版）"
)
FILES_TO_DELETE_PER_DIR=3
CHECK_INTERVAL=3600
SERVICE_NAME="dmrdelete"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# ========================================================

load_credentials() {
    if [ -f "$CONFIG_FILE" ]; then
        IFS=":" read -r TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID < "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

prompt_credentials() {
    echo "=== Telegram Bot 凭据配置 ==="
    read -p "请输入 Bot Token: " BOT
    read -p "请输入 Chat ID: " CID
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "${BOT}:${CID}" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "凭据已保存到 $CONFIG_FILE"
}

send_telegram() {
    local raw="$1"
    local msg
    msg=$(echo -e "$raw")
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         --data-urlencode "text=${msg}" \
         -d "parse_mode=Markdown" >/dev/null 2>&1
}

get_disk_info() {
    local total used used_hr total_hr percent
    total=$(df -k / | awk 'NR==2{print $2}')
    used=$(df -k / | awk 'NR==2{print $3}')
    used_hr=$(df -h / | awk 'NR==2{print $3}')
    total_hr=$(df -h / | awk 'NR==2{print $2}')
    percent=$(( used * 100 / total ))
    echo "${percent}:${used_hr}:${total_hr}"
}

format_size() {
    local size=$1
    if   [ $size -ge 1073741824 ]; then printf "%.2f GB" "$(bc <<< "scale=2; $size/1073741824")"
    elif [ $size -ge 1048576 ];  then printf "%.2f MB" "$(bc <<< "scale=2; $size/1048576")"
    elif [ $size -ge 1024 ];     then printf "%.2f KB" "$(bc <<< "scale=2; $size/1024")"
    else printf "%d B" "$size"
    fi
}

clean_old_files() {
    local dir=$1 count=$2
    local deleted=0 total_size=0 report=""
    mapfile -d '' files < <(
        find "$dir" -maxdepth 1 -type f -printf '%T@ %p\0' \
        | sort -z -n \
        | head -z -n "$count" \
        | cut -z -d' ' -f2-
    )
    for file in "${files[@]}"; do
        [ -e "$file" ] || continue
        local size=$(stat -c%s "$file")
        if rm -f "$file"; then
            ((deleted++, total_size+=size))
            report+="• $(basename "$file") ($(format_size $size))\n"
        else
            report+="• 删除失败: $(basename "$file")\n"
        fi
    done
    echo "${deleted}:${total_size}:${report}"
}

perform_cleanup() {
    load_credentials || { echo "⚠️ 缺少 Telegram 凭据，请先安装或在菜单中配置"; return; }
    IFS=":" read -r usage used_hr total_hr <<<"$(get_disk_info)"
    if [ "$usage" -ge "$THRESHOLD" ]; then
        local msg="*${NOTIFY_TITLE} 清理通知* ($(date '+%F %T'))\n"
        msg+="⚠️ 磁盘使用率 ${usage}%（${used_hr}/${total_hr}），开始清理…\n"
        local total_deleted=0 total_freed=0 details=""
        for dir in "${DIRECTORIES[@]}"; do
            [ -d "$dir" ] || continue
            IFS=":" read -r dcnt dsize drep <<<"$(clean_old_files "$dir" $FILES_TO_DELETE_PER_DIR)"
            if [ "$dcnt" -gt 0 ]; then
                total_deleted=$((total_deleted + dcnt))
                total_freed=$((total_freed + dsize))
                details+="\n📁 *$(basename "$dir")*\n${drep}"
            fi
        done
        if [ "$total_deleted" -gt 0 ]; then
            IFS=":" read -r newu newuhr _ <<<"$(get_disk_info)"
            msg+="${details}\n\n✅ 共删除 ${total_deleted} 个文件"
            msg+="\n💾 释放 $(format_size $total_freed)"
            msg+="\n📉 清理后 ${newu}%（${newuhr}/${total_hr}）"
        else
            msg+="⚠️ 达到阈值但未找到可删除文件"
        fi
        send_telegram "$msg"
        echo "已执行一次清理并发送通知。"
    else
        echo "当前使用率 ${usage}% 未达到阈值 ${THRESHOLD}%，无需清理。"
    fi
}

run_daemon() {
    while true; do
        perform_cleanup
        sleep "$CHECK_INTERVAL"
    done
}

install_service() {
    [ -f "$CONFIG_FILE" ] || prompt_credentials
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=DMR 磁盘清理服务
After=network.target

[Service]
Type=simple
ExecStart=$(readlink -f "$0") --daemon
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start  "$SERVICE_NAME"
    echo "✅ 服务已安装并启动：systemctl status $SERVICE_NAME"
}

uninstall_service() {
    systemctl stop    "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    echo "✅ 服务已卸载并清理残留。"
}

show_menu() {
    while true; do
        clear
        cat <<EOF
========================================
      DMR 磁盘清理工具 v2.1 菜单
========================================
1. 安装并启动 systemd 服务
2. 卸载 systemd 服务
3. 启动服务 (systemctl start)
4. 停止服务 (systemctl stop)
5. 查看状态 (systemctl status)
6. 立即清理一次
7. 退出
----------------------------------------
EOF
        read -p "请选择 [1-7]: " choice
        case "$choice" in
            1) install_service   ; read -p "按回车继续…" ;;
            2) uninstall_service ; read -p "按回车继续…" ;;
            3) systemctl start   "$SERVICE_NAME" && echo "已启动" ; read -p "按回车继续…" ;;
            4) systemctl stop    "$SERVICE_NAME" && echo "已停止" ; read -p "按回车继续…" ;;
            5) systemctl status  "$SERVICE_NAME"; read -p "按回车继续…" ;;
            6) perform_cleanup   ; read -p "按回车继续…" ;;
            7) echo "退出。"; exit 0 ;;
            *) echo "无效选项"; sleep 1 ;;
        esac
    done
}

# 脚本入口
case "$1" in
    install)   install_service ;;
    uninstall) uninstall_service ;;
    --daemon)  run_daemon ;;
    "")         show_menu ;;
    *) echo "用法: sudo $0 [install|uninstall]"; exit 1 ;;
esac
