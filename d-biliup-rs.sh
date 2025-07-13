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
PURPLE="\033[35m"      # 新增颜色
LIGHT_GRAY="\033[37m"  # 新增颜色
DARK_GRAY="\033[90m"   # 新增颜色
ORANGE="\033[38;5;208m" # 新增颜色 (256色)
NC="\033[0m" # No Color

info()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
highlight(){ echo -e "${CYAN}${BOLD}$1${RESET}"; }

#######################
# 基础变量
#######################
INSTALL_DIR="/opt/DanmakuRender-5/tools"
DMR_DIR="/opt/DanmakuRender-5" # 假设这是 DanmakuRender 的基础目录
BINARY_PATH="$INSTALL_DIR/biliup"
GITHUB_API="https://api.github.com/repos/biliup/biliup-rs/releases"
LAST_BV_FILE="$INSTALL_DIR/last_bvs.txt" # 存储最近的BV号列表

# 全局变量，用于存储选定的视频文件路径
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
    error "以下依赖未安装，请先执行：sudo apt-get install -y ${missing_deps[*]}"
    exit 1
  fi
}

#######################
# 显示当前版本和目录
#######################
show_version_and_dir(){
  if [[ -x "$BINARY_PATH" ]]; then
    VER=$("$BINARY_PATH" -V 2>/dev/null || printf "")
    if [[ -n "$VER" ]]; then
      echo -e "${BOLD}当前已安装版本：${RESET}${BLUE}$VER${RESET}"
    else
      echo -e "${BOLD}当前已安装版本：${RED}未获取到版本信息${RESET}"
    fi
  else
    echo -e "${BOLD}当前已安装版本：${RED}未安装${RESET}"
  fi
  echo -e "${BOLD}当前文件目录：${RESET}${BLUE}$INSTALL_DIR${RESET}"
}

#######################
# 获取系统架构
#######################
get_arch(){
  case "$(uname -m)" in
    x86_64)  echo "x86_64";;
    aarch64) echo "aarch64";;
    armv7l)  echo "armv7";;
    armv7*)  echo "armv7";;
    *)       echo "$(uname -m)";;
  esac
}

#######################
# 列出并选择版本并安装
#######################
select_and_install(){
  ARCH=$(get_arch)
  info "检测到系统架构：${CYAN}$ARCH${RESET}"
  info "正在从 GitHub 拉取最新版本列表..."

  # 修复：修改 jq 命令，确保每个版本只列出一次，并优先选择 .tar.gz 格式的下载链接
  mapfile -t lines < <(curl -s "$GITHUB_API" | \
    jq -r --arg arch "$ARCH" '
      .[] | {
        tag: .tag_name,
        date: .published_at,
        # 过滤出匹配架构的 Linux 资产，并优先将 .tar.gz 放在前面
        assets: [
          .assets[] | select(.name | test("linux";"i") and test($arch;"i"))
        ] | sort_by(.name | test("\\.tar\\.gz$") | not)
      } | select(.assets | length > 0) | {
        tag: .tag,
        date: .date,
        url: (.assets[0].browser_download_url) # 取第一个（优先的）资产的下载链接
      } | "\(.tag) \(.date) \(.url)"
    ' | sort -rV | head -n 10) # 移除 uniq，因为 jq 已经确保了每个tag的唯一性

  if [[ ${#lines[@]} -eq 0 ]]; then
    error "未找到任何可用的 Linux/${RED}$ARCH${RESET} 版本"
    return 1
  fi

  echo -e "\n${BOLD}当前可用版本列表：${RESET}"
  for i in "${!lines[@]}"; do
    num=$((i+1))
    tag=$(echo "${lines[$i]}" | awk '{print $1}')
    date_raw=$(echo "${lines[$i]}" | awk '{print $2}')
    date_fmt=${date_raw:0:10}
    # 确保序号对齐
    printf " %2d) ${BLUE}%s${RESET} (%s)\n" "$num" "$tag" "$date_fmt"
  done

  read -p $'\n请选择要安装的版本（0 取消）：' choice
  [[ "$choice" == "0" ]] && return
  idx=$((choice-1))
  if ! [[ $idx -ge 0 && $idx -lt ${#lines[@]} ]]; then
    error "无效的选择"; return 1
  fi

  sel_line=${lines[$idx]}
  VERSION=$(echo "$sel_line" | awk '{print $1}')
  URL=$(echo "$sel_line" | awk '{print $3}')
  ARCHIVE_NAME=$(basename "$URL")

  info "开始下载 ${CYAN}$VERSION${RESET} ..."
  cd "$INSTALL_DIR" || { error "切换到 ${RED}$INSTALL_DIR${RESET} 失败"; return 1; }
  curl -L -o "$ARCHIVE_NAME" "$URL" || { error "下载失败"; return 1; }

  info "下载完成，正在解压..."
  case "$ARCHIVE_NAME" in
    *.tar.gz|*.tgz)   tar -xvzf "$ARCHIVE_NAME"   || { error "解压失败"; return 1; } ;;
    *.tar.xz)         tar -xvJf "$ARCHIVE_NAME"   || { error "解压失败"; return 1; } ;;
    *.zip)            unzip -v "$ARCHIVE_NAME"    || { error "解压失败"; return 1; } ;;
    *)                error "未知的压缩格式: ${RED}$ARCHIVE_NAME${RESET}"; return 1 ;;
  esac

  EXTRACT_DIR=$(tar -tf "$ARCHIVE_NAME" | head -1 | cut -f1 -d"/")
  if [[ -f "$EXTRACT_DIR/biliup" ]]; then
    mv "$EXTRACT_DIR/biliup" "$INSTALL_DIR/" || { error "移动二进制失败"; return 1; }
    chmod +x "$BINARY_PATH"
    info "安装完成：${GREEN}$VERSION${RESET}"
  else
    error "未在解压目录中找到 biliup 可执行文件"; return 1
  fi

  rm -rf "$EXTRACT_DIR"
}

#######################
# 登录与续期
#######################
login_biliup(){
  highlight "正在执行登录..."
  cd "$INSTALL_DIR" && "$BINARY_PATH" login
}

renew_biliup(){
  highlight "正在刷新登录信息..."
  cd "$INSTALL_DIR" && "$BINARY_PATH" renew
}

#######################
# 辅助函数：选择视频文件（已修改）
#######################
select_video_files() {
    local dir="$1"
    local mode="$2"
    local files=()
    local i=1
    selected_video_paths=()

    if [[ ! -d "$dir" ]]; then
        error "目录不存在: ${RED}$dir${RESET}"
        return 1
    fi

    info "正在列出目录 '${CYAN}$dir${RESET}' 中的视频文件..."
    mapfile -t files < <(
        find "$dir" -maxdepth 1 -type f \
            \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.webm" \) \
        | sort
    )

    if [[ ${#files[@]} -eq 0 ]]; then
        warning "在目录 '${CYAN}$dir${RESET}' 中未找到任何视频文件。"
        return 1
    fi

    echo -e "\n${BOLD}可用视频文件列表：${RESET}"
    for file_path in "${files[@]}"; do
        local file_name=$(basename "$file_path")
        local file_size=$(du -h "$file_path" | cut -f1)
        # 序号对齐、文件名加色加粗、文件大小加色
        printf "%2d) ${BLUE}${BOLD}%s${RESET} ${GREEN}(%s)${RESET}\n" \
            "$i" "$file_name" "$file_size"
        ((i++))
    done

    if [[ "$mode" == "single" ]]; then
        read -p $'\n请选择要上传的视频文件编号（0 取消）：' choice
        [[ "$choice" == "0" ]] && { warning "取消选择。"; return 1; }
        idx=$((choice-1))
        if [[ $idx -ge 0 && $idx -lt ${#files[@]} ]]; then
            selected_video_paths+=("${files[$idx]}")
        else
            error "无效的选择。"; return 1
        fi
    else
        read -p $'\n请输入要上传的视频文件编号，用空格分隔（0 取消）：' -a choices
        if [[ "${choices[0]}" == "0" ]]; then
            warning "取消选择。"; return 1
        fi
        for choice in "${choices[@]}"; do
            if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
                warning "无效的选择: '${RED}$choice${RESET}'。跳过。"
                continue
            fi
            idx=$((choice-1))
            if [[ $idx -ge 0 && $idx -lt ${#files[@]} ]]; then
                selected_video_paths+=("${files[$idx]}")
            else
                warning "无效的选择: ${RED}$choice${RESET}。跳过。"
            fi
        done
        if [[ ${#selected_video_paths[@]} -eq 0 ]]; then
            error "未选择任何有效文件。"; return 1
        fi
    fi

    return 0
}

#######################
# 上传视频
#######################
upload_video(){
    highlight "正在准备上传视频..."

    local upload_cmd_parts=("$BINARY_PATH" "upload") # 使用数组构建命令，避免eval
    local submit_val="client"
    # local line_val="bda" # 不再有默认值
    local limit_val="3"
    local copyright_val="1"
    local source_val=""
    local tid_val="65"
    local cover_val=""
    local title_val=""
    local desc_val=""
    local dynamic_val=""
    local tag_val=""
    local topic_id_val=""
    local dtime_val=""
    local dolby_val=""
    local hires_val=""
    local no_reprint_val="0"
    local open_elec_val="0"

    # 提交接口
    echo
    echo -e "${CYAN}请选择提交接口${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET}"
    local submit_options=("client" "app" "web")
    for i in "${!submit_options[@]}"; do
        echo -e "    ${BOLD}$((i+1)))${RESET} ${submit_options[$i]}"
    done
    read -p "$(echo -e "${CYAN}请输入选项编号 [默认: 1 (${submit_options[0]})]: ${RESET}")" submit_choice
    submit_choice=${submit_choice:-1}
    if [[ "$submit_choice" =~ ^[0-9]+$ && "$submit_choice" -ge 1 && "$submit_choice" -le ${#submit_options[@]} ]]; then
        submit_val="${submit_options[$((submit_choice-1))]}"
    else
        warning "无效的提交接口选择，使用默认值: ${CYAN}$submit_val${RESET}"
    fi
    upload_cmd_parts+=("--submit" "$submit_val")

    # 上传线路
    echo
    echo -e "${CYAN}请选择上传线路${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET}"
    local line_options=("bda2" "ws" "qn" "bldsa" "tx" "txa" "bda" "alia")
    for i in "${!line_options[@]}"; do
        echo -e "    ${BOLD}$((i+1)))${RESET} ${line_options[$i]}"
    done
    read -p "$(echo -e "${CYAN}请输入选项编号（回车跳过，让biliup-rs自动选择）: ${RESET}")" line_choice # 提示语修改
    if [[ -n "$line_choice" ]]; then # 如果用户输入了内容
        if [[ "$line_choice" =~ ^[0-9]+$ && "$line_choice" -ge 1 && "$line_choice" -le ${#line_options[@]} ]]; then
            local selected_line="${line_options[$((line_choice-1))]}"
            upload_cmd_parts+=("--line" "$selected_line")
            info "已选择上传线路: ${CYAN}$selected_line${RESET}"
        else
            warning "无效的上传线路选择，跳过设置上传线路，biliup-rs将自动选择。"
        fi
    else
        info "未选择上传线路，biliup-rs将自动选择。"
    fi

    # 单文件最大并发数
    echo
    echo -e "${CYAN}请输入单文件最大并发数${RESET}"
    read -p "$(echo -e "${CYAN}请输入线程 [默认: 3]: ${RESET}")" limit_input
    limit_input=${limit_input:-$limit_val}
    if [[ "$limit_input" =~ ^[0-9]+$ && "$limit_input" -gt 0 ]]; then
        limit_val="$limit_input"
    else
        warning "无效的并发数，使用默认值: ${CYAN}$limit_val${RESET}"
    fi
    upload_cmd_parts+=("--limit" "$limit_val")

    # 是否转载
    echo
    echo -e "${CYAN}是否转载${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 1为自制, 2为转载"
    read -p "$(echo -e "${CYAN}请输入选项 [默认: 1]: ${RESET}")" copyright_input
    copyright_input=${copyright_input:-$copyright_val}
    if [[ "$copyright_input" == "1" || "$copyright_input" == "2" ]]; then
        copyright_val="$copyright_input"
    else
        warning "无效的转载选项，使用默认值: ${CYAN}$copyright_val${RESET}"
    fi
    upload_cmd_parts+=("--copyright" "$copyright_val")

    if [[ "$copyright_val" == "2" ]]; then
        echo
        echo -e "${CYAN}请输入转载来源${RESET}"
        read -p "$(echo -e "${CYAN}请输入字符串: ${RESET}")" source_input
        if [[ -n "$source_input" ]]; then
            source_val="$source_input"
            upload_cmd_parts+=("--source" "$source_val")
        else
            warning "未输入转载来源，可能导致上传失败。"
        fi
    fi

    # 投稿分区
    echo
    echo -e "${CYAN}请输入投稿分区 可参考${NC}" # 链接换行
    echo -e "${BLUE}https://biliup.github.io/tid-ref.html${NC}" # 链接换行
    read -p "$(echo -e "${CYAN}请输入分区号 [默认: 65]: ${RESET}")" tid_input
    tid_input=${tid_input:-$tid_val}
    if [[ "$tid_input" =~ ^[0-9]+$ ]]; then
        tid_val="$tid_input"
    else
        warning "无效的分区ID，使用默认值: ${CYAN}$tid_val${RESET}"
    fi
    upload_cmd_parts+=("--tid" "$tid_val")

    # 视频封面
    echo
    echo -e "${CYAN}请选择视频封面${RESET}"
    read -p "$(echo -e "${CYAN}请输入绝对路径（回车跳过）: ${RESET}")" cover_input # 提示语修改
    if [[ -n "$cover_input" ]]; then
        if [[ -f "$cover_input" ]]; then
            cover_val="$cover_input"
            upload_cmd_parts+=("--cover" "$cover_val")
        else
            warning "封面文件不存在或不是常规文件，跳过设置封面。"
        fi
    fi

    # 视频标题
    echo
    echo -e "${CYAN}请输入视频标题${RESET}"
    read -p "$(echo -e "${CYAN}请输入视频标题（回车则默认使用第一个视频文件名）: ${RESET}")" title_input
    if [[ -n "$title_input" ]]; then
        title_val="$title_input"
    fi

    # 视频简介
    echo
    echo -e "${CYAN}请输入视频简介${RESET}"
    read -p "$(echo -e "${CYAN}请输入简介内容（回车跳过）: ${RESET}")" desc_input # 提示语修改
    if [[ -n "$desc_input" ]]; then
        desc_val="$desc_input"
    fi

    # 空间动态
    echo
    echo -e "${CYAN}请输入空间动态${RESET}"
    read -p "$(echo -e "${CYAN}请输入动态（回车跳过）: ${RESET}")" dynamic_input # 提示语修改
    if [[ -n "$dynamic_input" ]]; then
        dynamic_val="$dynamic_input"
    fi

    # 视频标签 (强制输入，增加默认值)
    echo
    while true; do
        echo -e "${CYAN}请输入视频标签${RESET}"
        local tag_input_raw
        read -p "$(echo -e "${CYAN}请输入标签（必填，逗号分隔多个tag） [默认: 直播回放]: ${RESET}")" tag_input_raw
        tag_val="${tag_input_raw:-直播回放}" # 如果用户输入为空，则使用默认值

        if [[ -z "$tag_val" ]]; then
            error "视频标签不能为空，请重新输入。"
            echo # Add a blank line for better separation
        else
            upload_cmd_parts+=("--tag" "$tag_val")
            break # Exit the loop if tag is provided
        fi
    done

    # 视频参与话题
    echo
    echo -e "${CYAN}是否输入视频参与话题${RESET}"
    read -p "$(echo -e "${CYAN}请输入数字（需要自己获取topic_id配合填写mission_id，回车跳过）: ${RESET}")" topic_id_input # 提示语修改
    if [[ -n "$topic_id_input" ]]; then
        if [[ "$topic_id_input" =~ ^[0-9]+$ ]]; then
            topic_id_val="$topic_id_input"
            upload_cmd_parts+=("--topic-id" "$topic_id_val")
        else
            warning "无效的话题ID，跳过设置。"
        fi
    fi

    # 延时发布视频时间
    echo
    echo -e "${CYAN}是否延时发布${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 秒数，距离提交必须大于4小时（即14400秒）"
    read -p "$(echo -e "${CYAN}请输入数字（回车跳过）: ${RESET}")" dtime_input # 提示语修改
    if [[ -n "$dtime_input" ]]; then
        if [[ "$dtime_input" =~ ^[0-9]+$ && "$dtime_input" -ge 14400 ]]; then
            dtime_val=$(($(date +%s) + dtime_input))
            upload_cmd_parts+=("--dtime" "$dtime_val")
        else
            warning "无效的延时发布时间（必须为数字且大于等于14400），跳过设置延时发布。"
        fi
    fi

    # 是否开启杜比音效
    echo
    echo -e "${CYAN}是否开启杜比音效${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 0-关闭, 1-开启"
    read -p "$(echo -e "${CYAN}请输入选项（回车跳过）: ${RESET}")" dolby_input # 提示语修改
    if [[ -n "$dolby_input" ]]; then
        if [[ "$dolby_input" == "0" || "$dolby_input" == "1" ]]; then
            dolby_val="$dolby_input"
            upload_cmd_parts+=("--dolby" "$dolby_val")
        else
            warning "无效的杜比音效选项，跳过设置。"
        fi
    fi

    # 是否开启 Hi-Res
    echo
    echo -e "${CYAN}是否开启 Hi-Res${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 0-关闭, 1-开启"
    read -p "$(echo -e "${CYAN}请输入选项（回车跳过）: ${RESET}")" hires_input # 提示语修改
    if [[ -n "$hires_input" ]]; then
        if [[ "$hires_input" == "0" || "$hires_input" == "1" ]]; then
            hires_val="$hires_input"
            upload_cmd_parts+=("--hires" "$hires_val")
        else
            warning "无效的 Hi-Res 选项，跳过设置。"
        fi
    fi

    # 是否允许转载
    echo
    echo -e "${CYAN}是否允许转载${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 0-允许转载, 1-禁止转载"
    read -p "$(echo -e "${CYAN}请输入选项 [默认: 0]: ${RESET}")" no_reprint_input
    no_reprint_input=${no_reprint_input:-$no_reprint_val}
    if [[ "$no_reprint_input" == "0" || "$no_reprint_input" == "1" ]]; then
        no_reprint_val="$no_reprint_input"
    else
        warning "无效的允许转载选项，使用默认值: ${CYAN}$no_reprint_val${RESET}"
    fi
    upload_cmd_parts+=("--no-reprint" "$no_reprint_val")

    # 是否开启充电
    echo
    echo -e "${CYAN}是否开启充电${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET} 0-关闭, 1-开启"
    read -p "$(echo -e "${CYAN}请输入选项 [默认: 0]: ${RESET}")" open_elec_input
    open_elec_input=${open_elec_input:-$open_elec_val}
    if [[ "$open_elec_input" == "0" || "$open_elec_input" == "1" ]]; then
        open_elec_val="$open_elec_input"
    else
        warning "无效的充电选项，使用默认值: ${CYAN}$open_elec_val${RESET}"
    fi
    upload_cmd_parts+=("--open-elec" "$open_elec_val")

    # 仅提交接口为app时需要交互的内容
    if [[ "$submit_val" == "app" ]]; then
        info "提交接口为 '${CYAN}app${RESET}'，以下为额外选项："

        # 是否开启精选评论
        echo
        echo -e "${CYAN}是否开启精选评论${RESET}"
        read -p "$(echo -e "${CYAN}回车跳过: ${RESET}")" up_selection_reply_input # 提示语修改
        if [[ -n "$up_selection_reply_input" ]]; then
            upload_cmd_parts+=("--up-selection-reply")
        fi

        # 是否关闭评论
        echo
        echo -e "${CYAN}是否关闭评论${RESET}"
        read -p "$(echo -e "${CYAN}回车跳过: ${RESET}")" up_close_reply_input # 提示语修改
        if [[ -n "$up_close_reply_input" ]]; then
            upload_cmd_parts+=("--up-close-reply")
        fi

        # 是否关闭弹幕
        echo
        echo -e "${CYAN}是否关闭弹幕${RESET}"
        read -p "$(echo -e "${CYAN}回车跳过: ${RESET}")" up_close_danmu_input # 提示语修改
        if [[ -n "$up_close_danmu_input" ]]; then
            upload_cmd_parts+=("--up-close-danmu")
        fi
    fi

    local video_selection_successful=false
    declare -a video_paths_to_upload=() # 局部数组，用于本次上传

    while true; do
        echo -e "\n${BOLD}请选择视频文件来源：${RESET}"
        echo -e " 1. 从 ${CYAN}$DMR_DIR/直播回放${NC} 目录选择"
        echo -e " 2. 从 ${CYAN}$DMR_DIR/直播回放（弹幕版）${NC} 目录选择"
        echo -e " 3. 手动输入视频文件绝对路径"
        echo -e " 0. 返回 biliup 菜单"
        read -p "$(echo -e "${CYAN}请输入选项 (0-3): ${RESET}")" type_choice

        local current_video_dir=""
        declare -a current_video_paths=() # 使用临时数组进行当前选择尝试

        case $type_choice in
            1) current_video_dir="$DMR_DIR/直播回放" ;;
            2) current_video_dir="$DMR_DIR/直播回放（弹幕版）" ;;
            3)
                echo
                echo -e "${CYAN}请输入一个或多个视频文件的绝对路径，用 ${BOLD}空格${RESET}${CYAN} 分隔:${RESET}"
                read -p "> " -a current_video_paths
                if [ ${#current_video_paths[@]} -eq 0 ]; then
                    error "未输入任何文件路径！"
                    continue # 循环回视频选择菜单
                fi
                local all_files_exist=true
                for file_path in "${current_video_paths[@]}"; do
                     if [ ! -f "$file_path" ]; then
                          error "文件不存在或不是常规文件: ${RED}$file_path${RESET}"
                          all_files_exist=false
                          break
                     fi
                done
                if [ "$all_files_exist" = false ]; then
                     continue # 循环回视频选择菜单
                fi
                ;;
            0) warning "返回 biliup 菜单..."; return 0 ;; # 退出整个函数
            *) error "无效选项 '${RED}$type_choice${RESET}'！"; continue ;; # 循环回视频选择菜单
        esac

        # 如果到达这里，说明选择了 1, 2, 或 3。
        # 现在，处理 1 和 2 的实际文件选择。
        if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
            select_video_files "$current_video_dir" "multiple"
            if [ $? -ne 0 ]; then # select_video_files 返回 1 表示取消或失败
                # 如果 select_video_files 失败或被取消，循环回视频来源菜单
                continue
            fi
            current_video_paths=("${selected_video_paths[@]}") # 从全局数组复制
            if [ ${#current_video_paths[@]} -eq 0 ]; then
                error "未从目录选择任何文件。"
                continue # 循环回视频选择菜单
            fi
        fi

        # 如果到达这里，说明选择了有效的文件或手动输入了文件。
        # 将其分配给主 video_paths_to_upload 数组，供函数其余部分使用。
        video_paths_to_upload=("${current_video_paths[@]}")
        video_selection_successful=true
        break # 退出内部 while 循环
    done

    if [ "$video_selection_successful" = false ]; then
        error "未能成功选择视频文件，取消上传。"
        return 1
    fi

    # 将视频文件路径添加到命令中
    for file_path in "${video_paths_to_upload[@]}"; do
        upload_cmd_parts+=("$file_path")
    done

    info "即将执行的上传命令："
    # 打印命令数组，确保每个元素都正确引用
    printf "%s " "${upload_cmd_parts[@]}" | highlight "$(cat)"
    echo

    read -p "$(echo -e "${CYAN}确认执行上传？ (y/N): ${RESET}")" confirm_upload
    if [[ "$confirm_upload" =~ ^[Yy]$ ]]; then
        # 切换到安装目录执行命令，确保配置文件等能被找到
        (cd "$INSTALL_DIR" && "${upload_cmd_parts[@]}")
        if [ $? -eq 0 ]; then
            info "视频上传命令执行成功。"
        else
            error "视频上传命令执行失败。"
        fi
    else
        warning "上传已取消。"
    fi
}

#######################
# 追加视频
#######################
append_video(){
    highlight "正在准备追加视频..."

    local append_cmd_parts=("$BINARY_PATH" "append") # 使用数组构建命令，避免eval
    # local line_val="bda" # 不再有默认值
    local limit_val="3"
    local bv=""

    # 上传线路
    echo
    echo -e "${CYAN}请选择上传线路${RESET}"
    echo -e "  ${BOLD}可选参数：${RESET}"
    local line_options=("bda2" "ws" "qn" "bldsa" "tx" "txa" "bda" "alia")
    for i in "${!line_options[@]}"; do
        echo -e "    ${BOLD}$((i+1)))${RESET} ${line_options[$i]}"
    done
    read -p "$(echo -e "${CYAN}请输入选项编号（回车跳过由biliup-rs自动选择）: ${RESET}")" line_choice # 提示语修改
    if [[ -n "$line_choice" ]]; then # 如果用户输入了内容
        if [[ "$line_choice" =~ ^[0-9]+$ && "$line_choice" -ge 1 && "$line_choice" -le ${#line_options[@]} ]]; then
            local selected_line="${line_options[$((line_choice-1))]}"
            append_cmd_parts+=("--line" "$selected_line")
            info "已选择上传线路: ${CYAN}$selected_line${RESET}"
        else
            warning "无效的上传线路选择，跳过设置上传线路，biliup-rs将自动选择。"
        fi
    else
        info "未选择上传线路，biliup-rs将自动选择。"
    fi

    # 单文件最大并发数
    echo
    echo -e "${CYAN}请输入单文件最大并发数${RESET}"
    read -p "$(echo -e "${CYAN}请输入线程 [默认: 3]: ${RESET}")" limit_input
    limit_input=${limit_input:-$limit_val}
    if [[ "$limit_input" =~ ^[0-9]+$ && "$limit_input" -gt 0 ]]; then
        limit_val="$limit_input"
    else
        warning "无效的并发数，使用默认值: ${CYAN}$limit_val${RESET}"
    fi
    append_cmd_parts+=("--limit" "$limit_val")

    # BV号选择逻辑
    local recent_bvs=()
    if [[ -f "$LAST_BV_FILE" ]]; then
        mapfile -t recent_bvs < "$LAST_BV_FILE"
    fi

    local selected_bv=""
    while true; do
        echo
        info "--- 哔哩哔哩视频追加上传 (使用 biliup-rs) ---"
        echo -e "${CYAN}请选择 BV 号来源：${RESET}"
        local bv_option_num=1
        for current_bv in "${recent_bvs[@]}"; do
            printf " %2d) ${RESET}使用最近的 BV 号：${BLUE}%s${RESET}\n" "$bv_option_num" "$current_bv"
            ((bv_option_num++))
        done
        printf " %2d) ${RESET}输入新的 BV 号\n" "$bv_option_num"
        echo -e "  0) 取消追加"

        read -p "$(echo -e "${CYAN}请输入选项 (0-${bv_option_num}): ${RESET}")" bv_choice

        if [[ "$bv_choice" == "0" ]]; then
            warning "操作已取消。"
            return 0
        elif [[ "$bv_choice" =~ ^[1-9][0-9]*$ && "$bv_choice" -ge 1 && "$bv_choice" -lt "$bv_option_num" ]]; then
            selected_bv="${recent_bvs[$((bv_choice-1))]}"
            info "已选择最近的 BV 号：${GREEN}${selected_bv}${RESET}"
            break
        elif [[ "$bv_choice" == "$bv_option_num" ]]; then
            echo
            read -p "$(echo -e "${CYAN}请输入要追加到的视频的 ${BOLD}BV 号${RESET}${CYAN} (必须以 BV 开头): ${RESET}")" new_bv_input
            if [[ "$new_bv_input" =~ ^BV[a-zA-Z0-9]{10}$ ]]; then
                selected_bv="$new_bv_input"
                info "已输入新的 BV 号：${GREEN}${selected_bv}${RESET}"
                break
            else
                error "无效的 BV 号格式。请输入正确的 BV 号 (例如 ${BOLD}BV1fx4y1z7Xq${RESET})。"
                continue
            fi
        else
            error "无效的选项。"
            continue
        fi
    done

    # 更新最近的 BV 号列表
    if [[ -n "$selected_bv" ]]; then
        # 将当前选中的BV号添加到列表最前面（如果它不在列表中）
        # 或者将其移到最前面（如果它已经在列表中）
        local temp_bvs=("$selected_bv")
        for b in "${recent_bvs[@]}"; do
            if [[ "$b" != "$selected_bv" ]]; then
                temp_bvs+=("$b")
            fi
        done
        # 只保留最近的3个
        recent_bvs=("${temp_bvs[@]:0:3}")
        printf "%s\n" "${recent_bvs[@]}" > "$LAST_BV_FILE"
    fi

    info "将追加视频到: ${GREEN}$selected_bv${RESET}"
    append_cmd_parts+=("--vid" "$selected_bv") # 使用 --vid 参数

    local video_selection_successful=false
    declare -a video_paths_to_append=() # 局部数组，用于本次追加

    while true; do
        echo -e "\n${BOLD}请选择要追加的视频文件来源：${RESET}"
        echo -e " 1. 从 ${CYAN}$DMR_DIR/直播回放${NC} 目录选择"
        echo -e " 2. 从 ${CYAN}$DMR_DIR/直播回放（弹幕版）${NC} 目录选择"
        echo -e " 3. 手动输入视频文件绝对路径"
        echo -e " 0. 返回 biliup 菜单"
        read -p "$(echo -e "${CYAN}请输入选项 (0-3): ${RESET}")" type_choice

        local current_video_dir=""
        declare -a current_video_paths=() # 使用临时数组进行当前选择尝试

        case $type_choice in
            1) current_video_dir="$DMR_DIR/直播回放" ;;
            2) current_video_dir="$DMR_DIR/直播回放（弹幕版）" ;;
            3)
                echo
                echo -e "${CYAN}请输入一个或多个视频文件的绝对路径，用 ${BOLD}空格${RESET}${CYAN} 分隔:${RESET}"
                read -p "> " -a current_video_paths
                if [ ${#current_video_paths[@]} -eq 0 ]; then
                    error "未输入任何文件路径！"
                    continue # 循环回视频选择菜单
                fi
                local all_files_exist=true
                for file_path in "${current_video_paths[@]}"; do
                     if [ ! -f "$file_path" ]; then
                          error "文件不存在或不是常规文件: ${RED}$file_path${RESET}"
                          all_files_exist=false
                          break
                     fi
                done
                if [ "$all_files_exist" = false ]; then
                     continue # 循环回视频选择菜单
                fi
                ;;
            0) warning "返回 biliup 菜单..."; return 0 ;; # 退出整个函数
            *) error "无效选项 '${RED}$type_choice${RESET}'！"; continue ;; # 循环回视频选择菜单
        esac

        # 如果到达这里，说明选择了 1, 2, 或 3。
        # 现在，处理 1 和 2 的实际文件选择。
        if [[ "$type_choice" == "1" || "$type_choice" == "2" ]]; then
            select_video_files "$current_video_dir" "multiple"
            if [ $? -ne 0 ]; then # select_video_files 返回 1 表示取消或失败
                # 如果 select_video_files 失败或被取消，循环回视频来源菜单
                continue
            fi
            current_video_paths=("${selected_video_paths[@]}") # 从全局数组复制
            if [ ${#current_video_paths[@]} -eq 0 ]; then
                error "未从目录选择任何文件。"
                continue # 循环回视频选择菜单
            fi
        fi

        # 如果到达这里，说明选择了有效的文件或手动输入了文件。
        # 将其分配给主 video_paths_to_append 数组，供函数其余部分使用。
        video_paths_to_append=("${current_video_paths[@]}")
        video_selection_successful=true
        break # 退出内部 while 循环
    done

    if [ "$video_selection_successful" = false ]; then
        error "未能成功选择视频文件，取消追加。"
        return 1
    fi

    # 将视频文件路径添加到命令中
    for file_path in "${video_paths_to_append[@]}"; do
        append_cmd_parts+=("$file_path")
    done

    info "即将执行的追加命令："
    # 打印命令数组，确保每个元素都正确引用
    printf "%s " "${append_cmd_parts[@]}" | highlight "$(cat)"
    echo

    read -p "$(echo -e "${CYAN}确认执行追加？ (y/N): ${RESET}")" confirm_append
    if [[ "$confirm_append" =~ ^[Yy]$ ]]; then
        # 切换到安装目录执行命令，确保配置文件等能被找到
        (cd "$INSTALL_DIR" && "${append_cmd_parts[@]}")
        if [ $? -eq 0 ]; then
            info "视频追加命令执行成功。"
        else
            error "视频追加命令执行失败。"
        fi
    else
        warning "追加已取消。"
    fi
}

#######################
# 打印视频详情 (新增功能)
#######################
show_video_details(){
    highlight "正在查询视频详情..."
    local bv_to_show=""

    while true; do
        echo
        read -p "$(echo -e "${CYAN}请输入要查询的视频的 ${BOLD}BV 号${RESET}${CYAN} (0 返回菜单): ${RESET}")" bv_to_show
        if [[ "$bv_to_show" == "0" ]]; then
            warning "返回 biliup 菜单..."
            return 0
        elif [[ "$bv_to_show" =~ ^BV[a-zA-Z0-9]{10}$ ]]; then
            info "正在查询 BV 号：${GREEN}${bv_to_show}${RESET} 的详情..."
            (cd "$INSTALL_DIR" && "$BINARY_PATH" "$bv_to_show" show)
            if [ $? -eq 0 ]; then
                info "视频详情查询成功。"
            else
                error "视频详情查询失败，请检查 BV 号或网络连接。"
            fi
            break # 查询完成后退出循环
        else
            error "无效的 BV 号格式。请输入正确的 BV 号 (例如 ${BOLD}BV1fx4y1z7Xq${RESET})。"
        fi
    done
}

#######################
# 列出所有已上传视频 (新增功能)
#######################
list_uploaded_videos(){
    highlight "正在列出所有已上传视频..."
    (cd "$INSTALL_DIR" && "$BINARY_PATH" list)
    if [ $? -eq 0 ]; then
        info "已上传视频列表查询成功。"
    else
        error "已上传视频列表查询失败，请检查登录状态或网络连接。"
    fi
}


#######################
# 主菜单
#######################
# 在脚本开始时执行依赖检查
check_dependencies

while true; do
  clear
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}       biliup-rs 管理菜单       ${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  show_version_and_dir
  echo
  echo -e "${GREEN}${BOLD}1)${RESET}${GREEN} 重新选择 biliup-rs 版本并安装${RESET}"
  echo -e "${YELLOW}${BOLD}2)${RESET}${YELLOW} 登录 B 站并保存登录信息${RESET}"
  echo -e "${YELLOW}${BOLD}3)${RESET}${YELLOW} 手动验证并刷新登录信息${RESET}"
  echo -e "${BLUE}${BOLD}4)${RESET}${BLUE} 上传视频${RESET}"
  echo -e "${BLUE}${BOLD}5)${RESET}${BLUE} 对稿件追加视频${RESET}"
  echo -e "${PURPLE}${BOLD}6)${RESET}${PURPLE} 打印视频详情${RESET}"
  echo -e "${PURPLE}${BOLD}7)${RESET}${PURPLE} 列出所有已上传视频${RESET}"
  echo -e "${RED}${BOLD}0)${RESET}${RED} 退出${RESET}"
  echo
  read -p "请输入选项编号：" opt
  case "$opt" in
    1) select_and_install; read -p $'\n按回车继续...';;
    2) login_biliup; read -p $'\n按回车继续...';;
    3) renew_biliup; read -p $'\n按回车继续...';;
    4) upload_video; read -p $'\n按回车继续...';;
    5) append_video; read -p $'\n按回车继续...';;
    6) show_video_details; read -p $'\n按回车继续...';;
    7) list_uploaded_videos; read -p $'\n按回车继续...';;
    0) exit 0;;
    *) warning "无效选项，请重新输入"; read -p $'\n按回车继续...';;
  esac
done

