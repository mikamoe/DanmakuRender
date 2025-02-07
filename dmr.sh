#!/bin/bash

DMR_DIR="/opt/DanmakuRender-5"
DMR_CMD="python3 main.py"
LOG_FILE="nohup.out"
COOKIES_TOOL_DIR="tools"
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"
BILIUP_URL="https://github.com/biliup/biliup-rs/releases/download/v0.2.2/biliupR-v0.2.2-x86_64-linux.tar.xz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BOLD=$(tput bold)
NORMAL=$(tput sgr0)

show_header() {
    clear
    echo -e "${CYAN}==============================${NC}"
    echo -e "${CYAN}        ${BOLD}DanmakuRender${NORMAL}        ${NC}"
    echo -e "${CYAN}==============================${NC}"
}

check_dmr() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${YELLOW}${BOLD}当前状态：DanmakuRender V5 未安装${NC}${NORMAL}"
        return 2
    fi

    if pgrep -f "$DMR_CMD" > /dev/null; then
        echo -e "${GREEN}${BOLD}当前状态：DMR正在运行${NC}${NORMAL}"
        return 0
    else
        echo -e "${RED}${BOLD}当前状态：DMR未运行${NC}${NORMAL}"
        return 1
    fi
}

install_dmr() {
    echo -e "${BLUE}正在下载 DanmakuRender V5...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}进入临时目录失败！${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}下载失败！${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}解压失败！${NC}"; return 1; }

    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}未找到解压后的文件夹！${NC}"
        return 1
    fi

    sudo mv "$extracted_folder" /opt/DanmakuRender-5 || { echo -e "${RED}移动文件夹失败！${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${GREEN}文件下载并解压完成！${NC}"

    cd /opt/DanmakuRender-5 || { echo -e "${RED}进入目录失败！${NC}"; return 1; }
    echo -e "${BLUE}安装 python3-venv...${NC}"
    sudo apt install python3-venv -y || { echo -e "${RED}python3-venv 安装失败！${NC}"; return 1; }

    echo -e "${BLUE}创建虚拟环境...${NC}"
    python3 -m venv venv || { echo -e "${RED}创建虚拟环境失败！${NC}"; return 1; }

    echo -e "${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}激活虚拟环境失败！${NC}"; return 1; }

    echo -e "${BLUE}安装 pip3...${NC}"
    sudo apt-get install python3-pip -y || { echo -e "${RED}pip3 安装失败！${NC}"; return 1; }

    echo -e "${BLUE}安装 Python 依赖...${NC}"
    pip3 install -r requirements.txt || { echo -e "${RED}Python 依赖安装失败！${NC}"; return 1; }

    deactivate

    echo -e "${BLUE}正在下载 biliup...${NC}"
    mkdir -p "$BILIUP_DIR" || { echo -e "${RED}创建 tools 文件夹失败！${NC}"; return 1; }
    cd "$BILIUP_DIR" || { echo -e "${RED}进入 tools 文件夹失败！${NC}"; return 1; }
    curl -LO "$BILIUP_URL" || { echo -e "${RED}下载 biliup 压缩包失败！${NC}"; return 1; }
    archive_name=$(basename "$BILIUP_URL")
    tar -xJvf "$archive_name" || { echo -e "${RED}解压 biliup 压缩包失败！${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}未找到解压后的 biliup 文件夹！${NC}"
        return 1
    fi
    mv "$extracted_folder/biliup" . || { echo -e "${RED}移动 biliup 文件失败！${NC}"; return 1; }
    chmod +x biliup || { echo -e "${RED}设置 biliup 可执行权限失败！${NC}"; return 1; }
    rm -rf "$extracted_folder" || { echo -e "${RED}删除解压后的文件夹失败！${NC}"; return 1; }
    echo -e "${GREEN}biliup 部署成功！${NC}"

    echo -e "${GREEN}DanmakuRender V5 安装完成！${NC}"
}

update_dmr() {
    echo -e "${BLUE}正在更新 DanmakuRender V5...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}进入临时目录失败！${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}下载失败！${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}解压失败！${NC}"; return 1; }

    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}未找到解压后的文件夹！${NC}"
        return 1
    fi

    sudo rsync -a --delete "$extracted_folder/" /opt/DanmakuRender-5/ || { echo -e "${RED}文件覆盖失败！${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${GREEN}DanmakuRender V5 更新完成！${NC}"
}

uninstall_dmr() {
    [ ! -d "$DMR_DIR" ] && {
        echo -e "${YELLOW}未找到安装目录${NC}"
        return 0
    }

    rm -rf "$DMR_DIR" && \
    echo -e "${GREEN}卸载完成！${NC}" || \
    echo -e "${RED}卸载失败！${NC}"
}

start_dmr() {
    cd "$DMR_DIR" && source venv/bin/activate && \
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    echo -e "${GREEN}DMR启动成功！PID: $!${NC}"
}

stop_dmr() {
    pkill -f "$DMR_CMD" && \
    echo -e "${GREEN}已停止DMR${NC}" || \
    echo -e "${RED}停止DMR失败${NC}"
}

view_log() {
    tail -f "$DMR_DIR/$LOG_FILE"
}

delete_replays() {
    rm -rf "$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）"
    echo -e "${GREEN}已删除所有回放文件${NC}"
}

update_cookies() {
    cd "$BILIUP_DIR" && ./biliup login
}

biliup_upload() {
    while true; do
        read -p "请输入视频目录路径: " video_path
        [ -d "$video_path" ] && break
        echo -e "${RED}路径不存在！${NC}"
    done

    read -p "请输入分区tid: " tid
    read -p "请输入视频标签: " tags

    cd "$BILIUP_DIR" && \
    ./biliup upload "$video_path" --tid "$tid" --tag "$tags"
}

biliup_append() {
    while true; do
        read -p "请输入BV号: " vid
        [[ "$vid" =~ ^BV ]] && break
        echo -e "${RED}无效的BV号！${NC}"
    done

    video_paths=()
    while true; do
        read -p "请输入视频路径: " path
        if [ -f "$path" ]; then
            video_paths+=("$path")
            read -p "继续添加？(y/n): " choice
            [[ "$choice" != "y" ]] && break
        else
            echo -e "${RED}文件不存在！${NC}"
        fi
    done

    cd "$BILIUP_DIR" && \
    ./biliup append --vid "$vid" "${video_paths[@]}"
}

install_fonts() {
    sudo mkdir -p /usr/share/fonts/truetype/microsoft
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/
    sudo fc-cache -fv
    sudo apt install -y fonts-noto-color-emoji fonts-symbola
    echo -e "${GREEN}字体安装完成！${NC}"
}

main_menu() {
    while true; do
        show_header
        check_dmr
        echo -e "\n${CYAN}${BOLD}请选择操作：${NC}${NORMAL}"
        echo "1.  安装DanmakuRender V5"
        echo "2.  启动/停止录制"
        echo "3.  查看实时日志"
        echo "4.  删除回放/渲染文件"
        echo "5.  更新哔哩哔哩Cookies"
        echo "6.  哔哩哔哩快速上传"
        echo "7.  哔哩哔哩视频追加上传"
        echo "8.  安装微软雅黑和Emoji表情"
        echo "9.  更新DanmakuRender V5"
        echo "10. 卸载DanmakuRender V5"
        echo "0.  退出脚本"

        read -p "请输入选项： " choice
        case $choice in
            1) install_dmr ;;
            2)
                if check_dmr; then
                    stop_dmr
                else
                    start_dmr
                fi ;;
            3) view_log ;;
            4) delete_replays ;;
            5) update_cookies ;;
            6) biliup_upload ;;
            7) biliup_append ;;
            8) install_fonts ;;
            9) update_dmr ;;
            10) uninstall_dmr ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项！${NC}" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

main_menu
