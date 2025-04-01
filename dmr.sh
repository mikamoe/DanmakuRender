#!/bin/bash
# ===================== 配置变量 =====================
# 安装路径及相关文件、目录设置
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

# biliup‑rs 项目信息（用于动态获取最新版本）
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup-rs"
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases/download"

# GitHub 克隆地址
DMR_GITHUB_BASE="https://github.com/SmallPeaches/DanmakuRender"

# 字体下载链接配置（使用 GitHub raw 链接）
FONT_MSYH_URL="https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/msyh.ttf"
FONT_ALIBABA_URL="https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/AlibabaPuHuiTi-3-65-Medium.ttf"

# ANSI 颜色和样式设置，便于终端输出信息区分
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

# ===================== 辅助函数 =====================

# 检查必备工具：jq、curl 和 git
check_dependencies() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}Checking dependencies...${NC}"
    local required_tools=("jq" "curl" "git")
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

# 获取 Python3 的版本号，便于检查环境
get_python_version() {
    if command -v python3 &>/dev/null; then
        echo "Python $(python3 -V 2>&1 | awk '{print $2}')"
    else
        echo "not_installed"
    fi
}

# 将给定时间转换为北京时间，若失败则返回“获取失败”
convert_to_beijing_time() {
    local raw_time="$1"
    if [ -z "$raw_time" ]; then
        echo "获取失败"
        return
    fi
    local converted
    converted=$(TZ=Asia/Shanghai date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -n "$converted" ]; then
        echo "$converted"
    else
        converted=$(date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
        if [ -n "$converted" ]; then
            echo "$converted"
        else
            echo "获取失败"
        fi
    fi
}

# 回滚安装：安装过程中出错时删除安装目录
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装过程中出错，正在回滚...${NC}"
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" \
       && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" \
       || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}回滚删除安装目录失败！${NC}"
}

# 检查配置文件是否存在（用于判断是否正确配置）
check_config() {
    if find "$DMR_DIR/configs" -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 从 GitHub 获取最新提交时间、提交说明以及最新 Release 时间、版本号
fetch_github_times() {
    local branch_info
    branch_info=$(curl -sf "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/branches/$GITHUB_BRANCH")
    if [[ -n "$branch_info" ]]; then
        local raw_time
        raw_time=$(jq -r '.commit.commit.author.date // empty' <<< "$branch_info")
        commit_time=$(convert_to_beijing_time "$raw_time")
        commit_message=$(jq -r '.commit.commit.message // empty' <<< "$branch_info")
    else
        commit_time="获取失败"
        commit_message=""
    fi

    local release_info
    release_info=$(curl -sf "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest")
    if [[ -n "$release_info" ]]; then
        release_version=$(jq -r '.tag_name // empty' <<< "$release_info")
        local raw_release_time
        raw_release_time=$(jq -r '.published_at // empty' <<< "$release_info")
        release_time=$(convert_to_beijing_time "$raw_release_time")
    else
        release_version="获取失败"
        release_time="获取失败"
    fi
}

# 从文件中读取上次安装/更新的日期，并转换为北京时间
get_install_date() {
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        install_date=$(convert_to_beijing_time "$(date -d "@$timestamp" --rfc-3339=seconds 2>/dev/null)")
    fi
}

# ===================== 系统安装及更新函数 =====================

# 检查系统必备工具是否存在，否则自动安装
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查系统依赖工具...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar" "xz")
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

# 安装 biliup‑rs 工具：自动获取最新版本，根据系统架构下载相应的二进制文件
install_biliup_rs() {
    cd "$BILIUP_DIR" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入 tools 目录失败！${NC}"
        return 1
    }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}获取 biliup-rs 最新版本信息...${NC}"
    local latest_info
    latest_info=$(curl -sf "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}获取 biliup-rs 最新版本信息失败！${NC}"
        return 1
    fi
    local latest_version
    latest_version=$(echo "$latest_info" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解析 biliup-rs 版本失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}最新 biliup-rs 版本：${latest_version}${NC}"

    # 根据系统架构选择合适的压缩包
    local arch
    arch=$(uname -m)
    local asset
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

    local asset_file="biliupR-${latest_version}-${asset}"
    local download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}下载 URL：${download_url}${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在下载 biliup-rs...${NC}"
    curl -LO "$download_url" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}下载 biliup-rs 失败！${NC}"
        return 1
    }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在解压 ${asset_file}...${NC}"
    tar -xJvf "$asset_file" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}解压 biliup-rs 失败！${NC}"
        return 1
    }

    # 查找解压后的文件夹，移动二进制文件到当前目录，并删除临时文件夹
    local extracted_folder
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未找到解压后的文件夹！${NC}"
        return 1
    fi
    if [ ! -f "$extracted_folder/biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}未在解压文件夹中找到 biliup 文件！${NC}"
        return 1
    fi
    mv "$extracted_folder/biliup" . || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}移动 biliup 文件失败！${NC}"
        return 1
    }
    rm -rf "$extracted_folder" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除解压文件夹失败！${NC}"
        return 1
    }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${GREEN}安装 biliup-rs 完成！${NC}"
}

# 更新 biliup‑rs：删除旧的二进制文件后重新安装
update_biliup_rs() {
    cd "$BILIUP_DIR" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}进入 tools 目录失败！${NC}"
        return 1
    }
    echo -e "${BLUE}${BOLD}[INFO]${NC} ${BLUE}正在更新 biliup-rs...${NC}"
    rm -f "$BILIUP_DIR/biliup" || {
        echo -e "${RED}${BOLD}[ERROR]${NC} ${RED}删除旧的 biliup 文件失败！${NC}"
        return 1
    }
    install_biliup_rs
}

# 更新 DanmakuRender v5：备份当前安装、下载新版本、覆盖文件、重建虚拟环境及安装依赖
update_dmr() {
    require_installed || return 1
    read -p "是否进行更新？(y/n): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         return 0
    fi

    echo -e "${YELLOW}更新前将删除现有的直播回放及直播回放（弹幕版）目录，请确保重要文件已备份。${NC}"
    read -p "是否删除这两个目录？(y/n): " delete_choice
    if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
        [ -d "$DMR_DIR/直播回放" ] && sudo rm -rf "$DMR_DIR/直播回放" && echo -e "${BLUE}[INFO] 已删除 直播回放 目录" || echo -e "${YELLOW}直播回放 目录不存在${NC}"
        [ -d "$DMR_DIR/直播回放（弹幕版）" ] && sudo rm -rf "$DMR_DIR/直播回放（弹幕版）" && echo -e "${BLUE}[INFO] 已删除 直播回放（弹幕版） 目录" || echo -e "${YELLOW}直播回放（弹幕版） 目录不存在${NC}"
    else
        echo -e "${YELLOW}未删除直播回放目录，更新过程将继续。${NC}"
    fi

    sudo apt update && sudo apt install rsync -y

    if pgrep -f "$DMR_CMD" > /dev/null; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在停止运行中的进程..."
         stop_dmr
    fi

    backup_dir="${DMR_DIR}_backup_$(date +%s)"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在备份主目录到 ${YELLOW}$backup_dir${NC} ..."
    if ! sudo cp -r "$DMR_DIR" "$backup_dir"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 备份失败！"
         return 1
    fi

    # 备份当前的 configs 文件夹
    backup_configs="${DMR_DIR}_configs_backup_$(date +%s)"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在备份配置文件夹到 ${YELLOW}$backup_configs${NC} ..."
    if ! sudo cp -r "$DMR_DIR/configs" "$backup_configs"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 配置文件夹备份失败！"
         return 1
    fi

    update_fail=0
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入临时目录失败！"; update_fail=1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在克隆 DanmakuRender v5 更新包..."
    if ! git clone -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$tmp_dir/update_repo"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 克隆更新包失败！"
         update_fail=1
    fi

    # 检测更新包中的 configs 文件夹是否有变动
    if ! diff -qr "$DMR_DIR/configs" "$tmp_dir/update_repo/configs" >/dev/null 2>&1; then
         echo -e "${YELLOW}${BOLD}[INFO]${NC}${NORMAL} 更新包中的 configs 文件夹有变动，请记得检查并更新您的配置文件。"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在覆盖主目录文件..."
    # 使用 rsync 时排除更新包中的 configs 文件夹
    if ! sudo rsync -a --exclude='configs' "$tmp_dir/update_repo/" "$DMR_DIR/"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 文件覆盖失败！"
         update_fail=1
    fi
    # 将备份的配置文件夹覆盖回去
    sudo rm -rf "$DMR_DIR/configs"
    sudo mv "$backup_configs" "$DMR_DIR/configs"

    cd - > /dev/null
    rm -rf "$tmp_dir"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; update_fail=1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在删除旧虚拟环境..."
    [ -d "venv" ] && rm -rf venv || true

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在创建新的虚拟环境..."
    if ! python3 -m venv venv; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建虚拟环境失败！"
         update_fail=1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在激活虚拟环境并安装 Python 依赖..."
    if ! source venv/bin/activate; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"
         update_fail=1
    fi
    if ! pip install --quiet --upgrade pip; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} pip 升级失败！"
         update_fail=1
    fi
    if ! pip install -r requirements.txt; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} Python 依赖安装失败！"
         update_fail=1
    fi
    deactivate

    if [ "$update_fail" -eq 1 ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 更新过程中出现错误，正在恢复备份..."
         sudo rm -rf "$DMR_DIR"
         sudo mv "$backup_dir" "$DMR_DIR"
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 恢复备份完成！"
         return 1
    else
         echo -e "${GREEN}${BOLD}[INFO]${NC}${NORMAL} 更新成功！"
         sudo rm -rf "$backup_dir"
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在记录更新日期..."
         date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 记录更新日期失败！"
         fetch_github_times
         get_install_date
    fi
}

# 安装 DanmakuRender v5：使用 git clone 拉取代码、设置虚拟环境、安装依赖及其他工具
install_dmr() {
    local rollback_needed=true
    # 设置安装错误时自动回滚
    trap '[[ "$rollback_needed" = true ]] && rollback_installation' EXIT

    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}DanmakuRender V5 已经安装！${NC}"
        read -p "是否要重新安装Python依赖？(y/n) " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消重新安装${NC}"
            return 0
        fi
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在重新安装Python依赖...${NC}"
        cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; return 1; }
        [ -d "venv" ] && rm -rf venv
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建新的虚拟环境...${NC}"
        python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建虚拟环境失败！"; return 1; }
        source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; return 1; }
        pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} pip 升级失败！"; return 1; }
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} Python 依赖安装失败！"; return 1; }
        deactivate
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python依赖重新安装完成！${NC}"
        return 0
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装必要工具...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} apt update 失败！${NC}"; return 1; }
    sudo apt install -y unzip curl wget xz-utils || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 必要工具安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}必要工具安装完成！${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在使用 git clone 拉取 DanmakuRender v5...${NC}"
    if ! command -v git &>/dev/null; then
         echo -e "${YELLOW}${BOLD}[INFO]${NC}${NORMAL} 未检测到 git，正在安装..."
         sudo apt install -y git || { echo -e "${RED}${BOLD}[ERROR]${NC} git 安装失败！"; return 1; }
    fi
    if ! git clone -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$DMR_DIR"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} git clone 失败！"
         return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}代码拉取完成！${NC}"

    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 python3-venv...${NC}"
    sudo apt install python3-venv -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} python3-venv 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建虚拟环境...${NC}"
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建虚拟环境失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！${NC}"; return 1; }
    pip install --quiet --upgrade pip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} pip 升级失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 Python 依赖...${NC}"
    pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} Python 依赖安装失败！${NC}"; return 1; }
    deactivate

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装 ffmpeg...${NC}"
    sudo apt install ffmpeg -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ffmpeg 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}ffmpeg 安装完成！${NC}"

    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} biliup-rs 安装失败！${NC}"; return 1; }

    # 安装完成后询问是否安装 JavaScript 解释器和 JS 引擎
    read -p "安装完成，是否安装 JavaScript 解释器和 JS 引擎？(y/n): " js_choice
    if [[ "$js_choice" =~ ^[Yy]$ ]]; then
         install_js_engine
    fi

    echo -e "${GREEN}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}DanmakuRender v5 安装完成！${NC}"
    # 优化提示：让用户更清晰地知道如何安装字体
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 如需安装字体，请在主菜单中选择选项 8。"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在记录安装日期..."
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录安装日期失败！${NC}"
        return 1
    }
    get_install_date

    rollback_needed=false
    trap - EXIT
}

# 卸载 DanmakuRender v5：询问后先停止进程再卸载
uninstall_dmr() {
    require_installed || return 1
    read -p "确定要卸载 DanmakuRender v5 吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
         echo -e "${YELLOW}取消卸载。${NC}"
         return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}先停止运行中的进程...${NC}"
    stop_dmr

    rm -rf "$DMR_DIR" \
      && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}卸载完成！${NC}" \
      || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}卸载失败！${NC}"
}

# ===================== 运行与测试管理函数 =====================

# 启动 DanmakuRender v5：激活虚拟环境并使用 nohup 后台运行
start_dmr() {
    require_installed || return 1
    cd "$DMR_DIR" && source venv/bin/activate
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$DMR_DIR/dmr.pid"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}启动成功！PID: $pid${NC}"
}

# 停止 DanmakuRender v5：依据 PID 文件或进程名停止服务
stop_dmr() {
    require_installed || return 1
    if [ -f "$DMR_DIR/dmr.pid" ]; then
        local pid
        pid=$(cat "$DMR_DIR/dmr.pid")
        kill "$pid" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已停止进程 $pid ${NC}" && rm "$DMR_DIR/dmr.pid"
    else
        pkill -f "$DMR_CMD" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已停止 ${NC}"
    fi
}

# 实时查看日志，支持按 q 键退出
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

# 运行测试：调用 dryrun.py 进行测试运行
run_test() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行测试...${NC}"
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！${NC}"; return 1; }
    python3 dryrun.py || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 测试运行失败！${NC}"; return 1; }
    deactivate
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}测试运行完成！${NC}"
}

# 手动渲染视频：调用 render_only.py 进行渲染
manual_render() {
    require_installed || return 1
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC} 进入目录失败！${NC}"; return 1; }
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC} 激活虚拟环境失败！${NC}"; return 1; }
    python3 render_only.py || { echo -e "${RED}${BOLD}[ERROR]${NC} 渲染失败！${NC}"; return 1; }
    deactivate
}

# 删除回放/渲染文件：列出目录内容后，确认是否删除所有文件
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

# ===================== 字体安装相关函数 =====================

# 安装微软雅黑和 Emoji 字体：从指定链接下载字体文件并移动至系统字体目录
install_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载并安装微软雅黑和 Emoji 字体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/microsoft || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建字体目录失败！${NC}"; return 1; }
    if ! wget -O /tmp/msyh.ttf "$FONT_MSYH_URL"; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 下载微软雅黑字体失败！${NC}"
        return 1
    fi
    sudo mv /tmp/msyh.ttf /usr/share/fonts/truetype/microsoft/ || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 移动微软雅黑字体失败！${NC}"; return 1; }
    # 这里加粗“已安装微软雅黑字体！”
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}已安装微软雅黑字体！${NC}"
    fc-list | grep "Microsoft YaHei" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未找到微软雅黑字体！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新字体缓存...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 刷新字体缓存失败！${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 安装 Emoji 字体包失败！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}微软雅黑和 Emoji 字体安装完成！${NC}"
}

# 安装阿里巴巴普惠体和 Emoji 字体：同上，使用不同的下载链接
install_alibaba_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载并安装阿里巴巴普惠体和 Emoji 字体...${NC}"
    sudo mkdir -p /usr/share/fonts/truetype/AlibabaPuHuiTi || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 创建字体目录失败！${NC}"; return 1; }
    if ! wget -O /tmp/AlibabaPuHuiTi.ttf "$FONT_ALIBABA_URL"; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 下载阿里巴巴普惠体失败！${NC}"
        return 1
    fi
    sudo mv /tmp/AlibabaPuHuiTi.ttf /usr/share/fonts/truetype/AlibabaPuHuiTi/ || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 移动阿里巴巴普惠体失败！${NC}"; return 1; }
    # 这里加粗“已安装阿里巴巴普惠体！”
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}已安装阿里巴巴普惠体！${NC}"
    fc-list | grep "Alibaba PuHuiTi" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未找到阿里巴巴普惠体！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新字体缓存...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 刷新字体缓存失败！${NC}"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 安装 Emoji 字体包失败！${NC}"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}阿里巴巴普惠体和 Emoji 字体安装完成！${NC}"
}

# 字体安装子菜单：循环显示菜单供用户选择安装字体方案
font_menu() {
    local oneshot=${1:-false}
    while true; do
        echo -e "\n${CYAN}${BOLD}字体安装子菜单：${NC}${NORMAL}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 安装微软雅黑和 Emoji 字体"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 安装阿里巴巴普惠体和 Emoji 字体"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        read -p "请输入选项： " font_choice
        case $font_choice in
            1) install_fonts ;;
            2) install_alibaba_fonts ;;
            0) break ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！" ;;
        esac
        if [ "$oneshot" = true ]; then
            break
        fi
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ===================== biliup‑rs 相关函数 =====================

# 哔哩哔哩快速上传：用户选择视频目录及文件后调用 biliup 工具上传
biliup_upload() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice
    local video_dir
    case $type_choice in
        1) video_dir="$DMR_DIR/直播回放" ;;
        2) video_dir="$DMR_DIR/直播回放（弹幕版）" ;;
        3)
            read -p "请输入视频所在目录的绝对路径: " video_dir
            ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！" ; return 1 ;;
    esac

    local files=()
    local video_paths=()

    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录不存在：$video_dir${NC}"; return 1; }
        mapfile -t files < <(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)
        if [ ${#files[@]} -eq 0 ]; then
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录下没有视频文件！${NC}"
            return 1
        fi
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
            local valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}无效选项：$num${NC}"
                    valid=false
                    break
                fi
            done
            $valid && break
        done
        local all_option=$(( ${#files[@]} + 1 ))
        if [[ " ${selections[@]} " =~ " $all_option " ]]; then
            video_paths=("${files[@]}")
        else
            for num in "${selections[@]}"; do
                if (( num >= 1 && num <= ${#files[@]} )); then
                    video_paths+=("${files[$((num-1))]}")
                else
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项：$num"
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

    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入工具目录失败！"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}执行命令：./biliup upload ${video_paths[*]} --tid $tid --tag \"$tags\"${NC}"
    ./biliup upload "${video_paths[@]}" --tid "$tid" --tag "$tags"
}

# 哔哩哔哩视频追加上传：允许用户追加上传视频到已上传的视频中
biliup_append() {
    require_installed || return 1
    local last_bv_file="$BILIUP_DIR/last_bv.txt"
    local bv
    if [ -f "$last_bv_file" ]; then
        local last_bv
        last_bv=$(cat "$last_bv_file")
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 检测到上一次使用的视频BV号：${last_bv}"
        echo "1) 使用上一次的BV号"
        echo "2) 重新输入BV号"
        read -p "请选择选项 (1/2): " choice_bv
        if [ "$choice_bv" = "1" ]; then
            bv="$last_bv"
        elif [ "$choice_bv" = "2" ]; then
            while true; do
                read -p "请输入视频BV号: " bv
                [[ "$bv" =~ ^BV ]] && break || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效的BV号，请确保以BV开头！"
            done
            echo "$bv" > "$last_bv_file"
        else
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！"
            return 1
        fi
    else
        while true; do
            read -p "请输入视频BV号: " bv
            [[ "$bv" =~ ^BV ]] && break || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效的BV号，请确保以BV开头！"
        done
        echo "$bv" > "$last_bv_file"
    fi

    local video_paths=()
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}请选择视频所在目录类型：${NC}"
    echo "1. 直播回放"
    echo "2. 直播回放弹幕版"
    echo "3. 其他路径"
    read -p "请输入选项 (1/2/3): " type_choice

    local files=()
    case $type_choice in
        1)
            local video_dir="$DMR_DIR/直播回放"
            [ ! -d "$video_dir" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录不存在：$video_dir${NC}"; return 1; }
            mapfile -t files < <(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)
            ;;
        2)
            local video_dir2="$DMR_DIR/直播回放（弹幕版）"
            [ ! -d "$video_dir2" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录不存在：$video_dir2${NC}"; return 1; }
            mapfile -t files < <(find "$video_dir2" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)
            ;;
        3)
            read -p "请输入视频文件的绝对路径（多个请用空格分隔）： " -a video_paths
            ;;
        *)
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！"
            return 1
            ;;
    esac

    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        if [ ${#files[@]} -eq 0 ]; then
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录下没有视频文件！${NC}"
            return 1
        fi
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
            local valid=true
            for num in "${selections[@]}"; do
                if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                    echo -e "${RED}无效选项：$num${NC}"
                    valid=false
                    break
                fi
            done
            $valid && break
        done
        local all_option=$(( ${#files[@]} + 1 ))
        if [[ " ${selections[@]} " =~ " $all_option " ]]; then
            video_paths=("${files[@]}")
        else
            for num in "${selections[@]}"; do
                if (( num >= 1 && num <= ${#files[@]} )); then
                    video_paths+=("${files[$((num-1))]}")
                else
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项：$num"
                    return 1
                fi
            done
        fi
    fi

    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入工具目录失败！"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}执行命令：./biliup append --vid \"$bv\" ${video_paths[*]}${NC}"
    ./biliup append --vid "$bv" "${video_paths[@]}"
}

# biliup‑rs 工具子菜单：展示版本信息及相关上传、登录、更新选项
biliup_menu() {
    while true; do
        show_header
        echo -e "${PINK}=== biliup-rs ===${NC}"
        echo -e "${CYAN}当前 biliup-rs 版本信息：${NC}"
        cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无法进入工具目录"; return 1; }
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
                cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无法进入工具目录"; return 1; }
                ./biliup login
                ;;
            9) update_biliup_rs ;;
            0) return 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！" ;;
        esac
        [ "$sub_choice" != "0" ] && read -n 1 -s -r -p "按任意键继续..."
    done
}

# ===================== 新增：安装 JavaScript 解释器和 JS 引擎 =====================
install_js_engine() {
    read -p "是否进行安装 JavaScript 解释器和 JS 引擎？(y/n): " js_ans
    if [[ "$js_ans" =~ ^[Yy]$ ]]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装 Node.js 和 npm...${NC}"
         sudo apt install -y nodejs npm || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} Node.js 和 npm 安装失败！"; return 1; }
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}切换到主目录并激活虚拟环境...${NC}"
         cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录失败！"; return 1; }
         source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; return 1; }
         pip install quickjs || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} quickjs 安装失败！"; deactivate; return 1; }
         deactivate
         echo -e "${GREEN}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}JavaScript解释器和 JS 引擎安装完成！${NC}"
    else
         echo -e "${YELLOW}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消安装。${NC}"
    fi
    # 此处去掉原本的“按任意键返回菜单”提示
}

# ===================== 状态及主菜单 =====================

# 显示头部信息：清屏后显示版本、提交、更新日期、项目地址及 Python 版本信息
show_header() {
    clear
    echo -e "${PINK}==============================${NC}"
    echo -e "${BLUE}${BOLD}DanmakuRender v5${NORMAL}"
    echo -e "${PINK}最新提交日期${NC} ${BOLD}${commit_time}"
    echo -e "${PINK}版本号  ${NC} ${BOLD}${release_version}"
    echo -e "${PINK}更新日期${NC} ${BOLD}${release_time}"
    echo -e "${PURPLE}${BOLD}项目原地址${NC}"
    echo -e "${BLUE}${BOLD}${DMR_GITHUB_BASE}${NC}"
    local python_version
    python_version=$(get_python_version)
    if [[ "$python_version" == "not_installed" ]]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} Python3 未安装或未检测到！${NC}"
    else
        echo -e "${YELLOW}${BOLD}当前Python版本：${BOLD}${python_version}${NC}\n"
    fi
}

# 显示当前状态：检查安装目录、运行状态及配置情况
show_status() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${YELLOW}${BOLD}当前状态：DanmakuRender v5 未安装${NC}${NORMAL}"
    elif pgrep -f "$DMR_CMD" > /dev/null; then
        local pid
        pid=$(pgrep -f "$DMR_CMD" | head -n 1)
        echo -e "${GREEN}${BOLD}当前状态：正在运行 (PID: $pid)${NC}${NORMAL}"
    else
        echo -e "${RED}${BOLD}当前状态：未运行${NC}${NORMAL}"
    fi

    if [ -d "$DMR_DIR" ]; then
        echo -e "配置文件：$(check_config && echo -e "${GREEN}${BOLD}已完成配置${NC}${NORMAL}" || echo -e "${RED}${BOLD}未正确配置${NC}${NORMAL}")"
        echo -e "上一次安装/更新日期：${PINK}${BOLD}${install_date}${NC}"
    fi
}

# 检查是否已经安装 DanmakuRender v5，未安装则提示用户
require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} DanmakuRender v5 未安装，请先选择安装选项（1）进行安装！${NC}"
        return 1
    fi
    return 0
}

# 主菜单：循环显示菜单供用户选择操作
main_menu() {
    check_dependencies || { echo -e "${RED}${BOLD}[ERROR]${NC} 依赖检查失败，脚本终止"; exit 1; }
    fetch_github_times
    get_install_date

    local skip_read=false
    while true; do
        show_header
        show_status
        echo -e "${CYAN}${BOLD}请选择操作：${NC}${NORMAL}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 安装DanmakuRender v5"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 启动/停止录制"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 查看实时日志 (按Q退出)"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL} 手动渲染视频"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL} 运行一次测试"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL} 删除回放/渲染视频文件"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL} biliup-rs"
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL} 字体安装"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} 安装JavaScript解释器和JS引擎"
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL}${LIGHT_BLUE} 更新DanmakuRender v5"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD} 卸载DanmakuRender v5"
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
                                view_log; skip_read=true
                            fi
                        fi
                    else
                        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 配置文件未正确配置"
                    fi
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            3)
                if require_installed; then
                    view_log; skip_read=true
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
                    biliup_menu; skip_read=true
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            8)
                if require_installed; then
                    font_menu
                else
                    echo -e "${RED}请先安装DanmakuRender v5!${NC}"
                fi
                skip_read=false
                ;;
            9)
                if require_installed; then
                    install_js_engine
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
                fetch_github_times
                get_install_date
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
            0) exit 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项！"; skip_read=false ;;
        esac

        if [ "$skip_read" = false ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# ===================== 脚本入口 =====================
main_menu
