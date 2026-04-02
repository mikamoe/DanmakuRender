#!/bin/bash
# font-dinstall.sh - 字体安装/卸载脚本（统一路径版）

# ======== 颜色与格式变量 ========
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

# ======== 统一字体目录 ========
CUSTOM_FONT_DIR="/usr/local/share/fonts/custom"

# ======== 字体文件 ========
MSYH_FILE="msyh.ttf"
SEGOE_EMOJI_FILE="Segoe.UI.Emoji.with.Twemoji.Flags.ttf"
NOTO_EMOJI_FILE="NotoColorEmoji.ttf"
LXGW_WENKAI_FILE="LXGWWenKai-Medium.ttf"

# ======== root 检查 ========
if [[ $EUID -ne 0 ]]; then
    echo -e "${LOG_ERROR}${RED}请使用 sudo 运行该脚本${NC}"
    exit 1
fi

# ======== 确保字体目录存在 ========
mkdir -p "$CUSTOM_FONT_DIR"
chmod 755 "$CUSTOM_FONT_DIR"

# ======== 检测字体安装状态 ========
check_font() {
    local font_name="$1"
    if fc-list | grep -qi "$font_name"; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# ======== 对齐打印 ========
print_status() {
    local label="$1"
    local status="$2"
    local target_width=22

    local visual_width=0
    for (( i=0; i<${#label}; i++ )); do
        local char="${label:i:1}"
        if [[ "$char" =~ [[:ascii:]] ]]; then
            ((visual_width++))
        else
            ((visual_width+=2))
        fi
    done

    echo -ne " ${label}"
    local pad=$((target_width - visual_width))
    for (( i=0; i<pad; i++ )); do echo -n " "; done
    echo -e ": ${status}"
}

# ======== 统一权限与缓存刷新 ========
refresh_fonts() {
    chmod 644 "$CUSTOM_FONT_DIR"/* 2>/dev/null
    chmod 755 "$CUSTOM_FONT_DIR"
    fc-cache -fv > /dev/null
}

# ======== 下载字体 ========
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

# ======== 主循环 ========
while true; do
    clear
    echo -e "${CYAN}${BOLD}========================================"
    echo -e "       Linux 字体一键管理工具"
    echo -e "========================================${NC}"

    print_status "微软雅黑" "$(check_font "Microsoft YaHei")"
    print_status "Segoe UI Emoji" "$(check_font "Segoe UI Emoji")"
    print_status "Noto Color Emoji" "$(check_font "Noto Color Emoji")"
    print_status "霞鹜文楷" "$(check_font "LXGW WenKai")"

    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${YELLOW}${BOLD}可用操作:${NC}"
    echo -e " 1. 安装 微软雅黑"
    echo -e " 2. 安装 Segoe UI Emoji (Win11)"
    echo -e " 3. 安装 Noto Color Emoji"
    echo -e " 4. 安装 LxgwWenKai"
    echo -e " 99. ${RED}卸载字体${NC}"
    echo -e " 0. 退出脚本"
    echo -e "${CYAN}----------------------------------------${NC}"
    read -rp "请选择序号: " choice

    case "$choice" in
        1)
            echo -e "${LOG_INFO}正在下载安装 微软雅黑..."
            if download_font \
                "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/msyh.ttf" \
                "$CUSTOM_FONT_DIR/$MSYH_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}微软雅黑安装完成！"
            else
                echo -e "${LOG_ERROR}微软雅黑下载失败"
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        2)
            echo -e "${LOG_INFO}正在下载安装 Segoe UI Emoji (Win11)..."
            if download_font \
                "https://github.com/Chasmical/flag-emojis-for-windows/releases/latest/download/Segoe.UI.Emoji.with.Twemoji.Flags.ttf" \
                "$CUSTOM_FONT_DIR/$SEGOE_EMOJI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}Segoe UI Emoji 安装完成！"
            else
                echo -e "${LOG_ERROR}Segoe UI Emoji 下载失败"
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        3)
            echo -e "${LOG_INFO}正在下载安装 Noto Color Emoji..."
            if download_font \
                "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf" \
                "$CUSTOM_FONT_DIR/$NOTO_EMOJI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}Noto Color Emoji 安装完成！"
            else
                echo -e "${LOG_ERROR}Noto Color Emoji 下载失败"
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        4)
            echo -e "${LOG_INFO}正在下载安装 LxgwWenKai..."
            if download_font \
                "https://raw.githubusercontent.com/lxgw/LxgwWenKai/main/fonts/TTF/LXGWWenKai-Medium.ttf" \
                "$CUSTOM_FONT_DIR/$LXGW_WENKAI_FILE"; then
                refresh_fonts
                echo -e "${LOG_SUCCESS}LxgwWenKai 安装完成！"
            else
                echo -e "${LOG_ERROR}LxgwWenKai 下载失败"
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        99)
            clear
            echo -e "${CYAN}==== 卸载字体 ====${NC}"

            declare -A fonts=(
                [1]="$MSYH_FILE|微软雅黑"
                [2]="$SEGOE_EMOJI_FILE|Segoe UI Emoji"
                [3]="$NOTO_EMOJI_FILE|Noto Color Emoji"
                [4]="$LXGW_WENKAI_FILE|LxgwWenKai"
            )

            has_installed=false
            for i in 1 2 3 4; do
                file="${fonts[$i]%%|*}"
                name="${fonts[$i]##*|}"
                if [[ -f "$CUSTOM_FONT_DIR/$file" ]]; then
                    echo " $i. $name"
                    has_installed=true
                fi
            done

            if [[ "$has_installed" == false ]]; then
                echo -e "${LOG_WARN}当前没有可卸载的字体"
                read -rp "按任意键继续..." -n1 -s
                continue
            fi

            read -rp "请输入编号: " del_choice
            if [[ -z "${fonts[$del_choice]}" ]]; then
                echo -e "${LOG_ERROR}无效选择"
            else
                file="${fonts[$del_choice]%%|*}"
                name="${fonts[$del_choice]##*|}"
                if [[ -f "$CUSTOM_FONT_DIR/$file" ]]; then
                    rm -f "$CUSTOM_FONT_DIR/$file"
                    refresh_fonts
                    echo -e "${LOG_SUCCESS}$name 已卸载"
                else
                    echo -e "${LOG_WARN}$name 未安装"
                fi
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        0)
            echo -e "${LOG_INFO}已退出脚本"
            exit 0
            ;;
        *)
            echo -e "${LOG_ERROR}无效选项"
            read -rp "按任意键继续..." -n1 -s
            ;;
    esac
done
