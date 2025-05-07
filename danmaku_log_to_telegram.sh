#!/bin/bash

# 定义日志文件路径
LOG_FILE="/opt/DanmakuRender-5/nohup.out"

# 后台进程 PID
BACKGROUND_PID=""

# 函数：发送 Telegram 消息
send_message() {
    local message=$1
    response=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$message")
    if echo "$response" | grep -q '"ok":true'; then
        return 0
    else
        echo "发送消息失败: $response"
        return 1
    fi
}

# 函数：显示菜单并指示状态
show_menu() {
    local status="未运行"
    if [ -n "$BACKGROUND_PID" ] && kill -0 "$BACKGROUND_PID" 2>/dev/null; then
        status="正在运行 (PID: $BACKGROUND_PID)"
    fi
    echo "实时日志推送状态: $status"
    echo "1. 启动实时日志推送到Telegram"
    echo "2. 停止实时日志推送"
    echo "0. 退出"
}

# 主循环，提供交互菜单
while true; do
    show_menu
    read -p "请输入您的选择: " choice

    case $choice in
        1)
            # 检查是否已有推送进程运行
            if [ -n "$BACKGROUND_PID" ] && kill -0 "$BACKGROUND_PID" 2>/dev/null; then
                echo "日志推送已在运行。"
            else
                # 交互询问 Bot Token 和 Chat ID
                read -p "请输入 Bot Token: " BOT_TOKEN
                read -p "请输入 Chat ID: " CHAT_ID

                # 发送测试消息验证输入
                if send_message "测试消息"; then
                    # 启动后台进程推送日志
                    (
                        tail -f "$LOG_FILE" | while read line; do
                            curl -s "https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$line"
                        done
                    ) &
                    BACKGROUND_PID=$!
                    echo "日志推送已启动。"
                else
                    echo "启动失败，请检查 Bot Token 和 Chat ID 是否正确。"
                fi
            fi
            ;;
        2)
            # 检查是否有推送进程可停止
            if [ -n "$BACKGROUND_PID" ] && kill -0 "$BACKGROUND_PID" 2>/dev/null; then
                send_message "日志推送已停止"
                kill "$BACKGROUND_PID"
                BACKGROUND_PID=""
                echo "日志推送已停止。"
            else
                echo "没有正在运行的日志推送进程。"
            fi
            ;;
        0)
            echo "退出脚本。"
            break
            ;;
        *)
            echo "无效的选择，请重新输入。"
            ;;
    esac
done
