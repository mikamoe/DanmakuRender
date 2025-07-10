#!/usr/bin/env bash
# ===================== 配置变量 =====================
# 设置 Bash 严格模式：
# -e: 任何命令失败时立即退出。
# -u: 尝试使用未设置的变量时报错并退出。
# -o pipefail: 管道命令中任何一个命令失败时，整个管道返回非零状态码。
set -euo pipefail

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

# biliup-rs 项目信息（用于动态获取最新版本）
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup-rs"
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases/download"

# GitHub 克隆地址
DMR_GITHUB_BASE="https://github.com/SmallPeaches/DanmakuRender"

# 字体下载链接配置（使用 GitHub raw 链接）
FONT_MSYH_URL="https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/msyh.ttf" # 未直接使用，但保留
FONT_ALIBABA_URL="https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/AlibabaPuHuiTi-3-85-Bold.ttf" # 未直接使用，但保留

# ANSI 颜色和样式设置
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
ORANGE='\033[38;5;208m'

# Global variables for GitHub info
commit_sha=""
commit_time=""
commit_message=""
release_version=""
release_time=""
install_date="" # Track installation date for display

# Global variables for biliup-rs version info
BILIUP_LOCAL_VERSION=""
BILIUP_REMOTE_VERSION=""

# ===================== 辅助函数 =====================

# 检查并安装必要的系统依赖工具
check_dependencies() {
    local required_tools=("jq" "curl" "git")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool，正在安装...${NC}"
            # 尝试安装，如果失败则退出
            sudo apt update && sudo apt install -y "$tool" || {
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${RED}$tool 安装失败！请手动安装后重试。${NC}"
                return 1
            }
        fi
    done
    return 0
}

# 获取 Python 版本信息
get_python_version() {
    if command -v python3 &>/dev/null; then
        echo "Python $(python3 -V 2>&1 | awk '{print $2}')"
    else
        echo "not_installed"
    fi
}

# 将 UTC 时间转换为北京时间
convert_to_beijing_time() {
    local raw_time="$1"
    if [ -z "$raw_time" ]; then
        echo "获取失败"
        return
    fi
    local converted
    # 尝试使用 Asia/Shanghai 时区转换
    converted=$(TZ=Asia/Shanghai date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -n "$converted" ]; then
        echo "$converted"
    else
        # 如果失败，尝试使用系统默认时区转换
        converted=$(date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
        if [ -n "$converted" ]; then
            echo "$converted (可能为服务器本地时间)"
        else
            echo "获取失败"
        fi
    fi
}

# 回滚安装（用于全新安装失败时清理）
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装过程中出错，正在回滚...${NC}"
    if [ -d "$DMR_DIR" ]; then
        sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}回滚删除安装目录失败！${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装目录不存在，无需回滚删除。${NC}"
    fi
}

# 回滚更新（恢复备份）
rollback_update() {
    local backup_dir="$1"
    local configs_backup="$2"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}更新失败，正在回滚更新...${NC}"

    # 删除可能已拉下来的新目录（如果 rsync 失败，可能存在部分新文件）
    if [ -d "$DMR_DIR" ]; then
        sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除临时目录：$DMR_DIR${NC}"
    fi

    # 恢复整个项目备份
    if [ -d "$backup_dir" ]; then
        sudo mv "$backup_dir" "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已恢复项目目录：$DMR_DIR${NC}"
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到备份目录：$backup_dir，回滚失败！${NC}"
    fi

    # 恢复 configs（如果存在）
    if [ -d "$configs_backup" ]; then
        # 确保先删除可能存在的新configs目录，再恢复旧的
        sudo rm -rf "$DMR_DIR/configs" 2>/dev/null || true # 忽略删除不存在目录的错误
        sudo mv "$configs_backup" "$DMR_DIR/configs" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已恢复配置文件：$DMR_DIR/configs${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 回滚完成，请检查后重试。"
}

# 检查配置文件是否存在且包含 DanmakuRender 相关文件
check_config() {
    if [ ! -d "$DMR_DIR/configs" ]; then
        return 1
    fi
    # 检查 configs 目录下是否有以 "DMR" 结尾的文件
    if find "$DMR_DIR/configs" -maxdepth 1 -type f -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 从 GitHub API 获取 DanmakuRender 的最新提交和发布信息
fetch_github_times() {
    local branch_info
    branch_info=$(curl -sfL "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/branches/$GITHUB_BRANCH")
    if [[ -n "$branch_info" ]]; then
        local raw_time
        raw_time=$(jq -r '.commit.commit.author.date // empty' <<< "$branch_info")
        commit_time=$(convert_to_beijing_time "$raw_time")
        commit_message=$(jq -r '.commit.commit.message // empty' <<< "$branch_info")
        commit_sha=$(jq -r '.commit.sha // empty' <<< "$branch_info")
    else
        commit_time="获取失败"
        commit_message="获取失败"
        commit_sha=""
    fi

    local release_info
    release_info=$(curl -sfL "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest")
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

# 获取本地安装日期
get_install_date() {
    install_date=""
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
            local rfc_date
            rfc_date=$(date -d "@$timestamp" --rfc-3339=seconds 2>/dev/null)
            if [ -n "$rfc_date" ]; then
                install_date=$(convert_to_beijing_time "$rfc_date")
            else
                install_date="无法解析日期"
            fi
        else
            install_date="无效日期记录"
        fi
    fi
}

# 从 GitHub API 获取 biliup-rs 的本地和远程版本信息
fetch_biliup_times() {
    # 如果 biliup 可执行文件存在且可执行
    if [ -x "$BILIUP_DIR/biliup" ]; then
        # 获取本地版本号（假设输出类似 “biliup-cli 0.2.2”）
        local_ver=$("$BILIUP_DIR/biliup" -V 2>&1 | awk '{print $NF}')
        BILIUP_LOCAL_VERSION="$local_ver"

        # 从 GitHub API 获取最新 Release 信息
        local latest_info
        latest_info=$(curl -sfL "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
        if [[ -n "$latest_info" ]]; then
            # 取 tag_name 作为远程最新版本号（如 “v0.2.3”）
            remote_ver=$(echo "$latest_info" | jq -r '.tag_name // empty')
            # 如有前缀 “v”，去掉以便对比（可选，但通常版本号对比时会去掉）
            remote_ver="${remote_ver#v}"
            BILIUP_REMOTE_VERSION="$remote_ver"
        else
            BILIUP_REMOTE_VERSION=""
        fi
    else
        # 未安装 biliup，清空版本变量
        BILIUP_LOCAL_VERSION=""
        BILIUP_REMOTE_VERSION=""
    fi
}

# ===================== 系统安装及更新函数 =====================

# 检查并安装 DanmakuRender 运行所需的系统工具
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查系统依赖工具...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar" "xz-utils" "git")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool ...${NC}"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}正在尝试安装缺失的工具: ${missing_tools[*]}${NC}"
        sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！可能需要手动运行。${NC}"; return 1; }
        sudo apt install -y "${missing_tools[@]}" || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}一个或多个工具 (${missing_tools[*]}) 安装失败！请尝试手动安装。${NC}"
            return 1
        }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}缺失工具安装完成或已尝试安装。${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}所有必要的系统依赖工具已安装。${NC}"
    fi
    return 0
}

# 安装或更新 biliup-rs 工具
install_biliup_rs() {
    sudo mkdir -p "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建工具目录失败: $BILIUP_DIR${NC}"; return 1; }
    pushd "$BILIUP_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入工具目录失败: $BILIUP_DIR${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}获取 biliup-rs 最新版本信息...${NC}"
    local latest_info
    latest_info=$(curl -sfL "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}获取 biliup-rs 最新版本信息失败！${NC}"
        popd > /dev/null || true
        return 1
    fi

    local latest_version
    latest_version=$(jq -r '.tag_name' <<< "$latest_info")
    if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解析 biliup-rs 版本失败！${NC}"
        popd > /dev/null || true
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}最新 biliup-rs 版本：${GREEN}${latest_version}${NC}"

    # 检查当前版本是否已是最新
    if [ -f "./biliup" ] && ./biliup -V 2>/dev/null | grep -q "$latest_version"; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已经是最新版本 biliup-rs (${latest_version})。${NC}"
        popd > /dev/null || true
        return 0
    fi

    local arch
    arch=$(uname -m)
    local asset_suffix=""
    case "$arch" in
        aarch64)    asset_suffix="aarch64-linux.tar.xz" ;;
        armv7l|armv6l) asset_suffix="arm-linux.tar.xz" ;;
        x86_64)
            if ldd --version 2>&1 | grep -qi 'musl'; then
                asset_suffix="x86_64-linux-musl.tar.xz"
            else
                asset_suffix="x86_64-linux.tar.xz"
            fi
            ;;
        *)  echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}不支持的架构：$arch${NC}"; popd > /dev/null || true; return 1 ;;
    esac

    # 从 API 响应中查找正确的资源下载 URL
    local download_url
    download_url=$(jq -r --arg suffix "$asset_suffix" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' <<< "$latest_info")

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到适用于架构 ${arch} (${asset_suffix}) 的资源文件！${NC}"
        # 回退到推测的 URL
        local asset_file="biliup-${latest_version}-${asset_suffix}"
        download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}尝试使用推测的 URL: ${download_url}${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}找到资源文件 URL: ${download_url}${NC}"
    fi

    local asset_filename
    asset_filename=$(basename "$download_url")

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 biliup-rs (${asset_filename})...${NC}"
    curl -fLo "$asset_filename" "$download_url" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载 biliup-rs 失败！${NC}"
        rm -f "$asset_filename" || true
        popd > /dev/null || true
        rollback_installation # 下载失败也尝试回滚
        return 1
    }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在解压 ${asset_filename}...${NC}"
    tar -xJf "$asset_filename" --strip-components=1 || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压 biliup-rs 失败！${NC}"
        rm -f "$asset_filename" || true
        popd > /dev/null || true
        rollback_installation # 解压失败也尝试回滚
        return 1
    }
    rm -f "$asset_filename" || true

    if [ ! -f "./biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压后未找到 'biliup' 可执行文件！${NC}"
        popd > /dev/null || true
        rollback_installation
        return 1
    fi
    chmod +x ./biliup || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}设置 'biliup' 权限失败！${NC}"
        popd > /dev/null || true
        rollback_installation
        return 1
    }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}安装/更新 biliup-rs 完成！${NC}"
    popd > /dev/null || true
    return 0
}

# 更新 DanmakuRender v5
update_dmr() {
    require_installed || return 1

    # 1. 确保 rsync 已安装
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查 rsync 依赖...${NC}"
    if ! command -v rsync &>/dev/null; then
        echo -e "${YELLOW}未找到 rsync，正在安装...${NC}"
        sudo apt update || { echo -e "${RED}apt update 失败，请手动安装 rsync。${NC}"; return 1; }
        sudo apt install -y rsync || { echo -e "${RED}rsync 安装失败，请手动安装后重试。${NC}"; return 1; }
        echo -e "${GREEN}rsync 安装完成！${NC}"
    else
        echo -e "${GREEN}rsync 已安装。${NC}"
    fi

    # 2. 询问确认更新
    read -p "$(echo -e "${YELLOW}是否确认更新 DanmakuRender v5？(y/n): ${NC}")" confirm_update
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消更新操作。${NC}"
        return 0
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}开始更新 DanmakuRender v5...${NC}"

    # 3. 停止运行中的进程
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并停止运行中的进程...${NC}"
    if pgrep -f "$DMR_CMD" > /dev/null; then
        stop_dmr || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}停止进程失败！更新中止。${NC}"
            return 1
        }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已成功停止运行中的进程。${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}当前没有运行中的进程。${NC}"
    fi

    # 4. 创建完整备份目录 (临时备份，更新成功后删除)
    local backup_dir="/opt/DanmakuRender_backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建临时完整备份目录: ${backup_dir}${NC}"
    sudo mkdir -p "$backup_dir" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建备份目录失败！${NC}"
        return 1
    }

    # 5. 单独备份 configs 文件夹
    local configs_backup_root="${DMR_DIR}/configs_backups"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local configs_backup="${configs_backup_root}/configs_backup_${timestamp}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建 configs 备份根目录（若不存在）: ${configs_backup_root}${NC}"
    sudo mkdir -p "$configs_backup_root" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建 configs_backups 根目录失败！${NC}"
        return 1
    }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}备份配置文件到: ${configs_backup}${NC}"
    sudo cp -r "$DMR_DIR/configs" "$configs_backup" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}备份配置文件失败！${NC}"
        return 1
    }

    # 6. 备份整个 DMR 目录到临时备份目录
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}备份整个 DMR 目录到 ${backup_dir}...${NC}"
    sudo cp -r "$DMR_DIR" "$backup_dir" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}备份 DMR 目录失败！${NC}"
        return 1
    }

    # 7. 拉取最新代码并覆盖
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}拉取最新代码...${NC}"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    # 确保临时目录在函数退出时被清理
    trap "rm -rf '$tmp_dir'" EXIT

    if ! git clone --depth 1 -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$tmp_dir"; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}克隆最新代码失败！请检查网络、权限或仓库地址/分支。${NC}"
        rollback_update "$backup_dir" "$configs_backup"
        return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}覆盖现有文件...${NC}"
    # 使用 rsync 排除 configs 目录，以保留用户配置
    if ! sudo rsync -a --exclude='configs' "$tmp_dir/" "$DMR_DIR/"; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}文件覆盖失败！${NC}"
        rollback_update "$backup_dir" "$configs_backup"
        return 1
    fi
    # 临时目录将在 trap 触发时清理

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}更新成功完成！${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}配置文件备份存放于：${configs_backup}${NC}"

    # 8. 删除临时完整备份并刷新安装日期
    sudo rm -rf "$backup_dir" || true # 忽略删除失败的错误
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录安装日期失败！(权限问题？)${NC}"
    }
    # 刷新全局变量
    fetch_github_times
    get_install_date

    trap - EXIT # 成功后移除 trap
    return 0
}

# 全新安装 DanmakuRender v5
install_dmr() {
    local rollback_needed=true
    # 仅在非零退出码（出错或被 SIGHUP 杀掉）且 rollback_needed 仍为 true 时回滚
    trap 'if [[ "$rollback_needed" == true && $? -ne 0 ]]; then rollback_installation; fi' EXIT

    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}DanmakuRender V5 似乎已经安装在 ${DMR_DIR}！${NC}"
        read -p "$(echo -e "${YELLOW}是否要重新安装 Python 依赖？(y/n, 默认n): ${NC}")" reinstall_choice
        reinstall_choice=${reinstall_choice:-n}
        if [[ "$reinstall_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在重新安装 Python 依赖...${NC}"
            pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; trap - EXIT; return 1; }
            if [ ! -d "venv" ] || [ ! -f "venv/bin/activate" ]; then
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}虚拟环境 'venv' 不存在或不完整！无法重新安装依赖。请尝试完整卸载后重新安装。${NC}"
                popd > /dev/null || true; trap - EXIT; return 1
            fi
            if [ ! -f "requirements.txt" ]; then
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'requirements.txt' 文件不存在！无法重新安装依赖。${NC}"
                popd > /dev/null || true; trap - EXIT; return 1
            fi
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
            # shellcheck source=/dev/null
            source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; popd > /dev/null || true; trap - EXIT; return 1; }
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}升级 pip...${NC}"
            pip install --quiet --upgrade pip || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} pip 升级失败，尝试继续..."
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}从 requirements.txt 安装依赖...${NC}"
            pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！${NC}"; deactivate || true; popd > /dev/null || true; trap - EXIT; return 1; }
            deactivate || true
            popd > /dev/null || true
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 依赖重新安装完成！${NC}"
            # 成功完成依赖安装后，取消回滚
            rollback_needed=false
            trap - EXIT
            return 0
        else
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消重新安装 Python 依赖。${NC}"
            rollback_needed=false
            trap - EXIT
            return 0
        fi
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}开始全新安装 DanmakuRender v5...${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并安装必要的系统工具...${NC}"
    check_install_tools || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}系统工具检查或安装失败！安装中止。${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}系统工具检查/安装完成。${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在使用 git clone 拉取 DanmakuRender ${GITHUB_BRANCH} 分支...${NC}"
    if ! git clone --depth 1 -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$DMR_DIR"; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}git clone 失败！请检查网络、权限或仓库地址/分支。${NC}"
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}代码拉取完成！${NC}"

    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入安装目录 $DMR_DIR 失败！"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建 Python 虚拟环境 (venv)...${NC}"
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建 Python 虚拟环境失败！${NC}"; popd > /dev/null || true; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境并安装 Python 依赖...${NC}"
    # shellcheck source=/dev/null
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; popd > /dev/null || true; return 1; }
    pip install --quiet --upgrade pip || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} pip 升级失败，尝试继续..."
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！请检查 'requirements.txt' 或网络。${NC}"; deactivate || true; popd > /dev/null || true; return 1; }
    else
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}未找到 requirements.txt 文件，跳过 Python 依赖安装。${NC}"
    fi
    deactivate || true
    popd > /dev/null || true

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 依赖安装完成。${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装/更新 biliup-rs...${NC}"
    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}biliup-rs 安装失败！${NC}"; return 1; }

    read -p "$(echo -e "${YELLOW}安装完成，是否额外安装 JavaScript 解释器 (Node.js) 和相关 Python 库 (quickjs)？(y/N): ${NC}")" js_choice
    js_choice=${js_choice:-n}
    if [[ "$js_choice" =~ ^[Yy]$ ]]; then
        install_js_engine || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}JavaScript 环境安装过程中可能出现问题。${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} ${GREEN}${BOLD}DanmakuRender v5 安装完成！${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 安装目录: ${GREEN}$DMR_DIR${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 如需渲染弹幕，请确保已安装合适的字体 (主菜单选项 8)。"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 首次运行前，请务必检查并修改 ${GREEN}${DMR_DIR}/configs/${NC} 目录下的配置文件！"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在记录安装日期..."
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录安装日期失败！(权限问题？)${NC}"
    }
    get_install_date

    # 提示用户添加快捷键
    echo -e "\n${CYAN}${BOLD}提示：您可以为本脚本添加一个快捷键 'd'。${NC}"
    echo -e "${CYAN}在您的 shell 配置文件 (例如 ~/.bashrc 或 ~/.zshrc) 中添加以下行：${NC}"
    echo -e "  ${GREEN}alias d='bash $(readlink -f "$0")'${NC}"
    echo -e "${CYAN}然后运行 'source ~/.bashrc' (或对应的文件) 使其生效。${NC}"

    # 安装一切正常，取消回滚
    rollback_needed=false
    trap - EXIT

    return 0
}

# 卸载 DanmakuRender v5
uninstall_dmr() {
    require_installed || return 1
    echo -e "${RED}${BOLD}警告：这将永久删除 DanmakuRender v5 的所有文件，包括程序、配置、日志、工具和可能存在的备份！${NC}"
    echo -e "${RED}${BOLD}此操作不会删除 '直播回放' 或 '直播回放（弹幕版）' 目录中的视频文件。${NC}"
    read -p "$(echo -e "${YELLOW}确定要完全卸载 DanmakuRender v5 吗？(请输入 'yes' 确认): ${NC}")" confirm
    # 严格确认，必须输入 'yes'
    if [[ "$confirm" != "yes" ]]; then
         echo -e "${YELLOW}输入不匹配 'yes'，取消卸载。${NC}"
         return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在停止可能在运行的 DanmakuRender 进程...${NC}"
    # 停止进程
    if pgrep -f "$DMR_CMD" > /dev/null; then
        stop_dmr || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}停止进程时遇到问题，将继续尝试卸载。${NC}"
        sleep 1 # 稍作等待
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}DanmakuRender 未在运行。${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在删除安装目录: ${DMR_DIR}...${NC}"
    # 使用 sudo 删除目录
    sudo rm -rf "$DMR_DIR"
    # 验证删除
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}DanmakuRender v5 卸载完成！${NC}"
        # 重置安装日期显示变量
        install_date=""
        # 提示用户移除快捷键
        echo -e "\n${CYAN}${BOLD}提示：如果您之前添加了 'd' 快捷键，请在您的 shell 配置文件中移除以下行：${NC}"
        echo -e "  ${RED}alias d='bash $(readlink -f "$0")'${NC}"
        echo -e "${CYAN}然后运行 'source ~/.bashrc' (或对应的文件) 使其生效。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}卸载失败！目录 ${DMR_DIR} 仍然存在。请检查权限或手动删除。${NC}"
        return 1
    fi
}

# ===================== JavaScript 环境安装函数 ===============
install_js_engine() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}开始安装 JavaScript 环境...${NC}"
    
    # 安装 Node.js
    if ! command -v node &>/dev/null; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 Node.js，正在安装...${NC}"
        # 使用 NodeSource 官方脚本安装 LTS 版本 Node.js
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt install -y nodejs || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Node.js 安装失败！${NC}"
            return 1
        }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Node.js 安装完成！${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Node.js 已安装。${NC}"
    fi

    # 安装 quickjs Python 包
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装 quickjs Python 包...${NC}"
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }
    # shellcheck source=/dev/null
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null || true; return 1; }
    
    pip install quickjs || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}quickjs 安装失败！${NC}"
        deactivate || true
        popd > /dev/null || true
        return 1
    }
    
    deactivate || true
    popd > /dev/null || true
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}JavaScript 环境安装完成！${NC}"
    return 0
}

# ===================== 运行与测试管理函数 =====================
start_dmr() {
    require_installed || return 1
    # 检查配置文件有效性
    if ! check_config; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}配置文件检查失败或未配置！请在 ${DMR_DIR}/configs/ 中正确配置 *DMR* 文件后重试。${NC}"
         return 1
    fi
    # 检查是否已在运行
    if pgrep -f "$DMR_CMD" > /dev/null; then
        local existing_pid
        existing_pid=$(pgrep -f "$DMR_CMD" | head -n 1)
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}DanmakuRender 似乎已在运行 (PID: $existing_pid)。无需重复启动。${NC}"
        return 1
    fi

    # 进入工作目录
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    # shellcheck source=/dev/null
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null || true; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}使用 nohup 在后台启动 ${DMR_CMD}...${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 日志将输出到: ${GREEN}${DMR_DIR}/${LOG_FILE}${NC}"
    # 使用nohup后台启动程序
    nohup "$DMR_CMD" > "$LOG_FILE" 2>&1 &
    local pid=$! # 获取后台进程PID

    # 检查进程是否启动成功
    sleep 1 # 等待1秒防止误判
    if ps -p "$pid" > /dev/null; then
        # 将PID写入文件
        echo "$pid" > "$DMR_DIR/dmr.pid" || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} 无法写入 PID 文件 ${DMR_DIR}/dmr.pid (权限问题?)${NC}"
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}启动成功！进程 PID: $pid${NC}"
        
        # 实时显示日志功能
        echo -e "\n${CYAN}正在实时显示日志 (按 q 退出查看)...${NC}"
        tail -f "$LOG_FILE" &  # 后台运行tail命令
        local tail_pid=$!
        
        # 监听键盘输入
        while true; do
            # read -t 1 -n 1 key: 尝试读取一个字符，超时1秒。-n 1 表示只读取一个字符，-s 表示不回显，-r 表示原始输入（不处理反斜杠）
            # 注意：在某些终端环境下，-t 1 可能导致 CPU 占用较高。对于简单的退出机制，通常可以接受。
            read -t 1 -n 1 key || true # 允许 read 失败（超时）
            if [[ "$key" == "q" ]]; then
                kill "$tail_pid" 2>/dev/null || true # 停止tail进程，忽略错误
                break
            fi
            # 如果 tail 进程已经退出，也结束循环
            if ! ps -p "$tail_pid" > /dev/null; then
                break
            fi
        done
        
        deactivate || true
        popd > /dev/null || true
        return 0 # 返回成功状态
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}启动失败！进程未能成功运行。请检查 ${LOG_FILE} 获取错误信息。${NC}"
        # 清理可能创建的pid文件
        rm -f "$DMR_DIR/dmr.pid" || true
        deactivate || true
        popd > /dev/null || true
        return 1 # 返回失败状态
    fi
}

# 停止 DanmakuRender 进程
stop_dmr() {
    require_installed || return 1
    local pid_file="$DMR_DIR/dmr.pid"
    local pid_to_kill=""
    local stopped=false

    # 首先尝试从pid文件中获取PID
    if [ -f "$pid_file" ]; then
        pid_to_kill=$(cat "$pid_file")
        if [[ "$pid_to_kill" =~ ^[0-9]+$ ]]; then
            # 检查进程是否存在
            if ps -p "$pid_to_kill" > /dev/null; then
                # 检查进程命令是否匹配（基础验证，防止误杀）
                 if ps -p "$pid_to_kill" -o cmd= | grep -q -F "$DMR_CMD"; then
                    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在尝试停止 PID 文件中的进程: $pid_to_kill...${NC}"
                    # 先尝试发送TERM信号优雅停止
                    kill "$pid_to_kill" || true # 允许失败
                    sleep 1 # 等待1秒
                    if ! ps -p "$pid_to_kill" > /dev/null; then
                        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}进程 $pid_to_kill 已停止 (TERM)。${NC}"
                        stopped=true
                    else
                        # TERM无效时强制KILL
                        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}进程 $pid_to_kill 未响应 TERM 信号，强制停止 (KILL)...${NC}"
                        kill -9 "$pid_to_kill" || true # 允许失败
                        sleep 1
                        if ! ps -p "$pid_to_kill" > /dev/null; then
                             echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}进程 $pid_to_kill 已停止 (KILL)。${NC}"
                             stopped=true
                        else
                             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无法停止进程 $pid_to_kill！${NC}"
                        fi
                    fi
                 else
                     echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}PID 文件中的进程 $pid_to_kill 存在，但命令不匹配 ${DMR_CMD}。可能不是目标进程，跳过。${NC}"
                     pid_to_kill="" # 重置pid_to_kill以便后续使用pkill
                 fi
            else
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}PID 文件中的进程 $pid_to_kill 不存在。可能已停止。${NC}"
                stopped=true # 如果PID不存在则认为已停止
            fi
        else
             echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}PID 文件 ($pid_file) 包含无效内容: '$pid_to_kill'。${NC}"
             pid_to_kill="" # 重置pid_to_kill
        fi
        # 无论是否成功停止，都清理pid文件
        rm -f "$pid_file" || true
    fi

    # 如果通过pid文件未能停止，尝试使用pkill作为备用方案
    if [ "$stopped" = false ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未通过 PID 文件停止进程，尝试使用 pkill 查找 '${DMR_CMD}'...${NC}"
        # 先用pgrep检查是否有匹配进程
        if pgrep -f "$DMR_CMD" > /dev/null; then
            # 使用pkill根据命令字符串停止
            pkill -f "$DMR_CMD" || true # 允许失败
            sleep 1
            # 检查是否已停止
            if ! pgrep -f "$DMR_CMD" > /dev/null; then
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已使用 pkill 停止匹配 '${DMR_CMD}' 的进程。${NC}"
                stopped=true
            else
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}使用 pkill 停止进程失败！请手动检查。${NC}"
            fi
        else
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}未找到正在运行的匹配 '${DMR_CMD}' 的进程。${NC}"
            stopped=true # 无需停止
        fi
    fi

    # 返回状态
    if [ "$stopped" = true ]; then
        return 0
    else
        return 1
    fi
}

# 停止额外录制/ffmpeg 相关进程
stop_extra_processes() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 检查并停止带 ${YELLOW}“正在录制”${NC}${NORMAL} 关键字的进程…"
    # 列出所有包含 “正在录制” 的进程（排除 grep 自身），提取 PID 并尝试优雅终止
    for pid in $(ps aux | grep -v grep | grep '正在录制' | awk '{print $2}'); do
        echo -e "${YELLOW} 发现 PID=$pid，发送 TERM…${NC}"
        kill "$pid" || true && echo -e "${GREEN} 进程 $pid 已停止。${NC}"
    done

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 检查并停止带 ${YELLOW}“ffmpeg”${NC}${NORMAL} 关键字的进程…"
    for pid in $(ps aux | grep -v grep | grep 'ffmpeg' | awk '{print $2}'); do
        echo -e "${YELLOW} 发现 PID=$pid，发送 TERM…${NC}"
        kill "$pid" || true && echo -e "${GREEN} 进程 $pid 已停止。${NC}"
    done
}

# 日志查看函数（修复 q 无法退出问题）
view_log() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}按 q 键退出日志查看${NC}"

    # 使用 tail -F 实时跟踪日志
    tail -n 50 -F "$DMR_DIR/$LOG_FILE" &
    local tail_pid=$!

    # 确保在退出时恢复终端设置
    trap "stty echo icanon; wait '$tail_pid' 2>/dev/null || true" EXIT

    # 切换终端到无缓冲模式，实时读取单字符
    stty -echo -icanon time 0 min 0
    while true; do
        # 读取一个字符（如果有）
        IFS= read -r -n1 key || true # 允许 read 失败（超时）
        if [[ "$key" == "q" ]]; then
            kill "$tail_pid" 2>/dev/null || true # 停止tail进程，忽略错误
            break
        fi
        # 如果 tail 进程已经退出，也结束循环
        if ! ps -p "$tail_pid" > /dev/null; then
            break
        fi
    done
    # 恢复终端设置（由 trap 处理）
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 日志查看已退出。"
    trap - EXIT # 成功退出后移除 trap
}

# 运行 DanmakuRender 的测试脚本
run_test() {
    require_installed || return 1
    local test_script="dryrun.py"
    local test_script_path="$DMR_DIR/$test_script"

    if [ ! -f "$test_script_path" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}测试脚本 ${test_script_path} 不存在！${NC}"; return 1;
    fi

    # 增加确认提示
    read -p "$(echo -e "${YELLOW}是否确认运行测试脚本？(y/n): ${NC}")" confirm_test
    if [[ ! "$confirm_test" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消测试运行。${NC}"
        return 0
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}准备运行测试脚本: ${test_script}...${NC}"
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    # shellcheck source=/dev/null
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null || true; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行 ${test_script}...${NC}"
    # 执行脚本
    python3 "$test_script"
    local exit_code=$? # 捕获测试脚本的退出码

    deactivate || true
    popd > /dev/null || true

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}测试运行完成 (退出码: 0)。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}测试运行失败 (退出码: $exit_code)！请检查上面的输出。${NC}";
        return 1
    fi
}

# 手动渲染视频
manual_render() {
    require_installed || return 1
    local render_script="render_only.py"
    local render_script_path="$DMR_DIR/$render_script"

    if [ ! -f "$render_script_path" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}手动渲染脚本 ${render_script_path} 不存在！${NC}"; return 1;
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}准备运行手动渲染脚本: ${render_script}...${NC}"
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    # shellcheck source=/dev/null
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null || true; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行 ${render_script}... (这可能需要一些时间)${NC}"
    # 执行脚本
    python3 "$render_script"
    local exit_code=$? # 捕获退出码

    deactivate || true
    popd > /dev/null || true

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}手动渲染运行完成 (退出码: 0)。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}手动渲染运行失败 (退出码: $exit_code)！请检查上面的输出。${NC}";
        return 1
    fi
}

# 删除回放及弹幕视频文件
delete_replays() {
    require_installed || return 1
    local replay_dir_plain="$DMR_DIR/直播回放"
    local replay_dir_danmaku="$DMR_DIR/直播回放（弹幕版）"
    local -a files_to_delete=() # Array to store full paths of files
    local file_index=0
    local found_any_files=false

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}检查目录内容:${NC}"
    echo "----------------------------------------"

    # Function to list files from a directory
    list_files_in_dir() {
        local dir="$1"
        if [ -d "$dir" ]; then
            echo -e "${PURPLE}目录: ${dir}${NC}"
            local files_in_current_dir=0
            # Using find to get files and iterate, safer than ls for parsing
            while IFS= read -r -d $'\0' file; do
                if [ -f "$file" ]; then # Ensure it's a regular file
                    files_to_delete+=("$file")
                    echo " $((++file_index))) $(basename "$file")"
                    found_any_files=true
                    ((files_in_current_dir++))
                fi
            done < <(find "$dir" -maxdepth 1 -type f -print0)

            if [ "$files_in_current_dir" -eq 0 ]; then
                echo "(空)"
            fi
        else
            echo -e "${YELLOW}目录不存在: ${dir}${NC}"
        fi
        echo "----------------------------------------"
    }

    list_files_in_dir "$replay_dir_plain"
    list_files_in_dir "$replay_dir_danmaku"

    if [ "$found_any_files" = false ]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}两个回放目录均为空或不存在，无需删除。${NC}"
         return 0
    fi

    echo -e "\n${YELLOW}请选择操作：${NC}"
    echo -e " ${RED}${BOLD}y/Y${NC}${YELLOW}: 删除 ${RED}所有${NC}${YELLOW}列出的视频文件 (不可恢复!)"
    echo -e " ${CYAN}数字 (如: 1 3 5)${NC}${YELLOW}: 删除指定序号的视频文件"
    echo -e " ${ORANGE}0${NC}${YELLOW}: 取消操作"
    read -p "$(echo -e "${CYAN}请输入您的选择 (默认取消): ${NC}")" confirm_or_select
    confirm_or_select=${confirm_or_select:-0} # Default to 0 (cancel)

    local delete_success=true

    case "$confirm_or_select" in
        [yY])
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${RED}正在删除所有文件...${NC}"
            for file_path in "${files_to_delete[@]}"; do
                sudo rm -f "$file_path" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 ${file_path} 失败！"; delete_success=false; }
            done
            ;;
        0)
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消删除操作。${NC}"
            return 1 # Indicate cancellation
            ;;
        *)
            local selected_indices=()
            # Split input by space and validate
            for num_str in $confirm_or_select; do
                if [[ "$num_str" =~ ^[0-9]+$ ]]; then
                    local idx=$((num_str - 1)) # Convert to 0-based index
                    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#files_to_delete[@]}" ]; then
                        selected_indices+=("$idx")
                    else
                        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效的序号: $num_str。请重新输入。${NC}"
                        return 1 # Invalid input, exit
                    fi
                else
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效输入: '$num_str'。请输入 'y/Y' 或数字序号。${NC}"
                    return 1 # Invalid input, exit
                fi
            done

            if [ ${#selected_indices[@]} -eq 0 ]; then
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未选择任何有效文件。${NC}"
                return 1
            fi

            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${RED}正在删除选定的文件...${NC}"
            for idx in "${selected_indices[@]}"; do
                local file_path="${files_to_delete[$idx]}"
                sudo rm -f "$file_path" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 ${file_path} 失败！"; delete_success=false; }
            done
            ;;
    esac

    if [ "$delete_success" = true ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已删除指定文件。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}删除过程中发生错误。${NC}"
        return 1
    fi
}


# 刷新字体缓存
refresh_font_cache() {
    if command -v fc-cache &>/dev/null; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 刷新字体缓存..."
        sudo fc-cache -f || true # 允许失败
    else
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} fc-cache 未找到，跳过刷新字体缓存。"
    fi
}

# 安装 Segoe UI Emoji 字体 （含已装检测与重装提示）
install_segoe_emoji() {
    # 检测安装状态
    if fc-list | grep -qi "Segoe UI Emoji"; then
        read -p "检测到已安装 Segoe UI Emoji，是否先卸载再重新安装？(y/N): " _c
        if [[ ! "$_c" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过 Segoe UI Emoji 安装。${NC}"
            return
        fi
        echo -e "${BLUE}[INFO]${NC} 卸载现有 Segoe UI Emoji..."
        sudo rm -f /usr/share/fonts/truetype/microsoft/seguiemj.ttf || true # 允许文件不存在
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 安装 Segoe UI Emoji 字体"
    echo " 0) 返回字体菜单"
    echo " 1) Win10 版"
    echo " 2) Win11 版"
    read -p "$(echo -e "${CYAN}请选择要安装的版本 (0-2, 默认 2): ${NC}")" seg_choice
    seg_choice=${seg_choice:-2}

    if [[ "$seg_choice" == "0" ]]; then
        echo -e "${YELLOW}已取消，返回字体菜单${NC}"
        return
    fi

    local url
    if [[ "$seg_choice" == "1" ]]; then
        url="https://github.com/sillda76/DanmakuRender/blob/v5/fonts/Segoe-UI-Emoji-Win10/seguiemj.ttf?raw=true"
        echo -e "${BLUE}[INFO]${NC} 安装 Win10 版 Segoe UI Emoji"
    else
        url="https://github.com/sillda76/DanmakuRender/blob/v5/fonts/Segoe-UI-Emoji-Win11/seguiemj.ttf?raw=true"
        echo -e "${BLUE}[INFO]${NC} 安装 Win11 版 Segoe UI Emoji"
    fi

    local font_dir="/usr/share/fonts/truetype/microsoft"
    sudo mkdir -p "$font_dir" || { echo -e "${RED}创建字体目录失败！${NC}"; return 1; }
    sudo curl -fsSL -o "$font_dir/seguiemj.ttf" "$url" || { echo -e "${RED}下载字体失败！${NC}"; return 1; }
    sudo chmod 644 "$font_dir/seguiemj.ttf" || { echo -e "${RED}设置字体权限失败！${NC}"; return 1; }
    echo -e "${GREEN}Segoe UI Emoji 安装完成！${NC}"
}

# 安装 Noto Color Emoji 字体 （含已装检测与重装提示）
install_noto_color_emoji() {
    if fc-list | grep -qi "Noto Color Emoji"; then
        read -p "检测到已安装 Noto Color Emoji，是否先卸载再重新安装？(y/N): " _c
        if [[ ! "$_c" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过 Noto Color Emoji 安装。${NC}"
            return
        fi
        echo -e "${BLUE}[INFO]${NC} 卸载现有 Noto Color Emoji..."
        sudo rm -f /usr/share/fonts/truetype/noto-emoji/NotoColorEmoji.ttf || true # 允许文件不存在
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 安装 Noto Color Emoji 字体"
    local font_dir="/usr/share/fonts/truetype/noto-emoji"
    sudo mkdir -p "$font_dir" || { echo -e "${RED}创建字体目录失败！${NC}"; return 1; }
    sudo curl -fsSL \
        -o "$font_dir/NotoColorEmoji.ttf" \
        "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf" || { echo -e "${RED}下载字体失败！${NC}"; return 1; }
    sudo chmod 644 "$font_dir/NotoColorEmoji.ttf" || { echo -e "${RED}设置字体权限失败！${NC}"; return 1; }
    echo -e "${GREEN}Noto Color Emoji 安装完成！${NC}"
}

# 安装“微软雅黑 + Emoji 系列”
install_fonts() {
    # 微软雅黑
    if fc-list | grep -qi "Microsoft YaHei"; then
        read -p "检测到已安装 Microsoft YaHei，是否先卸载再重新安装？(y/N): " _c
        if [[ "$_c" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[INFO]${NC} 卸载 Microsoft YaHei（ttf-mscorefonts-installer）..."
            sudo apt remove -y ttf-mscorefonts-installer || true # 允许卸载失败
        else
            echo -e "${YELLOW}跳过 Microsoft YaHei 安装。${NC}"
        fi
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 准备安装 微软雅黑 + Emoji 系列 字体..."
    # 安装微软雅黑
    sudo apt update || { echo -e "${RED}apt update 失败！${NC}"; return 1; }
    sudo apt install -y ttf-mscorefonts-installer || { echo -e "${RED}安装 ttf-mscorefonts-installer 失败！${NC}"; return 1; }

    # 安装 Emoji
    install_segoe_emoji
    install_noto_color_emoji

    refresh_font_cache
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} 微软雅黑 + Emoji 系列 字体安装完成！"
}

# 安装“阿里巴巴普惠体 + Emoji 系列”
install_alibaba_fonts() {
    # 阿里巴巴普惠体
    if fc-list | grep -qi "Alibaba PuHuiTi"; then
        read -p "检测到已安装 Alibaba PuHuiTi，是否先卸载再重新安装？(y/N): " _c
        if [[ "$_c" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[INFO]${NC} 卸载 Alibaba PuHuiTi..."
            sudo rm -rf /usr/share/fonts/truetype/AlibabaPuHuiTi || true # 允许删除失败
        else
            echo -e "${YELLOW}跳过 Alibaba PuHuiTi 安装。${NC}"
        fi
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 准备安装 阿里巴巴普惠体 + Emoji 系列 字体..."
    local ali_dir="/usr/share/fonts/truetype/AlibabaPuHuiTi"
    sudo mkdir -p "$ali_dir" || { echo -e "${RED}创建字体目录失败！${NC}"; return 1; }
    sudo curl -fsSL \
        -o "$ali_dir/AlibabaPuHuiTi-3-85-Bold.ttf" \
        "https://raw.githubusercontent.com/sillda76/DanmakuRender/v5/fonts/AlibabaPuHuiTi-3-85-Bold.ttf" || { echo -e "${RED}下载字体失败！${NC}"; return 1; }
    sudo chmod 644 "$ali_dir/AlibabaPuHuiTi-3-85-Bold.ttf" || { echo -e "${RED}设置字体权限失败！${NC}"; return 1; }

    # 安装 Emoji
    install_segoe_emoji
    install_noto_color_emoji

    refresh_font_cache
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} 阿里巴巴普惠体 + Emoji 系列 字体安装完成！"
}

# 单独安装 Emoji 系列 字体
install_emoji_fonts() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 准备单独安装 Emoji 系列 字体..."
    install_segoe_emoji
    install_noto_color_emoji
    refresh_font_cache
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} Emoji 字体安装完成！"
}

# 字体安装子菜单
font_menu() {
    require_installed || return 1

    while true; do
        # 检测安装状态
        local ms_status="${RED}未安装${NC}"
        if fc-list | grep -qi "Microsoft YaHei"; then ms_status="${GREEN}已安装${NC}"; fi

        local ali_status="${RED}未安装${NC}"
        if fc-list | grep -qi "Alibaba PuHuiTi"; then ali_status="${GREEN}已安装${NC}"; fi

        local seg_status="${RED}未安装${NC}"
        if fc-list | grep -qi "Segoe UI Emoji"; then seg_status="${GREEN}已安装${NC}"; fi

        local noto_status="${RED}未安装${NC}"
        if fc-list | grep -qi "Noto Color Emoji"; then noto_status="${GREEN}已安装${NC}"; fi

        clear
        echo -e "${CYAN}${BOLD}字体安装子菜单：${NC}${NORMAL}"
        echo -e " 微软雅黑:           ${ms_status}"
        echo -e " 阿里巴巴普惠体:     ${ali_status}"
        echo -e " Segoe UI Emoji:     ${seg_status}"
        echo -e " Noto Color Emoji:   ${noto_status}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e " ${BLUE}${BOLD}1.${NC} 安装/更新 微软雅黑 + Emoji 系列"
        echo -e " ${BLUE}${BOLD}2.${NC} 安装/更新 阿里巴巴普惠体 + Emoji 系列"
        echo -e " ${BLUE}${BOLD}3.${NC} 单独安装 Emoji 字体"
        echo -e " ${BLUE}${BOLD}4.${NC} 卸载 已安装字体"
        echo -e " ${BLUE}${BOLD}0.${NC} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "$(echo -e "${CYAN}请输入选项 (0-4): ${NC}")" font_choice

        case "$font_choice" in
            1) install_fonts ;;
            2) install_alibaba_fonts ;;
            3) install_emoji_fonts ;;
            4)
                # 列出并卸载
                local installed_fonts=()
                echo
                echo -e "${CYAN}检测到已安装的字体：${NC}"
                local i=1
                if fc-list | grep -qi "Microsoft YaHei"; then
                    installed_fonts+=("Microsoft YaHei")
                    echo " $i) Microsoft YaHei"
                    ((i++))
                fi
                if fc-list | grep -qi "Alibaba PuHuiTi"; then
                    installed_fonts+=("AlibabaPuHuiTi")
                    echo " $i) Alibaba PuHuiTi"
                    ((i++))
                fi
                if fc-list | grep -qi "Segoe UI Emoji"; then
                    installed_fonts+=("SegoeUIEmoji")
                    echo " $i) Segoe UI Emoji"
                    ((i++))
                fi
                if fc-list | grep -qi "Noto Color Emoji"; then
                    installed_fonts+=("NotoColorEmoji")
                    echo " $i) Noto Color Emoji"
                    ((i++))
                fi

                if [ ${#installed_fonts[@]} -eq 0 ]; then
                    echo -e "${YELLOW}未检测到可卸载的字体。${NC}"
                    read -n1 -s -r -p "按任意键返回字体菜单..."
                else
                    echo " 0) 取消"
                    read -p "请输入要卸载的字体编号 (0-${#installed_fonts[@]}): " idx
                    if [[ "$idx" =~ ^[1-9]$ ]] && [ "$idx" -le ${#installed_fonts[@]} ]; then
                        local choice_font="${installed_fonts[$((idx-1))]}"
                        echo -e "${BLUE}正在卸载：$choice_font …${NC}"
                        case "$choice_font" in
                            "Microsoft YaHei")
                                sudo apt remove -y ttf-mscorefonts-installer || true ;;
                            "AlibabaPuHuiTi")
                                sudo rm -rf /usr/share/fonts/truetype/AlibabaPuHuiTi || true ;;
                            "SegoeUIEmoji")
                                sudo rm -f /usr/share/fonts/truetype/microsoft/seguiemj.ttf || true ;;
                            "NotoColorEmoji")
                                sudo rm -f /usr/share/fonts/truetype/noto-emoji/NotoColorEmoji.ttf || true ;;
                        esac
                        refresh_font_cache
                        echo -e "${GREEN}卸载完成并已刷新字体缓存。${NC}"
                        read -n1 -s -r -p "按任意键返回字体菜单..."
                    else
                        echo -e "${YELLOW}取消卸载。${NC}"
                        read -n1 -s -r -p "按任意键返回字体菜单..."
                    fi
                fi
                ;;
            0) echo -e "${YELLOW}返回主菜单...${NC}" && break ;;
            *) echo -e "${RED}无效选项 '$font_choice'，请输入 0 到 4。${NC}" ;;
        esac

        echo
    done
}


# ===================== 状态及主菜单 =====================

# 显示脚本头部信息
show_header() {
    clear
    local title="DanmakuRender v5 管理脚本"
    echo -e "${BLUE}${BOLD}${title}${NORMAL}${NC}"
    if [ -n "$release_version" ] && [ "$release_version" != "获取失败" ]; then
        echo -e "${CYAN}最新发布版本:${NC} ${BOLD}${release_version}${NORMAL} (${release_time})"
    fi
    if [ -n "$commit_time" ] && [ "$commit_time" != "获取失败" ]; then
        echo -e "${CYAN}最新代码提交:${NC} ${BOLD}${commit_time}${NORMAL}"
    fi
    echo -e "${CYAN}${BOLD}原地址:${NC} ${BLUE}${BOLD}${DMR_GITHUB_BASE}${NC}"
    echo -e "${PINK}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    # 更新提示
    if [ -d "$DMR_DIR" ] && [ -f "$INSTALL_DATE_FILE" ]; then
        local install_epoch
        install_epoch=$(cat "$INSTALL_DATE_FILE" 2>/dev/null || true)
        local commit_epoch
        commit_epoch=$(date -d "$commit_time" +%s 2>/dev/null || true)
        if [[ "$install_epoch" =~ ^[0-9]+$ ]] && [[ "$commit_epoch" =~ ^[0-9]+$ ]] && [ "$install_epoch" -lt "$commit_epoch" ]; then
            echo -e "${YELLOW}${BOLD}-检测到项目有更新！建议运行选项 10 进行更新。 ${NC}"
        fi
    fi
}

# 显示 DanmakuRender 的当前状态
show_status() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${YELLOW}${BOLD}程序状态：${RED}未安装${NC}${NORMAL}"
        echo -e "${YELLOW}${BOLD}配置文件：${RED}未安装${NC}${NORMAL}"
        echo -e "${YELLOW}${BOLD}运行状态：${RED}未安装${NC}${NORMAL}"
    else
        echo -e "${GREEN}${BOLD}程序状态：${GREEN}已安装${NC}${NORMAL} ($DMR_DIR)"
        if check_config; then
            local streamers_count
            streamers_count=$(find "$DMR_DIR/configs" -maxdepth 1 -type f -name "*DMR*" | wc -l)
            echo -e "${GREEN}${BOLD}配置文件：${GREEN}已获取${NC}${NORMAL}共${streamers_count}位主播"
        else
            echo -e "${YELLOW}${BOLD}配置文件：${RED}未找到或未配置！${NC}${NORMAL} (请检查目录/configs/)"
        fi
        if pgrep -f "$DMR_CMD" > /dev/null; then
            local pid
            pid=$(pgrep -f "$DMR_CMD" | head -n 1)
            echo -e "${GREEN}${BOLD}运行状态：${GREEN}${BOLD}当前正在运行 (PID: $pid)${NC}${NORMAL}"
        else
            echo -e "${YELLOW}${BOLD}运行状态：${RED}未运行${NC}${NORMAL}"
        fi
        if [ -n "$install_date" ] && [[ "$install_date" != "无效日期记录" && "$install_date" != "无法解析日期" ]]; then
            echo -e "${CYAN}${BOLD}上一次安装/更新：${PINK}${install_date}${NC}${NORMAL}"
        elif [ -f "$INSTALL_DATE_FILE" ]; then
            echo -e "${CYAN}${BOLD}上一次安装/更新：${RED}日期记录无效${NC}${NORMAL}"
        fi
    fi
}

# 检查 DanmakuRender 是否已安装，未安装则提示并返回非零
require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "\n${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}DanmakuRender v5 未安装！${NC}"
        echo -e "${YELLOW}请先在主菜单中选择选项 ${BOLD}'1'${NORMAL}${YELLOW} 进行安装。${NC}"
        return 1
    fi
    return 0
}

# 主菜单循环
main_menu() {
    # 初始化：检查基础依赖，并获取 GitHub 和 biliup-rs 的最新版本信息
    check_dependencies || { echo -e "${RED}[ERROR] 基础依赖安装失败，请手动安装 jq、curl、git${NC}"; exit 1; }

    fetch_github_times
    get_install_date
    fetch_biliup_times

    while true; do
        # 打印头部和状态
        show_header
        show_status

        # 主菜单选项
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} ${GREEN}${BOLD}安装DanmakuRender v5${NC}"
        if pgrep -f "$DMR_CMD" > /dev/null; then
            echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} ${RED}${BOLD}停止录制${NC}"
        else
            echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} ${GREEN}${BOLD}启动录制(后台运行)${NC}"
        fi
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} ${CYAN}${BOLD}查看实时日志(按Q退出)${NC}"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL} ${PURPLE}${BOLD}手动渲染视频${NC}"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL} ${PURPLE}${BOLD}运行测试${NC}"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL} ${YELLOW}${BOLD}删除回放/渲染的视频文件${NC}"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL} ${PINK}${BOLD}biliup-rs上传菜单${NC}"
        # 仅当本地和远程版本都非空且不相等时才提示更新
        if [[ -n "$BILIUP_LOCAL_VERSION" && -n "$BILIUP_REMOTE_VERSION" && "$BILIUP_REMOTE_VERSION" != "$BILIUP_LOCAL_VERSION" ]]; then
            echo -e "${YELLOW}${BOLD}→ 检测到 biliup-rs 新版本：${BILIUP_REMOTE_VERSION} (本地 ${BILIUP_LOCAL_VERSION})，建议更新${NC}"
        fi
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL} ${CYAN}${BOLD}字体安装菜单${NC}"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} ${LIGHT_BLUE}${BOLD}安装JavaScript 环境${NC}"
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL}${YELLOW}${BOLD}更新DanmakuRender v5${NC}"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD}卸载DanmakuRender v5${NC}"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} ${ORANGE}${BOLD}退出菜单${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 读取用户选择并分发
        read -p "$(echo -e "${CYAN}${BOLD}请输入选项(0-11): ${NC}")" choice
        case "$choice" in
            1) install_dmr ;;
            2)
                if require_installed; then
                    if pgrep -f "$DMR_CMD" > /dev/null; then
                        stop_dmr
                        stop_extra_processes
                    else
                        if ! check_config; then
                            echo -e "${RED}配置文件检查失败！请配置 ${DMR_DIR}/configs/ 下的 *DMR* 文件。${NC}"
                        else
                            start_dmr
                        fi
                    fi
                fi
                ;;
            3) view_log ;;
            4) require_installed && manual_render ;;
            5) require_installed && run_test ;;
            6) require_installed && delete_replays ;;
            7) require_installed && bash <(wget -qO- https://raw.githubusercontent.com/sillda76/DanmakuRender/refs/heads/v5/bp-in.sh) ;;
            8) require_installed && font_menu ;;
            9)
                if require_installed; then
                    read -p "$(echo -e "${YELLOW}确定要安装 JavaScript 环境吗？(y/N): ${NC}")" js_confirm
                    js_confirm=${js_confirm:-n}
                    if [[ "$js_confirm" =~ ^[Yy]$ ]]; then
                        install_js_engine
                    else
                        echo -e "${CYAN}已取消 JavaScript 环境安装。${NC}"
                    fi
                fi
                ;;
            10)
                if require_installed; then
                    update_dmr
                    fetch_github_times # 刷新显示信息
                    get_install_date   # 刷新安装日期
                fi
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                    # 卸载后清空状态显示
                    install_date=""
                    commit_time="N/A"
                    release_version="N/A"
                    release_time="N/A"
                    commit_sha=""
                    BILIUP_LOCAL_VERSION=""
                    BILIUP_REMOTE_VERSION=""
                fi
                ;;
            0) echo -e "${YELLOW}退出脚本${NC}" && exit 0 ;;
            *) echo -e "${RED}无效选项 '$choice'！请输入 0 到 11。${NC}" ;;
        esac

        # 等待按键后刷新菜单
        echo
        read -n 1 -s -r -p "$(echo -e "${CYAN}按任意键返回主菜单...${NC}")"
        echo
    done
}

# 启动主菜单
main_menu


