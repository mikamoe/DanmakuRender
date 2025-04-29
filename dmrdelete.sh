#!/bin/bash
# DMR 磁盘清理脚本 v1.9（改进版）
# 文件名: dmrdelete.sh

# ======================= 配置区域 =======================
# 凭据文件路径：保存 Telegram Bot Token 和 Chat ID
CONFIG_FILE="/opt/DanmakuRender-5/dmrdeletetokenchatid"

# 通知标题，启动时可修改
NOTIFY_TITLE="$(hostname)"

# 磁盘使用率阈值（%），启动时可修改
THRESHOLD=94

# 需清理的目录列表
DIRECTORIES=(
    "/opt/DanmakuRender-5/直播回放"
    "/opt/DanmakuRender-5/直播回放（弹幕版）"
)

# 每个目录要删除的最旧文件数，启动时可修改
FILES_TO_DELETE_PER_DIR=3

# 检查间隔（秒）
CHECK_INTERVAL=3600

# PID 文件目录
PID_DIR="/var/run/dmr_delete"
PID_FILE="${PID_DIR}/dmrdelete.pid"
# ========================================================

# 从配置文件加载 TOKEN/CHAT_ID
load_credentials() {
    if [ -f "$CONFIG_FILE" ]; then
        IFS=":" read -r TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID < "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# 保存 TOKEN/CHAT_ID 到配置文件
save_credentials() {
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "${TELEGRAM_BOT_TOKEN}:${TELEGRAM_CHAT_ID}" | sudo tee "$CONFIG_FILE" >/dev/null
    sudo chmod 600 "$CONFIG_FILE"
}

init_pid_dir() {
    sudo mkdir -p "$PID_DIR" 2>/dev/null
    sudo chmod 755 "$PID_DIR"
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
    local disk_total=$(df -k / 2>/dev/null | awk 'NR==2 {print $2}')
    local disk_used=$(df -k / 2>/dev/null | awk 'NR==2 {print $3}')
    local disk_used_hr=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
    local disk_total_hr=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
    local disk_percent=$(awk -v used="$disk_used" -v total="$disk_total" 'BEGIN {
        if (total>0) printf "%.0f", (used/total)*100;
        else printf "0";
    }')
    echo "${disk_percent}:${disk_used_hr}:${disk_total_hr}"
}

format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        echo "$(echo "scale=2; $size/1073741824" | bc) GB"
    elif [ $size -ge 1048576 ]; then
        echo "$(echo "scale=2; $size/1048576" | bc) MB"
    elif [ $size -ge 1024 ]; then
        echo "$(echo "scale=2; $size/1024" | bc) KB"
    else
        echo "${size} B"
    fi
}

clean_old_files() {
    local dir="$1"
    local count="$2"
    local report=""
    local deleted=0
    local total_size=0

    while read -r line; do
        local file=$(echo "$line" | awk '{print $2}')
        local filename=$(basename "$file")
        local size=$(sudo stat -c%s "$file" 2>/dev/null || echo 0)

        if sudo rm -f "$file"; then
            report+="• ${filename} ($(format_size $size))\n"
            ((deleted++))
            total_size=$((total_size + size))
        else
            report+="• 删除失败: ${filename}\n"
        fi
    done <<< "$(find "$dir" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -n | head -n "$count")"

    echo "$deleted:$total_size:$report"
}

perform_cleanup() {
    # 确保已加载凭据
    load_credentials || return

    local disk_info
    disk_info=$(get_disk_info)
    local usage=$(echo "$disk_info" | cut -d: -f1)
    local used_hr=$(echo "$disk_info" | cut -d: -f2)
    local total_hr=$(echo "$disk_info" | cut -d: -f3)

    if [ "$usage" -ge "$THRESHOLD" ]; then
        local message="*${NOTIFY_TITLE} 清理通知* ($(date '+%Y-%m-%d %H:%M:%S'))\n"
        message+="⚠️ 磁盘使用率过高！当前: *${usage}%*（${used_hr} / ${total_hr}）\n开始自动清理...\n"

        local total_deleted=0 total_freed=0 details=""

        for dir in "${DIRECTORIES[@]}"; do
            [ -d "$dir" ] || continue
            local result
            result=$(clean_old_files "$dir" "$FILES_TO_DELETE_PER_DIR")
            local deleted=$(echo "$result" | cut -d: -f1)
            local size=$(echo "$result" | cut -d: -f2)
            local report=$(echo "$result" | cut -d: -f3-)

            if [ "$deleted" -gt 0 ]; then
                total_deleted=$((total_deleted + deleted))
                total_freed=$((total_freed + size))
                details+="\n📁 *$(basename "$dir")*\n${report}"
            fi
        done

        if [ "$total_deleted" -gt 0 ]; then
            disk_info=$(get_disk_info)
            local new_usage=$(echo "$disk_info" | cut -d: -f1)
            local new_used_hr=$(echo "$disk_info" | cut -d: -f2)

            message+="${details}\n\n✅ 共删除: ${total_deleted} 个文件"
            message+="\n💾 释放空间: $(format_size $total_freed)"
            message+="\n📉 清理后: ${new_usage}%（${new_used_hr} / ${total_hr}）"
        else
            message="*${NOTIFY_TITLE} 清理通知* ($(date '+%Y-%m-%d %H:%M:%S'))\n"
            message+="⚠️ 达到阈值但未找到可清理文件\n当前: *${usage}%*（${used_hr} / ${total_hr}）"
        fi

        send_telegram "$message"
    fi
}

run_as_daemon() {
    init_pid_dir
    echo $$ | sudo tee "$PID_FILE" >/dev/null
    perform_cleanup
    while true; do
        sleep $CHECK_INTERVAL
        perform_cleanup
    done
}

service_control() {
    case "$1" in
        start)
            # 已有守护进程检查
            if [ -f "$PID_FILE" ]; then
                local pid
                pid=$(cat "$PID_FILE")
                if ps -p "$pid" >/dev/null; then
                    echo "服务已在运行 (PID: $pid)"
                    exit 1
                else
                    sudo rm -f "$PID_FILE"
                fi
            fi

            # Token/Chat ID 配置
            if load_credentials; then
                read -p "检测到已保存的 Telegram 凭据，是否继续使用？[Y/n]: " use_last
                use_last=${use_last:-Y}
                if [[ ! "$use_last" =~ ^[Yy]$ ]]; then
                    read -p "请输入 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
                    read -p "请输入 Telegram Chat ID: " TELEGRAM_CHAT_ID
                    save_credentials
                fi
            else
                read -p "请输入 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
                read -p "请输入 Telegram Chat ID: " TELEGRAM_CHAT_ID
                save_credentials
            fi

            # 交互式配置阈值、标题和文件数量
            read -p "请输入磁盘使用率阈值 (%) (默认: ${THRESHOLD}%): " input_thresh
            THRESHOLD=${input_thresh:-$THRESHOLD}

            read -p "请输入 Telegram 通知标题 (默认: ${NOTIFY_TITLE}): " input_title
            NOTIFY_TITLE=${input_title:-$NOTIFY_TITLE}

            read -p "请输入每个目录要清理的视频文件数量 (默认: ${FILES_TO_DELETE_PER_DIR}): " input_count
            FILES_TO_DELETE_PER_DIR=${input_count:-$FILES_TO_DELETE_PER_DIR}

            # 启动守护进程
            nohup sudo "$0" --daemon >/dev/null 2>&1 &
            local daemon_pid=$!
            echo "服务已启动 (PID: $daemon_pid)"

            # 发送启动通知
            local now dirs start_msg
            now=$(date '+%Y-%m-%d %H:%M:%S')
            dirs=$(printf "%s, %s" "$(basename "${DIRECTORIES[0]}")" "$(basename "${DIRECTORIES[1]}")")
            start_msg="*${NOTIFY_TITLE} 服务启动成功* (${now})\n"
            start_msg+="⚙️ 当前配置:\n"
            start_msg+="- 阈值: ${THRESHOLD}%\n"
            start_msg+="- 每目录删除: ${FILES_TO_DELETE_PER_DIR} 个文件\n"
            start_msg+="- 监控目录: ${dirs}"
            send_telegram "$start_msg"
            ;;
        stop)
            if [ -f "$PID_FILE" ]; then
                local pid now dirs stop_msg
                pid=$(cat "$PID_FILE")
                sudo kill "$pid" 2>/dev/null || true
                pkill -f "$(basename "$0") --daemon" 2>/dev/null || true
                sudo rm -rf "$PID_DIR"
                rm -f nohup.out >/dev/null 2>&1
                echo "服务已停止，所有残留已清理"

                now=$(date '+%Y-%m-%d %H:%M:%S')
                dirs=$(printf "%s, %s" "$(basename "${DIRECTORIES[0]}")" "$(basename "${DIRECTORIES[1]}")")
                stop_msg="*${NOTIFY_TITLE} 服务已停止* (${now})\n"
                stop_msg+="🛑 服务已停止运行\n"
                stop_msg+="⚙️ 最后配置: 阈值 ${THRESHOLD}%，每目录删除 ${FILES_TO_DELETE_PER_DIR} 个文件\n"
                stop_msg+="- 监控目录: ${dirs}"
                load_credentials && send_telegram "$stop_msg"
            else
                echo "服务未运行"
            fi
            ;;
        status)
            if [ -f "$PID_FILE" ]; then
                local pid
                pid=$(cat "$PID_FILE")
                if ps -p "$pid" >/dev/null; then
                    echo "服务运行中 (PID: $pid)"
                    exit 0
                else
                    sudo rm -f "$PID_FILE"
                fi
            fi
            echo "服务未运行"
            ;;
        cleanup)
            perform_cleanup
            ;;
        *)
            echo "用法: $0 {start|stop|status|cleanup|--daemon}"
            exit 1
            ;;
    esac
}

show_menu() {
    clear
    cat <<EOF

======================================
    DMR 磁盘清理工具 (v1.9 改进版)
======================================
  1. 启动服务
  2. 停止服务
  3. 查看状态
  4. 立即清理
  5. 退出
--------------------------------------
EOF
    read -p "请选择操作 [1-5]: " choice
    case $choice in
        1) service_control start ;;
        2) service_control stop ;;
        3) service_control status ;;
        4) service_control cleanup ;;
        5) exit 0 ;;
        *) echo "无效选项，请重新输入"; sleep 1 ;;
    esac
    read -p "按 Enter 键继续..."
}

# 脚本入口
case "$1" in
    --daemon)
        run_as_daemon
        ;;
    start|stop|status|cleanup)
        service_control "$1"
        ;;
    *)
        while true; do
            show_menu
        done
        ;;
esac
