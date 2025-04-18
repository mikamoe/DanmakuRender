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

# Global variable for commit sha
commit_sha=""

# ===================== 辅助函数 =====================

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

    # 更新检测提示
    echo -e "\n(◕‿◕) 正在检查更新..."
    fetch_github_times # Ensure latest times are fetched before checking
    if [ -d "$DMR_DIR" ] && [ -f "$INSTALL_DATE_FILE" ]; then
        install_epoch=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        commit_epoch=$(date -d "$commit_time" +%s 2>/dev/null)

        # Check if both install_epoch and commit_epoch are valid numbers and if an update exists
        if [[ "$install_epoch" =~ ^[0-9]+$ ]] && [[ "$commit_epoch" =~ ^[0-9]+$ ]] && [ "$install_epoch" -lt "$commit_epoch" ]; then
            echo -e "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧ 发现新版本啦！"
            echo -e "最新提交日期: ${PINK}${BOLD}${commit_time}${NC}"
            echo -e "提交说明: ${CYAN}${commit_message}${NC}"
            # Check if commit_sha was successfully fetched before creating the specific commit link
            if [ -n "$commit_sha" ]; then
                echo -e "更新详情: ${BLUE}${DMR_GITHUB_BASE}/commit/${commit_sha}${NC}" # <-- Modified link
            else
                # Fallback link to commits page if SHA couldn't be fetched
                echo -e "更新详情 (分支): ${BLUE}${DMR_GITHUB_BASE}/commits/${GITHUB_BRANCH}${NC}"
            fi
            echo -e "(｡･ω･｡) 按任意键继续进入脚本..."
            read -n 1 -s -r
        fi
    fi
    # Return 0 explicitly if checks pass or no update needed/possible to check
    return 0
}


get_python_version() {
    if command -v python3 &>/dev/null; then
        echo "Python $(python3 -V 2>&1 | awk '{print $2}')"
    else
        echo "not_installed"
    fi
}

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
        # Fallback if TZ conversion fails, try direct conversion (might be server's local time)
        converted=$(date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
        if [ -n "$converted" ]; then
            echo "$converted (可能为服务器本地时间)"
        else
            echo "获取失败"
        fi
    fi
}

rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装过程中出错，正在回滚...${NC}"
    # Check if directory exists before attempting removal
    if [ -d "$DMR_DIR" ]; then
        sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}回滚删除安装目录失败！${NC}"
    else
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装目录不存在，无需回滚删除。${NC}"
    fi

}

check_config() {
    # Check if the directory exists first
    if [ ! -d "$DMR_DIR/configs" ]; then
        return 1
    fi
    # Use find with -quit to stop after the first match for efficiency
    if find "$DMR_DIR/configs" -maxdepth 1 -name "*DMR*" -print -quit | grep -q .; then
        return 0 # Found a file
    else
        return 1 # No matching file found
    fi
}


fetch_github_times() {
    local branch_info
    # Fetch branch info including the latest commit
    branch_info=$(curl -sfL "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/branches/$GITHUB_BRANCH")
    if [[ -n "$branch_info" ]]; then
        local raw_time
        # Extract commit author date, commit message, and commit SHA
        raw_time=$(jq -r '.commit.commit.author.date // empty' <<< "$branch_info")
        commit_time=$(convert_to_beijing_time "$raw_time")
        commit_message=$(jq -r '.commit.commit.message // empty' <<< "$branch_info")
        commit_sha=$(jq -r '.commit.sha // empty' <<< "$branch_info") # <-- Extract commit SHA
    else
        # Set defaults if fetching branch info fails
        commit_time="获取失败"
        commit_message="获取失败"
        commit_sha="" # <-- Default empty SHA
    fi

    local release_info
    # Fetch latest release info
    release_info=$(curl -sfL "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest")
    if [[ -n "$release_info" ]]; then
        # Extract release tag name and publication date
        release_version=$(jq -r '.tag_name // empty' <<< "$release_info")
        local raw_release_time
        raw_release_time=$(jq -r '.published_at // empty' <<< "$release_info")
        release_time=$(convert_to_beijing_time "$raw_release_time")
    else
        # Set defaults if fetching release info fails
        release_version="获取失败"
        release_time="获取失败"
    fi
}


get_install_date() {
    # Reset install_date at the beginning
    install_date=""
    if [ -f "$INSTALL_DATE_FILE" ]; then
        local timestamp
        # Read timestamp, suppress errors if file is empty or unreadable
        timestamp=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
        # Check if timestamp is a valid number
        if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
            # Convert timestamp to RFC 3339 format, then to Beijing time
            local rfc_date
            rfc_date=$(date -d "@$timestamp" --rfc-3339=seconds 2>/dev/null)
            if [ -n "$rfc_date" ]; then
                 install_date=$(convert_to_beijing_time "$rfc_date")
            else
                 install_date="无法解析日期" # Handle potential date command failure
            fi
        else
             install_date="无效日期记录" # Handle invalid content in file
        fi
    fi
    # If install_date is still empty (file not found or errors), keep it empty.
}

# ===================== 系统安装及更新函数 =====================

check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查系统依赖工具...${NC}"
    # Added git here as it's needed for cloning in install_dmr
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar" "xz-utils" "git")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            # Collect missing tools first
            missing_tools+=("$tool")
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool ...${NC}"
        fi
    done

    # If any tools are missing, try to install them all at once
    if [ ${#missing_tools[@]} -gt 0 ]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}正在尝试安装缺失的工具: ${missing_tools[*]}${NC}"
         # Update package list before installing
         sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！可能需要手动运行。${NC}"; return 1; }
         # Install all missing tools in one command
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

install_biliup_rs() {
    sudo mkdir -p "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建工具目录失败: $BILIUP_DIR${NC}"; return 1; }
    pushd "$BILIUP_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入工具目录失败: $BILIUP_DIR${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}获取 biliup-rs 最新版本信息...${NC}"
    local latest_info
    latest_info=$(curl -sfL "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}获取 biliup-rs 最新版本信息失败！${NC}"
        popd > /dev/null
        return 1
    fi

    local latest_version
    latest_version=$(jq -r '.tag_name' <<< "$latest_info")
    if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解析 biliup-rs 版本失败！${NC}"
        popd > /dev/null
        return 1
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}最新 biliup-rs 版本：${GREEN}${latest_version}${NC}"

    if [ -f "./biliup" ] && ./biliup -V 2>/dev/null | grep -q "$latest_version"; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已经是最新版本 biliup-rs (${latest_version})。${NC}"
        popd > /dev/null
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
        *)  echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}不支持的架构：$arch${NC}"; popd > /dev/null; return 1 ;;
    esac

    # 从 API 响应中查找正确的资源下载 URL
    local download_url
    download_url=$(jq -r --arg suffix "$asset_suffix" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' <<< "$latest_info")

    if [ -z "$download_url" ]; then
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
    curl -fLo "$asset_filename" "$download_url" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载 biliup-rs 失败！${NC}"; rm -f "$asset_filename"; popd > /dev/null; rollback_installation; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在解压 ${asset_filename}...${NC}"
    tar -xJf "$asset_filename" --strip-components=1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压 biliup-rs 失败！${NC}"; rm -f "$asset_filename"; popd > /dev/null; rollback_installation; return 1; }
    rm -f "$asset_filename"

    if [ ! -f "./biliup" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压后未找到 'biliup' 可执行文件！${NC}"
        popd > /dev/null
        rollback_installation
        return 1
    fi
    chmod +x ./biliup || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}设置 'biliup' 权限失败！${NC}"; popd > /dev/null; rollback_installation; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}安装/更新 biliup-rs 完成！${NC}"
    popd > /dev/null
    return 0
}

update_dmr() {
    require_installed || return 1
    read -p "$(echo -e "${YELLOW}是否确定要更新 DanmakuRender v5？(y/n): ${NC}")" update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         echo -e "${YELLOW}已取消更新。${NC}"
         return 0
    fi

    echo -e "${YELLOW}更新前建议备份重要数据。更新会覆盖除 'configs' 外的所有文件。${NC}"
    read -p "$(echo -e "${YELLOW}是否在更新前删除现有的 '直播回放' 和 '直播回放（弹幕版）' 目录？(y/N, 默认n): ${NC}")" delete_choice
    delete_choice=${delete_choice:-n} # Default to 'n' if user just presses Enter
    if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在删除旧的回放目录...${NC}"
        if [ -d "$DMR_DIR/直播回放" ]; then
             sudo rm -rf "$DMR_DIR/直播回放" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 已删除 '直播回放' 目录" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 '直播回放' 目录失败！"
        else
             echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} '直播回放' 目录不存在，无需删除。${NC}"
        fi
        if [ -d "$DMR_DIR/直播回放（弹幕版）" ]; then
             sudo rm -rf "$DMR_DIR/直播回放（弹幕版）" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 已删除 '直播回放（弹幕版）' 目录" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 '直播回放（弹幕版）' 目录失败！"
        else
             echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} '直播回放（弹幕版）' 目录不存在，无需删除。${NC}"
        fi
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}跳过删除回放目录。${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并安装 rsync...${NC}"
    if ! command -v rsync &> /dev/null; then
        sudo apt update && sudo apt install -y rsync || {
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}rsync 安装失败！无法继续更新。${NC}"
             return 1
        }
    fi

    # Check if the process is running and stop it
    if pgrep -f "$DMR_CMD" > /dev/null; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检测到 DanmakuRender 正在运行，正在停止...${NC}"
         stop_dmr || {
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}停止 DanmakuRender 进程失败！请手动停止后再尝试更新。${NC}"
             return 1
         }
         # Add a small delay to ensure the process has fully stopped
         sleep 2
    fi

    # Create a timestamped backup directory
    backup_configs_dir="${DMR_DIR}/config_backup/$(date +%Y%m%d_%H%M%S)"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在备份 'configs' 文件夹到 ${GREEN}${backup_configs_dir}${NC}"
    # Ensure the parent directory exists
    sudo mkdir -p "$(dirname "$backup_configs_dir")" || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建备份父目录失败！${NC}"
        return 1
    }
    # Copy the configs directory
    if [ -d "$DMR_DIR/configs" ]; then
        sudo cp -rp "$DMR_DIR/configs" "$backup_configs_dir" || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'configs' 文件夹备份失败！${NC}"
            return 1
        }
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}'configs' 备份成功。${NC}"
    else
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}'configs' 目录不存在，跳过备份。${NC}"
        # Create an empty backup dir marker so restore logic doesn't fail later if needed
        sudo mkdir -p "$backup_configs_dir/configs"
    fi


    local update_fail=0
    # Create a temporary directory for the update files
    local tmp_dir
    tmp_dir=$(mktemp -d)
    if [ -z "$tmp_dir" ] || [ ! -d "$tmp_dir" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建临时目录失败！${NC}"
         # Attempt to clean up partial backup
         [ -d "$backup_configs_dir" ] && sudo rm -rf "$backup_configs_dir"
         return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在克隆 DanmakuRender ${GITHUB_BRANCH} 分支到临时目录...${NC}"
    # Clone only the specified branch, depth 1 for speed
    if ! git clone --depth 1 -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$tmp_dir/update_repo"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}克隆更新仓库失败！请检查网络或仓库地址。${NC}"
         update_fail=1
    fi

    if [ "$update_fail" -eq 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在使用 rsync 同步文件 (排除 'configs')...${NC}"
        # Use rsync: archive mode, verbose, exclude 'configs', delete extraneous files from destination
        # Source ends with / to copy contents, destination is the main dir
        if ! sudo rsync -av --delete --exclude='/configs/' --exclude='/config_backup/' --exclude='.git/' "$tmp_dir/update_repo/" "$DMR_DIR/"; then
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}使用 rsync 同步文件失败！${NC}"
             update_fail=1
        fi
    fi

    # Clean up the temporary directory regardless of success or failure
    rm -rf "$tmp_dir"

    if [ "$update_fail" -eq 1 ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}更新过程中出现错误，正在尝试恢复 'configs' 备份...${NC}"
         # Check if backup exists before attempting restore
         if [ -d "$backup_configs_dir/configs" ]; then
              # Remove potentially corrupted configs from failed update
              sudo rm -rf "$DMR_DIR/configs"
              # Restore from backup
              sudo cp -rp "$backup_configs_dir/configs" "$DMR_DIR/" || {
                   echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}从 ${backup_configs_dir} 恢复备份失败！请手动检查。${NC}"
                   # Don't return yet, let the user know the update failed
              }
              echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}已尝试恢复 'configs' 备份。更新失败。${NC}"
         else
              echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到有效的 'configs' 备份，无法恢复。更新失败。${NC}"
         fi
         return 1
    else
         echo -e "${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} ${GREEN}DanmakuRender v5 更新成功！${NC}"
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}配置文件备份保留在：${backup_configs_dir}${NC}"
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在更新安装/更新日期记录...${NC}"
         # Record the current time as epoch seconds
         date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录更新日期失败！${NC}"

         # Update python dependencies after successful update
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在检查并更新 Python 依赖...${NC}"
         pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败"; return 1; }
         if [ -f "requirements.txt" ]; then
             source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null; return 1; }
             pip install --quiet --upgrade pip || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} pip 升级可能失败，继续安装依赖..."
             pip install -r requirements.txt || {
                 echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}更新 Python 依赖失败！请检查 'requirements.txt' 或网络。${NC}"
                 deactivate
                 popd > /dev/null
                 # Don't return error, update itself was successful, but warn user
             }
             deactivate
             echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 依赖检查/更新完成。${NC}"
         else
             echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}未找到 requirements.txt，跳过 Python 依赖更新。${NC}"
         fi
         popd > /dev/null

         # Re-fetch times to reflect the update immediately
         fetch_github_times
         get_install_date
         return 0 # Explicitly return success
    fi
}


install_dmr() {
    local rollback_needed=true
    # Setup trap to call rollback_installation on EXIT signal if rollback_needed is true
    trap '[[ "$rollback_needed" == true ]] && rollback_installation' EXIT

    if [ -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}DanmakuRender V5 似乎已经安装在 ${DMR_DIR}！${NC}"
        read -p "$(echo -e "${YELLOW}是否要重新安装 Python 依赖？(y/n, 默认n): ${NC}")" reinstall_choice
        reinstall_choice=${reinstall_choice:-n}
        if [[ "$reinstall_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在重新安装 Python 依赖...${NC}"
            pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; trap - EXIT; return 1; } # Disable trap on early exit
            # Check if virtual environment exists
            if [ ! -d "venv" ] || [ ! -f "venv/bin/activate" ]; then
                 echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}虚拟环境 'venv' 不存在或不完整！无法重新安装依赖。请尝试完整卸载后重新安装。${NC}"
                 popd > /dev/null; trap - EXIT; return 1;
            fi
             # Check if requirements file exists
            if [ ! -f "requirements.txt" ]; then
                 echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'requirements.txt' 文件不存在！无法重新安装依赖。${NC}"
                 popd > /dev/null; trap - EXIT; return 1;
            fi
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
            source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; popd > /dev/null; trap - EXIT; return 1; }
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}升级 pip...${NC}"
            pip install --quiet --upgrade pip || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} pip 升级失败，尝试继续..." # Don't fail immediately
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}从 requirements.txt 安装依赖...${NC}"
            # Use --force-reinstall maybe? Or just install? Let's stick to install for now.
            pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！${NC}"; deactivate; popd > /dev/null; trap - EXIT; return 1; }
            deactivate
            popd > /dev/null
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 依赖重新安装完成！${NC}"
            # Successfully reinstalled deps, disable rollback and exit normally
            rollback_needed=false
            trap - EXIT
            return 0
        else
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消重新安装 Python 依赖。${NC}"
            # Nothing to install, disable rollback and exit normally
            rollback_needed=false
            trap - EXIT
            return 0
        fi
    fi

    # If not installed, proceed with full installation
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}开始全新安装 DanmakuRender v5...${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并安装必要的系统工具...${NC}"
    # Call the check/install function
    check_install_tools || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}系统工具检查或安装失败！安装中止。${NC}"; return 1; } # Trap will handle rollback
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}系统工具检查/安装完成。${NC}"

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在使用 git clone 拉取 DanmakuRender ${GITHUB_BRANCH} 分支...${NC}"
    # Clone with depth 1 for efficiency
    if ! git clone --depth 1 -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$DMR_DIR"; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}git clone 失败！请检查网络、权限或仓库地址/分支。${NC}"
         return 1 # Trap will handle rollback
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}代码拉取完成！${NC}"

    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入安装目录 $DMR_DIR 失败！"; return 1; } # Trap will handle rollback

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建 Python 虚拟环境 (venv)...${NC}"
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建 Python 虚拟环境失败！${NC}"; popd > /dev/null; return 1; } # Trap will handle rollback

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境并安装 Python 依赖...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; popd > /dev/null; return 1; } # Trap will handle rollback

    pip install --quiet --upgrade pip || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} pip 升级失败，尝试继续..." # Don't fail immediately

    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！请检查 'requirements.txt' 或网络。${NC}"; deactivate; popd > /dev/null; return 1; } # Trap will handle rollback
    else
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}未找到 requirements.txt 文件，跳过 Python 依赖安装。${NC}"
    fi
    deactivate
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 依赖安装完成。${NC}"

    # Go back to original directory before installing biliup-rs (it cds into its own dir)
    popd > /dev/null

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装/更新 biliup-rs...${NC}"
    install_biliup_rs || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}biliup-rs 安装失败！${NC}"; return 1; } # Trap will handle rollback

    # Ask about JS engine installation AFTER main components are installed
    read -p "$(echo -e "${YELLOW}安装完成，是否额外安装 JavaScript 解释器 (Node.js) 和相关 Python 库 (quickjs)？(y/N): ${NC}")" js_choice
    js_choice=${js_choice:-n}
    if [[ "$js_choice" =~ ^[Yy]$ ]]; then
         install_js_engine || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}JavaScript 环境安装过程中可能出现问题。${NC}" # Don't fail the whole install for optional part
    fi

    echo -e "\n${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} ${GREEN}${BOLD}DanmakuRender v5 安装完成！${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 安装目录: ${GREEN}$DMR_DIR${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 如需渲染弹幕，请确保已安装合适的字体 (主菜单选项 8)。"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 首次运行前，请务必检查并修改 ${GREEN}${DMR_DIR}/configs/${NC} 目录下的配置文件！"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 正在记录安装日期..."
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || {
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}记录安装日期失败！(权限问题？)${NC}"
        # Don't trigger rollback for this minor failure, but inform user
    }
    get_install_date # Update the display variable

    # Installation successful, disable the rollback trap
    rollback_needed=false
    trap - EXIT
    return 0
}


uninstall_dmr() {
    require_installed || return 1
    echo -e "${RED}${BOLD}警告：这将永久删除 DanmakuRender v5 的所有文件，包括程序、配置、日志、工具和可能存在的备份！${NC}"
    echo -e "${RED}${BOLD}此操作不会删除 '直播回放' 或 '直播回放（弹幕版）' 目录中的视频文件。${NC}"
    read -p "$(echo -e "${YELLOW}确定要完全卸载 DanmakuRender v5 吗？(请输入 'yes' 确认): ${NC}")" confirm
    # Stricter confirmation
    if [[ "$confirm" != "yes" ]]; then
         echo -e "${YELLOW}输入不匹配 'yes'，取消卸载。${NC}"
         return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在停止可能在运行的 DanmakuRender 进程...${NC}"
    # Stop the process if it's running
    if pgrep -f "$DMR_CMD" > /dev/null; then
        stop_dmr || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}停止进程时遇到问题，将继续尝试卸载。${NC}"
        sleep 1 # Give it a moment
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}DanmakuRender 未在运行。${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在删除安装目录: ${DMR_DIR}...${NC}"
    # Use sudo to remove the directory
    sudo rm -rf "$DMR_DIR"
    # Verify removal
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}DanmakuRender v5 卸载完成！${NC}"
        # Reset install date display variable
        install_date=""
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}卸载失败！目录 ${DMR_DIR} 仍然存在。请检查权限或手动删除。${NC}"
        return 1
    fi
}


# ===================== 运行与测试管理函数 =====================

start_dmr() {
    require_installed || return 1
    # Check config validity before starting
    if ! check_config; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}配置文件检查失败或未配置！请在 ${DMR_DIR}/configs/ 中正确配置 *DMR* 文件后重试。${NC}"
         return 1
    fi
     # Check if already running
    if pgrep -f "$DMR_CMD" > /dev/null; then
        local existing_pid
        existing_pid=$(pgrep -f "$DMR_CMD" | head -n 1)
        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}DanmakuRender 似乎已在运行 (PID: $existing_pid)。无需重复启动。${NC}"
        return 1 # Indicate not started by this call
    fi

    # Navigate to the directory
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}使用 nohup 在后台启动 ${DMR_CMD}...${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 日志将输出到: ${GREEN}${DMR_DIR}/${LOG_FILE}${NC}"
    # Start the command with nohup, redirect stdout/stderr, run in background
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$! # Get the PID of the background process

    # Check if the process started successfully
    sleep 1 # Give it a moment to potentially fail
    if ps -p $pid > /dev/null; then
        # Store the PID in the pid file
        echo $pid > "$DMR_DIR/dmr.pid" || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} 无法写入 PID 文件 ${DMR_DIR}/dmr.pid (权限问题?)${NC}"
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}启动成功！进程 PID: $pid${NC}"
        deactivate
        popd > /dev/null
        return 0 # Success
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}启动失败！进程未能成功运行。请检查 ${LOG_FILE} 获取错误信息。${NC}"
        # Clean up pid file if it was created somehow
        rm -f "$DMR_DIR/dmr.pid"
        deactivate
        popd > /dev/null
        return 1 # Failure
    fi
}


stop_dmr() {
    require_installed || return 1
    local pid_file="$DMR_DIR/dmr.pid"
    local pid_to_kill=""
    local stopped=false

    # Try finding PID from pid file first
    if [ -f "$pid_file" ]; then
        pid_to_kill=$(cat "$pid_file")
        if [[ "$pid_to_kill" =~ ^[0-9]+$ ]]; then
            # Check if the process actually exists
            if ps -p "$pid_to_kill" > /dev/null; then
                # Check if the process command matches (as a basic sanity check)
                 if ps -p "$pid_to_kill" -o cmd= | grep -q -F "$DMR_CMD"; then
                    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在尝试停止 PID 文件中的进程: $pid_to_kill...${NC}"
                    # Try graceful TERM signal first
                    kill "$pid_to_kill"
                    sleep 1 # Wait a bit
                    if ! ps -p "$pid_to_kill" > /dev/null; then
                        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}进程 $pid_to_kill 已停止 (TERM)。${NC}"
                        stopped=true
                    else
                        # Force kill if TERM didn't work
                        echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}进程 $pid_to_kill 未响应 TERM 信号，强制停止 (KILL)...${NC}"
                        kill -9 "$pid_to_kill"
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
                     pid_to_kill="" # Reset pid_to_kill so pkill might run
                 fi
            else
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}PID 文件中的进程 $pid_to_kill 不存在。可能已停止。${NC}"
                stopped=true # Consider it stopped if PID doesn't exist
            fi
        else
             echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}PID 文件 ($pid_file) 包含无效内容: '$pid_to_kill'。${NC}"
             pid_to_kill="" # Reset pid_to_kill
        fi
        # Clean up the pid file if we attempted to stop using it or if it was invalid/stale
        rm -f "$pid_file"
    fi

    # If not stopped via pid file, try pkill as a fallback
    if [ "$stopped" = false ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未通过 PID 文件停止进程，尝试使用 pkill 查找 '${DMR_CMD}'...${NC}"
        # Use pgrep first to see if any process matches
        if pgrep -f "$DMR_CMD" > /dev/null; then
            # Use pkill -f to kill based on the command string
            pkill -f "$DMR_CMD"
            sleep 1
            # Check if stopped
            if ! pgrep -f "$DMR_CMD" > /dev/null; then
                echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已使用 pkill 停止匹配 '${DMR_CMD}' 的进程。${NC}"
                stopped=true
            else
                echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}使用 pkill 停止进程失败！请手动检查。${NC}"
            fi
        else
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}未找到正在运行的匹配 '${DMR_CMD}' 的进程。${NC}"
            stopped=true # Nothing to stop
        fi
    fi

    # Return status
    if [ "$stopped" = true ]; then
        return 0
    else
        return 1
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

run_test() {
    require_installed || return 1
    local test_script="dryrun.py"
    local test_script_path="$DMR_DIR/$test_script"

    if [ ! -f "$test_script_path" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}测试脚本 ${test_script_path} 不存在！${NC}"; return 1;
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}准备运行测试脚本: ${test_script}...${NC}"
    pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行 ${test_script}...${NC}"
    # Execute the script
    python3 "$test_script"
    local exit_code=$? # Capture exit code of the test script

    deactivate
    popd > /dev/null

    if [ $exit_code -eq 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}测试运行完成 (退出码: 0)。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}测试运行失败 (退出码: $exit_code)！请检查上面的输出。${NC}";
        return 1
    fi
}

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
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null; return 1; }

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在运行 ${render_script}... (这可能需要一些时间)${NC}"
    # Execute the script
    python3 "$render_script"
    local exit_code=$? # Capture exit code

    deactivate
    popd > /dev/null

    if [ $exit_code -eq 0 ]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}手动渲染运行完成 (退出码: 0)。${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}手动渲染运行失败 (退出码: $exit_code)！请检查上面的输出。${NC}";
        return 1
    fi
}


delete_replays() {
    require_installed || return 1
    local replay_dir_plain="$DMR_DIR/直播回放"
    local replay_dir_danmaku="$DMR_DIR/直播回放（弹幕版）"
    local found_files=false

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}检查目录内容:${NC}"
    echo "----------------------------------------"
    if [ -d "$replay_dir_plain" ]; then
        echo -e "${PURPLE}目录: ${replay_dir_plain}${NC}"
        # Use find to count files, safer for large numbers of files than ls
        local file_count_plain=$(find "$replay_dir_plain" -maxdepth 1 -type f | wc -l)
        if [ "$file_count_plain" -gt 0 ]; then
            ls -lh "$replay_dir_plain" # List details only if not empty
            found_files=true
        else
            echo "(空)"
        fi
    else
        echo -e "${YELLOW}目录不存在: ${replay_dir_plain}${NC}"
    fi
    echo "----------------------------------------"
     if [ -d "$replay_dir_danmaku" ]; then
        echo -e "${PURPLE}目录: ${replay_dir_danmaku}${NC}"
        local file_count_danmaku=$(find "$replay_dir_danmaku" -maxdepth 1 -type f | wc -l)
         if [ "$file_count_danmaku" -gt 0 ]; then
            ls -lh "$replay_dir_danmaku"
            found_files=true
        else
            echo "(空)"
        fi
    else
        echo -e "${YELLOW}目录不存在: ${replay_dir_danmaku}${NC}"
    fi
    echo "----------------------------------------"

    if [ "$found_files" = false ]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}两个回放目录均为空或不存在，无需删除。${NC}"
         return 0
    fi

    read -p "$(echo -e "\n${YELLOW}是否要删除 ${RED}${BOLD}这两个目录中的所有文件${NC}${YELLOW}？ (此操作不可恢复! y/N): ${NC}")" confirm
    confirm=${confirm:-n} # Default to 'n'
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${RED}正在删除文件...${NC}"
        local delete_success=true
        if [ -d "$replay_dir_plain" ]; then
            # Remove contents, not the directory itself, more flexible
            sudo rm -rf "$replay_dir_plain"/* || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 ${replay_dir_plain} 内容失败！"; delete_success=false; }
        fi
        if [ -d "$replay_dir_danmaku" ]; then
             sudo rm -rf "$replay_dir_danmaku"/* || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 删除 ${replay_dir_danmaku} 内容失败！"; delete_success=false; }
        fi

        if [ "$delete_success" = true ]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已删除指定目录下的所有文件。${NC}"
            return 0
        else
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}删除过程中发生错误。${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消删除操作。${NC}"
        return 1 # Indicate cancellation
    fi
}


# ===================== 字体安装相关函数 =====================

install_fonts_package() {
    local font_name="$1"
    local font_pkg="$2"

    if ! dpkg -s "$font_pkg" &> /dev/null; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在使用 apt 安装 ${font_name} 字体包 (${font_pkg})...${NC}"
        sudo apt update || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} apt update 失败，尝试继续安装..."
        sudo apt install -y "$font_pkg" || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}安装 ${font_name} 字体包 (${font_pkg}) 失败！${NC}"
            return 1
        }
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${font_name} 字体包 (${font_pkg}) 安装成功。${NC}"
    else
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${font_name} 字体包 (${font_pkg}) 已安装。${NC}"
    fi
    return 0
}

install_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${PURPLE}--- 开始安装微软雅黑和 Noto Emoji 字体 ---${NC}"

    # 1. Install Microsoft YaHei
    local ms_font_dir="/usr/share/fonts/truetype/microsoft"
    local ms_font_path="${ms_font_dir}/msyh.ttf"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查微软雅黑字体...${NC}"
    if [ -f "$ms_font_path" ] && fc-list | grep -q "Microsoft YaHei"; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}微软雅黑字体似乎已安装。${NC}"
    else
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}微软雅黑字体未找到，开始下载和安装...${NC}"
        sudo mkdir -p "$ms_font_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建字体目录 ${ms_font_dir} 失败！${NC}"; return 1; }
        local tmp_font_path="/tmp/msyh.ttf"
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 ${FONT_MSYH_URL}...${NC}"
        wget -O "$tmp_font_path" "$FONT_MSYH_URL" || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载微软雅黑字体失败！请检查URL或网络。${NC}"
            rm -f "$tmp_font_path" # Clean up partial download
            return 1
        }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在移动字体到 ${ms_font_path}...${NC}"
        sudo mv "$tmp_font_path" "$ms_font_path" || {
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}移动微软雅黑字体失败！(权限问题？)${NC}"
             rm -f "$tmp_font_path" # Clean up if move failed
             return 1
        }
         # Set correct permissions
         sudo chmod 644 "$ms_font_path"
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}已安装微软雅黑字体！${NC}"
         # Verify with fc-list immediately (might need cache refresh first)
         # fc-list | grep "Microsoft YaHei" || echo -e "${YELLOW}fc-list 可能需要刷新缓存才能看到新字体${NC}"
    fi

    # 2. Install Noto Fonts and Emoji
    local noto_emoji_pkg="fonts-noto-color-emoji"
    install_fonts_package "Noto Color Emoji" "$noto_emoji_pkg" || return 1

    # Optional: Install other Noto fonts if needed
    # install_fonts_package "Noto CJK" "fonts-noto-cjk"
    # install_fonts_package "Noto Extra" "fonts-noto-extra"
    # install_fonts_package "Noto Basic" "fonts-noto"
    # install_fonts_package "Symbola" "fonts-symbola"

    # 3. Refresh Font Cache
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新系统字体缓存 (fc-cache)...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}字体缓存刷新完成。${NC}"

    # Final verification for MS YaHei
    if ! fc-list | grep -q "Microsoft YaHei"; then
         echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}fc-list 仍然未检测到微软雅黑。可能需要重启应用或系统。${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}微软雅黑和 Noto Emoji 字体安装/检查完成！${NC}"
    echo -e "${PURPLE}-------------------------------------------------${NC}"
    return 0
}

install_alibaba_fonts() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${PURPLE}--- 开始安装阿里巴巴普惠体和 Noto Emoji 字体 ---${NC}"

    # 1. Install Alibaba PuHuiTi
    local ali_font_dir="/usr/share/fonts/truetype/AlibabaPuHuiTi"
    local ali_font_path="${ali_font_dir}/AlibabaPuHuiTi-3-65-Medium.ttf" # Match the actual filename
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查阿里巴巴普惠体...${NC}"
    if [ -f "$ali_font_path" ] && fc-list | grep -q "Alibaba PuHuiTi"; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}阿里巴巴普惠体似乎已安装。${NC}"
    else
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}阿里巴巴普惠体未找到，开始下载和安装...${NC}"
        sudo mkdir -p "$ali_font_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建字体目录 ${ali_font_dir} 失败！${NC}"; return 1; }
        local tmp_font_path="/tmp/AlibabaPuHuiTi.ttf" # Temporary download name
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 ${FONT_ALIBABA_URL}...${NC}"
        wget -O "$tmp_font_path" "$FONT_ALIBABA_URL" || {
            echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载阿里巴巴普惠体失败！请检查URL或网络。${NC}"
            rm -f "$tmp_font_path"
            return 1
        }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在移动字体到 ${ali_font_path}...${NC}"
        sudo mv "$tmp_font_path" "$ali_font_path" || {
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}移动阿里巴巴普惠体失败！(权限问题？)${NC}"
             rm -f "$tmp_font_path"
             return 1
        }
         sudo chmod 644 "$ali_font_path"
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}已安装阿里巴巴普惠体！${NC}"
    fi

    # 2. Install Noto Fonts and Emoji (same as in the other function)
    local noto_emoji_pkg="fonts-noto-color-emoji"
    install_fonts_package "Noto Color Emoji" "$noto_emoji_pkg" || return 1

    # 3. Refresh Font Cache
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在刷新系统字体缓存 (fc-cache)...${NC}"
    sudo fc-cache -fv > /dev/null 2>&1 || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}刷新字体缓存失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}字体缓存刷新完成。${NC}"

    # Final verification for Alibaba
     if ! fc-list | grep -q "Alibaba PuHuiTi"; then
         echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}fc-list 仍然未检测到阿里巴巴普惠体。可能需要重启应用或系统。${NC}"
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}阿里巴巴普惠体和 Noto Emoji 字体安装/检查完成！${NC}"
    echo -e "${PURPLE}-----------------------------------------------------${NC}"
    return 0
}


font_menu() {
    local oneshot=${1:-false} # Check if called in oneshot mode (currently not used)
    while true; do
        # Clear screen for sub-menu clarity? Optional.
        # clear
        echo -e "\n${CYAN}${BOLD}字体安装子菜单：${NC}${NORMAL}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e " ${BLUE}${BOLD}1.${NC}${NORMAL} 安装/检查 ${GREEN}微软雅黑${NC} + Noto Emoji"
        echo -e " ${BLUE}${BOLD}2.${NC}${NORMAL} 安装/检查 ${GREEN}阿里巴巴普惠体${NC} + Noto Emoji"
        echo -e " ${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "$(echo -e "${CYAN}请输入选项 (0-2): ${NC}")" font_choice
        case $font_choice in
            1) install_fonts ;;
            2) install_alibaba_fonts ;;
            0) echo -e "${YELLOW}返回主菜单...${NC}"; break ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项 '$font_choice'！请输入 0, 1 或 2。${NC}" ;;
        esac
        # Pause only if not returning to main menu
        if [ "$font_choice" != "0" ]; then
             read -n 1 -s -r -p "$(echo -e "${CYAN}按任意键返回字体菜单...${NC}")"
             echo # Add a newline after the pause
        fi
        # If oneshot was intended, break here:
        # if [ "$oneshot" = true ] && [ "$font_choice" != "0" ]; then break; fi
    done
}


# ===================== biliup‑rs 相关函数 =====================

# Helper function to select video files
select_video_files() {
    local source_dir="$1"
    local selection_mode="$2" # "single" or "multiple"
    # Output variables declared with -g to be accessible outside the function
    declare -g selected_video_paths=()

    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录不存在: ${source_dir}${NC}"
        return 1
    fi

    local files=()
    local file_display=()
    local file_map=() # Associative array to map index to full path

    # Find video files, handle potential spaces or special chars in names, sort by modification time (oldest first)
    # Using find is more robust than ls for parsing
    local i=1
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
        file_display+=("$(basename "$file")")
        file_map[$i]="$file"
        i=$((i + 1))
    done < <(find "$source_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\0" | sort -z -n | cut -z -d' ' -f2-)

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 目录 ${source_dir} 下没有找到支持的视频文件 (.mp4, .flv, .mkv, .avi)！${NC}"
        return 1
    fi

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}在 ${source_dir} 中找到以下视频文件：${NC}"
    for idx in "${!file_display[@]}"; do
        printf " %3d) %s\n" $((idx + 1)) "${file_display[$idx]}"
    done

    if [[ "$selection_mode" == "multiple" ]]; then
         echo -e " ${GREEN}${BOLD} 99)${NC} 全部选择"
    fi
     echo -e " ${YELLOW}${BOLD}  0)${NC} 取消/返回"
    echo "----------------------------------------"

    local prompt_msg="请输入要操作的视频选项编号"
    if [[ "$selection_mode" == "multiple" ]]; then
        prompt_msg+="(可输入多个编号，用空格分隔；输入 99 选择全部；输入 0 取消): "
    else
        prompt_msg+="(输入 0 取消): "
    fi

    while true; do
        read -p "$(echo -e "${CYAN}${prompt_msg}${NC}")" -a selections
        local valid_selection=true
        selected_video_paths=() # Reset selection

        # Check for cancellation first
        if [[ " ${selections[@]} " =~ " 0 " ]]; then
            echo -e "${YELLOW}操作已取消。${NC}"
            return 1 # Indicate cancellation
        fi

        # Handle "select all" for multiple mode
        if [[ "$selection_mode" == "multiple" ]] && [[ " ${selections[@]} " =~ " 99 " ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已选择全部 ${#files[@]} 个文件。${NC}"
            selected_video_paths=("${files[@]}") # Assign all found files
            return 0 # Success
        fi

        # Validate individual selections
        for num in "${selections[@]}"; do
            if [[ ! "$num" =~ ^[1-9][0-9]*$ ]] || (( num < 1 || num > ${#files[@]} )); then
                echo -e "${RED}无效选项：'$num'。请输入 1 到 ${#files[@]} 之间的数字，或 0${NC}${selection_mode == "multiple" && " (或 99)" || ""}。"
                valid_selection=false
                break # Exit inner loop on first error
            fi
            # Add valid path to selection (avoid duplicates if user enters same number twice)
            local path_to_add="${file_map[$num]}"
            if [[ ! " ${selected_video_paths[@]} " =~ " ${path_to_add} " ]]; then
                 selected_video_paths+=("$path_to_add")
            fi

            # Break after first selection in single mode
            if [[ "$selection_mode" == "single" ]]; then
                 break
            fi
        done

        if $valid_selection; then
            if [ ${#selected_video_paths[@]} -eq 0 ]; then
                 echo -e "${RED}错误：未选择任何文件。${NC}" # Should not happen if validation is correct
                 continue
            fi
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已选择 ${#selected_video_paths[@]} 个文件。${NC}"
            # Optional: List selected files here for confirmation
            return 0 # Success
        fi
        # Loop again if selection was invalid
    done
}

biliup_upload() {
    require_installed || return 1
    pushd "$BILIUP_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入工具目录 $BILIUP_DIR 失败！"; return 1; }

    if [ ! -f "./biliup" ] || [ ! -x "./biliup" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'biliup' 工具不存在或不可执行！请尝试更新 (主菜单 -> 7 -> 9)。${NC}"; popd > /dev/null; return 1;
    fi

    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}--- 哔哩哔哩视频上传 (使用 biliup-rs) ---${NC}"
    echo "请选择视频文件来源："
    echo " 1. 从 '$DMR_DIR/直播回放' 目录选择"
    echo " 2. 从 '$DMR_DIR/直播回放（弹幕版）' 目录选择"
    echo " 3. 手动输入视频文件绝对路径"
    echo " 0. 返回 biliup 菜单"
    read -p "$(echo -e "${CYAN}请输入选项 (0-3): ${NC}")" type_choice

    local video_dir=""
    declare -a video_paths_to_upload=() # Use a different name

    case $type_choice in
        1) video_dir="$DMR_DIR/直播回放" ;;
        2) video_dir="$DMR_DIR/直播回放（弹幕版）" ;;
        3)
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}请输入一个或多个视频文件的绝对路径，用 ${BOLD}空格${NORMAL}${YELLOW} 分隔:${NC}"
            read -p "> " -a video_paths_to_upload
            if [ ${#video_paths_to_upload[@]} -eq 0 ]; then
                echo -e "${RED}未输入任何文件路径！取消上传。${NC}"
                popd > /dev/null; return 1
            fi
            # Basic check if files exist
            local all_files_exist=true
            for file_path in "${video_paths_to_upload[@]}"; do
                 if [ ! -f "$file_path" ]; then
                      echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 文件不存在或不是常规文件: $file_path${NC}"
                      all_files_exist=false
                 fi
            done
            if [ "$all_files_exist" = false ]; then
                 popd > /dev/null; return 1
            fi
            ;;
        0) echo "${YELLOW}返回 biliup 菜单...${NC}"; popd > /dev/null; return 0 ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项 '$type_choice'！"; popd > /dev/null; return 1 ;;
    esac

    # If source is directory, call helper function
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        select_video_files "$video_dir" "multiple" || { popd > /dev/null; return 1; } # Call helper, exit if it cancels/fails
        # The selected paths are now in the global 'selected_video_paths' array
        video_paths_to_upload=("${selected_video_paths[@]}") # Copy to local array
        if [ ${#video_paths_to_upload[@]} -eq 0 ]; then
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未从目录选择任何文件。${NC}" # Should be caught by select_video_files
             popd > /dev/null; return 1
        fi
    fi

    # Get upload parameters
    read -p "$(echo -e "${CYAN}请输入 B站投稿分区 ${BOLD}tid${NORMAL}${CYAN} 号 (例如: 游戏->单机游戏 是 17, 生活->日常 是 21, 默认: 65 '虚拟UP主'): ${NC}")" tid
    tid=${tid:-65} # Default to 65 if empty
    read -p "$(echo -e "${CYAN}请输入视频标签 (用 ${BOLD},${NORMAL}${CYAN} 分隔, 默认: '直播回放,录播'): ${NC}")" tags
    tags=${tags:-"直播回放,录播"}
    # Optional: Ask for title, description etc. if needed

    # Construct and display command
    # Quote paths properly for the command line
    local cmd_args=()
    for path in "${video_paths_to_upload[@]}"; do
        cmd_args+=("$path")
    done
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}准备执行上传命令:${NC}"
    echo -e "${PURPLE}./biliup upload \\${NC}"
    for arg in "${cmd_args[@]}"; do printf "    '%s' \\\n" "$arg"; done # Print each file path quoted
    echo -e "${PURPLE}    --tid '$tid' \\${NC}"
    echo -e "${PURPLE}    --tag '$tags'${NC}"
    echo "----------------------------------------"
    read -p "$(echo -e "${YELLOW}确认执行上传吗？(y/N): ${NC}")" confirm_upload
    confirm_upload=${confirm_upload:-n}

    if [[ "$confirm_upload" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}开始上传...${NC}"
        # Execute the command
        ./biliup upload "${cmd_args[@]}" --tid "$tid" --tag "$tags"
        local upload_status=$?
        if [ $upload_status -eq 0 ]; then
             echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}biliup 上传命令执行完成。${NC}"
        else
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}biliup 上传命令执行失败 (退出码: $upload_status)。${NC}"
        fi
    else
        echo -e "${YELLOW}上传已取消。${NC}"
    fi

    popd > /dev/null # Return to original directory
    return 0 # Even if upload failed, the function itself completed
}


biliup_append() {
    require_installed || return 1
    pushd "$BILIUP_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入工具目录 $BILIUP_DIR 失败！"; return 1; }

    if [ ! -f "./biliup" ] || [ ! -x "./biliup" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'biliup' 工具不存在或不可执行！请尝试更新 (主菜单 -> 7 -> 9)。${NC}"; popd > /dev/null; return 1;
    fi

    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}--- 哔哩哔哩视频追加上传 (使用 biliup-rs) ---${NC}"
    local last_bv_file="$BILIUP_DIR/last_bv.txt"
    local bv="" # BVID of the video to append to

    # Ask for BVID, suggesting the last used one
    if [ -f "$last_bv_file" ]; then
        local last_bv
        last_bv=$(cat "$last_bv_file")
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 检测到上次使用的视频 BV 号：${GREEN}${last_bv}${NC}"
        echo " 1) 使用上次的 BV 号 (${last_bv})"
        echo " 2) 输入新的 BV 号"
        echo " 0) 取消追加"
        read -p "$(echo -e "${CYAN}请选择 (0-2): ${NC}")" choice_bv
        case "$choice_bv" in
            1) bv="$last_bv" ;;
            2) ;; # Will ask below
            0) echo "${YELLOW}操作已取消。${NC}"; popd > /dev/null; return 0 ;;
            *) echo "${RED}无效选项。${NC}"; popd > /dev/null; return 1 ;;
        esac
    fi

    # If no previous BV or user chose to enter new one
    if [ -z "$bv" ]; then
        while true; do
            read -p "$(echo -e "${CYAN}请输入要追加到的视频的 ${BOLD}BV 号${NORMAL}${CYAN} (必须以 BV 开头): ${NC}")" bv
            if [[ "$bv" =~ ^BV[a-zA-Z0-9]{10}$ ]]; then
                 echo "$bv" > "$last_bv_file" # Save the valid BV for next time
                 break
            else
                 echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效的 BV 号格式。请输入正确的 BV 号 (例如 BV1fx4y1z7Xq)。${NC}"
            fi
        done
    fi
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}将追加视频到: ${GREEN}$bv${NC}"

    # Select video files to append
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}请选择要追加的视频文件来源：${NC}"
    echo " 1. 从 '$DMR_DIR/直播回放' 目录选择"
    echo " 2. 从 '$DMR_DIR/直播回放（弹幕版）' 目录选择"
    echo " 3. 手动输入视频文件绝对路径"
    echo " 0. 返回 biliup 菜单"
     read -p "$(echo -e "${CYAN}请输入选项 (0-3): ${NC}")" type_choice

    local video_dir=""
    declare -a video_paths_to_append=()

    case $type_choice in
        1) video_dir="$DMR_DIR/直播回放" ;;
        2) video_dir="$DMR_DIR/直播回放（弹幕版）" ;;
        3)
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}请输入 ${BOLD}一个或多个${NORMAL}${YELLOW} 要追加的视频文件的绝对路径，用 ${BOLD}空格${NORMAL}${YELLOW} 分隔:${NC}"
            read -p "> " -a video_paths_to_append
             if [ ${#video_paths_to_append[@]} -eq 0 ]; then
                echo -e "${RED}未输入任何文件路径！取消追加。${NC}"
                popd > /dev/null; return 1
            fi
            # Basic check if files exist
            local all_files_exist=true
            for file_path in "${video_paths_to_append[@]}"; do
                 if [ ! -f "$file_path" ]; then
                      echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 文件不存在或不是常规文件: $file_path${NC}"
                      all_files_exist=false
                 fi
            done
            if [ "$all_files_exist" = false ]; then
                 popd > /dev/null; return 1
            fi
            ;;
        0) echo "${YELLOW}返回 biliup 菜单...${NC}"; popd > /dev/null; return 0 ;;
        *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项 '$type_choice'！"; popd > /dev/null; return 1 ;;
    esac

     # If source is directory, call helper function
    if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
        # Need multiple files for append usually
        select_video_files "$video_dir" "multiple" || { popd > /dev/null; return 1; }
        video_paths_to_append=("${selected_video_paths[@]}")
        if [ ${#video_paths_to_append[@]} -eq 0 ]; then
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 未从目录选择任何要追加的文件。${NC}"
             popd > /dev/null; return 1
        fi
    fi

    # Construct and display command
    local cmd_args=()
    for path in "${video_paths_to_append[@]}"; do
        cmd_args+=("$path")
    done
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}准备执行追加命令:${NC}"
    echo -e "${PURPLE}./biliup append \\${NC}"
    echo -e "${PURPLE}    --vid '$bv' \\${NC}"
    for arg in "${cmd_args[@]}"; do printf "    '%s' \\\n" "$arg"; done
    echo "----------------------------------------"
    read -p "$(echo -e "${YELLOW}确认执行追加吗？(y/N): ${NC}")" confirm_append
    confirm_append=${confirm_append:-n}

    if [[ "$confirm_append" =~ ^[Yy]$ ]]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}开始追加...${NC}"
        # Execute the command
        ./biliup append --vid "$bv" "${cmd_args[@]}"
        local append_status=$?
        if [ $append_status -eq 0 ]; then
             echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}biliup 追加命令执行完成。${NC}"
        else
             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}biliup 追加命令执行失败 (退出码: $append_status)。${NC}"
        fi
    else
        echo -e "${YELLOW}追加已取消。${NC}"
    fi

    popd > /dev/null # Return to original directory
    return 0
}

# Function to update biliup-rs (just calls the installer)
update_biliup_rs() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}开始检查并更新 biliup-rs...${NC}"
    # Simply call the installation function, which handles checking the latest version and downloading if needed
    install_biliup_rs
}

biliup_menu() {
    # Ensure we are in the correct directory for biliup commands
    require_installed || return 1
    pushd "$BILIUP_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无法进入工具目录 $BILIUP_DIR"; return 1; }

    while true; do
        # Don't clear screen here, keep main menu header visible? Or clear? Let's keep it simple.
        # show_header # Re-show main header? Might be too much.
        echo -e "\n${PINK}=== biliup-rs 管理菜单 ===${NC}"
        echo -e "${CYAN}当前目录: $(pwd)${NC}"
        echo -e "${CYAN}biliup-rs 版本信息：${NC}"
        if [ -f "./biliup" ] && [ -x "./biliup" ]; then
            ./biliup -V # Display version
        else
            echo -e "${RED}biliup 工具未找到或不可执行！${NC}"
        fi
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e " ${BLUE}${BOLD}1.${NC}${NORMAL} 视频 ${GREEN}上传${NC} (新投稿)"
        echo -e " ${BLUE}${BOLD}2.${NC}${NORMAL} 视频 ${GREEN}追加${NC} (添加到已有投稿)"
        echo -e " ${BLUE}${BOLD}3.${NC}${NORMAL} ${YELLOW}登录/更新${NC} B站 Cookies (./biliup login)"
        echo -e " ${BLUE}${BOLD}9.${NC}${NORMAL} ${LIGHT_BLUE}检查/更新${NC} biliup-rs 工具"
        echo -e " ${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "$(echo -e "${CYAN}请输入 biliup 菜单选项 (0-3, 9): ${NC}")" sub_choice
        case $sub_choice in
            1) biliup_upload ;;
            2) biliup_append ;;
            3)
                if [ -f "./biliup" ] && [ -x "./biliup" ]; then
                     echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}执行 ./biliup login ...${NC}"
                     ./biliup login
                else
                     echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}'biliup' 工具不存在或不可执行！${NC}"
                fi
                ;;
            9) update_biliup_rs ;; # Correctly call the update function now
            0) echo -e "${YELLOW}返回主菜单...${NC}"; break ;; # Exit the biliup menu loop
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项 '$sub_choice'！" ;;
        esac
        # Pause only if not returning to main menu
        if [ "$sub_choice" != "0" ]; then
             read -n 1 -s -r -p "$(echo -e "${CYAN}按任意键返回 biliup 菜单...${NC}")"
             echo # Add a newline
        fi
    done
    # Return to the directory script was run from
    popd > /dev/null
    return 0
}


# ===================== 新增：安装 JavaScript 解释器和 JS 引擎 =====================
install_js_engine() {
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}--- JavaScript 环境安装 ---${NC}"
    echo "此功能将尝试安装 Node.js (提供 'node' 和 'npm' 命令) 和 Python 的 'quickjs' 库。"
    echo "Node.js 将通过系统包管理器 (apt) 安装。"
    echo "'quickjs' 将安装在 DanmakuRender 的 Python 虚拟环境中。"
    read -p "$(echo -e "${YELLOW}是否确定要安装 JavaScript 环境？(y/N): ${NC}")" js_ans
    js_ans=${js_ans:-n} # Default to 'n'

    if [[ "$js_ans" =~ ^[Yy]$ ]]; then
         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并安装 Node.js 和 npm...${NC}"
         local node_installed=false
         local npm_installed=false
         command -v node &>/dev/null && node_installed=true
         command -v npm &>/dev/null && npm_installed=true

         if [ "$node_installed" = true ] && [ "$npm_installed" = true ]; then
              echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Node.js 和 npm 似乎已安装。${NC}"
         else
              echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}正在使用 apt 安装 nodejs 和 npm...${NC}"
              sudo apt update || echo -e "${YELLOW}${BOLD}[WARN]${NC}${NORMAL} apt update 失败，尝试继续安装..."
              sudo apt install -y nodejs npm || {
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Node.js 或 npm 安装失败！请尝试手动安装。${NC}"
                    # Decide whether to proceed with quickjs or not. Let's try.
              }
              # Verify again
               command -v node &>/dev/null && node_installed=true
               command -v npm &>/dev/null && npm_installed=true
               if [ "$node_installed" = true ] && [ "$npm_installed" = true ]; then
                    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Node.js 和 npm 安装完成。${NC}"
               else
                    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Node.js 或 npm 安装后仍未检测到！${NC}"
               fi
         fi

         echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}检查并安装 Python 'quickjs' 库...${NC}"
         require_installed || return 1 # Need main install for venv
         pushd "$DMR_DIR" > /dev/null || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 进入目录 $DMR_DIR 失败！"; return 1; }

         if [ ! -d "venv" ] || [ ! -f "venv/bin/activate" ]; then
              echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 虚拟环境 'venv' 不存在或不完整！无法安装 quickjs。${NC}"
              popd > /dev/null; return 1;
         fi

         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
         source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 激活虚拟环境失败！"; popd > /dev/null; return 1; }

         echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}使用 pip 安装 'quickjs'...${NC}"
         pip install quickjs
         local pip_status=$?

         deactivate
         popd > /dev/null

         if [ $pip_status -eq 0 ]; then
              echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}Python 'quickjs' 库安装成功！${NC}"
              echo -e "\n${GREEN}${BOLD}[SUCCESS]${NC}${NORMAL} ${GREEN}JavaScript 环境 (Node.js, npm, quickjs) 安装/检查完成！${NC}"
              return 0
         else
              echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 'quickjs' 库安装失败！(退出码: $pip_status)${NC}"
              echo -e "\n${YELLOW}${BOLD}[WARN]${NC}${NORMAL} ${YELLOW}JavaScript 环境安装未完全成功。${NC}"
              return 1
         fi
    else
         echo -e "${YELLOW}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消安装 JavaScript 环境。${NC}"
         return 1 # Indicate cancellation/non-action
    fi
}


# ===================== 状态及主菜单 =====================

show_header() {
    clear
    local title="DanmakuRender v5 管理脚本"
    
    echo -e "${BLUE}${BOLD}${title}${NORMAL}${NC}"
    
    if [ -n "$release_version" ] && [ "$release_version" != "获取失败" ]; then
         echo -e "${CYAN}最新发布版本:${NC} ${BOLD}${release_version}${NORMAL} (${release_time})"
    fi
    if [ -n "$commit_time" ] && [ "$commit_time" != "获取失败" ]; then
         echo -e "${CYAN}最新代码提交:${NC} ${BOLD}${commit_time}${NORMAL}"
         # echo -e "${CYAN}提交信息:${NC} ${commit_message}" # Can be long
    fi
    echo -e "${CYAN}项目地址:${NC} ${BLUE}${BOLD}${DMR_GITHUB_BASE}${NC}"

    # Update Notification within header
    if [ -d "$DMR_DIR" ] && [ -f "$INSTALL_DATE_FILE" ]; then
         install_epoch=$(cat "$INSTALL_DATE_FILE" 2>/dev/null)
         commit_epoch=$(date -d "$commit_time" +%s 2>/dev/null)
         if [[ "$install_epoch" =~ ^[0-9]+$ ]] && [[ "$commit_epoch" =~ ^[0-9]+$ ]] && [ "$install_epoch" -lt "$commit_epoch" ]; then
              echo -e "${YELLOW}${BOLD}✨ 检测到项目有更新！建议运行选项 10 进行更新。 ✨${NC}"
              echo -e "${YELLOW}   最新提交说明: ${commit_message}${NC}"
         fi
    fi
     echo -e "${PINK}${border}${NC}"
}

show_status() {
    # Installation Status
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${YELLOW}${BOLD}程序状态：${RED}未安装${NC}${NORMAL}"
        echo -e "${YELLOW}${BOLD}配置文件：${RED}未安装${NC}${NORMAL}"
        echo -e "${YELLOW}${BOLD}运行状态：${RED}未安装${NC}${NORMAL}"
    else
        echo -e "${GREEN}${BOLD}程序状态：${GREEN}已安装${NC}${NORMAL} (目录: $DMR_DIR)"
        # Configuration Status
        if check_config; then
             echo -e "${GREEN}${BOLD}配置文件：${GREEN}已找到 (*DMR* in configs)${NC}${NORMAL}"
        else
             echo -e "${YELLOW}${BOLD}配置文件：${RED}未找到或未配置！${NC}${NORMAL} (请检查目录/configs/)"
        fi
        # Running Status
        if pgrep -f "$DMR_CMD" > /dev/null; then
            local pid
            pid=$(pgrep -f "$DMR_CMD" | head -n 1)
            echo -e "${GREEN}${BOLD}运行状态：${GREEN}正在运行 (PID: $pid)${NC}${NORMAL}"
        else
            echo -e "${YELLOW}${BOLD}运行状态：${RED}未运行${NC}${NORMAL}"
        fi
         # Last Install/Update Date
        if [ -n "$install_date" ] && [ "$install_date" != "无效日期记录" ] && [ "$install_date" != "无法解析日期" ]; then
            echo -e "${CYAN}${BOLD}上一次安装/更新：${PINK}${install_date}${NC}${NORMAL}"
        elif [ -f "$INSTALL_DATE_FILE" ]; then
             echo -e "${CYAN}${BOLD}上一次安装/更新：${RED}日期记录无效${NC}${NORMAL}"
        fi
    fi

}

require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "\n${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}DanmakuRender v5 未安装！${NC}"
        echo -e "${YELLOW}请先在主菜单中选择选项 ${BOLD}'1'${NORMAL}${YELLOW} 进行安装。${NC}"
        return 1 # Return failure code
    fi
    return 0 # Return success code
}

main_menu() {
    # Initial checks and data fetching on script start
    echo "正在初始化脚本，请稍候..."
    check_dependencies || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}依赖检查或安装失败，脚本无法继续。请检查错误信息并手动安装所需工具 (jq, curl, git)。${NC}"; exit 1; }
    fetch_github_times
    get_install_date # Get initial install date if available

    local skip_read=false # Flag to skip "Press any key" prompt sometimes
    while true; do
        show_header # Display project info and update notice
        show_status # Display installed/running status


        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} ${GREEN}安装${NC} DanmakuRender v5"
        # Start/Stop Logic based on current status
        if pgrep -f "$DMR_CMD" > /dev/null; then
             echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} ${RED}停止${NC} 录制进程"
        else
             echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} ${GREEN}启动${NC} 录制进程 (后台运行)"
        fi
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} ${CYAN}查看${NC} 实时日志 (按 'q' 退出)"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL} ${PURPLE}手动渲染${NC} 视频 (render_only.py)"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL} ${PURPLE}运行测试${NC} (dryrun.py)"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL} ${YELLOW}删除${NC} 回放/渲染的视频文件"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL} ${PINK}biliup-rs${NC} 上传工具菜单"
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL} ${LIGHT_BLUE}字体${NC} 安装菜单 (微软雅黑/阿里普惠)"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL} ${LIGHT_BLUE}安装${NC} JavaScript 环境 (Node.js + quickjs)"
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL}${YELLOW}${BOLD}更新${NC}${NORMAL} DanmakuRender v5 (保留配置)"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD}卸载${NC}${NORMAL} DanmakuRender v5"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} ${RED}退出${NC} 脚本"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Reset skip_read flag before reading choice
        skip_read=false

        read -p "$(echo -e "${CYAN}请输入选项 (0-11): ${NC}")" choice

        case $choice in
            1) install_dmr ;;
            2)
                if require_installed; then
                    if pgrep -f "$DMR_CMD" > /dev/null; then
                        stop_dmr
                    else
                        # Check config before starting
                         if ! check_config; then
                             echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}配置文件检查失败或未配置！请在 ${DMR_DIR}/configs/ 中正确配置 *DMR* 文件后重试。${NC}"
                         else
                             python_version=$(get_python_version)
                             echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} 当前 Python 版本： ${GREEN}${python_version}${NC}"
                             if start_dmr; then
                                 # Optionally view log immediately after starting?
                                 # read -p "$(echo -e "${YELLOW}启动成功，是否立即查看日志？(y/N): ${NC}")" viewlognow
                                 # if [[ "$viewlognow" =~ ^[Yy]$ ]]; then
                                 #    view_log; skip_read=true
                                 # fi
                                 : # Do nothing extra by default after start
                             fi
                         fi
                    fi
                fi
                ;;
            3)
                if require_installed; then
                    view_log; skip_read=true # Skip "press any key" after exiting log view
                fi
                ;;
            4)
                if require_installed; then
                    manual_render
                fi
                ;;
            5)
                if require_installed; then
                    run_test
                fi
                ;;
            6)
                if require_installed; then
                    delete_replays
                fi
                ;;
            7)
                if require_installed; then
                    biliup_menu # This function handles its own loops and pauses
                    skip_read=true # Skip main menu pause after returning from sub-menu
                fi
                ;;
            8)
                if require_installed; then
                    font_menu # Handles its own loops and pauses
                    skip_read=true # Skip main menu pause
                fi
                ;;
            9)
                # No need to require_installed here, JS engine can be installed independently
                # Though quickjs part needs the venv
                install_js_engine
                ;;
            10)
                if require_installed; then
                    update_dmr
                    # Re-fetch info after update
                    fetch_github_times
                    get_install_date
                fi
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                    # Clear status variables after uninstall
                    install_date=""
                    commit_time="N/A"
                    release_version="N/A"
                    release_time="N/A"
                    commit_sha=""
                fi
                ;;
            0) echo -e "${YELLOW}退出脚本${NC}"; exit 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} 无效选项 '$choice'！请输入 0 到 11 之间的数字。${NC}" ;;
        esac

        # Pause for user to see output, unless skipped
        if [ "$skip_read" = false ]; then
             # Add a newline for better spacing before the prompt
             echo
             read -n 1 -s -r -p "$(echo -e "${CYAN}按任意键返回主菜单...${NC}")"
             echo # Add a newline after the pause
        fi
    done
}

# ===================== 脚本入口 =====================
main_menu
