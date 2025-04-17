#!/bin/bash
# DMR 磁盘清理脚本 v1.6（修复Telegram换行与排版）
# 文件名: dmrdelete.sh

# ======================= 配置区域 =======================
TELEGRAM_BOT_TOKEN="7685027520:AAGewSctXvuXPnyo1essLU8Xtteuva43O3U"
TELEGRAM_CHAT_ID="-1002426244394"
THRESHOLD=94
DIRECTORIES=(
    "/opt/DanmakuRender-5/直播回放" 
    "/opt/DanmakuRender-5/直播回放（弹幕版）"
)
FILES_TO_DELETE_PER_DIR=2
CHECK_INTERVAL=3600
PID_DIR="/var/run/dmr_delete"
PID_FILE="${PID_DIR}/dmrdelete.pid"
# ========================================================

init_pid_dir() {
    sudo mkdir -p "$PID_DIR" 2>/dev/null
    sudo chmod 755 "$PID_DIR"
}

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
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
    local disk_info=$(get_disk_info)
    local usage=$(echo "$disk_info" | cut -d: -f1)
    local used_hr=$(echo "$disk_info" | cut -d: -f2)
    local total_hr=$(echo "$disk_info" | cut -d: -f3)

    if [ "$usage" -ge "$THRESHOLD" ]; then
        local message="*DMR 清理通知*\n⚠️ *磁盘使用率过高！*\n当前使用率: *${usage}%*（${used_hr} / ${total_hr}）\n开始自动清理...\n"
        local total_deleted=0
        local total_freed=0
        local details=""

        for dir in "${DIRECTORIES[@]}"; do
            if [ -d "$dir" ]; then
                result=$(clean_old_files "$dir" "$FILES_TO_DELETE_PER_DIR")
                deleted=$(echo "$result" | cut -d: -f1)
                size=$(echo "$result" | cut -d: -f2)
                report=$(echo "$result" | cut -d: -f3-)

                [ "$deleted" -gt 0 ] && {
                    total_deleted=$((total_deleted + deleted))
                    total_freed=$((total_freed + size))
                    details+="\n📁 *$(basename "$dir")*\n${report}"
                }
            fi
        done

        if [ "$total_deleted" -gt 0 ]; then
            disk_info=$(get_disk_info)
            local new_usage=$(echo "$disk_info" | cut -d: -f1)
            local new_used_hr=$(echo "$disk_info" | cut -d: -f2)

            message+="${details}\n\n✅ *共删除:* ${total_deleted} 个文件"
            message+="\n💾 *释放空间:* $(format_size $total_freed)"
            message+="\n📉 *清理后使用率:* ${new_usage}%（${new_used_hr} / ${total_hr}）"
            send_telegram "$(echo -e "$message")"
        else
            send_telegram "*DMR 清理通知*\n⚠️ 达到阈值但未找到可清理文件\n当前使用率: *${usage}%*（${used_hr} / ${total_hr}）"
        fi
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
            if [ -f "$PID_FILE" ]; then
                local pid=$(cat "$PID_FILE")
                if ps -p "$pid" >/dev/null; then
                    echo "服务已在运行 (PID: $pid)"
                    return 1
                fi
            fi
            nohup sudo "$0" --daemon >/dev/null 2>&1 &
            echo "服务已启动 (PID: $!)"
            send_telegram "*DMR 清理通知*\n🟢 服务启动成功"
            ;;
        stop)
            if [ -f "$PID_FILE" ]; then
                local pid=$(cat "$PID_FILE")
                sudo kill "$pid" 2>/dev/null
                sudo rm -f "$PID_FILE"
                sudo rmdir "$PID_DIR" 2>/dev/null
                echo "服务已停止"
                send_telegram "*DMR 清理通知*\n🔴 磁盘清理服务已停止"
            else
                echo "服务未运行"
            fi
            ;;
        status)
            if [ -f "$PID_FILE" ]; then
                local pid=$(cat "$PID_FILE")
                if ps -p "$pid" >/dev/null; then
                    echo "服务运行中 (PID: $pid)"
                    return 0
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
    echo ""
    echo "======================================"
    echo "    DMR 磁盘清理工具 (v1.6)"
    echo "======================================"
    echo "  1. 启动服务"
    echo "  2. 停止服务"
    echo "  3. 查看状态"
    echo "  4. 立即清理"
    echo "  5. 退出"
    echo "--------------------------------------"
    read -p "请选择操作 [1-5]: " choice

    case $choice in
        1) service_control start ;;
        2) service_control stop ;;
        3) service_control status ;;
        4) service_control cleanup ;;
        5) exit 0 ;;
        *) echo "无效选项，请重新输入"; sleep 1 ;;
    esac

    read -p "按Enter键继续..."
}

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
