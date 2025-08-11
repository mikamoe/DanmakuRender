#!/bin/bash
# font-dinstall.sh - 字体安装/卸载脚本

# ======== 颜色变量 ========
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# ======== 字体目录变量 ========
MICROSOFT_FONT_DIR="/usr/share/fonts/truetype/microsoft"
NOTO_EMOJI_DIR="/usr/share/fonts/truetype/noto-emoji"
ALIPUHUITI_DIR="/usr/share/fonts/truetype/AlibabaPuHuiTi"
MARU_FONT_DIR="/usr/share/fonts/truetype/975MaruSC"

# ======== 检查是否以 root 权限运行 ========
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 sudo 运行该脚本${RESET}"
    exit 1
fi

# ======== 检测字体安装状态 ========
check_font() {
    local font_name="$1"
    if fc-list | grep -qi "$font_name"; then
        echo -e "${GREEN}已安装${RESET}"
    else
        echo -e "${RED}未安装${RESET}"
    fi
}

echo -e "${CYAN}==== 字体安装检测 ====${RESET}"
printf "微软雅黑           : %b\n" "$(check_font "Microsoft YaHei")"
printf "Segoe UI Emoji     : %b\n" "$(check_font "Segoe UI Emoji")"
printf "Noto Color Emoji   : %b\n" "$(check_font "Noto Color Emoji")"
printf "阿里巴巴普惠体 3.0 : %b\n" "$(check_font "Alibaba PuHuiTi 3.0")"
printf "975MaruSC          : %b\n" "$(check_font "975MaruSC")"
echo

# ======== 主菜单 ========
echo -e "${YELLOW}请选择要执行的操作:${RESET}"
echo "1. 安装 微软雅黑"
echo "2. 安装 Segoe UI Emoji"
echo "3. 安装 Noto Color Emoji"
echo "4. 安装 阿里巴巴普惠体 3.0"
echo "5. 安装 975Maru"
echo "99. 卸载字体"
echo "0. 退出脚本"
read -rp "请输入选项: " choice

case "$choice" in
    1)
        echo "安装 微软雅黑..."
        mkdir -p "$MICROSOFT_FONT_DIR"
        wget -O "$MICROSOFT_FONT_DIR/msyh.ttf" "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/msyh.ttf"
        chmod 644 "$MICROSOFT_FONT_DIR/msyh.ttf"
        fc-cache -fv
        echo -e "${GREEN}微软雅黑安装完成！${RESET}"
        ;;
    2)
        echo "请选择 Segoe UI Emoji 版本:"
        echo "1. Win10"
        echo "2. Win11"
        read -rp "请输入选项(1/2): " sechoice

        mkdir -p "$MICROSOFT_FONT_DIR"
        if [[ "$sechoice" == "1" ]]; then
            wget -O "$MICROSOFT_FONT_DIR/seguiemj.ttf" "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/Segoe-UI-Emoji-Win10/seguiemj.ttf"
        elif [[ "$sechoice" == "2" ]]; then
            wget -O "$MICROSOFT_FONT_DIR/seguiemj.ttf" "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/Segoe-UI-Emoji-Win11/seguiemj.ttf"
        else
            echo -e "${RED}无效的选项${RESET}"
            exit 1
        fi
        chmod 644 "$MICROSOFT_FONT_DIR/seguiemj.ttf"
        fc-cache -fv
        echo -e "${GREEN}Segoe UI Emoji 安装完成！${RESET}"
        ;;
    3)
        mkdir -p "$NOTO_EMOJI_DIR"
        wget -O "$NOTO_EMOJI_DIR/NotoColorEmoji.ttf" "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf"
        chmod 644 "$NOTO_EMOJI_DIR/NotoColorEmoji.ttf"
        fc-cache -f -v
        echo -e "${GREEN}Noto Color Emoji 安装完成！${RESET}"
        ;;
    4)
        mkdir -p "$ALIPUHUITI_DIR"
        wget -O "$ALIPUHUITI_DIR/AlibabaPuHuiTi-3-85-Bold.ttf" "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/AlibabaPuHuiTi-3-85-Bold.ttf"
        chmod 644 "$ALIPUHUITI_DIR/AlibabaPuHuiTi-3-85-Bold.ttf"
        fc-cache -fv
        echo -e "${GREEN}阿里巴巴普惠体 3.0 安装完成！${RESET}"
        ;;
    5)
        mkdir -p "$MARU_FONT_DIR"
        wget -O "$MARU_FONT_DIR/975MaruSC-Bold.ttf" "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/975MaruSC-Bold.ttf"
        chmod 644 "$MARU_FONT_DIR/975MaruSC-Bold.ttf"
        fc-cache -fv
        echo -e "${GREEN}975Maru 安装完成！${RESET}"
        ;;
    99)
        echo -e "${CYAN}==== 卸载字体 ====${RESET}"
        declare -A fonts=(
            [1]="$MICROSOFT_FONT_DIR|微软雅黑"
            [2]="$MICROSOFT_FONT_DIR|Segoe UI Emoji"
            [3]="$NOTO_EMOJI_DIR|Noto Color Emoji"
            [4]="$ALIPUHUITI_DIR|阿里巴巴普惠体 3.0"
            [5]="$MARU_FONT_DIR|975MaruSC"
        )

        for i in "${!fonts[@]}"; do
            dir="${fonts[$i]%%|*}"
            name="${fonts[$i]##*|}"
            if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
                echo "$i. $name"
            fi
        done

        read -rp "请输入要卸载的字体编号: " del_choice
        dir="${fonts[$del_choice]%%|*}"
        name="${fonts[$del_choice]##*|}"

        if [ -n "$dir" ] && [ -d "$dir" ]; then
            rm -rf "$dir"
            fc-cache -fv
            echo -e "${GREEN}$name 已卸载${RESET}"
        else
            echo -e "${RED}无效的选择或字体未安装${RESET}"
        fi
        ;;
    0)
        echo -e "${CYAN}已退出脚本${RESET}"
        exit 0
        ;;
    *)
        echo -e "${RED}无效的选项${RESET}"
        exit 1
        ;;
esac
