#!/usr/bin/env bash

# 日志文件路径
LOG_FILE="/opt/DanmakuRender-5/nohup.out"
# 存放后台进程 PID 的文件
PID_FILE="/opt/DanmakuRender-5/telegram_log.pid"
# 存放 Token 和 Chat ID 的配置文件
CONFIG_FILE="/opt/DanmakuRender-5/telegram_config.txt"

# 检查推送进程状态
function is_running() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(<"$PID_FILE")
        if ps -p "$pid" > /dev/null; then
            echo "运行中 (PID=$pid)"
            return 0
        else
            # 进程不存在则清理旧的 PID 文件
            rm -f "$PID_FILE"
        fi
    fi
    echo "已停止"
    return 1
}

# 读取配置文件
function read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        TOKEN=$(grep '^TOKEN=' "$CONFIG_FILE" | cut -d'=' -f2-)
        CHAT_ID=$(grep '^CHAT_ID=' "$CONFIG_FILE" | cut -d'=' -f2-)
        if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
            echo "配置文件格式不正确，请重新输入 Token 和 Chat ID。"
            return 1
        fi
        return 0
    else
        return 1
    fi
}

# 保存 Token 和 Chat ID 到配置文件
function save_config() {
    echo "TOKEN=$1" > "$CONFIG_FILE"
    echo "CHAT_ID=$2" >> "$CONFIG_FILE"
}

# 获取 Token 和 Chat ID
function get_token_and_chat_id() {
    if read_config; then
        echo "检测到保存的 Token 和 Chat ID："
        echo "Token: $TOKEN"
        echo "Chat ID: $CHAT_ID"
        read -p "是否继续使用？（y/n）: " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            return 0
        fi
    fi

    while true; do
        read -p "请输入 Telegram Bot Token（输入 0 返回菜单）: " TOKEN
        [[ "$TOKEN" == "0" ]] && return 1
        if [[ -z "$TOKEN" ]]; then
            echo "Token 不能为空。"
            continue
        fi
        if [[ ! "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            echo "Token 格式不正确，请重新输入。"
            continue
        fi

        read -p "请输入 Chat ID（输入 0 返回菜单）: " CHAT_ID
        [[ "$CHAT_ID" == "0" ]] && return 1
        if [[ -z "$CHAT_ID" ]]; then
            echo "Chat ID 不能为空。"
            continue
        fi
        if [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
            echo "Chat ID 应为纯数字，请重新输入。"
            continue
        fi

        save_config "$TOKEN" "$CHAT_ID"
        return 0
    done
}

# 清理所有残留进程
function cleanup_processes() {
    # 清理所有相关的 tail 和 bash 进程
    pkill -f "tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
    pkill -f "bash -c tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
    sleep 1
    pkill -9 -f "tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
    pkill -9 -f "bash -c tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
}

# 启动日志推送
function start_push() {
    is_running && {
        echo "日志推送已经在运行，请先停止再重新启动。"
        return
    }

    if [[ ! -e "$LOG_FILE" ]]; then
        echo "找不到日志文件：$LOG_FILE"
        return
    fi

    if ! get_token_and_chat_id; then
        return
    fi

    # 先清理可能存在的残留进程
    cleanup_processes

    echo "正在启动日志推送..."
    {
        tail -n0 -F "$LOG_FILE" 2>/dev/null | \
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
                -d chat_id="$CHAT_ID" \
                -d text="$(echo "$line" | sed 's/\"/\\"/g')" \
                >/dev/null
        done
    } &
    
    echo $! > "$PID_FILE"
    echo "日志推送已启动 (PID=$!)"
}

# 停止日志推送并清理
function stop_push() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "未检测到推送进程，当前并未运行。"
        return
    fi

    pid=$(<"$PID_FILE")
    echo "正在停止日志推送 (PID=$pid)..."
    
    # 杀死进程组
    kill -- -$(ps -o pgid= "$pid" | grep -o '[0-9]*') 2>/dev/null
    sleep 1
    kill -9 -- -$(ps -o pgid= "$pid" | grep -o '[0-9]*') 2>/dev/null
    
    # 额外清理
    cleanup_processes
    
    # 清理残留 PID 文件
    rm -f "$PID_FILE"
    echo "日志推送已停止"
}

# 主菜单循环
while true; do
    status=$(is_running)
    cat <<EOF

===============================
  实时日志推送到 Telegram
  当前状态：$status
===============================
  1) 启动实时推送
  2) 停止实时推送
  0) 退出
-------------------------------
请选择操作 [0-2]:
EOF

    read -p "> " choice
    case "$choice" in
        1) start_push ;;
        2) stop_push ;;
        0) exit 0 ;;
        *) echo "请输入有效选项 0、1 或 2。" ;;
    esac
done
