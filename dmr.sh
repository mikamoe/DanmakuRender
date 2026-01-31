#!/bin/bash
VERSION="260131"
# ===================== 配置变量 =====================
# 安装路径及相关文件、目录设置
DMR_DIR="/opt/DanmakuRender-5"
DMR_CMD="python3 main.py"
SCRIPT_NAME="dmr.sh"
COOKIES_TOOL_DIR="tools"
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"
INSTALL_DATE_FILE="$DMR_DIR/install_date"

# GitHub 项目信息
GITHUB_OWNER="SmallPeaches"
GITHUB_REPO="DanmakuRender"
GITHUB_BRANCH="v5"
DMR_GITHUB_BASE="https://github.com/SmallPeaches/DanmakuRender"

# biliupR 项目信息
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup"
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases"

# 脚本更新 URL
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/mikamoe/DanmakuRender/refs/heads/v5/dmr.sh"

# ANSI 颜色和样式设置
RED='\033[1;31m'    GREEN='\033[1;32m'  YELLOW='\033[1;33m'
BLUE='\033[1;34m'   PINK='\033[1;35m'   CYAN='\033[1;36m'
WHITE='\033[1;37m'  GRAY='\033[0;90m'   ORANGE='\033[38;5;208m'
NC='\033[0m'
BOLD=$(tput bold)   NORMAL=$(tput sgr0)

# ===================== 状态格式化辅助 =====================
LOG_INFO="${BLUE}${BOLD}[i]${NC} "
LOG_SUCCESS="${GREEN}${BOLD}[✓]${NC} "
LOG_WARN="${YELLOW}${BOLD}[!]${NC} "
LOG_ERROR="${RED}${BOLD}[✗]${NC} "

# 全局变量
commit_sha="" commit_time="" commit_message=""
release_version="" release_time="" install_date=""
BILIUP_LOCAL_VERSION="" BILIUP_REMOTE_VERSION=""

# ===================== 辅助函数 =====================
check_dependencies() {
    local required_tools=("curl" "jq") 
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${LOG_INFO}${YELLOW}未找到 $tool，正在安装...${NC}"
            sudo apt install -y "$tool" || {
                echo -e "${LOG_ERROR}${RED}$tool 安装失败！${NC}"
                return 1
            }
        fi
    done
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
        converted=$(date -d "$raw_time" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
        if [ -n "$converted" ]; then
            echo "$converted (可能为本地时间)"
        else
            echo "获取失败"
        fi
    fi
}

rollback_installation() {
    echo -e "${LOG_WARN}${YELLOW}安装过程中出错，正在回滚...${NC}"
    if [ -d "$DMR_DIR" ]; then
        sudo rm -rf "$DMR_DIR" && echo -e "${LOG_INFO}${GRAY}已清理安装目录：$DMR_DIR${NC}" || echo -e "${LOG_ERROR}回滚删除目录失败！"
    else
        echo -e "${LOG_INFO}${GRAY}安装目录不存在，无需回滚。${NC}"
    fi
}

# ===================== 更新脚本函数 =====================
update_script() {
    echo -e "${LOG_INFO}正在下载并更新脚本到 ${DMR_DIR}/${SCRIPT_NAME} …"
    if curl -sfL "$SCRIPT_UPDATE_URL" -o "$DMR_DIR/${SCRIPT_NAME}"; then
        chmod +x "$DMR_DIR/${SCRIPT_NAME}"
        echo -e "${LOG_SUCCESS}${GREEN}脚本已完成更新！${NC}"
        echo -e "${CYAN}即将重新加载新版脚本...${NC}"
        sleep 1
        exec "$DMR_DIR/${SCRIPT_NAME}" "$@"
    else
        echo -e "${LOG_ERROR}脚本更新失败，请检查网络或 URL"
    fi
}

rollback_update() {
    local backup_dir="$1"
    local configs_backup="$2"
    echo -e "${LOG_WARN}${YELLOW}更新失败，正在回滚...${NC}"
    if [ -d "$DMR_DIR" ]; then
        sudo rm -rf "$DMR_DIR" && echo -e "${LOG_INFO}${GRAY}已清理临时目录。${NC}"
    fi
    if [ -d "$backup_dir" ]; then
        sudo mv "$backup_dir" "$DMR_DIR" && echo -e "${LOG_SUCCESS}已恢复项目目录。${NC}"
    else
        echo -e "${LOG_ERROR}未找到备份目录：$backup_dir，回滚失败！${NC}"
    fi
    if [ -d "$configs_backup" ]; then
        sudo rm -rf "$DMR_DIR/configs" 2>/dev/null
        sudo mv "$configs_backup" "$DMR_DIR/configs" && echo -e "${LOG_SUCCESS}已恢复配置文件。${NC}"
    fi
    echo -e "${LOG_INFO}回滚完成。"
}

check_config() {
    if [ ! -d "$DMR_DIR/configs" ]; then return 1; fi
    if find "$DMR_DIR/configs" -maxdepth 1 -name "*DMR*" -print -quit | grep -q .; then
        return 0
    else
        return 1
    fi
}

get_local_version() {
    local file="$DMR_DIR/main.py"
    if [ -f "$file" ]; then
        grep -oP "VERSION\s*=\s*['\"]\K[0-9]+\.[0-9]+\.[0-9]+" "$file" || echo ""
    else
        echo ""
    fi
}

get_remote_version() {
    local url="${DMR_GITHUB_BASE}/raw/${GITHUB_BRANCH}/main.py"
    curl -sfL "$url" | grep -oP "VERSION\s*=\s*['\"]\K[0-9]+\.[0-9]+\.[0-9]+" || echo ""
}

fetch_github_times() {
    echo -e "${LOG_INFO}${GRAY}同步 GitHub 仓库信息...${NC}"
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
    local local_ver
    local_ver=$(get_local_version)
    release_version=$(get_remote_version)
    if [ -n "$local_ver" ] && [ -n "$release_version" ] && [ "$local_ver" != "$release_version" ]; then
        echo -e "\n${ORANGE}${BOLD}>>> 发现新版本: ${PINK}${release_version}${NC} ${GRAY}(本地: ${local_ver})${NC}"
        echo -e "${WHITE}更新说明: ${CYAN}${commit_message}${NC}"
        echo -e "${WHITE}建议运行选项 ${BOLD}[10]${NORMAL}${WHITE} 进行更新。${NC}"
        echo -e "${GRAY}按任意键继续...${NC}"
        read -n 1 -s -r
    fi
}

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

check_install_tools() {
    echo -e "${LOG_INFO}检查系统依赖工具...${NC}"
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar" "xz-utils" "git" "jq")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
            echo -e "${LOG_INFO}${YELLOW}缺少工具: $tool${NC}"
        fi
    done
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${LOG_INFO}正在尝试安装: ${missing_tools[*]}"
        sudo apt update && sudo apt install -y "${missing_tools[@]}" || return 1
    fi
    return 0
}

install_biliup_rs() {
    sudo mkdir -p "$BILIUP_DIR"
    pushd "$BILIUP_DIR" > /dev/null || return 1
    echo -e "${LOG_INFO}获取 biliupR 最新版本...${NC}"
    local latest_info
    latest_info=$(curl -sfL "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    local latest_version
    latest_version=$(jq -r '.tag_name' <<< "$latest_info")
    if [ -f "./biliup" ] && ./biliup -V 2>/dev/null | grep -q "$latest_version"; then
        echo -e "${LOG_SUCCESS}biliupR 已是最新版本 (${latest_version})。${NC}"
        popd > /dev/null; return 0
    fi
    local arch=$(uname -m)
    local asset_suffix=""
    case "$arch" in
        aarch64) asset_suffix="aarch64-linux.tar.xz" ;;
        armv7l|armv6l) asset_suffix="arm-linux.tar.xz" ;;
        x86_64) asset_suffix="x86_64-linux.tar.xz" ;;
        *) echo -e "${LOG_ERROR}不支持的架构：$arch"; popd > /dev/null; return 1 ;;
    esac
    local download_url=$(jq -r --arg suffix "$asset_suffix" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' <<< "$latest_info")
    local asset_filename=$(basename "$download_url")
    echo -e "${LOG_INFO}下载并解压 biliupR...${NC}"
    curl -fLo "$asset_filename" "$download_url" && tar -xJf "$asset_filename" --strip-components=1 && rm -f "$asset_filename"
    chmod +x ./biliup || { popd > /dev/null; rollback_installation; return 1; }
    echo -e "${LOG_SUCCESS}biliupR 安装完成！${NC}"
    popd > /dev/null; return 0
}

update_dmr() {
    require_installed || return 1

    if ! command -v rsync &>/dev/null; then
        sudo apt update && sudo apt install -y rsync
    fi

    read -p "$(echo -e "${YELLOW}是否确认更新 DanmakuRender v5？(y/n): ${NC}")" confirm_update
    [[ ! "$confirm_update" =~ ^[Yy]$ ]] && return 0

    echo -e "${LOG_INFO}开始更新程序...${NC}"
    pgrep -f "$DMR_CMD" > /dev/null && stop_dmr

    # ========= 备份 =========
    local backup_dir="/opt/DanmakuRender_backup_$(date +%Y%m%d_%H%M%S)"
    sudo mkdir -p "$backup_dir"

    local configs_backup_root="${DMR_DIR}/configs_backups"
    local configs_backup="${configs_backup_root}/configs_backup_$(date +%Y%m%d_%H%M%S)"
    sudo mkdir -p "$configs_backup_root"

    sudo cp -r "$DMR_DIR/configs" "$configs_backup"
    sudo cp -r "$DMR_DIR" "$backup_dir"

    # ========= 选择更新来源 =========
    echo -e "\n${CYAN}请选择更新来源：${NC}"
    echo -e "  ${GREEN}1) 最新提交 (开发分支)${NC} [默认]"
    echo -e "  ${GREEN}2) 最新稳定版 (Releases)${NC}"
    read -p "$(echo -e "${YELLOW}输入选择 [1/2]: ${NC}")" update_choice
    update_choice="${update_choice:-1}"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # ========= 拉取代码 =========
    if [[ "$update_choice" == "1" ]]; then
        echo -e "${LOG_INFO}使用开发分支最新提交进行更新...${NC}"
        if ! git clone -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$tmp_dir"; then
            rollback_update "$backup_dir" "$configs_backup"
            return 1
        fi
    else
        echo -e "${LOG_INFO}使用最新 Releases 稳定版进行更新...${NC}"
        local latest_tag
        latest_tag=$(curl -sfL "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest" \
            | jq -r '.tag_name // empty')

        if [ -z "$latest_tag" ]; then
            echo -e "${LOG_ERROR}获取最新 Releases 版本失败！${NC}"
            rollback_update "$backup_dir" "$configs_backup"
            return 1
        fi

        curl -fsL -o "${tmp_dir}/release.tar.gz" \
            "${DMR_GITHUB_BASE}/archive/refs/tags/${latest_tag}.tar.gz" || {
            rollback_update "$backup_dir" "$configs_backup"
            return 1
        }

        tar -xzf "${tmp_dir}/release.tar.gz" -C "$tmp_dir" || {
            rollback_update "$backup_dir" "$configs_backup"
            return 1
        }
    fi

    # ========= 覆盖更新（保留 configs） =========
    sudo rsync -a --exclude='configs' "$tmp_dir/" "$DMR_DIR/" || {
        rollback_update "$backup_dir" "$configs_backup"
        return 1
    }

    rm -rf "$tmp_dir"
    sudo rm -rf "$backup_dir"

    echo -e "${LOG_SUCCESS}更新成功！配置备份位于: ${configs_backup}${NC}"

    # ========= 更新状态信息 =========
    fetch_github_times
    return 0
}

install_dmr() {
    local rollback_needed=true
    trap 'if [[ "$rollback_needed" == true && $? -ne 0 ]]; then rollback_installation; fi' EXIT
    if [ -d "$DMR_DIR" ]; then
        echo -e "${LOG_WARN}程序已存在于 ${DMR_DIR}${NC}"
        read -p "$(echo -e "${YELLOW}是否要重新安装 Python 依赖？(y/n, 默认n): ${NC}")" reinstall_choice
        if [[ "${reinstall_choice:-n}" =~ ^[Yy]$ ]]; then
            pushd "$DMR_DIR" > /dev/null || return 1
            source venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt && deactivate
            popd > /dev/null
            echo -e "${LOG_SUCCESS}依赖重新安装完成！${NC}"
            rollback_needed=false; trap - EXIT; return 0
        fi
        rollback_needed=false; trap - EXIT; return 0
    fi
    echo -e "${LOG_INFO}开始全新安装 DanmakuRender v5...${NC}"
    check_install_tools || return 1
    echo -e "\n${CYAN}请选择安装来源：${NC}"
    echo -e "  ${GREEN}1) 最新提交 (开发分支)${NC} [默认]"
    echo -e "  ${GREEN}2) 最新稳定版 (Releases)${NC}"
    read -p "$(echo -e "${YELLOW}输入选择 [1/2]: ${NC}")" install_choice
    local tmp_dir=$(mktemp -d)
    if [[ "${install_choice:-1}" == "1" ]]; then
        git clone --depth 1 -b "$GITHUB_BRANCH" "${DMR_GITHUB_BASE}.git" "$DMR_DIR"
    else
        local latest_tag=$(curl -sfL "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest" | jq -r '.tag_name // empty')
        curl -fsL -o "${tmp_dir}/release.tar.gz" "${DMR_GITHUB_BASE}/archive/refs/tags/${latest_tag}.tar.gz"
        tar -xzf "${tmp_dir}/release.tar.gz" -C "$tmp_dir"
        sudo mv "$tmp_dir/${GITHUB_REPO}"* "$DMR_DIR"
    fi
    rm -rf "$tmp_dir"
    pushd "$DMR_DIR" > /dev/null || return 1
    python3 -m venv venv && source venv/bin/activate && pip install --upgrade pip
    [ -f "requirements.txt" ] && pip install -r requirements.txt
    deactivate; popd > /dev/null
    install_biliup_rs
    read -p "$(echo -e "${YELLOW}是否安装 JS 引擎 (Node.js & quickjs)? (y/N): ${NC}")" js_choice
    [[ "${js_choice:-n}" =~ ^[Yy]$ ]] && install_js_engine
    echo -e "\n${LOG_SUCCESS}${GREEN}${BOLD}安装完成！${NC}"
    # 已按要求：安装完成后不再记录安装时间（不写入 $INSTALL_DATE_FILE）
    sudo curl -sfL "$SCRIPT_UPDATE_URL" -o "$DMR_DIR/$SCRIPT_NAME"
    sudo chmod +x "$DMR_DIR/$SCRIPT_NAME"
    sudo ln -sf "$DMR_DIR/$SCRIPT_NAME" /usr/local/bin/d
    echo -e "${LOG_INFO}输入 ${CYAN}d${NC} 即可快速启动管理脚本。"
    rollback_needed=false; trap - EXIT; return 0
}

uninstall_dmr() {
    require_installed || return 1
    echo -e "${RED}${BOLD}!!! 警告：此操作将永久删除程序及所有配置 !!!${NC}"
    read -p "$(echo -e "${YELLOW}请输入 'yes' 以确认卸载: ${NC}")" confirm
    [[ "$confirm" != "yes" ]] && return 1
    pgrep -f "$DMR_CMD" > /dev/null && stop_dmr
    sudo rm -rf "$DMR_DIR"
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${LOG_SUCCESS}卸载完成！${NC}"; install_date=""; return 0
    fi
}

install_js_engine() {
    echo -e "${LOG_INFO}配置 JavaScript 环境...${NC}"
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    pushd "$DMR_DIR" > /dev/null || return 1
    source venv/bin/activate && pip install quickjs && deactivate
    popd > /dev/null
    echo -e "${LOG_SUCCESS}JS 环境就绪。${NC}"
}

start_dmr() {
    require_installed || return 1
    if ! check_config; then
         echo -e "${LOG_ERROR}配置文件未就绪，请检查 ${DMR_DIR}/configs/${NC}"; return 1
    fi
    if pgrep -f "$DMR_CMD" > /dev/null; then
        echo -e "${LOG_WARN}程序已在运行中。${NC}"; return 1
    fi
    pushd "$DMR_DIR" > /dev/null || return 1
    source venv/bin/activate
    local logs_dir="$DMR_DIR/nohup_logs"; mkdir -p "$logs_dir"
    local full_logpath="${logs_dir}/nohup_$(date +"%Y%m%d_%H%M%S").log"
    echo -e "${LOG_INFO}正在启动主程序...${NC}"
    nohup $DMR_CMD > "$full_logpath" 2>&1 &
    local pid=$!
    sleep 1
    if ps -p $pid > /dev/null; then
        echo $pid > "$DMR_DIR/dmr.pid"
        echo -e "${LOG_SUCCESS}启动成功！PID: $pid${NC}"
        deactivate; popd > /dev/null; return 0
    else
        echo -e "${LOG_ERROR}启动失败，请查看日志: ${full_logpath}${NC}"
        rm -f "$DMR_DIR/dmr.pid"; deactivate; popd > /dev/null; return 1
    fi
}

stop_dmr() {
    require_installed || return 1
    local pid_file="$DMR_DIR/dmr.pid"
    local stopped=false
    if [ -f "$pid_file" ]; then
        local pid_to_kill=$(cat "$pid_file")
        if ps -p "$pid_to_kill" > /dev/null; then
            echo -e "${LOG_INFO}正在停止进程 $pid_to_kill...${NC}"
            kill "$pid_to_kill" 2>/dev/null && sleep 1
            ps -p "$pid_to_kill" > /dev/null && kill -9 "$pid_to_kill"
            stopped=true
        fi
        rm -f "$pid_file"
    fi
    if [ "$stopped" = false ]; then
        pkill -f "$DMR_CMD" && stopped=true
    fi
    pkill -f "streamgears_wrapper.py" 2>/dev/null
    pkill -f "streamlink" 2>/dev/null
    echo -e "${LOG_SUCCESS}所有相关进程已停止。${NC}"
    return 0
}

stop_extra_processes() {
    echo -e "${LOG_INFO}清理录制及 ffmpeg 进程...${NC}"
    for pid in $(ps aux | grep -E '正在录制|ffmpeg' | grep -v grep | awk '{print $2}'); do
        kill "$pid" 2>/dev/null && echo -e "${GRAY}已清理进程 $pid${NC}"
    done
}

view_log() {
    require_installed || return 1
    local logs_dir="$DMR_DIR/nohup_logs"
    local latest=$(find "$logs_dir" -maxdepth 1 -type f -name "*.log" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)
    if [ -z "$latest" ]; then echo -e "${LOG_WARN}暂无日志文件。${NC}"; return 1; fi
    echo -e "${LOG_INFO}当前日志: ${CYAN}$(basename "$latest")${NC} (按 Q 退出)"
    tail -n 70 -F "$latest" &
    local tail_pid=$!
    stty -echo -icanon time 0 min 0
    while true; do
        read -r -n1 key
        [[ $key == "q" ]] && { kill "$tail_pid" 2>/dev/null; break; }
        ps -p "$tail_pid" > /dev/null || break
    done
    stty echo icanon; wait "$tail_pid" 2>/dev/null
}

run_test() {
    require_installed || return 1
    pushd "$DMR_DIR" > /dev/null || return 1
    source venv/bin/activate && python3 dryrun.py; local res=$?; deactivate; popd > /dev/null
    return $res
}

manual_render() {
    require_installed || return 1
    pushd "$DMR_DIR" > /dev/null || return 1
    source venv/bin/activate && python3 render_only.py; local res=$?; deactivate; popd > /dev/null
    return $res
}

delete_replays() {
    local dirs=("$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）")
    local files=()
    echo -e "${CYAN}${BOLD}== 视频文件列表 ==${NC}"
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        echo -e "\n${BLUE}[目录] ${d}${NC}"
        declare -A files_by_date
        declare -a date_list
        for f in "$d"/*; do
            [ -f "$f" ] || continue
            files+=("$f")
            local fdate=$(stat -c %y "$f" 2>/dev/null | cut -d' ' -f1 || date -r "$f" +%F)
            fdate=${fdate:-"未知日期"}
            if [[ ! " ${date_list[@]} " =~ " ${fdate} " ]]; then date_list+=("$fdate"); fi
            files_by_date["$fdate"]+="${#files[@]}|$(basename "$f")|$(du -h "$f" | awk '{print $1}')\n"
        done
        for dt in $(printf "%s\n" "${date_list[@]}" | sort -r); do
            echo -e "${ORANGE}▶ ${dt}${NC}"
            echo -e "${files_by_date[$dt]}" | while IFS='|' read -r idx name size; do
                [ -z "$idx" ] && continue
                printf "  ${CYAN}%2d)${NC} %-40s ${GREEN}[%s]${NC}\n" "$idx" "$name" "$size"
            done
        done
    done
    [ ${#files[@]} -eq 0 ] && { echo -e "${LOG_WARN}无可删除文件。${NC}"; return 0; }
    echo -ne "\n${YELLOW}请输入序号(空格分隔) 或 ${GREEN}Y${YELLOW}(全选) [默认N]: ${NC}"
    read sel
    sel=${sel:-N}; sel=${sel^^}
    [[ "$sel" == "N" ]] && return 0
    read -p "$(echo -e "${RED}确认删除？(y/N): ${NC}")" confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return 0
    if [[ "$sel" == "Y" ]]; then
        for f in "${files[@]}"; do rm -f "$f" && echo -e "${GRAY}已删除: $(basename "$f")${NC}"; done
    else
        for idx in $sel; do
            local f="${files[$((idx-1))]}"
            [ -f "$f" ] && rm -f "$f" && echo -e "${GRAY}已删除: $(basename "$f")${NC}"
        done
    fi
}

# ===================== 状态及主菜单 =====================
show_header() {
    clear
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "          ${WHITE}DanmakuRender v5 管理工具${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -n "$commit_time" ] && [ "$commit_time" != "获取失败" ]; then
        echo -e "${GRAY}最新提交: ${WHITE}${commit_time}${NC}"
    else
        echo -e "${GRAY}最新提交: ${RED}N/A (请检查网络)${NC}"
    fi
    if [ -n "$release_version" ]; then
        echo -e "${GRAY}远程版本: ${PINK}${release_version}${NC}"
    fi
    echo -e "${GRAY}──────────────────────────────────────────────────${NC}"
}

show_status() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "${LOG_INFO}当前状态: ${RED}未安装${NC}"
    else
        local local_version=$(get_local_version)
        echo -ne "${LOG_INFO}安装状态: ${GREEN}已安装${NC}"
        [ -n "$local_version" ] && echo -ne " ${CYAN}(v${local_version})${NC}"
        echo ""
        # 不再显示安装/更新时间（按用户要求移除）
    fi
}

require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
        echo -e "\n${LOG_ERROR}${RED}DanmakuRender v5 未安装！${NC}"
        echo -e "${YELLOW}请先运行选项 [1] 进行安装。${NC}"; return 1
    fi
    return 0
}

# ====== 替换：fetch_biliup_times() ======
fetch_biliup_times() {
    BILIUP_LOCAL_VERSION=""
    BILIUP_REMOTE_VERSION=""

    # 本地 biliup 可执行文件检测（更稳健）
    if [ -x "${BILIUP_DIR}/biliup" ]; then
        # biliup 输出格式如: biliup vX.Y.Z 或 biliup X.Y.Z，取最后一个字段并去 v 前缀
        BILIUP_LOCAL_VERSION=$("${BILIUP_DIR}/biliup" -V 2>/dev/null | awk '{print $NF}' | sed 's/^v//')
    else
        # 若在 PATH 中也可能存在 biliup，则再试一次查找
        if command -v biliup &>/dev/null; then
            BILIUP_LOCAL_VERSION=$(biliup -V 2>/dev/null | awk '{print $NF}' | sed 's/^v//')
        fi
    fi

    # 远程版本（静默失败）
    local latest_info
    latest_info=$(curl -sfL "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest" 2>/dev/null) || {
        BILIUP_REMOTE_VERSION=""
        return 0
    }
    BILIUP_REMOTE_VERSION=$(echo "$latest_info" | jq -r '.tag_name // empty' | sed 's/^v//')
}

main_menu() {
    check_dependencies || exit 1
    fetch_github_times
    get_install_date
    fetch_biliup_times

    while true; do
        running_pid=$(pgrep -f "$DMR_CMD" | head -n 1)

        show_header
        show_status

        echo -e "\n${BOLD}【 核心管理 】${NC}"
        echo -e " ${BLUE} 1.${NC} 安装程序"
        if [ -n "$running_pid" ]; then
            echo -e " ${BLUE} 2.${NC} ${RED}停止录制${NC} ${YELLOW}● 运行中 (PID:${running_pid})${NC}"
        else
            echo -e " ${BLUE} 2.${NC} ${GREEN}启动录制 (后台)${NC}"
        fi
        echo -e " ${BLUE} 3.${NC} 查看实时日志"
        echo -e " ${BLUE}10.${NC} 更新程序"
        echo -e " ${BLUE}11.${NC} ${RED}卸载程序${NC}"

        echo -e "\n${BOLD}【 功能扩展 】${NC}"

        # ===== biliupR 显示逻辑（仅在已安装时显示版本）=====
        if [ -n "$BILIUP_LOCAL_VERSION" ]; then
            echo -e " ${BLUE} 6.${NC} 视频文件管理      ${BLUE} 7.${NC} biliupR ${GREEN}[${BILIUP_LOCAL_VERSION}]${NC}"
        else
            echo -e " ${BLUE} 6.${NC} 视频文件管理      ${BLUE} 7.${NC} biliupR"
        fi
        # =====================================================

        echo -e " ${BLUE} 8.${NC} 字体安装菜单      ${BLUE} 9.${NC} JS 环境安装"

        echo -e "\n${BOLD}【 系统信息 】${NC}"

        if [[ -n "$BILIUP_LOCAL_VERSION" && -n "$BILIUP_REMOTE_VERSION" && "$BILIUP_REMOTE_VERSION" != "$BILIUP_LOCAL_VERSION" ]]; then
            echo -e " ${ORANGE}→ biliupR 有更新: ${BILIUP_REMOTE_VERSION} (当前 ${BILIUP_LOCAL_VERSION})${NC}"
        fi

        echo -e " ${BLUE}12.${NC} 更新脚本 [v${VERSION}]  ${BLUE}0.${NC} 退出"
        echo -e "${GRAY}──────────────────────────────────────────────────${NC}"

        read -p "$(echo -e "${BOLD}请选择操作: ${NC}")" choice
        case $choice in
            1) install_dmr ;;
            2) require_installed && {
                if [ -n "$running_pid" ]; then
                    if ps aux | grep -v grep | grep -q '正在录制'; then
                        read -p "检测到录制中，强制停止？(y/N): " sc
                        [[ "$sc" =~ ^[Yy]$ ]] && { stop_dmr; stop_extra_processes; }
                    else
                        stop_dmr; stop_extra_processes
                    fi
                else
                    check_config && start_dmr && view_log
                fi
            } ;;
            3) view_log ;;
            4) manual_render ;;
            5) run_test ;;
            6) delete_replays ;;
            7) bash <(wget -qO- https://raw.githubusercontent.com/mikamoe/DanmakuRender/refs/heads/v5/biliupR.sh) ;;
            8) bash <(wget -qO- https://raw.githubusercontent.com/mikamoe/DanmakuRender/refs/heads/v5/c-font.sh) ;;
            9) install_js_engine ;;
            10) update_dmr ;;
            11) uninstall_dmr && sudo rm -f /usr/local/bin/d ;;
            12) update_script ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入!${NC}" ;;
        esac

        echo -e "\n${GRAY}按任意键返回...${NC}"
        read -n1 -s
    done
}

main_menu
