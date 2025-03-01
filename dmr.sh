#!/bin/bash
# =============================================================================
# DanmakuRender v5 管理脚本
# 用于安装、更新、启动、停止、日志查看、测试、视频渲染及相关辅助工具（如 biliup‑rs、字体安装）的管理，
# 并提供交互式主菜单。
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
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}$tool 未找到，正在安装...${NC}"
            sudo apt install -y "$tool" || { 
                echo -e "${BLUE}${BOLD}[INFO]${NC} ${RED}$tool 安装失败！${NC}"
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

# 出错时回滚安装（删除安装目录）
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}安装出错，正在回滚安装...${NC}"
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}回滚删除安装目录失败！${NC}"
}

# 检查配置文件是否存在
check_config() {
    if find "$DMR_DIR/configs" -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 检查 Cookies 文件是否存在
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

# 读取记录的安装/更新时间
get_install_date() {
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        install_date=$(TZ=Asia/Shanghai date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
    fi
}

# 检查安装所需系统工具（wget、unzip、python3-venv、ffmpeg 等）
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在检查系统工具...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}$tool 未找到，正在安装...${NC}"
            sudo apt install -y "$tool" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}$tool 安装失败！${NC}"; return 1; }
        fi
    done
}

# ------------------------- DanmakuRender v5 安装与更新 -------------------------

# 安装 DanmakuRender v5（下载、解压、创建虚拟环境、安装依赖及工具）
install_dmr() {
    local rollback_needed=true
    trap '[[ "$rollback_needed" = true ]] && rollback_installation' EXIT

    # 如果已安装，则只重新安装 Python 依赖
    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}DanmakuRender v5 已安装！${NC}"
        read -p "是否重新安装 Python 依赖？(y/n) " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}已取消操作${NC}"
            return 0
        fi
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在重新安装 Python 依赖...${NC}"
        cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入目录失败！${NC}"; return 1; }
        [ -d "venv" ] && rm -rf venv
        python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}创建虚拟环境失败！${NC}"; return 1; }
        source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}激活虚拟环境失败！${NC}"; return 1; }
        pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}pip 升级失败！${NC}"; return 1; }
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Python 依赖安装失败！${NC}"; return 1; }
        deactivate
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}Python 依赖重新安装完成！${NC}"
        return 0
    fi

    # 初次安装流程
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在安装必要的系统工具...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}apt update 失败！${NC}"; return 1; }
    sudo apt install -y unzip curl wget || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}工具安装失败！${NC}"; return 1; }
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}apt update 失败！${NC}"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在下载 DanmakuRender v5...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入临时目录失败！${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}下载失败！${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解压失败！${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到解压后的文件夹！${NC}"; return 1; }
    sudo mv "$extracted_folder" "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}移动文件夹失败！${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}下载并解压完成！${NC}"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入目录失败！${NC}"; return 1; }
    sudo apt install python3-venv -y || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}python3-venv 安装失败！${NC}"; return 1; }
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}创建虚拟环境失败！${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}激活虚拟环境失败！${NC}"; return 1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}pip 升级失败！${NC}"; return 1; }
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}Python 依赖安装失败！${NC}"; return 1; }
    deactivate

    sudo apt install ffmpeg -y || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}ffmpeg 安装失败！${NC}"; return 1; }
    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}biliup‑rs 安装失败！${NC}"; return 1; }
    
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}${BOLD}DanmakuRender v5 安装成功！${NC}"
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}记录安装日期失败！${NC}"; return 1; }
    get_install_date

    rollback_needed=false
    trap - EXIT

    read -p "安装完成，是否安装字体？(y/n): " font_ans
    if [[ "$font_ans" =~ ^[Yy]$ ]]; then
        read -p "请选择字体类型：8 为微软雅黑+Emoji，9 为阿里巴巴普惠体+Emoji，0 取消： " font_choice
        case $font_choice in
            8) install_fonts ;;
            9) install_alibaba_fonts ;;
            0) echo -e "${BLUE}${BOLD}[INFO]${NC} 取消字体安装" ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} 无效选项" ;;
        esac
    fi
}

# 更新 DanmakuRender v5（备份当前目录、下载更新包、覆盖文件并重新安装依赖）
update_dmr() {
    require_installed || return 1
    read -p "是否进行更新？(y/n): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         return 0
    fi

    check_install_tools || return 1

    if pgrep -f "$DMR_CMD" > /dev/null; then
         echo -e "${BLUE}${BOLD}[INFO]${NC} 正在停止运行中的进程..."
         stop_dmr
    fi

    backup_dir="${DMR_DIR}_backup_$(date +%s)"
    echo -e "${BLUE}${BOLD}[INFO]${NC} 正在备份主目录到 ${YELLOW}$backup_dir${NC} ..."
    sudo cp -r "$DMR_DIR" "$backup_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} 备份失败！"; return 1; }

    update_fail=0
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC} 进入临时目录失败！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} 正在下载更新包..."
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} 下载失败！"; update_fail=1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC} 解压失败！"; update_fail=1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} 未找到解压后的文件夹！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} 正在覆盖文件..."
    sudo rsync -a "$extracted_folder/" "$DMR_DIR/" || { echo -e "${RED}${BOLD}[ERROR]${NC} 文件覆盖失败！"; update_fail=1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} 进入目录失败！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} 正在重新安装 Python 依赖..."
    [ -d "venv" ] && rm -rf venv
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC} 创建虚拟环境失败！"; update_fail=1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} 激活虚拟环境失败！"; update_fail=1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC} pip 升级失败！"; update_fail=1; }
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC} Python 依赖安装失败！"; update_fail=1; }
    deactivate

    if [ "$update_fail" -eq 1 ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC} 更新失败，正在恢复备份..."
         sudo rm -rf "$DMR_DIR"
         sudo mv "$backup_dir" "$DMR_DIR"
         echo -e "${RED}${BOLD}[ERROR]${NC} 恢复备份完成！"
         return 1
    else
         echo -e "${GREEN}${BOLD}[INFO]${NC} 更新成功！"
         sudo rm -rf "$backup_dir"
    fi
}

# 卸载 DanmakuRender v5
uninstall_dmr() {
    require_installed || return 1
    rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}卸载完成！${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}卸载失败！${NC}"
}

# ------------------------- 进程控制与日志查看 -------------------------

# 启动 DanmakuRender v5（后台启动并记录日志）
start_dmr() {
    require_installed || return 1
    cd "$DMR_DIR" && source venv/bin/activate && nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}启动成功！PID: $pid${NC}"
    return 0
}

# 停止运行中的 DanmakuRender v5
stop_dmr() {
    require_installed || return 1
    pkill -f "$DMR_CMD" && echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}已停止${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}停止失败${NC}"
}

# 查看最新日志文件（进入 logs 目录查找最新 .log 文件，显示文件名及提示信息，使用 tail -f 实时查看，按 s 退出）
view_log() {
    require_installed || return 1
    local logs_dir="$DMR_DIR/logs"
    if [ ! -d "$logs_dir" ]; then
        echo -e "${RED}日志目录不存在：$logs_dir${NC}"
        return 1
    fi
    local latest_log
    latest_log=$(ls -t "$logs_dir"/*.log 2>/dev/null | head -n 1)
    if [ -z "$latest_log" ]; then
        echo -e "${RED}在 $logs_dir 中未找到日志文件${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC} 日志文件名称: $(basename "$latest_log")"
    echo -e "${BLUE}${BOLD}[INFO]${NC} 提示内容: 按 s 键退出查看"
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
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在运行测试...${NC}"
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入目录失败！${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}激活虚拟环境失败！${NC}"; return 1; }
    python3 dryrun.py || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}测试运行失败！${NC}"; return 1; }
    deactivate
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}测试完成！${NC}"
}

# 手动渲染视频（调用 render_only.py）
manual_render() {
    require_installed || return 1
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} 进入目录失败！"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} 激活虚拟环境失败！"; return 1; }
    python3 render_only.py || { echo -e "${RED}${BOLD}[ERROR]${NC} 渲染失败！"; return 1; }
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
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}已删除所有回放文件${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${YELLOW}取消删除操作${NC}"
    fi
}

# ------------------------- 字体安装 -------------------------

# 安装微软雅黑及 Emoji 字体
install_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在安装微软雅黑及 Emoji 字体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/microsoft || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}创建字体目录失败！${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/ || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}复制微软雅黑字体失败！${NC}"; return 1; }
    fc-list | grep "Microsoft YaHei" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到微软雅黑字体！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}安装 Emoji 字体包失败！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}字体安装完成！${NC}"
}

# 安装阿里巴巴普惠体及 Emoji 字体
install_alibaba_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在安装阿里巴巴普惠体及 Emoji 字体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}创建字体目录失败！${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/AlibabaPuHuiTi-3-65-Medium.ttf" /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}复制阿里巴巴普惠体字体失败！${NC}"; return 1; }
    fc-list | grep "Alibaba PuHuiTi 3.0" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到阿里巴巴普惠体字体！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}安装 Emoji 字体包失败！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}字体安装完成！${NC}"
}

# ------------------------- biliup‑rs 工具管理 -------------------------

# 安装 biliup‑rs 工具（获取最新版本信息、检测系统架构、下载、解压、移动执行文件）
install_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入工具目录失败${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在获取 biliup‑rs 最新版本信息...${NC}"
    latest_info=$(curl -sf "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}获取 biliup‑rs 信息失败！${NC}"
        return 1
    fi
    latest_version=$(echo "$latest_info" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解析版本失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}最新版本：${latest_version}${NC}"
    
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
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}不支持的架构：$arch${NC}"; return 1 ;;
    esac
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}检测到系统架构：$arch，资源文件：${asset}${NC}"
    
    asset_file="biliupR-${latest_version}-${asset}"
    download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}下载 URL：${download_url}${NC}"
    
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在下载 biliup‑rs...${NC}"
    curl -LO "$download_url" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}下载失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在解压 ${asset_file}...${NC}"
    tar -xJvf "$asset_file" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解压失败！${NC}"; return 1; }
    
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到解压后的文件夹！${NC}"
        return 1
    fi
    if [ ! -f "$extracted_folder/biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}在解压文件夹中未找到 biliup 文件！${NC}"
        return 1
    fi
    mv "$extracted_folder/biliup" . || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}移动 biliup 文件失败！${NC}"; return 1; }
    rm -rf "$extracted_folder" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除解压文件夹失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}biliup‑rs 安装成功！${NC}"
}

# 更新 biliup‑rs（删除旧文件后重新安装）
update_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入工具目录失败${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在更新 biliup‑rs...${NC}"
    rm -f "$BILIUP_DIR/biliup" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除旧文件失败！${NC}"; return 1; }
    install_biliup_rs
}

# ------------------------- 哔哩哔哩视频上传相关 -------------------------

# 哔哩哔哩视频快速上传功能
biliup_upload() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "请输入视频所在目录的绝对路径: " video_dir ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项！${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}目录不存在：$video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) 返回"
        while true; do
            read -p "请输入视频选项号码（用空格分隔，0 返回）： " -a selections
            if [[ " ${selections[@]} " =~ " 0 " ]]; then
                return
            fi
            valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}无效选项：$num${NC}"
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
                    echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项：$num${NC}"
                    return 1
                fi
            done
        fi
    else
        read -p "请输入视频文件的绝对路径（用空格分隔）： " -a video_paths
    fi
    read -p "请输入 tid（默认 65）： " tid
    tid=${tid:-65}
    read -p "请输入视频标签（默认 直播回放,录播）： " tags
    tags=${tags:-"直播回放,录播"}
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入工具目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}执行命令：./biliup upload ${video_paths[*]} --tid $tid --tag \"$tags\"${NC}"
    ./biliup upload "${video_paths[@]}" --tid "$tid" --tag "$tags"
}

# 哔哩哔哩视频追加上传功能
biliup_append() {
    require_installed || return 1
    while true; do
        read -p "请输入视频 BV 号： " bv
        [[ "$bv" =~ ^BV ]] && break || echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效的 BV 号！必须以 BV 开头。${NC}"
    done
    video_paths=()
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "请输入视频文件的绝对路径（用空格分隔）： " -a video_paths ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项！${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}目录不存在：$video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${CYAN}视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) 返回"
        while true; do
            read -p "请输入视频选项号码（用空格分隔，0 返回）： " -a selections
            if [[ " ${selections[@]} " =~ " 0 " ]]; then
                return
            fi
            valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}无效选项：$num${NC}"
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
                    echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无效选项：$num${NC}"
                    return 1
                fi
            done
        fi
    fi
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入工具目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}执行命令：./biliup append --vid \"$bv\" ${video_paths[*]}${NC}"
    ./biliup append --vid "$bv" "${video_paths[@]}"
}

# ------------------------- 主菜单及状态显示 -------------------------

# 显示头部信息（版本、提交日期、更新日期、项目地址、Python 版本等）
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

# 显示当前状态及配置信息、更新提示
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
        echo -e "Cookies ：$(check_cookies && echo -e "${GREEN}${BOLD}已完成配置${NC}" || echo -e "${RED}${BOLD}未正确配置，请检查 /tools 目录！${NC}")"
        echo -e "上一次安装/更新日期：${PINK}${BOLD}${install_date}${NC}"
        if [ -f "$INSTALL_DATE_FILE" ] && [[ "$commit_time" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            local last_update
            last_update=$(date -d "$install_date" +%s 2>/dev/null || echo 0)
            local commit_timestamp
            commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo 0)
            if [ $commit_timestamp -gt $last_update ]; then
                echo -e "${YELLOW}${BOLD}提示：v5 分支有更新，请选择选项 10 进行更新！${NC}"
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
        echo -e "\n${CYAN}${BOLD}请选择操作：${NC}"
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
                        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}配置文件未正确配置！${NC}"
                    fi
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            3)
                if require_installed; then
                    view_log
                    skip_read=true
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            4)
                if require_installed; then
                    manual_render
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            5)
                if require_installed; then
                    run_test
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            6)
                if require_installed; then
                    delete_replays
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            7)
                if require_installed; then
                    biliup_menu
                    skip_read=true
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            8)
                if require_installed; then
                    install_fonts
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            9)
                if require_installed; then
                    install_alibaba_fonts
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            10)
                if require_installed; then
                    update_dmr
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
                fi
                skip_read=false
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                else
                    echo -e "${RED}请先安装 DanmakuRender v5！${NC}"
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
        cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无法进入工具目录！${NC}"; return 1; }
        ./biliup -V
        echo ""
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${NORMAL} 哔哩哔哩快速上传"
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${NORMAL} 哔哩哔哩视频追加上传"
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${NORMAL} 更新哔哩哔哩 Cookies"
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${NORMAL} 更新 biliup‑rs"
        echo -e "${BLUE}${BOLD}[INFO]${NC} ${NORMAL} 返回主菜单"
        read -p "请输入选项： " sub_choice
        case $sub_choice in
            1) biliup_upload ;;
            2) biliup_append ;;
            3)
                cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}无法进入工具目录！${NC}"; return 1; }
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
