#!/bin/bash

# 配置变量
DMR_DIR="/opt/DanmakuRender-5"
DMR_CMD="python3 main.py"
LOG_FILE="nohup.out"
COOKIES_TOOL_DIR="tools"
BILIUP_DIR="$DMR_DIR/$COOKIES_TOOL_DIR"
BILIUP_URL="https://github.com/biliup/biliup-rs/releases/download/v0.2.2/biliupR-v0.2.2-x86_64-linux.tar.xz"

# 颜色与字体样式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# 回滚安装：安装出错时删除安装目录
rollback_installation() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}安装过程中出错，正在回滚安装...${NC}"
    [ -d "$DMR_DIR" ] && sudo rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已删除安装目录：$DMR_DIR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}回滚删除安装目录失败！${NC}"
}

# 检查配置文件状态
check_config() {
    if find "$DMR_DIR/configs" -name "*DMR*" -print -quit | grep -q .; then
        echo -e "${GREEN}${BOLD}已配置${NC}${NORMAL}"
        return 0
    else
        echo -e "${RED}${BOLD}未正确配置${NC}${NORMAL}"
        return 1
    fi
}

# 检查Cookies状态
check_cookies() {
    if find "$BILIUP_DIR" -name "*.json" -print -quit | grep -q .; then
        echo -e "${GREEN}${BOLD}已配置${NC}${NORMAL}"
        return 0
    else
        echo -e "${RED}${BOLD}未正确配置${NC}${NORMAL}"
        return 1
    fi
}

# 显示头部信息
show_header() {
    clear
    echo -e "${CYAN}==============================${NC}"
    echo -e "${CYAN}        ${BOLD}DanmakuRender${NORMAL}        ${NC}"
    echo -e "${CYAN}==============================${NC}"
    echo -e "${CYAN}项目地址：https://github.com/sillda76/DanmakuRender${NC}\n"
}

# 显示当前状态（安装及运行情况）
show_status() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${YELLOW}${BOLD}当前状态：DanmakuRender V5 未安装${NC}${NORMAL}"
    elif pgrep -f "$DMR_CMD" > /dev/null; then
         pid=$(pgrep -f "$DMR_CMD" | head -n 1)
         echo -e "${GREEN}${BOLD}当前状态：正在运行 (PID: $pid)${NC}${NORMAL}"
    else
         echo -e "${RED}${BOLD}当前状态：未运行${NC}${NORMAL}"
    fi
    
    if [ -d "$DMR_DIR" ]; then
        echo -e "配置文件：$(check_config)"
        echo -e "Cookies：$(check_cookies)"
    fi
}

# 检查是否已安装
require_installed() {
    if [ ! -d "$DMR_DIR" ]; then
         echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}DanmakuRender V5 未安装，请先选择安装选项（1）进行安装！${NC}"
         return 1
    fi
    return 0
}

# 检查安装必要工具
check_install_tools() {
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在检查系统依赖工具...${NC}"
    declare -a required_tools=("wget" "unzip" "python3-venv" "python3-pip" "ffmpeg" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}未找到 $tool，正在安装...${NC}"
            sudo apt install -y $tool || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}$tool 安装失败！${NC}"; return 1; }
        fi
    done
}

# 安装 DanmakuRender V5（含回滚机制）
install_dmr() {
    local rollback_needed=true
    trap 'if [ "$rollback_needed" = true ]; then rollback_installation; fi' EXIT

    # 安装必要工具
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装必要工具（unzip、curl、wget）...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！${NC}"; return 1; }
    sudo apt install -y unzip curl wget || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}必要工具安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}必要工具安装完成！${NC}"

    # 更新软件包列表
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在更新软件包列表...${NC}"
    sudo apt update || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}apt update 失败！${NC}"; return 1; }

    # 下载 DanmakuRender V5
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 DanmakuRender V5...${NC}"
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

    # 安装 Python 虚拟环境和依赖
    cd "$DMR_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入目录失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 python3-venv...${NC}"
    sudo apt install python3-venv -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}python3-venv 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}创建虚拟环境...${NC}"
    python3 -m venv venv || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建虚拟环境失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}激活虚拟环境...${NC}"
    source venv/bin/activate || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}激活虚拟环境失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 pip3...${NC}"
    sudo apt-get install python3-pip -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}pip3 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}安装 Python 依赖...${NC}"
    pip3 install -r requirements.txt || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}Python 依赖安装失败！${NC}"; return 1; }
    deactivate

    # 下载并部署 biliup
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在下载 biliup...${NC}"
    mkdir -p "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}创建 tools 文件夹失败！${NC}"; return 1; }
    cd "$BILIUP_DIR" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入 tools 文件夹失败！${NC}"; return 1; }
    curl -LO "$BILIUP_URL" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载 biliup 压缩包失败！${NC}"; return 1; }
    archive_name=$(basename "$BILIUP_URL")
    tar -xJvf "$archive_name" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压 biliup 压缩包失败！${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "biliupR-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到解压后的 biliup 文件夹！${NC}"; return 1; }
    mv "$extracted_folder/biliup" . || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}移动 biliup 文件失败！${NC}"; return 1; }
    chmod +x biliup || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}设置 biliup 可执行权限失败！${NC}"; return 1; }
    rm -rf "$extracted_folder" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}删除解压后的文件夹失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}biliup 部署成功！${NC}"

    # 安装 ffmpeg
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在安装 ffmpeg...${NC}"
    sudo apt install ffmpeg -y || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}ffmpeg 安装失败！${NC}"; return 1; }
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}ffmpeg 安装完成！${NC}"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}${BOLD}DanmakuRender V5 安装完成！${NC}${NORMAL}"

    rollback_needed=false
    trap - EXIT
}

# 更新 DanmakuRender V5
update_dmr() {
    require_installed || return 1
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在停止运行中的进程...${NC}"
    pgrep -f "$DMR_CMD" > /dev/null && stop_dmr
    check_install_tools || return 1

    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${BLUE}正在更新 DanmakuRender V5...${NC}"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}进入临时目录失败！${NC}"; return 1; }
    wget -O DanmakuRender-5.zip https://github.com/sillda76/DanmakuRender/archive/refs/heads/v5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}下载失败！${NC}"; return 1; }
    unzip DanmakuRender-5.zip || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}解压失败！${NC}"; return 1; }
    extracted_folder=$(find . -maxdepth 1 -type d -name "DanmakuRender-*" | head -n 1)
    [ -z "$extracted_folder" ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}未找到解压后的文件夹！${NC}"; return 1; }
    sudo rsync -a "$extracted_folder/" "$DMR_DIR/" || { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}文件覆盖失败！${NC}"; return 1; }
    cd - > /dev/null
    rm -rf "$tmp_dir"
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}更新完成！${NC}"
}

# 卸载 DanmakuRender V5
uninstall_dmr() {
    require_installed || return 1
    rm -rf "$DMR_DIR" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}卸载完成！${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}卸载失败！${NC}"
}

# 启动 DanmakuRender V5
start_dmr() {
    require_installed || return 1
    
    # 配置检查
    local config_ok=0
    check_config >/dev/null && check_cookies >/dev/null && config_ok=1
    
    if [ $config_ok -ne 1 ]; then
        echo -e "${YELLOW}${BOLD}[警告]${NC}${NORMAL} ${RED}检测到未正确配置的组件，继续操作可能导致运行异常！${NC}"
        read -p "是否仍然要继续运行？(y/n) " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${YELLOW}已取消启动操作${NC}"
            return 1
        fi
    fi

    cd "$DMR_DIR" && source venv/bin/activate && nohup $DMR_CMD > "$LOG_FILE" 2>&1 &
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}DMR启动成功！PID: $!${NC}"
}

# 停止 DanmakuRender V5
stop_dmr() {
    require_installed || return 1
    pkill -f "$DMR_CMD" && echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}已停止DMR${NC}" || echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}停止DMR失败${NC}"
}

# 查看日志（带退出功能）
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

# 安装 微软雅黑 和 Emoji 字体
install_fonts() {
    sudo mkdir -p /usr/share/fonts/truetype/microsoft
    sudo cp "$DMR_DIR/fonts/msyh.ttf" /usr/share/fonts/truetype/microsoft/
    sudo fc-cache -fv
    sudo apt install -y fonts-noto-color-emoji fonts-symbola
    sudo fc-cache -fv
    echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${GREEN}字体安装完成！${NC}"
}

# biliup-rs 工具菜单
biliup_menu() {
    while true; do
        show_header
        echo -e "${CYAN}=== biliup-rs 工具 ===${NC}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL} 更新哔哩哔哩 Cookies"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL} 哔哩哔哩快速上传"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL} 哔哩哔哩视频追加上传"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL} 返回主菜单"
        read -p "请输入选项： " sub_choice
        case $sub_choice in
            1) update_cookies ;;
            2) biliup_upload ;;
            3) biliup_append ;;
            0) break ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 更新哔哩哔哩 Cookies
update_cookies() {
    require_installed || return 1
    cd "$BILIUP_DIR" && ./biliup login
}

# 哔哩哔哩快速上传（支持多选）
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
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \)))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录下没有视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}目录下的视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        read -p "请输入要上传的视频选项（数字，用空格分隔）： " -a selections
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

# 哔哩哔哩视频追加上传（支持多选）
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
        files=($(find "$video_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.flv" -o -iname "*.mkv" -o -iname "*.avi" \)))
        [ ${#files[@]} -eq 0 ] && { echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}目录下没有视频文件！${NC}"; return 1; }
        echo -e "${BLUE}${BOLD}[INFO]${NC}${NORMAL} ${CYAN}目录下的视频文件：${NC}"
        for i in "${!files[@]}"; do
            printf "%d) %s\n" $((i+1)) "$(basename "${files[$i]}")"
        done
        echo "$(( ${#files[@]} + 1 )) ) 全部上传"
        read -p "请输入要上传的视频选项（数字，用空格分隔）： " -a selections
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

# 主菜单
main_menu() {
    while true; do
        show_header
        show_status
        echo -e "\n${CYAN}${BOLD}请选择操作：${NC}${NORMAL}"
        echo -e "${BLUE}${BOLD}1.${NC}${NORMAL}  安装 DanmakuRender V5"
        echo -e "${BLUE}${BOLD}2.${NC}${NORMAL}  启动/停止录制"
        echo -e "${BLUE}${BOLD}3.${NC}${NORMAL}  查看实时日志"
        echo -e "${BLUE}${BOLD}4.${NC}${NORMAL}  运行测试"
        echo -e "${BLUE}${BOLD}5.${NC}${NORMAL}  删除回放/渲染文件"
        echo -e "${BLUE}${BOLD}6.${NC}${NORMAL}  biliup-rs 工具"
        echo -e "${BLUE}${BOLD}7.${NC}${NORMAL}  安装 微软雅黑 和 Emoji 表情"
        echo -e "${BLUE}${BOLD}8.${NC}${NORMAL}  更新 DanmakuRender V5"
        echo -e "${BLUE}${BOLD}9.${NC}${NORMAL}  卸载 DanmakuRender V5"
        echo -e "${BLUE}${BOLD}0.${NC}${NORMAL}  退出脚本"
        read -p "请输入选项： " choice
        case $choice in
            1) install_dmr ;;
            2)
                require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }
                pgrep -f "$DMR_CMD" > /dev/null && stop_dmr || start_dmr
                ;;
            3) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; view_log ;;
            4) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; run_test ;;
            5) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; delete_replays ;;
            6) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; biliup_menu ;;
            7) install_fonts ;;
            8) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; update_dmr ;;
            9) require_installed || { read -n 1 -s -r -p "按任意键继续..."; continue; }; uninstall_dmr ;;
            0) exit 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC}${NORMAL} ${RED}无效选项！${NC}" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

main_menu
