#!/bin/bash
# =============================================================================
# DanmakuRender v5 管理脚本
# 此脚本用于安装、更新、启动、停止、日志查看、测试、视频渲染及相关
# 辅助工具（如 biliup‑rs、字体安装）的管理，提供了交互式主菜单。
# =============================================================================

# ------------------------- 配置变量 -------------------------
DMR_DIR="/opt/DanmakuRender-5"              # 主程序安装目录
DMR_CMD="python3 main.py"                   # 启动命令
LOG_FILE="nohup.out"                        # 日志文件名称（用于后台运行日志记录）
COOKIES_TOOL_DIR="tools"                    # biliup‑rs 等工具所在子目录
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"       # biliup‑rs 工具所在目录
INSTALL_DATE_FILE="$DMR_DIR/install_date"     # 记录安装/更新时间的文件

# GitHub 项目信息
GITHUB_OWNER="SmallPeaches"
GITHUB_REPO="DanmakuRender"
GITHUB_BRANCH="v5"

# biliup‑rs 项目信息（用于动态获取最新版本）
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup-rs"
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases/download"

# ANSI 颜色及样式（用于终端输出美化）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
PINK='\033[1;35m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# ------------------------- 系统依赖与辅助函数 -------------------------

# 检查必备工具（jq、curl）
check_dependencies() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Checking dependencies...${NC}"
    local required_tools=("jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}$tool not found, installing...${NC}"
            sudo apt install -y "$tool" || { 
                echo -e "${BLUE}${BOLD}[INFO]${NC} ${RED}$tool installation failed!${NC}"
                return 1
            }
        fi
    done
}

# 获取当前 Python3 版本
get_python_version() {
    if command -v python3 &>/dev/null; then
        echo "Python $(python3 -V 2>&1 | awk '{print $2}')"
    else
        echo "not_installed"
    fi
}

# 出错时回滚安装，删除安装目录
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}Rolling back installation...${NC}"
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}Deleted directory: $DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Rollback failed!${NC}"
}

# 检查配置文件是否存在（判断 configs 目录下是否有匹配文件）
check_config() {
    if find "$DMR_DIR/configs" -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 检查 Cookies 文件是否配置（判断 tools 目录下是否有 json 文件）
check_cookies() {
    if find "$BILIUP_DIR" -name "*.json" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 从 GitHub 获取最新提交时间、提交说明及最新 Release 信息（转换为北京时间）
fetch_github_times() {
    local branch_info
    branch_info=$(curl -sf "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/branches/$GITHUB_BRANCH")
    if [[ -n "$branch_info" ]]; then
        local raw_time
        raw_time=$(jq -r '.commit.commit.author.date // empty' <<< "$branch_info")
        commit_time=$(TZ=Asia/Shanghai date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "获取失败")
        commit_message=$(jq -r '.commit.commit.message // empty' <<< "$branch_info")
    else
        commit_time="获取失败"
        commit_message=""
    fi

    local release_info
    release_info=$(curl -sf "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest")
    if [[ -n "$release_info" ]]; then
        release_version=$(jq -r '.tag_name // empty' <<< "$release_info")
        local raw_time
        raw_time=$(jq -r '.published_at // empty' <<< "$release_info")
        release_time=$(TZ=Asia/Shanghai date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "获取失败")
    else
        release_version="获取失败"
        release_time="获取失败"
    fi
}

# 读取记录的安装/更新日期
get_install_date() {
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        install_date=$(TZ=Asia/Shanghai date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
    fi
}

# 检查安装所需系统工具（wget、unzip、python3-venv、ffmpeg等）
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Checking system tools...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}$tool not found, installing...${NC}"
            sudo apt install -y "$tool" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}$tool installation failed!${NC}"; return 1; }
        fi
    done
}

# ------------------------- DanmakuRender v5 安装与更新 -------------------------

# 安装 DanmakuRender v5（包括下载、解压、创建虚拟环境、安装依赖及工具）
install_dmr() {
    local rollback_needed=true
    trap '[[ "$rollback_needed" = true ]] && rollback_installation' EXIT

    # 如果已安装，则仅重新安装 Python 依赖
    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}DanmakuRender v5 is already installed!${NC}"
        read -p "Reinstall Python dependencies? (y/n) " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}Canceled${NC}"
            return 0
        fi
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Reinstalling Python dependencies...${NC}"
        cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter directory!${NC}"; return 1; }
        [ -d "venv" ] && rm -rf venv
        python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Virtual environment creation failed!${NC}"; return 1; }
        source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to activate virtual environment!${NC}"; return 1; }
        pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}pip upgrade failed!${NC}"; return 1; }
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Dependency installation failed!${NC}"; return 1; }
        deactivate
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Python dependencies reinstalled!${NC}"
        return 0
    fi

    # 初次安装流程
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Installing required system tools...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}apt update failed!${NC}"; return 1; }
    sudo apt install -y unzip curl wget || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Tool installation failed!${NC}"; return 1; }
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}apt update failed!${NC}"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Downloading DanmakuRender v5 package...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter temporary directory!${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Download failed!${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Unzip failed!${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Extracted folder not found!${NC}"; return 1; }
    sudo mv "$extracted_folder" "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to move folder!${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Download and extraction complete!${NC}"

    # 进入安装目录，创建 Python 虚拟环境并安装依赖
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter directory!${NC}"; return 1; }
    sudo apt install python3-venv -y || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}python3-venv installation failed!${NC}"; return 1; }
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Virtual environment creation failed!${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to activate virtual environment!${NC}"; return 1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}pip upgrade failed!${NC}"; return 1; }
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Dependency installation failed!${NC}"; return 1; }
    deactivate

    # 安装 ffmpeg 工具
    sudo apt install ffmpeg -y || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}ffmpeg installation failed!${NC}"; return 1; }

    # 安装 biliup‑rs 工具
    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}biliup-rs installation failed!${NC}"; return 1; }
    
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}${BOLD}DanmakuRender v5 installed successfully!${NC}"
    # 记录安装时间
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to record installation date!${NC}"; return 1; }
    get_install_date

    rollback_needed=false
    trap - EXIT

    # 安装完成后询问是否安装字体
    read -p "Installation complete. Install fonts? (y/n): " font_ans
    if [[ "$font_ans" =~ ^[Yy]$ ]]; then
        read -p "Choose font type: 8 for Microsoft YaHei+Emoji, 9 for Alibaba PuHuiTi+Emoji, 0 to cancel: " font_choice
        case $font_choice in
            8) install_fonts ;;
            9) install_alibaba_fonts ;;
            0) echo -e "${BLUE}${BOLD}[INFO]${NC} Font installation cancelled" ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} Invalid option" ;;
        esac
    fi
}

# 更新 DanmakuRender v5（备份当前目录，下载更新包，覆盖文件并重新安装 Python 依赖）
update_dmr() {
    require_installed || return 1
    read -p "Proceed with update? (y/n): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         return 0
    fi

    check_install_tools || return 1

    if pgrep -f "$DMR_CMD" > /dev/null; then
         echo -e "${BLUE}${BOLD}[INFO]${NC} Stopping running process..."
         stop_dmr
    fi

    backup_dir="${DMR_DIR}_backup_$(date +%s)"
    echo -e "${BLUE}${BOLD}[INFO]${NC} Backing up directory to ${YELLOW}$backup_dir${NC} ..."
    sudo cp -r "$DMR_DIR" "$backup_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} Backup failed!"; return 1; }

    update_fail=0
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} Failed to enter temporary directory!"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} Downloading update package..."
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} Download failed!"; update_fail=1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} Unzip failed!"; update_fail=1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} Folder not found!"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} Overwriting files..."
    sudo rsync -a "$extracted_folder/" "$DMR_DIR/" || { echo -e "${RED}${BOLD}[ERROR]${NC} File overwrite failed!"; update_fail=1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} Failed to enter directory!"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} Reinstalling Python dependencies..."
    [ -d "venv" ] && rm -rf venv
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} Virtual environment creation failed!"; update_fail=1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} Failed to activate virtual environment!"; update_fail=1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} pip upgrade failed!"; update_fail=1; }
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} Dependency installation failed!"; update_fail=1; }
    deactivate

    if [ "$update_fail" -eq 1 ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC} Update failed, restoring backup..."
         sudo rm -rf "$DMR_DIR"
         sudo mv "$backup_dir" "$DMR_DIR"
         echo -e "${RED}${BOLD}[ERROR]${NC} Backup restored!"
         return 1
    else
         echo -e "${GREEN}${BOLD}[INFO]${NC} Update successful!"
         sudo rm -rf "$backup_dir"
    fi
}

# 卸载 DanmakuRender v5
uninstall_dmr() {
    require_installed || return 1
    rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Uninstall complete!${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Uninstall failed!${NC}"
}

# ------------------------- 进程控制与日志查看 -------------------------

# 启动 DanmakuRender v5（后台启动并写入日志）
start_dmr() {
    require_installed || return 1
    cd "$DMR_DIR" && source venv/bin/activate && nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Started! PID: $pid${NC}"
    return 0
}

# 停止运行中的 DanmakuRender v5
stop_dmr() {
    require_installed || return 1
    pkill -f "$DMR_CMD" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Stopped${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Stop failed${NC}"
}

# 查看最新日志文件
# 进入 $DMR_DIR/logs 下查找最新修改的 .log 文件，在文件顶部显示文件名及提示信息，
# 使用 tail -f 实时查看日志，按 s 键退出查看。
view_log() {
    require_installed || return 1
    local logs_dir="$DMR_DIR/logs"
    if [ ! -d "$logs_dir" ]; then
        echo -e "${RED}Logs directory does not exist: $logs_dir${NC}"
        return 1
    fi
    local latest_log
    latest_log=$(ls -t "$logs_dir"/*.log 2>/dev/null | head -n 1)
    if [ -z "$latest_log" ]; then
        echo -e "${RED}No log files found in $logs_dir${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}日志文件名称: $(basename "$latest_log")${NC}"
    echo -e "${BLUE}${BOLD}提示内容: 按s可退出查看${NC}"
    tail -f "$latest_log" & pid=$!
    while true; do
        read -t 1 -n 1 key
        if [[ "$key" == "s" ]]; then
            kill $pid 2>/dev/null
            break
        fi
        if ! kill -0 $pid 2>/dev/null; then
            break
        fi
    done
}

# ------------------------- 功能测试与手动渲染 -------------------------

# 运行测试脚本（dryrun.py）
run_test() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Running test...${NC}"
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter directory!${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to activate virtual environment!${NC}"; return 1; }
    python3 dryrun.py || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Test run failed!${NC}"; return 1; }
    deactivate
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Test complete!${NC}"
}

# 手动渲染视频（调用 render_only.py）
manual_render() {
    require_installed || return 1
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} Failed to enter directory!"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} Failed to activate virtual environment!"; return 1; }
    python3 render_only.py || { echo -e "${RED}${BOLD}[ERROR]${NC} Rendering failed!"; return 1; }
    deactivate
}

# 删除直播回放及弹幕版目录下的视频文件
delete_replays() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}直播回放目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放${NC}"
    echo -e "\n${BLUE}${BOLD}[INFO]${NC} ${CYAN}直播回放（弹幕版）目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放（弹幕版）" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放（弹幕版）${NC}"
    read -p $'\n是否删除所有回放文件？(y/n) ' confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf "$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）"
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Deleted all replay files${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}Deletion cancelled${NC}"
    fi
}

# ------------------------- 字体安装 -------------------------

# 安装微软雅黑及 Emoji 字体
install_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Installing Microsoft YaHei and Emoji fonts...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/microsoft || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to create font directory!${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/ || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to copy Microsoft YaHei font!${NC}"; return 1; }
    fc-list | grep "Microsoft YaHei" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Microsoft YaHei not found!${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Font cache refresh failed!${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Emoji fonts installation failed!${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Font cache refresh failed!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Font installation complete!${NC}"
}

# 安装阿里巴巴普惠体及 Emoji 字体
install_alibaba_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Installing Alibaba PuHuiTi and Emoji fonts...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to create font directory!${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/AlibabaPuHuiTi-3-65-Medium.ttf" /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to copy Alibaba PuHuiTi font!${NC}"; return 1; }
    fc-list | grep "Alibaba PuHuiTi 3.0" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Alibaba PuHuiTi not found!${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Font cache refresh failed!${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Emoji fonts installation failed!${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Font cache refresh failed!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Font installation complete!${NC}"
}

# ------------------------- biliup‑rs 工具管理 -------------------------

# 安装 biliup‑rs 工具（动态获取最新版本、检测系统架构、下载、解压、移动执行文件）
install_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter tools directory${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Fetching latest biliup‑rs info...${NC}"
    latest_info=$(curl -sf "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to fetch biliup‑rs info!${NC}"
        return 1
    fi
    latest_version=$(echo "$latest_info" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to parse version!${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Latest version: ${latest_version}${NC}"
    
    arch=$(uname -m)
    case "$arch" in
        aarch64) asset="aarch64-linux.tar.xz" ;;
        arm*|aarch32) asset="arm-linux.tar.xz" ;;
        x86_64)
            if ldd --version 2>&1 | grep -qi musl; then
                asset="x86_64-linux-musl.tar.xz"
            else
                asset="x86_64-linux.tar.xz"
            fi
            ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Unsupported architecture: $arch${NC}"; return 1 ;;
    esac
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Detected architecture: $arch, asset: ${asset}${NC}"
    
    asset_file="biliupR-${latest_version}-${asset}"
    download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Download URL: ${download_url}${NC}"
    
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Downloading biliup‑rs...${NC}"
    curl -LO "$download_url" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Download failed!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Extracting ${asset_file}...${NC}"
    tar -xJvf "$asset_file" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Extraction failed!${NC}"; return 1; }
    
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Extracted folder not found!${NC}"
        return 1
    fi
    if [ ! -f "$extracted_folder/biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}biliup file not found in the extracted folder!${NC}"
        return 1
    fi
    mv "$extracted_folder/biliup" . || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to move biliup file!${NC}"; return 1; }
    rm -rf "$extracted_folder" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to remove extracted folder!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}biliup‑rs installed successfully!${NC}"
}

# 更新 biliup‑rs（删除旧文件后重新安装）
update_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter tools directory${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Updating biliup‑rs...${NC}"
    rm -f "$BILIUP_DIR/biliup" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to remove old file!${NC}"; return 1; }
    install_biliup_rs
}

# ------------------------- 哔哩哔哩视频上传相关 -------------------------

# 哔哩哔哩视频快速上传功能
biliup_upload() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}Select video directory type:${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. Other path"
    read -p "Enter option (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "Enter absolute video directory path: " video_dir ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Invalid option!${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Directory not found: $video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}No video files found!${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}Video files:${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) Return"
        while true; do
            read -p "Enter video option numbers (space separated, 0 to return): " -a selections
            if [[ " ${selections[@]} " =~ " 0 " ]]; then
                return
            fi
            valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}Invalid option: $num${NC}"
                    valid=false
                    break
                fi
            done
            $valid && break
        done
        all_option=$(( ${#files[@]} + 1 ))
        if [[ " ${selections[@]} " =~ " $all_option " ]]; then
            video_paths=("${files[@]}")
        else
            video_paths=()
            for num in "${selections[@]}"; do
                if [[ "$num" -ge 1 && "$num" -le "${#files[@]}" ]]; then
                    video_paths+=("${files[$((num-1))]}")
                else
                    echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Invalid option: $num${NC}"
                    return 1
                fi
            done
        fi
    else
        read -p "Enter absolute video file paths (space separated): " -a video_paths
    fi
    read -p "Enter tid (default 65): " tid
    tid=${tid:-65}
    read -p "Enter video tags (default 直播回放,录播): " tags
    tags=${tags:-"直播回放,录播"}
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter tools directory!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Executing: ./biliup upload ${video_paths[*]} --tid $tid --tag \"$tags\"${NC}"
    ./biliup upload "${video_paths[@]}" --tid "$tid" --tag "$tags"
}

# 哔哩哔哩视频追加上传功能
biliup_append() {
    require_installed || return 1
    while true; do
        read -p "Enter video BV number: " bv
        [[ "$bv" =~ ^BV ]] && break || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Invalid BV number! Must start with BV.${NC}"
    done
    video_paths=()
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}Select video directory type:${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. Other path"
    read -p "Enter option (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "Enter absolute video file paths (space separated): " -a video_paths ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Invalid option!${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Directory not found: $video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}No video files found!${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}Video files:${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) Return"
        while true; do
            read -p "Enter video option numbers (space separated, 0 to return): " -a selections
            if [[ " ${selections[@]} " =~ " 0 " ]]; then
                return
            fi
            valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}Invalid option: $num${NC}"
                    valid=false
                    break
                fi
            done
            $valid && break
        done
        all_option=$(( ${#files[@]} + 1 ))
        if [[ " ${selections[@]} " =~ " $all_option " ]]; then
            video_paths=("${files[@]}")
        else
            video_paths=()
            for num in "${selections[@]}"; do
                if [[ "$num" -ge 1 && "$num" -le "${#files[@]}" ]]; then
                    video_paths+=("${files[$((num-1))]}")
                else
                    echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Invalid option: $num${NC}"
                    return 1
                fi
            done
        fi
    fi
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Failed to enter tools directory!${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}Executing: ./biliup append --vid \"$bv\" ${video_paths[*]}${NC}"
    ./biliup append --vid "$bv" "${video_paths[@]}"
}

# ------------------------- 主菜单及状态显示 -------------------------

# 显示头部信息（版本、更新时间、提交信息、Python 版本等）
show_header() {
    clear
    echo -e "${PINK}==============================${NC}"
    echo -e "${BLUE}${BOLD}DanmakuRender v5${NORMAL}"
    echo -e "${PINK}最新提交日期${NC} ${BOLD}${commit_time}"
    echo -e "${PINK}最新版本${NC}  ${BOLD}${release_version}"
    echo -e "${PINK}更新日期${NC}  ${BOLD}${release_time}"
    echo -e "${PURPLE}${BOLD}项目原地址：https://github.com/SmallPeaches/DanmakuRender${NC}"
    if [ -f "$INSTALL_DATE_FILE" ] && [[ "$commit_time" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        last_update=$(date -d "$install_date" +%s 2>/dev/null || echo 0)
        commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo 0)
        if [ "$commit_timestamp" -gt "$last_update" ]; then
            echo -e "${YELLOW}${BOLD}v5 分支有最新变动${NC}"
            echo -e "${YELLOW}${BOLD}提交日期：${NC}${commit_time}"
            [ -n "$commit_message" ] && echo -e "${YELLOW}${BOLD}提交说明：${NC}${commit_message}"
        fi
    fi
    python_version=$(get_python_version)
    if [[ "$python_version" == "not_installed" ]]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} Python3 未安装或未检测到！${NC}"
    else
        echo -e "${YELLOW}${BOLD}当前 Python 版本：${BOLD}${python_version}${NC}\n"
    fi  
}

# 显示当前状态及配置、更新提示
show_status() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${YELLOW}${BOLD}当前状态：DanmakuRender v5 未安装${NC}"
    elif pgrep -f "$DMR_CMD" > /dev/null; then
         pid=$(pgrep -f "$DMR_CMD" | head -n 1)
         echo -e "${GREEN}${BOLD}当前状态：正在运行 (PID: $pid)${NC}"
    else
         echo -e "${RED}${BOLD}当前状态：未运行${NC}"
    fi
    if [ -d "$DMR_DIR" ]; then
        echo -e "配置文件：$(check_config && echo -e "${GREEN}${BOLD}已完成配置${NC}" || echo -e "${RED}${BOLD}未正确配置${NC}")"
        echo -e "Cookies ：$(check_cookies && echo -e "${GREEN}${BOLD}已完成配置${NC}" || echo -e "${RED}${BOLD}未正确配置 请检查/tools目录！${NC}")"
        echo -e "上一次安装/更新日期：${PINK}${BOLD}${install_date}${NC}"
        if [ -f "$INSTALL_DATE_FILE" ] && [[ "$commit_time" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            local last_update
            last_update=$(date -d "$install_date" +%s 2>/dev/null || echo 0)
            local commit_timestamp
            commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo 0)
            if [ $commit_timestamp -gt $last_update ]; then
                echo -e "${YELLOW}${BOLD}提示：v5 分支有更新，请选择选项10进行更新！${NC}"
            fi
        fi
    fi
}

# 检查 DanmakuRender v5 是否已安装
require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}DanmakuRender v5 未安装，请先选择安装选项（1）进行安装！${NC}"
         return 1
    fi
    return 0
}

# 主菜单（交互式菜单，提供安装、启动、日志查看、更新、卸载等选项）
main_menu() {
    check_dependencies || { echo -e "${RED}${BOLD}[ERROR]${NC} 依赖检查失败，脚本终止"; exit 1; }
    fetch_github_times
    get_install_date
    local skip_read=false
    while true; do
        show_header
        show_status
        echo -e "${CYAN}${BOLD}请选择操作：${NC}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 安装 DanmakuRender v5"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 启动/停止录制"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 查看实时日志"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL} 手动渲染视频"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL} 运行一次测试"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL} 删除回放/渲染视频文件"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL} biliup‑rs 工具"
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL} 安装微软雅黑和 Emoji 表情"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} 安装阿里巴巴普惠体和 Emoji 表情"
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL} 更新 DanmakuRender v5"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD}卸载 DanmakuRender v5"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 退出脚本"
        read -p "请输入选项： " choice
        case $choice in
            1) install_dmr; skip_read=false ;;
            2)
                if require_installed; then
                    if check_config; then
                        if pgrep -f "$DMR_CMD" > /dev/null; then
                            stop_dmr
                        else
                            if start_dmr; then
                                view_log
                                skip_read=true
                            fi
                        fi
                    else
                        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}配置文件未正确配置${NC}"
                    fi
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            3)
                if require_installed; then
                    view_log
                    skip_read=true
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            4)
                if require_installed; then
                    manual_render
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            5)
                if require_installed; then
                    run_test
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            6)
                if require_installed; then
                    delete_replays
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            7)
                if require_installed; then
                    biliup_menu
                    skip_read=true
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            8)
                if require_installed; then
                    install_fonts
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            9)
                if require_installed; then
                    install_alibaba_fonts
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            10)
                if require_installed; then
                    update_dmr
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                else
                    echo -e "${RED}请先安装 DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项！${NC}"; skip_read=false ;;
        esac
        if [ "$skip_read" = false ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# biliup‑rs 子菜单（提供快速上传、追加上传、更新 Cookies、更新工具等功能）
biliup_menu() {
    while true; do
        show_header
        echo -e "${PINK}=== biliup‑rs ===${NC}"
        echo -e "${CYAN}当前 biliup‑rs 版本信息：${NC}"
        cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无法进入工具目录${NC}"; return 1; }
        ./biliup -V
        echo ""
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 哔哩哔哩快速上传"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 哔哩哔哩视频追加上传"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 更新哔哩哔哩Cookies"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} 更新 biliup‑rs"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        read -p "请输入选项： " sub_choice
        case $sub_choice in
            1) biliup_upload ;;
            2) biliup_append ;;
            3)
                cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无法进入工具目录${NC}"; return 1; }
                ./biliup login
                ;;
            9) update_biliup_rs ;;
            0) return 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项！${NC}" ;;
        esac
        if [ "$sub_choice" != "0" ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# ------------------------- 脚本入口 -------------------------
main_menu
