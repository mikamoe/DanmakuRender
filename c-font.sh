#!/bin/bash
# font-dinstall.sh - 字体安装/卸载脚本（稳定显示版）

# ======== 编码环境 ========
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ======== 颜色 ========
NC="\e[0m"
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"

LOG_INFO="${BLUE}${BOLD}[i]${NC} "
LOG_SUCCESS="${GREEN}${BOLD}[✓]${NC} "
LOG_WARN="${YELLOW}${BOLD}[!]${NC} "
LOG_ERROR="${RED}${BOLD}[✗]${NC} "

# ======== 字体目录 ========
CUSTOM_FONT_DIR="/usr/local/share/fonts/custom"

# ======== 字体文件 ========
MSYH_FILE="msyh.ttf"
SEGOE_EMOJI_FILE="Segoe.UI.Emoji.with.Twemoji.Flags.ttf"
NOTO_EMOJI_FILE="NotoColorEmoji.ttf"
LXGW_WENKAI_FILE="LXGWWenKai-Medium.ttf"

# ======== root 检查 ========
if [[ $EUID -ne 0 ]]; then
    echo -e "${LOG_ERROR}请使用 sudo 运行该脚本"
    exit 1
fi

mkdir -p "$CUSTOM_FONT_DIR"
chmod 755 "$CUSTOM_FONT_DIR"

# ======== 状态检测 ========
check_font() {
    local font="$1"
    if fc-list | grep -qi "$font"; then
        echo -e "${GREEN}[已安装]${NC}"
    else
        echo -e "${RED}[未安装]${NC}"
    fi
}

# ======== 显示状态（稳定版）=======
print_status() {
    local status="$1"
    local name="$2"
    echo -e " ${status} ${name}"
}

# ======== 刷新字体 ========
refresh_fonts() {
    chmod 644 "$CUSTOM_FONT_DIR"/* 2>/dev/null
    chmod 755 "$CUSTOM_FONT_DIR"
    fc-cache -fv > /dev/null
}

# ======== 下载函数 ========
download_font() {
    local url="$1"
    local output="$2"

    wget -q --show-progress -O "$output" "$url"
    if [[ $? -ne 0 || ! -s "$output" ]]; then
        rm -f "$output"
        return 1
    fi
    return 0
}

# ======== 头部 ========
show_header() {
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e "${CYAN}${BOLD}       Linux 字体一键管理工具${NC}"
    echo -e "${CYAN}${BOLD}========================================${NC}"
}

# ======== 菜单 ========
show_menu() {
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${YELLOW}${BOLD}可用操作:${NC}"
    echo " 1. 安装 微软雅黑"
    echo " 2. 安装 Segoe UI Emoji (Win11)"
    echo " 3. 安装 Noto Color Emoji"
    echo " 4. 安装 LxgwWenKai"
    echo -e " 99. ${RED}卸载字体${NC}"
    echo " 0. 退出脚本"
    echo -e "${CYAN}----------------------------------------${NC}"
}

# ======== 主循环 ========
while true; do
    clear
    show_header

    print_status "$(check_font "Microsoft YaHei")" "微软雅黑"
    print_status "$(check_font "Segoe UI Emoji")" "Segoe UI Emoji"
    print_status "$(check_font "Noto Color Emoji")" "Noto Color Emoji"
    print_status "$(check_font "LXGW WenKai")" "LxgwWenKai"

    show_menu
    read -rp "请选择序号: " choice

    case "$choice" in
        1)
            echo -e "${LOG_INFO}安装 微软雅黑..."
            if download_font \
                "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/msyh.ttf" \
                "$CUSTOM_FONT_DIR/$MSYH_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}完成"
            else
                echo -e "${LOG_ERROR}下载失败"
            fi
            read -n1 -s -r -p "按任意键继续..."
            ;;

        2)
            echo -e "${LOG_INFO}安装 Segoe UI Emoji..."
            if download_font \
                "https://github.com/Chasmical/flag-emojis-for-windows/releases/latest/download/Segoe.UI.Emoji.with.Twemoji.Flags.ttf" \
                "$CUSTOM_FONT_DIR/$SEGOE_EMOJI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}完成"
            else
                echo -e "${LOG_ERROR}下载失败"
            fi
            read -n1 -s -r -p "按任意键继续..."
            ;;

        3)
            echo -e "${LOG_INFO}安装 Noto Color Emoji..."
            if download_font \
                "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf" \
                "$CUSTOM_FONT_DIR/$NOTO_EMOJI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}完成"
            else
                echo -e "${LOG_ERROR}下载失败"
            fi
            read -n1 -s -r -p "按任意键继续..."
            ;;

        4)
            echo -e "${LOG_INFO}安装 LxgwWenKai..."
            if download_font \
                "https://raw.githubusercontent.com/lxgw/LxgwWenKai/main/fonts/TTF/LXGWWenKai-Medium.ttf" \
                "$CUSTOM_FONT_DIR/$LXGW_WENKAI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}完成"
            else
                echo -e "${LOG_ERROR}下载失败"
            fi
            read -n1 -s -r -p "按任意键继续..."
            ;;

        99)
            clear
            show_header
            echo -e "${CYAN}==== 卸载字体 ====${NC}"

            declare -A fonts=(
                [1]="$MSYH_FILE|微软雅黑"
                [2]="$SEGOE_EMOJI_FILE|Segoe UI Emoji"
                [3]="$NOTO_EMOJI_FILE|Noto Color Emoji"
                [4]="$LXGW_WENKAI_FILE|LxgwWenKai"
            )

            for i in 1 2 3 4; do
                file="${fonts[$i]%%|*}"
                name="${fonts[$i]##*|}"
                if [[ -f "$CUSTOM_FONT_DIR/$file" ]]; then
                    echo " $i. $name"
                fi
            done

            read -rp "请输入编号: " del_choice
            file="${fonts[$del_choice]%%|*}"
            name="${fonts[$del_choice]##*|}"

            rm -f "$CUSTOM_FONT_DIR/$file"
            refresh_fonts
            echo -e "${LOG_SUCCESS}$name 已卸载"

            read -n1 -s -r -p "按任意键继续..."
            ;;

        0)
            echo -e "${LOG_INFO}退出"
            exit 0
            ;;

        *)
            echo -e "${LOG_ERROR}无效选项"
            read -n1 -s -r -p "按任意键继续..."
            ;;
    esac
done
