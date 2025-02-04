#!/bin/bash

# 配置变量
DMR_DIR="/opt/DanmakuRender-5"
DMR_CMD="python3 main.py"
LOG_FILE="nohup.out"
COOKIES_TOOL_DIR="tools"
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"
GIT_REPO="https://github.com/sillda76/DanmakuRender.git"
GIT_BRANCH="v5"
BILIUP_REPO="https://api.github.com/repos/biliup/biliup-rs/releases/latest"

# 颜色配置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 加粗文本
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# 显示标题
show_header() {
    clear
    echo -e "${CYAN}==============================${NC}"
    echo -e "${CYAN}        ${BOLD}DanmakuRender${NORMAL}        ${NC}"
    echo -e "${CYAN}==============================${NC}"
}

# 检查DMR状态
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

# 安装DanmakuRender V5
install_dmr() {
    if [ -d "$DMR_DIR" ]; then
        echo -e "${YELLOW}DanmakuRender-5 已存在于 $DMR_DIR${NC}"
        read -p "是否重新安装？（将覆盖现有安装）(y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}已取消安装${NC}"
            return 0
        else
            echo -e "${BLUE}开始重新安装 DanmakuRender V5...${NC}"
            rm -rf "$DMR_DIR"
        fi
    fi

    # 安装git
    if ! command -v git &> /dev/null; then
        echo -e "${BLUE}正在安装git...${NC}"
        sudo apt update && sudo apt install -y git || {
            echo -e "${RED}git安装失败！${NC}"
            return 1
        }
    fi

    # 克隆仓库
    echo -e "${BLUE}正在克隆仓库...${NC}"
    git clone -b "$GIT_BRANCH" "$GIT_REPO" "$DMR_DIR" || {
        echo -e "${RED}仓库克隆失败！${NC}"
        return 1
    }

    # 安装python环境
    echo -e "${BLUE}正在设置Python环境...${NC}"
    sudo apt install -y python3-venv && \
    cd "$DMR_DIR" && \
    python3 -m venv venv && \
    source venv/bin/activate && \
    pip install -r requirements.txt || {
        echo -e "${RED}Python环境设置失败！${NC}"
        return 1
    }

    # 安装ffmpeg
    echo -e "${BLUE}正在安装ffmpeg...${NC}"
    sudo apt update
    sudo apt install -y ffmpeg || {
        echo -e "${RED}ffmpeg安装失败！${NC}"
        return 1
    }

    echo -e "${GREEN}DanmakuRender V5 安装完成！${NC}"
}

# 更新DanmakuRender V5
update_dmr() {
    echo -e "${BLUE}正在更新 DanmakuRender V5...${NC}"
    if pgrep -f "$DMR_CMD" >/dev/null; then
        echo -e "${YELLOW}正在停止运行中的DMR...${NC}"
        pkill -f "$DMR_CMD"
    fi
    install_dmr
}

# 卸载DanmakuRender V5
uninstall_dmr() {
    [ ! -d "$DMR_DIR" ] && {
        echo -e "${YELLOW}未找到安装目录${NC}"
        return 0
    }
    
    rm -rf "$DMR_DIR" && \
    echo -e "${GREEN}卸载完成！${NC}" || \
    echo -e "${RED}卸载失败！${NC}"
}

# 启动DMR
start_dmr() {
    cd "$DMR_DIR" && source venv/bin/activate && \
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    echo -e "${GREEN}DMR启动成功！PID: $!${NC}"
}

# 停止DMR
stop_dmr() {
    pkill -f "$DMR_CMD" && \
    echo -e "${GREEN}已停止DMR${NC}" || \
    echo -e "${RED}停止DMR失败${NC}"
}

# 查看日志
view_log() {
    tail -f "$DMR_DIR/$LOG_FILE"
}

# 删除回放
delete_replays() {
    rm -rf "$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）"
    echo -e "${GREEN}已删除所有回放文件${NC}"
}

# 更新Cookies
update_cookies() {
    echo -e "${YELLOW}注意：biliup已被移除，此功能不可用。${NC}"
}

# 上传视频
biliup_upload() {
    echo -e "${YELLOW}注意：biliup已被移除，此功能不可用。${NC}"
}

# 追加上传
biliup_append() {
    echo -e "${YELLOW}注意：biliup已被移除，此功能不可用。${NC}"
}

# 安装字体
install_fonts() {
    sudo mkdir -p /usr/share/fonts/truetype/microsoft
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/
    sudo fc-cache -fv
    sudo apt install -y fonts-noto-color-emoji fonts-symbola
    echo -e "${GREEN}字体安装完成！${NC}"
}

# 主菜单
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

# 启动脚本
main_menu
```​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​
