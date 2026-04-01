#!/usr/bin/env bash

#######################
# 配色和格式化
#######################
BOLD="\033[1m"
RESET="\033[0m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
CYAN="\033[36m"
PURPLE="\033[35m"
ORANGE="\033[38;5;208m"
GRAY="\033[90m"
NC="\033[0m"

# 交互反馈样式
LOG_INFO="${BLUE}${BOLD}[i]${NC} "
LOG_SUCCESS="${GREEN}${BOLD}[✓]${NC} "
LOG_WARN="${YELLOW}${BOLD}[!]${NC} "
LOG_ERROR="${RED}${BOLD}[✗]${NC} "

info()    { echo -e "${LOG_INFO}${RESET}$1"; }
success() { echo -e "${LOG_SUCCESS}${RESET}$1"; }
error()   { echo -e "${LOG_ERROR}${RESET}$1"; }
warning() { echo -e "${LOG_WARN}${RESET}$1"; }
highlight(){ echo -e "${CYAN}${BOLD}$1${RESET}"; }
divider()  { echo -e "${GRAY}──────────────────────────────────────────────────${RESET}"; }

#######################
# 基础变量
#######################
INSTALL_DIR="/opt/DanmakuRender-5/tools"
DMR_DIR="/opt/DanmakuRender-5"
BINARY_PATH="$INSTALL_DIR/biliup"
GITHUB_API="https://api.github.com/repos/biliup/biliup/releases"
LAST_BV_FILE="$INSTALL_DIR/last_bvs.txt"

declare -a selected_video_paths=()

#######################
# 依赖检查
#######################
check_dependencies(){
  local missing_deps=()
  for cmd in curl jq tar; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_deps+=("$cmd")
    fi
  done
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    error "以下依赖未安装：sudo apt-get install -y ${missing_deps[*]}"
    exit 1
  fi
}

#######################
# 显示状态信息
#######################
show_version_and_dir(){
  echo -e "${GRAY}系统状态:${RESET}"
  if [[ -x "$BINARY_PATH" ]]; then
    VER=$("$BINARY_PATH" -V 2>/dev/null || printf "")
    if [[ -n "$VER" ]]; then
      echo -e "  核心版本：${GREEN}$VER${RESET}"
    else
      echo -e "  核心版本：${RED}未获取到版本信息${RESET}"
    fi
  else
    echo -e "  核心版本：${RED}未安装${RESET}"
  fi
  echo -e "  工作目录：${BLUE}$INSTALL_DIR${RESET}"
}

#######################
# 获取系统架构
#######################
get_arch(){
  case "$(uname -m)" in
    x86_64)  echo "x86_64";;
    aarch64) echo "aarch64";;
    armv7l|armv7*) echo "armv7";;
    *)       echo "$(uname -m)";;
  esac
}

#######################
# 版本选择与安装
#######################
select_and_install(){
  ARCH=$(get_arch)
  info "检测到系统架构: ${CYAN}$ARCH${RESET}"
  info "正在获取 GitHub 版本列表..."

  mapfile -t lines < <(curl -s "$GITHUB_API" | \
    jq -r --arg arch "$ARCH" '
      .[] | {
        tag: .tag_name,
        date: .published_at,
        assets: [
          .assets[] | select(.name | test("linux";"i") and test($arch;"i"))
        ] | sort_by(.name | test("\\.tar\\.gz$") | not)
      } | select(.assets | length > 0) | {
        tag: .tag,
        date: .date,
        url: (.assets[0].browser_download_url)
      } | "\(.tag) \(.date) \(.url)"
    ' | sort -rV | head -n 10)

  if [[ ${#lines[@]} -eq 0 ]]; then
    error "未找到匹配架构 ${RED}$ARCH${RESET} 的发行版本"
    return 1
  fi

  echo -e "\n${BOLD}可用版本列表：${RESET}"
  for i in "${!lines[@]}"; do
    num=$((i+1))
    tag=$(echo "${lines[$i]}" | awk '{print $1}')
    date_raw=$(echo "${lines[$i]}" | awk '{print $2}')
    date_fmt=${date_raw:0:10}
    printf " %2d) ${CYAN}%-12s${RESET} [%s]\n" "$num" "$tag" "$date_fmt"
  done

  read -p $'\n请选择安装序号 (0 取消): ' choice
  [[ "$choice" == "0" || -z "$choice" ]] && return
  idx=$((choice-1))
  if ! [[ $idx -ge 0 && $idx -lt ${#lines[@]} ]]; then
    error "输入无效"; return 1
  fi

  sel_line=${lines[$idx]}
  VERSION=$(echo "$sel_line" | awk '{print $1}')
  URL=$(echo "$sel_line" | awk '{print $3}')
  ARCHIVE_NAME=$(basename "$URL")

  info "开始下载 ${CYAN}$VERSION${RESET}..."
  cd "$INSTALL_DIR" || return 1
  curl -L -o "$ARCHIVE_NAME" "$URL" || { error "下载失败"; return 1; }

  info "正在解压并配置..."
  case "$ARCHIVE_NAME" in
    *.tar.gz|*.tgz)   tar -xvzf "$ARCHIVE_NAME" >/dev/null 2>&1 ;;
    *.tar.xz)         tar -xvJf "$ARCHIVE_NAME" >/dev/null 2>&1 ;;
    *.zip)            unzip -o "$ARCHIVE_NAME" >/dev/null 2>&1 ;;
    *)                error "未知格式: $ARCHIVE_NAME"; return 1 ;;
  esac

  EXTRACT_DIR=$(tar -tf "$ARCHIVE_NAME" 2>/dev/null | head -1 | cut -f1 -d"/")
  if [[ -f "$EXTRACT_DIR/biliup" ]]; then
    mv "$EXTRACT_DIR/biliup" "$INSTALL_DIR/"
    chmod +x "$BINARY_PATH"
    success "已成功安装版本: ${GREEN}$VERSION${RESET}"
  else
    error "解压后未找到二进制文件"
  fi

  rm -rf "$EXTRACT_DIR" "$ARCHIVE_NAME"
}

#######################
# 登录功能
#######################
login_biliup(){
  info "启动登录流程..."
  cd "$INSTALL_DIR" && "$BINARY_PATH" login
}

renew_biliup(){
  info "刷新登录状态..."
  cd "$INSTALL_DIR" && "$BINARY_PATH" renew
}

#######################
# 视频文件选择逻辑
#######################
select_video_files() {
    local dir="$1"
    local mode="$2"
    local files=()
    selected_video_paths=()

    if [[ ! -d "$dir" ]]; then
        error "路径不存在: $dir"
        return 1
    fi

    info "扫描目录: ${BLUE}$dir${RESET}"
    mapfile -t files < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.webm" \) | sort)

    if [[ ${#files[@]} -eq 0 ]]; then
        warning "未发现支持的视频文件。"
        return 1
    fi

    declare -A files_by_date=()
    declare -a date_list=()
    for filepath in "${files[@]}"; do
        local fdate
        fdate=$(stat -c %y "$filepath" 2>/dev/null | cut -d' ' -f1)
        [ -z "$fdate" ] && fdate=$(date -r "$filepath" +%F 2>/dev/null)
        [ -z "$fdate" ] && fdate="未知日期"

        if [ -z "${files_by_date[$fdate]+_}" ]; then
            files_by_date["$fdate"]="$filepath"
            date_list+=("$fdate")
        else
            files_by_date["$fdate"]="${files_by_date[$fdate]}"$'\n'"$filepath"
        fi
    done

    IFS=$'\n' sorted_dates=($(printf "%s\n" "${date_list[@]}" | sort))
    unset IFS

    echo -e "\n${BOLD}待选视频列表：${RESET}"
    local total=${#files[@]}
    local num_width=${#total}

    for date in "${sorted_dates[@]}"; do
        echo -e "\n${ORANGE}日期: $date${RESET}"
        IFS=$'\n'
        for fp in ${files_by_date[$date]}; do
            [ -f "$fp" ] || continue
            local index=""
            for ((ii=0; ii<${#files[@]}; ii++)); do
                [[ "${files[ii]}" == "$fp" ]] && index=$((ii+1)) && break
            done
            printf " %${num_width}d) ${BLUE}%-40s${RESET} [%s]\n" \
                "$index" "$(basename "$fp")" "$(du -h "$fp" | cut -f1)"
        done
        unset IFS
    done

    if [[ "$mode" == "single" ]]; then
        read -p $'\n请输入编号 (0 取消): ' choice
        [[ "$choice" == "0" || -z "$choice" ]] && return 1
        idx=$((choice-1))
        [[ $idx -ge 0 && $idx -lt ${#files[@]} ]] && selected_video_paths+=("${files[$idx]}") || { error "无效选择"; return 1; }
    else
        read -p $'\n请输入编号 (空格分隔多个，0 取消): ' -a choices
        [[ "${choices[0]}" == "0" || -z "${choices[0]}" ]] && return 1
        for choice in "${choices[@]}"; do
            idx=$((choice-1))
            [[ $idx -ge 0 && $idx -lt ${#files[@]} ]] && selected_video_paths+=("${files[$idx]}")
        done
        [[ ${#selected_video_paths[@]} -eq 0 ]] && { error "未选择有效文件"; return 1; }
    fi
    return 0
}

#######################
# 上传流程
#######################
upload_video(){
    info "初始化上传配置..."
    local upload_cmd_parts=("$BINARY_PATH" "upload")
    
    echo -e "\n${CYAN}1. 提交接口:${RESET}"
    local submit_options=("client" "app" "web")
    for i in "${!submit_options[@]}"; do printf "   [%d] %s\n" "$((i+1))" "${submit_options[$i]}"; done
    read -p "   选择 [默认 1]: " s_choice
    upload_cmd_parts+=("--submit" "${submit_options[$(( ${s_choice:-1} - 1 ))]:-client}")

    echo -e "\n${CYAN}2. 上传线路 (回车自动):${RESET}"
    local line_options=("bda2" "ws" "qn" "bldsa" "tx" "txa" "bda" "alia")
    for i in "${!line_options[@]}"; do printf "   [%d] %-6s" "$((i+1))" "${line_options[$i]}"; [[ $(( (i+1) % 4 )) -eq 0 ]] && echo ""; done
    echo ""
    read -p "   选择序号: " l_choice
    if [[ -n "$l_choice" ]]; then
        local sel_line="${line_options[$((l_choice-1))]}"
        [[ -n "$sel_line" ]] && upload_cmd_parts+=("--line" "$sel_line")
    fi

    echo -e "\n${CYAN}3. 常规设置:${RESET}"
    read -p "   并发数 [默认 3]: " limit_in
    upload_cmd_parts+=("--limit" "${limit_in:-3}")
    read -p "   分区 ID [默认 65]: " tid_in
    upload_cmd_parts+=("--tid" "${tid_in:-65}")

    while true; do
        read -p "   标签 (必填，逗号分隔) [默认: 直播回放]: " tag_in
        tag_val="${tag_in:-直播回放}"
        [[ -n "$tag_val" ]] && upload_cmd_parts+=("--tag" "$tag_val") && break
    done

    # 来源选择
    while true; do
        echo -e "\n${BOLD}请选择文件来源：${RESET}"
        echo -e "  [1] 直播回放  [2] 弹幕版  [3] 手动路径  [0] 取消"
        read -p "  输入选项: " src_choice
        case $src_choice in
            1) select_video_files "$DMR_DIR/直播回放" "multiple" && break ;;
            2) select_video_files "$DMR_DIR/直播回放（弹幕版）" "multiple" && break ;;
            3) read -p "  输入绝对路径: " -a selected_video_paths; break ;;
            0) return 0 ;;
        esac
    done

    for fp in "${selected_video_paths[@]}"; do upload_cmd_parts+=("$fp"); done
    
    divider
    info "即将执行: ${upload_cmd_parts[*]}"
    read -p "确认上传？(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && (cd "$INSTALL_DIR" && "${upload_cmd_parts[@]}")
}

#######################
# 追加流程
#######################
append_video(){
    info "初始化追加程序..."
    local append_cmd_parts=("$BINARY_PATH" "append")
    
    local recent_bvs=()
    [[ -f "$LAST_BV_FILE" ]] && mapfile -t recent_bvs < "$LAST_BV_FILE"

    echo -e "\n${CYAN}选择目标 BV 号:${RESET}"
    local i=1
    for b in "${recent_bvs[@]}"; do
        [[ -n "$b" ]] || continue
        printf "   [%d] 历史: %s\n" "$i" "$b"
        ((i++))
    done
    printf "   [%d] 输入新 BV 号\n" "$i"
    read -p "   选择: " bv_choice
    
    local sel_bv=""
    if [[ "$bv_choice" =~ ^BV[a-zA-Z0-9]{10}$ ]]; then
        # 允许直接在“选择”这里粘贴 BV 号
        sel_bv="$bv_choice"
    elif [[ "$bv_choice" =~ ^[0-9]+$ ]]; then
        if (( bv_choice >= 1 && bv_choice < i )); then
            sel_bv="${recent_bvs[$((bv_choice-1))]}"
        elif (( bv_choice == i )); then
            read -p "   输入新 BV 号: " sel_bv
        else
            error "选择无效"; return 1
        fi
    else
        read -p "   输入新 BV 号: " sel_bv
    fi

    if [[ ! "$sel_bv" =~ ^BV[a-zA-Z0-9]{10}$ ]]; then
        error "BV 号无效"; return 1
    fi

    # 更新历史
    local temp_bvs=("$sel_bv")
    for b in "${recent_bvs[@]}"; do [[ -n "$b" && "$b" != "$sel_bv" ]] && temp_bvs+=("$b"); done
    printf "%s\n" "${temp_bvs[@]:0:3}" > "$LAST_BV_FILE"
    append_cmd_parts+=("--vid" "$sel_bv")

    echo -e "\n${CYAN}追加线路 (回车自动):${RESET}"
    local line_options=("bda2" "ws" "qn" "bldsa" "tx" "txa" "bda" "alia")
    for i in "${!line_options[@]}"; do printf "   [%d] %-6s" "$((i+1))" "${line_options[$i]}"; [[ $(( (i+1) % 4 )) -eq 0 ]] && echo ""; done
    echo ""
    read -p "   选择序号: " l_choice
    if [[ -n "$l_choice" ]]; then
        local sel_line="${line_options[$((l_choice-1))]}"
        [[ -n "$sel_line" ]] && append_cmd_parts+=("--line" "$sel_line")
    fi

    read -p "   并发数 [默认 3]: " limit_in
    append_cmd_parts+=("--limit" "${limit_in:-3}")

    while true; do
        echo -e "\n${BOLD}请选择追加文件来源：${RESET}"
        echo -e "  [1] 直播回放  [2] 弹幕版  [3] 手动路径  [0] 返回"
        read -p "  选择: " t_choice
        case $t_choice in
            1) select_video_files "$DMR_DIR/直播回放" "multiple" && break ;;
            2) select_video_files "$DMR_DIR/直播回放（弹幕版）" "multiple" && break ;;
            3) read -p "  输入绝对路径: " -a selected_video_paths; break ;;
            0) return 0 ;;
        esac
    done

    for fp in "${selected_video_paths[@]}"; do append_cmd_parts+=("$fp"); done
    divider
    info "即将执行: ${append_cmd_parts[*]}"
    read -p "确认追加？(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && (cd "$INSTALL_DIR" && "${append_cmd_parts[@]}")
}

show_video_details(){
    read -p $'\n请输入 BV 号 (0 返回): ' bv
    [[ "$bv" == "0" || -z "$bv" ]] && return
    (cd "$INSTALL_DIR" && "$BINARY_PATH" "$bv" show)
}

list_uploaded_videos(){
    info "查询已上传列表..."
    (cd "$INSTALL_DIR" && "$BINARY_PATH" list)
}

#######################
# 主菜单
#######################
check_dependencies

while true; do
  clear
  echo -e "${BOLD}biliupR 管理菜单${RESET}"
  divider
  show_version_and_dir
  echo
  echo -e "  ${GREEN}1)${RESET} 安装 / 更新组件"
  echo -e "  ${YELLOW}2)${RESET} 账号登录"
  echo -e "  ${YELLOW}3)${RESET} 刷新登录状态"
  echo -e "  ${BLUE}4)${RESET} 上传新视频"
  echo -e "  ${BLUE}5)${RESET} 追加视频"
  echo -e "  ${PURPLE}6)${RESET} 查询视频详情"
  echo -e "  ${PURPLE}7)${RESET} 列出上传记录"
  echo -e "  ${RED}0)${RESET} 退出脚本"
  echo
  read -p "请输入序号: " opt
  case "$opt" in
    1) select_and_install; read -p $'\n回车继续...';;
    2) login_biliup; read -p $'\n回车继续...';;
    3) renew_biliup; read -p $'\n回车继续...';;
    4) upload_video; read -p $'\n回车继续...';;
    5) append_video; read -p $'\n回车继续...';;
    6) show_video_details; read -p $'\n回车继续...';;
    7) list_uploaded_videos; read -p $'\n回车继续...';;
    0) exit 0;;
    *) warning "无效选项"; sleep 1;;
  esac
done
