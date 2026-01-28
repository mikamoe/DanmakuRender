#!/bin/bash
# font-dinstall.sh - 字体安装/卸载脚本

# ======== 颜色与格式变量 ========
NC="\e[0m"
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"

# 提示图标示例
LOG_INFO="${BLUE}${BOLD}[i]${NC} "
LOG_SUCCESS="${GREEN}${BOLD}[✓]${NC} "
LOG_WARN="${YELLOW}${BOLD}[!]${NC} "
LOG_ERROR="${RED}${BOLD}[✗]${NC} "

# ======== 字体目录变量 ========
MICROSOFT_FONT_DIR="/usr/share/fonts/truetype/microsoft"
NOTO_EMOJI_DIR="/usr/share/fonts/truetype/noto-emoji"
ALIPUHUITI_DIR="/usr/share/fonts/truetype/AlibabaPuHuiTi"
MARU_FONT_DIR="/usr/share/fonts/truetype/975MaruSC"

# ======== 检查是否以 root 权限运行 ========
if [[ $EUID -ne 0 ]]; then
    echo -e "${LOG_ERROR}${RED}请使用 sudo 运行该脚本${NC}"
    exit 1
fi

# ======== 检测字体安装状态 ========
check_font() {
    local font_name="$1"
    if fc-list | grep -qi "$font_name"; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# ======== 视觉对齐打印函数 ========
# 解决中英文混排对齐问题
print_status() {
    local label="$1"
    local status="$2"
    local target_width=22 # 冒号出现的对齐位置
    
    # 计算视觉宽度 (中文计2, 英文计1)
    local visual_width=0
    for (( i=0; i<${#label}; i++ )); do
        local char="${label:i:1}"
        if [[ "$char" =~ [[:ascii:]] ]]; then
            ((visual_width++))
        else
            ((visual_width+=2))
        fi
    done
    
    # 打印标签
    echo -ne " ${label}"
    # 补齐空格
    local pad=$((target_width - visual_width))
    for (( i=0; i<pad; i++ )); do echo -n " "; done
    # 打印状态
    echo -e ": ${status}"
}

# ======== 主菜单循环 ========
while true; do
    clear
    echo -e "${CYAN}${BOLD}========================================"
    echo -e "       Linux 字体一键管理工具"
    echo -e "========================================${NC}"
    
    # 使用新函数实现完美对齐
    print_status "微软雅黑" "$(check_font "Microsoft YaHei")"
    print_status "Segoe UI Emoji" "$(check_font "Segoe UI Emoji")"
    print_status "Noto Color Emoji" "$(check_font "Noto Color Emoji")"
    print_status "阿里巴巴普惠体 3.0" "$(check_font "Alibaba PuHuiTi 3.0")"
    print_status "975MaruSC" "$(check_font "975MaruSC")"
    
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${YELLOW}${BOLD}可用操作:${NC}"
    echo -e " 1. 安装 微软雅黑"
    echo -e " 2. 安装 Segoe UI Emoji (Win10/Win11)"
    echo -e " 3. 安装 Noto Color Emoji"
    echo -e " 4. 安装 阿里巴巴普惠体 3.0"
    echo -e " 5. 安装 975Maru"
    echo -e " 99. ${RED}卸载字体${NC}"
    echo -e " 0. 退出脚本"
    echo -e "${CYAN}----------------------------------------${NC}"
    read -rp "请选择序号: " choice

    case "$choice" in
        1)
            echo -e "${LOG_INFO}正在下载安装 微软雅黑..."
            mkdir -p "$MICROSOFT_FONT_DIR"
            wget -q --show-progress -O "$MICROSOFT_FONT_DIR/msyh.ttf" "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/msyh.ttf"
            chmod 644 "$MICROSOFT_FONT_DIR/msyh.ttf"
            fc-cache -fv > /dev/null
            echo -e "${LOG_SUCCESS}微软雅黑安装完成！"
            read -rp "按任意键继续..." -n1 -s
            ;;
        2)
            echo -e "${LOG_INFO}请选择 Segoe UI Emoji 版本:"
            echo "   1) Win10"
            echo "   2) Win11"
            read -rp "请输入选项(1/2): " sechoice

            mkdir -p "$MICROSOFT_FONT_DIR"
            if [[ "$sechoice" == "1" ]]; then
                wget -q --show-progress -O "$MICROSOFT_FONT_DIR/seguiemj.ttf" "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/Segoe-UI-Emoji-Win10/seguiemj.ttf"
            elif [[ "$sechoice" == "2" ]]; then
                wget -q --show-progress -O "$MICROSOFT_FONT_DIR/seguiemj.ttf" "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/Segoe-UI-Emoji-Win11/seguiemj.ttf"
            else
                echo -e "${LOG_ERROR}无效选项"
                read -rp "按任意键返回主菜单..." -n1 -s
                continue
            fi
            chmod 644 "$MICROSOFT_FONT_DIR/seguiemj.ttf"
            fc-cache -fv > /dev/null
            echo -e "${LOG_SUCCESS}Segoe UI Emoji 安装完成！"
            read -rp "按任意键继续..." -n1 -s
            ;;
        3)
            echo -e "${LOG_INFO}正在下载安装 Noto Color Emoji..."
            mkdir -p "$NOTO_EMOJI_DIR"
            wget -q --show-progress -O "$NOTO_EMOJI_DIR/NotoColorEmoji.ttf" "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf"
            chmod 644 "$NOTO_EMOJI_DIR/NotoColorEmoji.ttf"
            fc-cache -f -v > /dev/null
            echo -e "${LOG_SUCCESS}Noto Color Emoji 安装完成！"
            read -rp "按任意键继续..." -n1 -s
            ;;
        4)
            echo -e "${LOG_INFO}正在下载安装 阿里巴巴普惠体 3.0..."
            mkdir -p "$ALIPUHUITI_DIR"
            wget -q --show-progress -O "$ALIPUHUITI_DIR/AlibabaPuHuiTi-3-85-Bold.ttf" "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/AlibabaPuHuiTi-3-85-Bold.ttf"
            chmod 644 "$ALIPUHUITI_DIR/AlibabaPuHuiTi-3-85-Bold.ttf"
            fc-cache -fv > /dev/null
            echo -e "${LOG_SUCCESS}阿里巴巴普惠体 3.0 安装完成！"
            read -rp "按任意键继续..." -n1 -s
            ;;
        5)
            echo -e "${LOG_INFO}正在下载安装 975Maru..."
            mkdir -p "$MARU_FONT_DIR"
            wget -q --show-progress -O "$MARU_FONT_DIR/975MaruSC-Bold.ttf" "https://raw.githubusercontent.com/mikamoe/DanmakuRender/v5/fonts/975MaruSC-Bold.ttf"
            chmod 644 "$MARU_FONT_DIR/975MaruSC-Bold.ttf"
            fc-cache -fv > /dev/null
            echo -e "${LOG_SUCCESS}975Maru 安装完成！"
            read -rp "按任意键继续..." -n1 -s
            ;;
        99)
            clear
            echo -e "${CYAN}==== 卸载字体 ====${NC}"
            declare -A fonts=(
                [1]="$MICROSOFT_FONT_DIR|微软雅黑"
                [2]="$MICROSOFT_FONT_DIR|Segoe UI Emoji"
                [3]="$NOTO_EMOJI_DIR|Noto Color Emoji"
                [4]="$ALIPUHUITI_DIR|阿里巴巴普惠体 3.0"
                [5]="$MARU_FONT_DIR|975MaruSC"
            )

            for i in 1 2 3 4 5; do
                dir="${fonts[$i]%%|*}"
                name="${fonts[$i]##*|}"
                if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
                    echo "$i. $name"
                fi
            done

            read -rp "请输入要卸载的字体编号: " del_choice
            if [[ -z "${fonts[$del_choice]}" ]]; then
                echo -e "${LOG_ERROR}无效的选择"
            else
                dir="${fonts[$del_choice]%%|*}"
                name="${fonts[$del_choice]##*|}"
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                    fc-cache -fv > /dev/null
                    echo -e "${LOG_SUCCESS}$name 已成功卸载"
                else
                    echo -e "${LOG_WARN}字体未安装"
                fi
            fi
            read -rp "按任意键继续..." -n1 -s
            ;;
        0)
            echo -e "${LOG_INFO}已退出脚本"
            exit 0
            ;;
        *)
            echo -e "${LOG_ERROR}无效的选项"
            read -rp "按任意键返回主菜单..." -n1 -s
            ;;
    esac
done
