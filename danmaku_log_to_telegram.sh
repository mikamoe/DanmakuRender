#!/usr/bin/env bash

# ================================================
# 实时日志推送到 Telegram —— 美化版
# ================================================

# ======== 配色定义 ========
# 参考：\e[30m~\e[37m 前景色，\e[40m~\e[47m 背景色
RED='\e[31m'        # 错误／警告
GREEN='\e[32m'      # 成功／正常
YELLOW='\e[33m'     # 提示
BLUE='\e[34m'       # 信息
NC='\e[0m'          # 结束、恢复默认

# ======== 全局变量 ========
LOG_FILE="/opt/DanmakuRender-5/nohup.out"
PID_FILE="/opt/DanmakuRender-5/telegram_log.pid"
CONFIG_FILE="/opt/DanmakuRender-5/telegram_config.txt"

# ======== 打印函数 ========
_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# ======== 检查推送进程状态 ========
function is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid; pid=$(<"$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}运行中 (PID=$pid)${NC}"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    echo -e "${RED}已停止${NC}"
    return 1
}

# ======== 读取配置文件 ========
function read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        TOKEN=$(grep '^TOKEN=' "$CONFIG_FILE" | cut -d'=' -f2-)
        CHAT_ID=$(grep '^CHAT_ID=' "$CONFIG_FILE" | cut -d'=' -f2-)
        if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
            _error "配置文件格式错误，请重新输入。"
            return 1
        fi
        return 0
    fi
    return 1
}

# ======== 保存配置文件 ========
function save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    {
        echo "TOKEN=$1"
        echo "CHAT_ID=$2"
    } > "$CONFIG_FILE"
}

# ======== 获取 Token 和 Chat ID ========
function get_token_and_chat_id() {
    if read_config; then
        _info "检测到已保存 Token/Chat ID："
        echo "    Token:  $TOKEN"
        echo "    Chat ID: $CHAT_ID"
        read -p "$(echo -e ${YELLOW}“是否继续使用？ (y/n): ”${NC})" choice
        [[ "$choice" =~ ^[Yy]$ ]] && return 0
    fi

    while true; do
        read -p "$(echo -e ${YELLOW}“请输入 Telegram Bot Token（输入 0 退出）: ”${NC})" TOKEN
        [[ "$TOKEN" == "0" ]] && return 1
        if [[ ! "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            _error "Token 格式不正确，请重新输入。"
            continue
        fi

        read -p "$(echo -e ${YELLOW}“请输入 Chat ID（输入 0 退出）: ”${NC})" CHAT_ID
        [[ "$CHAT_ID" == "0" ]] && return 1
        if [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
            _error "Chat ID 应为纯数字，请重新输入。"
            continue
        fi

        save_config "$TOKEN" "$CHAT_ID"
        _success "已保存 Token 和 Chat ID 到配置文件。"
        return 0
    done
}

# ======== 清理残留进程 ========
function cleanup_processes() {
    pkill -f "tail -n0 -F \"$LOG_FILE\""      2>/dev/null
    pkill -f "bash -c tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
    sleep 1
    pkill -9 -f "tail -n0 -F \"$LOG_FILE\""    2>/dev/null
    pkill -9 -f "bash -c tail -n0 -F \"$LOG_FILE\"" 2>/dev/null
}

# ======== 启动日志推送（daemonized） ========
function start_push() {
    is_running && { _warn "请先停止正在运行的推送。"; return; }
    [[ ! -e "$LOG_FILE" ]] && { _error "找不到日志文件：$LOG_FILE"; return; }
    get_token_and_chat_id || return

    cleanup_processes

    _info "启动中，日志将后台持续推送到 Telegram..."
    nohup bash -c "\
        tail -n0 -F \"$LOG_FILE\" 2>/dev/null | \
        while IFS= read -r line; do
            [[ -z \"\$line\" ]] && continue
            curl -s -X POST \"https://api.telegram.org/bot\$TOKEN/sendMessage\" \
                -d chat_id=\"\$CHAT_ID\" \
                -d text=\"\$(echo \"\$line\" | sed 's/\"/\\\\\"/g')\" \
                >/dev/null
        done" >/dev/null 2>&1 &

    echo $! > "$PID_FILE"
    _success "日志推送已启动 (PID=$(<"$PID_FILE"))"
}

# ======== 停止日志推送 ========
function stop_push() {
    if [[ ! -f "$PID_FILE" ]]; then
        _warn "当前没有运行中的推送。"
        return
    fi

    local pid; pid=$(<"$PID_FILE")
    _info "正在停止 (PID=$pid)..."

    local pgid; pgid=$(ps -o pgid= "$pid" | grep -o '[0-9]*')
    kill -- -"$pgid" 2>/dev/null
    sleep 1
    kill -9 -- -"$pgid" 2>/dev/null

    cleanup_processes
    rm -f "$PID_FILE"
    _success "日志推送已停止"
}

# ======== 主菜单 ========
while true; do
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}   实时日志推送到 Telegram —— 管理界面${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo -e "当前状态：$(is_running)"
    echo
    echo -e "${YELLOW}1)${NC} 启动实时推送"
    echo -e "${YELLOW}2)${NC} 停止实时推送"
    echo -e "${YELLOW}0)${NC} 退出脚本"
    echo
    read -p "$(echo -e ${YELLOW}“请选择 [0-2]: ”${NC})" choice
    case "$choice" in
        1) start_push ;;
        2) stop_push  ;;
        0) _info "再见！"; exit 0 ;;
        *) _error "请输入有效选项：0、1 或 2。" ;;
    esac
    echo
    read -p "按回车键继续…" dummy
done
