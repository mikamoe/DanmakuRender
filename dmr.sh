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
DMR_GITHUB_BASE="https://github.com/SmallPeaches/DanmakuRender"

# biliup‑rs 项目信息（用于动态获取最新版本）
BILIUP_OWNER="biliup"
BILIUP_REPO="biliup-rs"
BILIUP_RELEASE_BASE="https://github.com/${BILIUP_OWNER}/${BILIUP_REPO}/releases/download"

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

# ===================== 公共函数 =====================
print_info() {
    # 参数1：信息内容
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} $1"
}

print_error() {
    # 参数1：错误信息内容
    echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} $1"
}

# 从目录中搜索视频文件，并由用户选择要处理的文件
# 参数1：搜索目录
# 参数2：返回的数组变量名（通过 indirect assignment 传递选中的文件列表）
select_video_files() {
    local search_dir="$1"
    local __resultvar="$2"
    # 搜索常见格式视频文件
    mapfile -t files < <(find "$search_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \) -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)
    if [ ${#files[@]} -eq 0 ]; then
         print_error "目录下没有视频文件！"
         return 1
    fi
    print_info "${CYAN}目录下的视频文件：${NC}"
    for i in "${!files[@]}"; do
         printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
    done
    echo "$(( ${#files[@]} + 1 )) ) 全部上传"
    echo "0 ) 返回上一级菜单"
    local selections
    while true; do
         read -p "请输入要上传的视频选项（数字，用空格分隔，0返回）： " -a selections
         if [[ " ${selections[@]} " =~ " 0 " ]]; then
             return 1
         fi
         local valid=true
         for num in "${selections[@]}"; do
             if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#files[@]} + 1 )); then
                 print_error "无效选项：$num"
                 valid=false
                 break
             fi
         done
         $valid && break
    done
    local all_option=$(( ${#files[@]} + 1 ))
    local video_paths=()
    if [[ " ${selections[@]} " =~ " $all_option " ]]; then
         video_paths=("${files[@]}")
    else
         for num in "${selections[@]}"; do
              if (( num >= 1 && num <= ${#files[@]} )); then
                  video_paths+=("${files[$((num-1))]}")
              else
                  print_error "无效选项：$num"
                  return 1
              fi
         done
    fi
    eval "$__resultvar=(\"\${video_paths[@]}\")"
}

# ===================== 辅助函数 =====================

# 检查必备工具：jq、curl 以及 git
check_dependencies() {
    print_info "Checking dependencies..."
    local required_tools=("jq" "curl" "git")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_info "未找到 $tool，正在安装..."
            sudo apt install -y "$tool" || {
                print_error "$tool 安装失败！"
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
    print_info "安装过程中出错，正在回滚..."
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" \
       && print_info "已删除安装目录：$DMR_DIR" \
       || print_error "回滚删除安装目录失败！"
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
    print_info "检查系统依赖工具..."
    local required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar" "xz")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_info "未找到 $tool，正在安装..."
            sudo apt install -y "$tool" || {
                print_error "$tool 安装失败！"
                return 1
            }
        fi
    done
}

# 安装 biliup‑rs 工具：自动获取最新版本，根据系统架构下载相应的二进制文件
install_biliup_rs() {
    cd "$BILIUP_DIR" || {
        print_error "进入 tools 目录失败！"
        return 1
    }
    print_info "获取 biliup-rs 最新版本信息..."
    local latest_info
    latest_info=$(curl -sf "https://api.github.com/repos/${BILIUP_OWNER}/${BILIUP_REPO}/releases/latest")
    if [ -z "$latest_info" ]; then
        print_error "获取 biliup-rs 最新版本信息失败！"
        return 1
    fi
    local latest_version
    latest_version=$(echo "$latest_info" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        print_error "解析 biliup-rs 版本失败！"
        return 1
    fi
    print_info "最新 biliup-rs 版本：${latest_version}"

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
            print_error "不支持的架构：$arch"
            return 1
            ;;
    esac
    print_info "检测到系统架构：$arch，选择资源文件：${asset}"

    local asset_file="biliupR-${latest_version}-${asset}"
    local download_url="${BILIUP_RELEASE_BASE}/${latest_version}/${asset_file}"
    print_info "下载 URL：${download_url}"

    print_info "正在下载 biliup-rs..."
    curl -LO "$download_url" || {
        print_error "下载 biliup-rs 失败！"
        return 1
    }
    print_info "正在解压 ${asset_file}..."
    tar -xJvf "$asset_file" || {
        print_error "解压 biliup-rs 失败！"
        return 1
    }

    # 查找解压后的文件夹，移动二进制文件到当前目录，并删除临时文件夹
    local extracted_folder
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        print_error "未找到解压后的文件夹！"
        return 1
    fi
    if [ ! -f "$extracted_folder/biliup" ]; then
        print_error "未在解压文件夹中找到 biliup 文件！"
        return 1
    fi
    mv "$extracted_folder/biliup" . || {
        print_error "移动 biliup 文件失败！"
        return 1
    }
    rm -rf "$extracted_folder" || {
        print_error "删除解压文件夹失败！"
        return 1
    }
    print_info "安装 biliup-rs 完成！"
}

# 更新 biliup‑rs：删除旧的二进制文件后重新安装
update_biliup_rs() {
    cd "$BILIUP_DIR" || {
        print_error "进入 tools 目录失败！"
        return 1
    }
    print_info "正在更新 biliup-rs..."
    rm -f "$BILIUP_DIR/biliup" || {
        print_error "删除旧的 biliup 文件失败！"
        return 1
    }
    install_biliup_rs
}

# 更新 DanmakuRender v5：备份当前安装、使用 git 更新代码、重建虚拟环境及安装依赖
update_dmr() {
    require_installed || return 1
    read -p "是否进行更新？(y/n): " update_choice
    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
         return 0
    fi

    echo -e "${YELLOW}更新前将删除现有的直播回放及直播回放（弹幕版）目录，请确保重要文件已备份。${NC}"
    read -p "是否删除这两个目录？(y/n): " delete_choice
    if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
        [ -d "$DMR_DIR/直播回放" ] && sudo rm -rf "$DMR_DIR/直播回放" && print_info "已删除 直播回放 目录" || echo -e "${YELLOW}直播回放 目录不存在${NC}"
        [ -d "$DMR_DIR/直播回放（弹幕版）" ] && sudo rm -rf "$DMR_DIR/直播回放（弹幕版）" && print_info "已删除 直播回放（弹幕版） 目录" || echo -e "${YELLOW}直播回放（弹幕版） 目录不存在${NC}"
    else
        echo -e "${YELLOW}未删除直播回放目录，更新过程将继续。${NC}"
    fi

    sudo apt update && sudo apt install rsync -y

    if pgrep -f "$DMR_CMD" > /dev/null; then
         print_info "正在停止运行中的进程..."
         stop_dmr
    fi

    # 备份configs目录，保证用户自定义配置不被更新覆盖
    update_fail=0
    if [ -d "$DMR_DIR/configs" ]; then
         configs_backup=$(mktemp -d)
         print_info "正在备份configs目录到 ${YELLOW}$configs_backup${NC} ..."
         if ! sudo cp -r "$DMR_DIR/configs" "$configs_backup"; then
              print_error "configs目录备份失败！"
              update_fail=1
         fi
    fi

    backup_dir="${DMR_DIR}_backup_$(date +%s)"
    print_info "正在备份主目录到 ${YELLOW}$backup_dir${NC} ..."
    if ! sudo cp -r "$DMR_DIR" "$backup_dir"; then
         print_error "备份失败！"
         return 1
    fi

    cd "$DMR_DIR" || { print_error "进入目录失败！"; update_fail=1; }
    print_info "正在更新代码..."
    git fetch origin || { print_error "git fetch 失败！"; update_fail=1; }
    git reset --hard origin/$GITHUB_BRANCH || { print_error "git reset 失败！"; update_fail=1; }

    # 恢复configs目录，避免更新过程中丢失用户配置
    if [ -n "$configs_backup" ] && [ -d "$configs_backup/configs" ]; then
         print_info "正在恢复configs目录..."
         sudo rm -rf "$DMR_DIR/configs"
         sudo mv "$configs_backup/configs" "$DMR_DIR/"
    fi

    print_info "正在删除旧虚拟环境..."
    [ -d "venv" ] && rm -rf venv || true

    print_info "正在创建新的虚拟环境..."
    if ! python3 -m venv venv; then
         print_error "创建虚拟环境失败！"
         update_fail=1
    fi

    print_info "正在激活虚拟环境并安装 Python 依赖..."
    if ! source venv/bin/activate; then
         print_error "激活虚拟环境失败！"
         update_fail=1
    fi
    if ! pip install --quiet --upgrade pip; then
         print_error "pip 升级失败！"
         update_fail=1
    fi
    if ! pip install -r requirements.txt; then
         print_error "Python 依赖安装失败！"
         update_fail=1
    fi
    deactivate

    if [ "$update_fail" -eq 1 ]; then
         print_error "更新过程中出现错误，正在恢复备份..."
         sudo rm -rf "$DMR_DIR"
         sudo mv "$backup_dir" "$DMR_DIR"
         print_error "恢复备份完成！"
         return 1
    else
         print_info "更新成功！"
         sudo rm -rf "$backup_dir"
         print_info "正在记录更新日期..."
         date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || print_error "记录更新日期失败！"
         fetch_github_times
         get_install_date
    fi
}

# 安装 DanmakuRender v5：使用 git clone 下载、设置虚拟环境、安装依赖及其他工具
install_dmr() {
    local rollback_needed=true
    # 设置安装错误时自动回滚
    trap '[[ "$rollback_needed" = true ]] && rollback_installation' EXIT

    if [ -d "$DMR_DIR" ]; then
        print_info "DanmakuRender V5 已经安装！"
        read -p "是否要重新安装Python依赖？(y/n) " reinstall_choice
        if [[ ! $reinstall_choice =~ ^[Yy]$ ]]; then
            print_info "已取消重新安装"
            return 0
        fi
        print_info "正在重新安装Python依赖..."
        cd "$DMR_DIR" || { print_error "进入目录失败！"; return 1; }
        [ -d "venv" ] && rm -rf venv
        print_info "创建新的虚拟环境..."
        python3 -m venv venv || { print_error "创建虚拟环境失败！"; return 1; }
        source venv/bin/activate || { print_error "激活虚拟环境失败！"; return 1; }
        pip install --quiet --upgrade pip || { print_error "pip 升级失败！"; return 1; }
        pip install -r requirements.txt || { print_error "Python 依赖安装失败！"; return 1; }
        deactivate
        print_info "Python依赖重新安装完成！"
        return 0
    fi

    print_info "正在安装必要工具..."
    sudo apt update || { print_error "apt update 失败！"; return 1; }
    sudo apt install -y unzip curl wget xz-utils git || { print_error "必要工具安装失败！"; return 1; }
    print_info "必要工具安装完成！"

    print_info "正在使用 git 克隆 DanmakuRender v5..."
    if ! git clone --depth 1 --branch "$GITHUB_BRANCH" "$DMR_GITHUB_BASE.git" "$DMR_DIR"; then
         print_error "Git clone 失败！"
         return 1
    fi
    print_info "代码克隆完成！"

    cd "$DMR_DIR" || { print_error "进入目录失败！"; return 1; }
    print_info "安装 python3-venv..."
    sudo apt install python3-venv -y || { print_error "python3-venv 安装失败！"; return 1; }
    print_info "创建虚拟环境..."
    python3 -m venv venv || { print_error "创建虚拟环境失败！"; return 1; }
    print_info "激活虚拟环境..."
    source venv/bin/activate || { print_error "激活虚拟环境失败！"; return 1; }
    pip install --quiet --upgrade pip || { print_error "pip 升级失败！"; return 1; }
    print_info "安装 Python 依赖..."
    pip install -r requirements.txt || { print_error "Python 依赖安装失败！"; return 1; }
    deactivate

    print_info "正在安装 ffmpeg..."
    sudo apt install ffmpeg -y || { print_error "ffmpeg 安装失败！"; return 1; }
    print_info "ffmpeg 安装完成！"

    install_biliup_rs || { print_error "biliup-rs 安装失败！"; return 1; }

    print_info "DanmakuRender v5 安装完成！"
    print_info "记录安装日期..."
    date +%s | sudo tee "$INSTALL_DATE_FILE" > /dev/null || {
        print_error "记录安装日期失败！"
        return 1
    }
    get_install_date

    # 安装完成后询问是否安装 JavaScript 解释器和 JS 引擎
    read -p "安装完成，是否安装 JavaScript 解释器和 JS 引擎？(y/n): " js_choice
    if [[ "$js_choice" =~ ^[Yy]$ ]]; then
         install_js_engine
    fi

    # 统一保留一个按键提示
    read -n 1 -s -r -p "按任意键继续..."
    echo ""

    rollback_needed=false
    trap - EXIT
}

# 卸载 DanmakuRender v5：提醒用户请自行备份配置文件后删除安装目录
uninstall_dmr() {
    require_installed || return 1
    print_info "请确保您已备份配置文件！"
    rm -rf "$DMR_DIR" \
      && print_info "卸载完成！" \
      || print_error "卸载失败！"
}

# ===================== 运行与测试管理函数 =====================

# 启动 DanmakuRender v5：激活虚拟环境并使用 nohup 后台运行
start_dmr() {
    require_installed || return 1
    cd "$DMR_DIR" && source venv/bin/activate
    nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$DMR_DIR/dmr.pid"
    print_info "启动成功！PID: $pid"
}

# 停止 DanmakuRender v5：依据 PID 文件或进程名停止服务
stop_dmr() {
    require_installed || return 1
    if [ -f "$DMR_DIR/dmr.pid" ]; then
        local pid
        pid=$(cat "$DMR_DIR/dmr.pid")
        kill "$pid" && print_info "已停止进程 $pid" && rm "$DMR_DIR/dmr.pid"
    else
        pkill -f "$DMR_CMD" && print_info "已停止"
    fi
}

# 实时查看日志，支持按 q 键退出
view_log() {
    require_installed || return 1
    print_info "按 q 键退出日志查看"
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
    print_info "正在运行测试..."
    cd "$DMR_DIR" || { print_error "进入目录失败！"; return 1; }
    source venv/bin/activate || { print_error "激活虚拟环境失败！"; return 1; }
    python3 dryrun.py || { print_error "测试运行失败！"; return 1; }
    deactivate
    print_info "测试运行完成！"
}

# 手动渲染视频：调用 render_only.py 进行渲染
manual_render() {
    require_installed || return 1
    cd "$DMR_DIR" || { print_error "进入目录失败！"; return 1; }
    source venv/bin/activate || { print_error "激活虚拟环境失败！"; return 1; }
    python3 render_only.py || { print_error "渲染失败！"; return 1; }
    deactivate
}

# 删除回放/渲染文件：列出目录内容后，确认是否删除所有文件
delete_replays() {
    require_installed || return 1
    print_info "${CYAN}直播回放目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放${NC}"
    echo -e "\n${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}直播回放（弹幕版）目录内容：${NC}"
    ls -lh "$DMR_DIR/直播回放（弹幕版）" 2>/dev/null || echo -e "${YELLOW}目录不存在：直播回放（弹幕版）${NC}"
    read -p $'\n是否要删除所有回放文件？(y/n) ' confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf "$DMR_DIR/直播回放" "$DMR_DIR/直播回放（弹幕版）"
        print_info "已删除所有回放文件"
    else
        print_info "已取消删除操作"
    fi
}

# ===================== 字体安装相关函数 =====================

# 安装微软雅黑和 Emoji 字体：从指定链接下载字体文件并移动至系统字体目录
install_fonts() {
    require_installed || return 1
    print_info "正在下载并安装微软雅黑和 Emoji 字体..."
    sudo mkdir -p /usr/share/fonts/truetype/microsoft || { print_error "创建字体目录失败！"; return 1; }
    if ! wget -O /tmp/msyh.ttf "$FONT_MSYH_URL"; then
        print_error "下载微软雅黑字体失败！"
        return 1
    fi
    sudo mv /tmp/msyh.ttf /usr/share/fonts/truetype/microsoft/ || { print_error "移动微软雅黑字体失败！"; return 1; }
    print_info "已安装微软雅黑字体！"
    fc-list | grep "Microsoft YaHei" || { print_error "未找到微软雅黑字体！"; return 1; }
    print_info "正在刷新字体缓存..."
    sudo fc-cache -fv > /dev/null 2>&1 || { print_error "刷新字体缓存失败！"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { print_error "安装 Emoji 字体包失败！"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { print_error "刷新字体缓存失败！"; return 1; }
    print_info "微软雅黑和 Emoji 字体安装完成！"
}

# 安装阿里巴巴普惠体和 Emoji 字体：同上，使用不同的下载链接
install_alibaba_fonts() {
    require_installed || return 1
    print_info "正在下载并安装阿里巴巴普惠体和 Emoji 字体..."
    sudo mkdir -p /usr/share/fonts/truetype/AlibabaPuHuiTi || { print_error "创建字体目录失败！"; return 1; }
    if ! wget -O /tmp/AlibabaPuHuiTi.ttf "$FONT_ALIBABA_URL"; then
        print_error "下载阿里巴巴普惠体失败！"
        return 1
    fi
    sudo mv /tmp/AlibabaPuHuiTi.ttf /usr/share/fonts/truetype/AlibabaPuHuiTi/ || { print_error "移动阿里巴巴普惠体失败！"; return 1; }
    print_info "已安装阿里巴巴普惠体！"
    fc-list | grep "Alibaba PuHuiTi" || { print_error "未找到阿里巴巴普惠体！"; return 1; }
    print_info "正在刷新字体缓存..."
    sudo fc-cache -fv > /dev/null 2>&1 || { print_error "刷新字体缓存失败！"; return 1; }
    sudo apt install -y fonts-noto fonts-noto-extra fonts-noto-cjk fonts-symbola fonts-noto-color-emoji > /dev/null 2>&1 || { print_error "安装 Emoji 字体包失败！"; return 1; }
    sudo fc-cache -fv > /dev/null 2>&1 || { print_error "刷新字体缓存失败！"; return 1; }
    print_info "阿里巴巴普惠体和 Emoji 字体安装完成！"
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
            *) print_error "无效选项！" ;;
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

# 哔哩哔哩视频追加上传
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


# ===================== 新增：安装 JavaScript 解释器和 JS 引擎 =====================
install_js_engine() {
    print_info "正在安装 Node.js 和 npm..."
    sudo apt install -y nodejs npm || { print_error "Node.js 和 npm 安装失败！"; return 1; }
    print_info "切换到主目录并激活虚拟环境..."
    cd "$DMR_DIR" || { print_error "进入目录失败！"; return 1; }
    source venv/bin/activate || { print_error "激活虚拟环境失败！"; return 1; }
    pip install quickjs || { print_error "quickjs 安装失败！"; deactivate; return 1; }
    deactivate
    print_info "JavaScript解释器和 JS 引擎安装完成！"
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
        print_error "Python3 未安装或未检测到！"
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
        print_error "DanmakuRender v5 未安装，请先选择安装选项（1）进行安装！"
        return 1
    fi
    return 0
}

# 主菜单：循环显示菜单供用户选择操作
main_menu() {
    check_dependencies || { print_error "依赖检查失败，脚本终止"; exit 1; }
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
        echo -e "${BLUE}${BOLD}10.${NC}${NORMAL}${LIGHT_BLUE}更新DanmakuRender v5"
        echo -e "${BLUE}${BOLD}11.${NC}${NORMAL}${RED}${BOLD}卸载DanmakuRender v5"
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
                        print_error "配置文件未正确配置"
                    fi
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            3)
                if require_installed; then
                    view_log; skip_read=true
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            4)
                if require_installed; then
                    manual_render
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            5)
                if require_installed; then
                    run_test
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            6)
                if require_installed; then
                    delete_replays
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            7)
                if require_installed; then
                    biliup_menu; skip_read=true
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            8)
                if require_installed; then
                    font_menu
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            9)
                if require_installed; then
                    read -p "是否安装 JavaScript 解释器和 JS 引擎？(y/n): " js_ans
                    if [[ "$js_ans" =~ ^[Yy]$ ]]; then
                        install_js_engine
                        read -n 1 -s -r -p "按任意键继续..."
                    fi
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            10)
                if require_installed; then
                    update_dmr
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                fetch_github_times
                get_install_date
                skip_read=false
                ;;
            11)
                if require_installed; then
                    uninstall_dmr
                else
                    print_error "请先安装DanmakuRender v5!"
                fi
                skip_read=false
                ;;
            0) exit 0 ;;
            *) print_error "无效选项！"; skip_read=false ;;
        esac

        if [ "$skip_read" = false ]; then
            read -n 1 -s -r -p "按任意键继续..."
        fi
    done
}

# ===================== 脚本入口 =====================
main_menu
