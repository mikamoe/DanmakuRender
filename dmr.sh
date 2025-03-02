#!/bin/bash
# ===================== 配置变量 =====================
DMR_DIR="/opt/DanmakuRender-5"
DMR_CMD="python3 main.py"
LOG_FILE="nohup.out"
COOKIES_TOOL_DIR="tools"
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"
INSTALL_DATE_FILE="$DMR_DIR/install_date"

# GitHub 项目信息
GITHUB_OWNER="SmallPeaches"
GITHUB_REPO="DanmakuRender"
GITHUB_BRANCH="v5"

# biliup-rs 项目信息（用于动态获取最新版本）
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup-rs"
# 定义 biliup-rs 发布基础 URL（安装时动态构造下载地址）
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases/download"

# ANSI 颜色和样式
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

# ===================== 系统检查及辅助函数 =====================
# 检查基本依赖工具（jq、curl）
check_dependencies() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}Checking dependencies......${NC}"
    local required_tools=("jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool，正在安装...${NC}"
            sudo apt install -y "$tool" || { 
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${RED}$tool 安装失败！${NC}"
                return 1
            }
        fi
    done
}

# 获取 Python3 版本
get_python_version() {
    if command -v python3 &>/dev/null; then
        echo "Python $(python3 -V 2>&1 | awk '{print $2}')"
    else
        echo "not_installed"
    fi
}

# 回滚安装（安装出错时删除安装目录）
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装过程中出错，正在回滚安装...${NC}"
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}回滚删除安装目录失败！${NC}"
}

# 检查配置文件状态
check_config() {
    if find "$DMR_DIR/configs" -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 检查 Cookies 文件状态
check_cookies() {
    if find "$BILIUP_DIR" -name "*.json" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 获取 GitHub 的最新提交和 Release 时间（转换为北京时间）以及最新提交说明
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

# 获取安装/更新日期
get_install_date() {
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        install_date=$(TZ=Asia/Shanghai date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
    fi
}

# ===================== 安装与更新 DanmakuRender v5 相关函数 =====================
# 检查安装必要工具（wget、unzip、python3-venv、python3-pip、ffmpeg、curl、tar）
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在检查系统依赖工具...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool，正在安装...${NC}"
            sudo apt install -y "$tool" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}$tool 安装失败！${NC}"; return 1; }
        fi
    done
}

# 安装 DanmakuRender v5（含回滚机制）
install_dmr() {
    local rollback_needed=true
    trap '[[ "$rollback_needed" = true ]] && rollback_installation' EXIT

    # 如果已安装，则只询问是否重新安装Python依赖，不再询问字体
    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}DanmakuRender V5 已经安装！${NC}"
        read -p "是否要重新安装Python依赖？(y/n) " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消重新安装${NC}"
            return 0
        fi
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在重新安装Python依赖...${NC}"
        cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入目录失败！${NC}"; return 1; }
        [ -d "venv" ] && rm -rf venv
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建新的虚拟环境...${NC}"
        python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建虚拟环境失败！${NC}"; return 1; }
        source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; return 1; }
        pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}pip 升级失败！${NC}"; return 1; }
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！${NC}"; return 1; }
        deactivate
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python依赖重新安装完成！${NC}"
        return 0
    fi

    # 如果是第一次安装，先进行正常安装流程
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装必要工具...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！${NC}"; return 1; }
    sudo apt install -y unzip curl wget || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}必要工具安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}必要工具安装完成！${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！${NC}"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 DanmakuRender v5...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入临时目录失败！${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载失败！${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压失败！${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到解压后的文件夹！${NC}"; return 1; }
    sudo mv "$extracted_folder" "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}移动文件夹失败！${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}文件下载并解压完成！${NC}"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 python3-venv...${NC}"
    sudo apt install python3-venv -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}python3-venv 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建虚拟环境...${NC}"
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建虚拟环境失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; return 1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}pip 升级失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 Python 依赖...${NC}"
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！${NC}"; return 1; }
    deactivate

    # ---------------- 安装 ffmpeg ----------------
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装 ffmpeg...${NC}"
    sudo apt install ffmpeg -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}ffmpeg 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}ffmpeg 安装完成！${NC}"
    
    # ---------------- 安装 biliup-rs ----------------
    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}biliup-rs 安装失败！${NC}"; return 1; }
    
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}DanmakuRender v5 安装完成！${NC}${NORMAL}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}记录安装日期...${NC}"
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录安装日期失败！${NC}"; return 1; }
    get_install_date

    rollback_needed=false
    trap - EXIT

    # =========================
    # 仅在首次安装完成后询问字体
    # =========================
    read -p "安装完成，是否安装字体？(y/n): " font_ans
    if [[ "$font_ans" =~ ^[Yy]$ ]]; then
        read -p "请选择安装字体类型: 8 为微软雅黑和Emoji, 9 为阿里巴巴普惠体和Emoji, 0 取消: " font_choice
        case $font_choice in
            8) install_fonts ;;
            9) install_alibaba_fonts ;;
            0) echo -e "${BLUE}${BOLD}[INFO]${NC} 取消安装字体" ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} 无效选项" ;;
        esac
    fi
}

# 更新 DanmakuRender v5（新逻辑：备份主目录，直接覆盖文件并重新安装 Python 依赖）
update_dmr() {
    require_installed || return 1
    read -p "是否进行更新？(y/n): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         return 0
    fi

    check_install_tools || return 1

    if pgrep -f "$DMR_CMD" > /dev/null; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在停止运行中的进程..."
         stop_dmr
    fi

    backup_dir="${DMR_DIR}_backup_$(date +%s)"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在备份主目录到 ${YELLOW}$backup_dir${NC} ..."
    sudo cp -r "$DMR_DIR" "$backup_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 备份失败！"; return 1; }

    update_fail=0

    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入临时目录失败！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在下载 DanmakuRender v5 更新包..."
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 下载失败！"; update_fail=1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 解压失败！"; update_fail=1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未找到解压后的文件夹！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在覆盖主目录文件..."
    sudo rsync -a "$extracted_folder/" "$DMR_DIR/" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 文件覆盖失败！"; update_fail=1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在重新安装 Python 依赖..."
    [ -d "venv" ] && rm -rf venv
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建虚拟环境失败！"; update_fail=1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; update_fail=1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} pip 升级失败！"; update_fail=1; }
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} Python 依赖安装失败！"; update_fail=1; }
    deactivate

    if [ "$update_fail" -eq 1 ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 更新失败，正在恢复备份..."
         sudo rm -rf "$DMR_DIR"
         sudo mv "$backup_dir" "$DMR_DIR"
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 恢复备份完成！"
         return 1
    else
         echo -e "${GREEN}${BOLD}[INFO]${NC}${NORMAL} 更新成功！"
         sudo rm -rf "$backup_dir"
    fi
}

# 卸载 DanmakuRender v5
uninstall_dmr() {
    require_installed || return 1
    rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}卸载完成！${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}卸载失败！${NC}"
}

# 启动 DanmakuRender v5
start_dmr() {
    require_installed || return 1
    cd "$DMR_DIR" && source venv/bin/activate
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$DMR_DIR/dmr.pid"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}启动成功！PID: $pid${NC}"
}

# 停止 DanmakuRender v5
stop_dmr() {
    require_installed || return 1
    if [ -f "$DMR_DIR/dmr.pid" ]; then
        local pid=$(cat "$DMR_DIR/dmr.pid")
        kill $pid && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已停止进程 $pid ${NC}" 
        rm "$DMR_DIR/dmr.pid"
    else
        pkill -f "$DMR_CMD" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已停止 ${NC}" 
    fi
}

# 查看日志（支持退出）
view_log() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}按 q 键退出日志查看${NC}"
    tail -f "$DMR_DIR/$LOG_FILE" & pid=$!
    while true; do
        if read -t 1 -n 1; then
            if [[ $REPLY == "q" ]]; then
                kill $pid 2>/dev/null
                break
            fi
        fi
        if ! ps -p $pid > /dev/null; then
            break
        fi
    done
}

# 运行测试
run_test() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行测试...${NC}"
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入目录失败！${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; return 1; }
    python3 dryrun.py || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}测试运行失败！${NC}"; return 1; }
    deactivate
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}测试运行完成！${NC}"
}

# 手动渲染视频
manual_render() {
    require_installed || return 1
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; return 1; }
    python3 render_only.py || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 渲染失败！"; return 1; }
    deactivate
}

# 删除回放/渲染文件
delete_replays() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}直播回放目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放${NC}"
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}直播回放（弹幕版）目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放（弹幕版）" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放（弹幕版）${NC}"
    read -p $'\n是否要删除所有回放文件？(y/n) ' confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf "$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）"
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已删除所有回放文件${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消删除操作${NC}"
    fi
}

# 安装字体（安装微软雅黑和Emoji）
install_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装微软雅黑和Emoji字体...${NC}"
    
    # 安装微软雅黑字体
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装微软雅黑字体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/microsoft || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建字体目录失败！${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/ || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}复制微软雅黑字体失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已安装微软雅黑字体！${NC}"
    
    # 显示已安装的微软雅黑字体
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}显示安装的微软雅黑字体...${NC}"
    fc-list | grep "Microsoft YaHei" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}没有找到微软雅黑字体！${NC}"; return 1; }
    
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新字体缓存...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    
    # 安装Emoji字体包
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装Emoji字体包...${NC}"
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}安装Emoji字体包失败！${NC}"; return 1; }

    # 显示已安装的Emoji字体包
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已安装以下Emoji字体包：${NC}"
    echo -e "${GREEN}1. fonts-noto${NC}"
    echo -e "${GREEN}2. fonts-noto-extra${NC}"
    echo -e "${GREEN}3. fonts-noto-cjk${NC}"
    echo -e "${GREEN}4. fonts-symbola${NC}"
    echo -e "${GREEN}5. fonts-noto-color-emoji${NC}"
    
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}字体安装完成！${NC}"
}

# 安装阿里巴巴普惠体字体和Emoji表情
install_alibaba_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装阿里巴巴普惠体和Emoji字体...${NC}"
    
    # 安装阿里巴巴普惠体字体
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装阿里巴巴普惠体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建字体目录失败！${NC}"; return 1; }
    sudo cp "$DMR_DIR/fonts/AlibabaPuHuiTi-3-65-Medium.ttf" /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}复制阿里巴巴普惠体字体失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已安装阿里巴巴普惠体！${NC}"
    
    # 显示已安装的阿里巴巴普惠体字体
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}显示安装的阿里巴巴普惠体...${NC}"
    fc-list | grep "Alibaba PuHuiTi 3.0" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}没有找到阿里巴巴普惠体字体！${NC}"; return 1; }
    
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新字体缓存...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    
    # 安装Emoji字体包
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装Emoji字体包...${NC}"
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}安装Emoji字体包失败！${NC}"; return 1; }

    # 显示已安装的Emoji字体包
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已安装以下Emoji字体包：${NC}"
    echo -e "${GREEN}1. fonts-noto${NC}"
    echo -e "${GREEN}2. fonts-noto-extra${NC}"
    echo -e "${GREEN}3. fonts-noto-cjk${NC}"
    echo -e "${GREEN}4. fonts-symbola${NC}"
    echo -e "${GREEN}5. fonts-noto-color-emoji${NC}"
    
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}字体安装完成！${NC}"
}

# ===================== biliup-rs 工具相关函数 =====================
# 安装 biliup-rs（动态获取最新版本、检测架构、下载、解压并移动 biliup 文件）
install_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入 tools 目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}获取 biliup-rs 最新版本信息...${NC}"
    latest_info=$(curl -sf "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}获取 biliup-rs 最新版本信息失败！${NC}"
        return 1
    fi
    latest_version=$(echo "$latest_info" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解析 biliup-rs 版本失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}最新 biliup-rs 版本：${latest_version}${NC}"
    
    arch=$(uname -m)
    case "$arch" in
        aarch64)
            asset="aarch64-linux.tar.xz"
            ;;
        arm*|aarch32)
            asset="arm-linux.tar.xz"
            ;;
        x86_64)
            if ldd --version 2>&1 | grep -qi musl; then
                asset="x86_64-linux-musl.tar.xz"
            else
                asset="x86_64-linux.tar.xz"
            fi
            ;;
        *)
            echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}不支持的架构：$arch${NC}"
            return 1
            ;;
    esac
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}检测到系统架构：$arch，选择资源文件：${asset}${NC}"
    
    asset_file="biliupR-${latest_version}-${asset}"
    download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}下载 URL：${download_url}${NC}"
    
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在下载 biliup-rs...${NC}"
    curl -LO "$download_url" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}下载 biliup-rs 失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在解压 ${asset_file}...${NC}"
    tar -xJvf "$asset_file" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解压 biliup-rs 失败！${NC}"; return 1; }
    
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到解压后的文件夹！${NC}"
        return 1
    fi
    if [ ! -f "$extracted_folder/biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未在解压文件夹中找到 biliup 文件！${NC}"
        return 1
    fi
    mv "$extracted_folder/biliup" . || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}移动 biliup 文件失败！${NC}"; return 1; }
    rm -rf "$extracted_folder" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除解压文件夹失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}安装 biliup-rs 完成！${NC}"
}

# 更新 biliup-rs（删除旧文件后重新安装）
update_biliup_rs() {
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入 tools 目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在更新 biliup-rs...${NC}"
    rm -f "$BILIUP_DIR/biliup" || { echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除旧的 biliup 文件失败！${NC}"; return 1; }
    install_biliup_rs
}

# 哔哩哔哩视频快速上传
biliup_upload() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "请输入视频所在目录的绝对路径: " video_dir ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录不存在：$video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录下没有视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}目录下的视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) 返回上一级菜单"
        while true; do
            read -p "请输入要上传的视频选项（数字，用空格分隔，0返回）： " -a selections
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
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项：$num${NC}"
                    return 1
                fi
            done
        fi
    else
        read -p "请输入视频文件的绝对路径（多个请用空格分隔）： " -a video_paths
    fi
    read -p "请输入tid号（默认65）: " tid
    tid=${tid:-65}
    read -p "请输入视频标签（默认直播回放,录播）: " tags
    tags=${tags:-"直播回放,录播"}
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入工具目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}执行命令：./biliup upload ${video_paths[*]} --tid $tid --tag \"$tags\"${NC}"
    ./biliup upload "${video_paths[@]}" --tid "$tid" --tag "$tags"
}

# 哔哩哔哩视频追加上传
biliup_append() {
    require_installed || return 1
    while true; do
        read -p "请输入视频BV号: " bv
        [[ "$bv" =~ ^BV ]] && break || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效的BV号，请确保以BV开头！${NC}"
    done
    video_paths=()
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice
    case $type_choice in
        1) video_dir="/opt/DanmakuRender-5/直播回放" ;;
        2) video_dir="/opt/DanmakuRender-5/直播回放（弹幕版）" ;;
        3) read -p "请输入视频文件的绝对路径（多个请用空格分隔）： " -a video_paths ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}"; return 1 ;;
    esac
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录不存在：$video_dir${NC}"; return 1; }
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录下没有视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}目录下的视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        echo "0 ) 返回上一级菜单"
        while true; do
            read -p "请输入要上传的视频选项（数字，用空格分隔，0返回）： " -a selections
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
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项：$num${NC}"
                    return 1
                fi
            done
        fi
    fi
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入工具目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}执行命令：./biliup append --vid \"$bv\" ${video_paths[*]}${NC}"
    ./biliup append --vid "$bv" "${video_paths[@]}"
}

# ===================== 主菜单及状态显示 =====================
# 显示头部信息
show_header() {
    clear
    echo -e "${PINK}==============================${NC}"
    echo -e "${BLUE}${BOLD}DanmakuRender v5${NORMAL}        ${NC}"
    echo -e "${PINK}最新提交日期${NC} ${BOLD}${commit_time}"
    echo -e "${PINK}版本号  ${NC}  ${BOLD}${release_version}"
    echo -e "${PINK}更新日期${NC}  ${BOLD}${release_time}"
    echo -e "${PURPLE}${BOLD}项目原地址https://github.com/SmallPeaches/DanmakuRender${NC}"
    
    # 如果上一次安装/更新日期早于最新提交日期，则显示最新提交信息
    if [ -f "$INSTALL_DATE_FILE" ] && [[ "$commit_time" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        last_update=$(date -d "$install_date" +%s 2>/dev/null || echo 0)
        commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo 0)
        if [ "$commit_timestamp" -gt "$last_update" ]; then
            echo -e "${YELLOW}${BOLD}v5分支有最新变动${NC}"
            echo -e "${YELLOW}${BOLD}提交日期：${NC}${commit_time}"
            if [ -n "$commit_message" ]; then
                echo -e "${YELLOW}${BOLD}提交说明：${NC}${commit_message}"
            fi
        fi
    fi

    python_version=$(get_python_version)
    if [[ "$python_version" == "not_installed" ]]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} Python3 未安装或未检测到！${NC}"
    else
        echo -e "${YELLOW}${BOLD}当前Python版本：${BOLD}${python_version}${NC}\n"
    fi  
}

# 显示当前状态及更新提示
show_status() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${YELLOW}${BOLD}当前状态：DanmakuRender v5 未安装${NC}${NORMAL}"
    elif pgrep -f "$DMR_CMD" > /dev/null; then
         pid=$(pgrep -f "$DMR_CMD" | head -n 1)
         echo -e "${GREEN}${BOLD}当前状态：正在运行 (PID: $pid)${NC}${NORMAL}"
    else
         echo -e "${RED}${BOLD}当前状态：未运行${NC}${NORMAL}"
    fi
    
    if [ -d "$DMR_DIR" ]; then
        echo -e "配置文件：$(check_config && echo -e "${GREEN}${BOLD}已完成配置${NC}${NORMAL}" || echo -e "${RED}${BOLD}未正确配置${NC}${NORMAL}")"
        echo -e "Cookies ：$(check_cookies && echo -e "${GREEN}${BOLD}已完成配置${NC}${NORMAL}" || echo -e "${RED}${BOLD}未正确配置 请检查/tools目录！${NC}${NORMAL}")"
        echo -e "上一次安装/更新日期：${PINK}${BOLD}${install_date}${NC}"
        if [ -f "$INSTALL_DATE_FILE" ] && [[ "$commit_time" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            local last_update
            last_update=$(date -d "$install_date" +%s 2>/dev/null || echo 0)
            local commit_timestamp
            commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo 0)
            if [ $commit_timestamp -gt $last_update ]; then
                echo -e "${YELLOW}${BOLD}提示：v5分支有更新，请选择选项10进行更新！${NC}"
            fi
        fi
    fi
}

# 检查是否已安装 DanmakuRender v5
require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}DanmakuRender v5 未安装，请先选择安装选项（1）进行安装！${NC}"
         return 1
    fi
    return 0
}

# 主菜单
main_menu() {
    check_dependencies || { echo -e "${RED}${BOLD}[ERROR]${NC} 依赖检查失败，脚本终止"; exit 1; }
    fetch_github_times
    get_install_date
    
    local skip_read=false
    while true; do
        show_header
        show_status
        echo -e "\n${CYAN}${BOLD}请选择操作：${NC}${NORMAL}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 安装DanmakuRender v5"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 启动/停止录制"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 查看实时日志(按Q退出查看)"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL} 手动渲染视频"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL} 运行一次测试"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL} 删除回放/渲染视频文件"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL} biliup-r工具"
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL} 安装微软雅黑和Emoji表情"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} 安装阿里巴巴普惠体和Emoji表情"
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL}${LIGHT_BLUE}更新DanmakuRender v5"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD}卸载DanmakuRender v5"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 退出脚本"
        
        read -p "请输入选项： " choice
        case $choice in
            1) 
                install_dmr
                skip_read=false
                ;;
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
                        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}配置文件未正确配置${NC}"
                    fi
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            3)
                if require_installed; then
                    view_log
                    skip_read=true
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            4)
                if require_installed; then
                    manual_render
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            5)
                if require_installed; then
                    run_test
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            6)
                if require_installed; then
                    delete_replays
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            7)
                if require_installed; then
                    biliup_menu
                    skip_read=true
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            8)
                if require_installed; then
                    install_fonts
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            9)
                if require_installed; then
                    install_alibaba_fonts
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            10)
                if require_installed; then
                    update_dmr
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            0) 
                exit 0 
                ;;
            *) 
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}"
                skip_read=false
                ;;
        esac
        
        if [ "$skip_read" = false ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# biliup-rs 工具子菜单
biliup_menu() {
    while true; do
        show_header
        echo -e "${PINK}=== biliup-rs ===${NC}"
        echo -e "${CYAN}当前 biliup-rs 版本信息：${NC}"
        cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无法进入工具目录${NC}"; return 1; }
        ./biliup -V
        echo ""
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 哔哩哔哩快速上传"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 哔哩哔哩视频追加上传"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 更新哔哩哔哩Cookies"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} 更新 biliup-rs"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        read -p "请输入选项： " sub_choice
        case $sub_choice in
            1) biliup_upload ;;
            2) biliup_append ;;
            3)
                cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无法进入工具目录${NC}"; return 1; }
                ./biliup login
                ;;
            9) update_biliup_rs ;;
            0) return 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}" ;;
        esac
        if [ "$sub_choice" != "0" ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# ===================== 脚本入口 =====================
main_menu
