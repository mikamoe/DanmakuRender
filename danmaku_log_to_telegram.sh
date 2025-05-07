#!/usr/bin/env bash

# 日志文件路径
LOG_FILE="/opt/DanmakuRender-5/nohup.out"
# 存放后台进程 PID 的文件
PID_FILE="/opt/DanmakuRender-5/telegram_log.pid"

# 检查推送进程状态
function is_running() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(<"$PID_FILE")
        if kill -0 "$pid" &>/dev/null; then
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

    # 获取 Bot Token
    read -p "请输入 Telegram Bot Token（输入 0 返回菜单）: " TOKEN
    [[ "$TOKEN" == "0" ]] && return
    if [[ -z "$TOKEN" ]]; then
        echo "Token 不能为空。"
        return
    fi
    if [[ ! "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        echo "Token 格式不正确，请重新运行“启动”并输入正确的 Token。"
        return
    fi

    # 获取 Chat ID
    read -p "请输入 Chat ID（输入 0 返回菜单）: " CHAT_ID
    [[ "$CHAT_ID" == "0" ]] && return
    if [[ -z "$CHAT_ID" ]]; then
        echo "Chat ID 不能为空。"
        return
    fi
    if [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
        echo "Chat ID 应为纯数字，请重新运行“启动”并输入正确的 Chat ID。"
        return
    fi

    echo "正在启动日志推送..."
    nohup bash -c "
        tail -n0 -F \"$LOG_FILE\" 2>/dev/null | \
        while IFS= read -r line; do
            [[ -z \"\$line\" ]] && continue
            curl -s -X POST \"https://api.telegram.org/bot$TOKEN/sendMessage\" \
                -d chat_id=\"$CHAT_ID\" \
                -d text=\"\$(echo \"\$line\" | sed 's/\"/\\\"/g')\" \
                >/dev/null
        done
    " >/dev/null 2>&1 &
    bg_pid=$!
    echo "$bg_pid" > "$PID_FILE"
    echo "日志推送已启动 (PID=$bg_pid)"
}

# 停止日志推送并清理
function stop_push() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "未检测到推送进程，当前并未运行。"
        return
    fi

    pid=$(<"$PID_FILE")
    if kill -0 "$pid" &>/dev/null; then
        echo "正在停止日志推送 (PID=$pid)..."
        kill "$pid"
        sleep 1
        if kill -0 "$pid" &>/dev/null; then
            kill -9 "$pid"
        fi
        echo "日志推送已停止"
    else
        echo "进程 $pid 不存在，已清理旧记录。"
    fi

    # 清理残留 PID 文件
    rm -f "$PID_FILE"
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
        0) echo "已退出。"; exit 0 ;;
        *) echo "请输入有效选项 0、1 或 2。" ;;
    esac
done
