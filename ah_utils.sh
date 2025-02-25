#!/bin/bash

# ==========================
# ADB/HDC 工具脚本
# Version: v1.0
# Author: lijun
# ==========================

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

# 全局变量
mode=""
device_id=""


# 通用函数
log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${RESET} $1"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1"; }

# 检查工具是否有效
check_command() {
    local tool=$1
    if ! command -v "$tool" &>/dev/null; then
        log_error "$tool 命令未找到，请确保已正确安装并添加到 PATH 环境变量中。"
        exit 1
    fi
}

# 列出设备
list_devices() {
    if [ "$mode" == "adb" ]; then
        adb devices | grep -v "List of devices attached" | grep "device$" | awk '{print $1}'
    elif [ "$mode" == "hdc" ]; then
        hdc list targets | grep -v -F "[Empty]" | grep -v "^$" | cut -d' ' -f1
    fi
}

# 选择设备
select_device() {
    devices=$(list_devices)
    if [ -z "$devices" ]; then
        log_error "未检测到任何设备，请检查设备连接或授权。"
        exit 1
    fi

    device_count=$(echo "$devices" | wc -w)
    if [ "$device_count" -eq 1 ]; then
        device_id=$(echo "$devices" | head -n 1)
    else
        echo "检测到多个设备，请选择一个设备："
        select device in $devices; do
            if [ -n "$device" ]; then
                device_id="$device"
                break
            else
                log_warning "无效选择，请重试。"
            fi
        done
    fi
    echo -e "${GREEN}当前选择的设备：$device_id${RESET}"
    if [ "$mode" == "adb" ]; then
        wifi_ip=$(adb -s "$device_id" shell "dumpsys wifi | grep -A10 'mWifiInfo' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1" 2>/dev/null)
    elif [ "$mode" == "hdc" ]; then
        wifi_ip=$(hdc shell "ifconfig wlan0 | grep 'inet addr:' | sed 's/.*addr:\([0-9.]*\).*/\1/'" 2>/dev/null)
    fi
}

# 获取设备信息
get_device_info() {
    local system_name
    local udid

    if [ "$mode" == "adb" ]; then
        system_name=$(adb -s "$device_id" shell getprop ro.build.version.release 2>/dev/null)
        udid="$device_id"
        wm_size=$(adb -s "$device_id" shell wm size | awk -F': ' '{print $2}' 2>/dev/null)
    elif [ "$mode" == "hdc" ]; then
        system_name=$(hdc -t "$device_id" shell param get const.product.software.version 2>/dev/null)
        udid=$(hdc -t "$device_id" shell bm get --udid | sed 's/udid of current device is ://')
    fi

    system_name=${system_name:-未知}
    echo -e "${CYAN}UDID:${RESET} $udid"
    echo -e "${CYAN}Android版本:${RESET} $system_name"
    echo -e "${CYAN}屏幕尺寸:${RESET} $wm_size"
    echo -e "${CYAN}wifi地址:${RESET} $wifi_ip"
}

# 获取应用列表
get_device_app_list() {
    if [ "$mode" == "adb" ]; then
        adb -s "$device_id" shell pm list packages | sed 's/package://g'
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" shell bm dump -a | grep -v "^ID:"
    fi
}

# 获取当前活动信息
get_app_activity() {
    if [ "$mode" == "adb" ]; then
        # adb -s "$device_id" shell dumpsys activity | grep "mResumedActivity"
        adb -s "$device_id" shell dumpsys window | grep "mCurrentFocus"
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" shell aa dump -l
    fi
}

# 录屏功能
start_screen_record() {
    local device_path time_str
    
    local_vedio_path="$HOME/Downloads"
    time_str=$(date +%Y%m%d_%H%M%S)
    case $mode in
        "adb")
            log_info "开始录屏，按${GREEN}Control+C${RESET}键停止..."
            scrcpy --no-audio-playback --no-window -m 1080 -b 2M --max-fps=15 -r "$local_vedio_path/$time_str.mp4"
            open $local_vedio_path
            ;;
        "hdc")
            log_warning "相关 hdc 命令还未支持，官方在开发中......"
            ;;
    esac
    
}

# 投屏
screen_projection() {
    case $mode in
        "adb")
            scrcpy -s ${device_id} -b2M -m1024 --max-fps 15 --prefer-text > /dev/null 2>&1 &
            scrcpy_pid=$!
            log_info "投屏进程已在后台运行,执行${GREEN}kill -9 $scrcpy_pid${RESET} 或者直接${GREEN}关闭投屏镜像${RESET}进行停止..."
            ;;
        "hdc")
            log_warning "相关 hdc 命令还未支持，官方在开发中......"
            ;;
    esac
}

# 截取屏幕截图
get_screenshot() {
    local local_img_path

    if [ "$mode" == "adb" ]; then
        local_img_path="$HOME/Downloads/screenshot_$(date +%Y%m%d%H%M%S).png"
        adb -s "$device_id" shell screencap -p /sdcard/screenshot.png
        adb -s "$device_id" pull /sdcard/screenshot.png "$local_img_path"
        adb -s "$device_id" shell rm /sdcard/screenshot.png
    elif [ "$mode" == "hdc" ]; then
        data_img_path=$(hdc -t "$device_id" shell snapshot_display 2>/dev/null | sed -n 's/.*write to \(\/data\/.*.jpg\).*/\1/p')
        local_img_path="$HOME/Downloads/$(basename "$data_img_path")"
        hdc -t "$device_id" file recv "$data_img_path" "$local_img_path" >/dev/null
    fi

    echo -e "${CYAN}截图保存到:${RESET} $local_img_path"
    open $HOME/Downloads
}

# 清理应用缓存
clean_app() {
    local package_name=$1

    if [ "$mode" == "adb" ]; then
        adb -s "$device_id" shell pm clear "$package_name"
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" shell bm clean -n "$package_name" -c 2>/dev/null
    fi
    log_success "已清理应用缓存：$package_name"
}

# 安装应用
install_app() {
    local apk_path=$1

    if [ ! -f "$apk_path" ]; then
        log_error "APK 文件 $apk_path 不存在，请检查路径是否正确。"
        return
    fi

    if [ "$mode" == "adb" ]; then
        adb -s "$device_id" push "$apk_path" "/data/local/tmp/"
        adb -s "$device_id" shell pm install "/data/local/tmp/$(basename "$apk_path")"
        adb -s "$device_id" shell rm "/data/local/tmp/$(basename "$apk_path")"
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" install "$apk_path"
    fi

    log_success "应用安装完成！"
}

# 卸载应用
uninstall_app() {
    local package_name=$1

    if [ "$mode" == "adb" ]; then
        adb -s "$device_id" uninstall "$package_name"
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" uninstall "$package_name"
    fi

    log_success "应用 $package_name 已卸载。"
}

# 检查/配置scrcpy (增强下载版)
check_scrcpy() {
    if ! command -v scrcpy &>/dev/null; then
        log_info "未检测到 scrcpy，开始自动部署流程..."
        # 系统信息获取
        local system_name=$(uname -s)
        local machine_arch=$(uname -m)
        local scrcpy_version="3.1"
        local base_url="https://github.moeyy.xyz/https://github.com/Genymobile/scrcpy/releases/download/v${scrcpy_version}"
        
        # 操作系统类型映射（关键修复点）
        case "$system_name" in
            Darwin)  local os_type="macos"  ;;  # 将Darwin映射为macos
            Linux)   local os_type="linux"  ;;
            *)       log_error "不支持的操作系统：$system_name"; return 1 ;;
        esac

        # 架构验证和文件名生成
        case "$system_name" in
            Darwin)
                case "$machine_arch" in
                    arm64 | aarch64) local arch_suffix="aarch64" ;;
                    x86_64)          local arch_suffix="x86_64" ;;
                    *)               log_error "不支持的Mac架构：$machine_arch"; return 1 ;;
                esac
                ;;
            Linux)
                case "$machine_arch" in
                    x86_64)          local arch_suffix="x86_64" ;;
                    aarch64)         local arch_suffix="aarch64" ;;
                    armv7l)          local arch_suffix="arm" ;;
                    *)               log_error "不支持的Linux架构：$machine_arch"; return 1 ;;
                esac
                ;;
            *) log_error "不支持的操作系统：$system_name"; return 1 ;;
        esac

        # 动态生成下载信息
        local pkg_name="scrcpy-${os_type}-${arch_suffix}-v${scrcpy_version}.tar.gz"
        local scrcpy_url="${base_url}/${pkg_name}"
        local target_dir=$(dirname $(command -v adb))

        # 临时目录处理
        local temp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'scrcpy_temp')
        trap 'rm -rf "$temp_dir"' EXIT

        # 下载流程
        log_info "下载 scrcpy v${scrcpy_version} (${system_name} ${machine_arch})..."
        if ! curl -L "$scrcpy_url" -o "${temp_dir}/${pkg_name}" --progress-bar; then
            log_error "下载失败，请检查：\n1. 网络连接\n2. 镜像源状态\n3. 版本是否存在"
            return 1
        fi

        # 解压流程
        log_info "正在部署到ADB目录：${target_dir}"
        sudo tar -xzf "${temp_dir}/${pkg_name}" -C "$target_dir" \
            --strip-components=1 \
            --exclude=*.bat \
            --exclude=README.md 2>/dev/null || {
            log_error "解压失败，可能原因：\n1. 磁盘空间不足\n2. 权限不足\n3. 文件损坏"
            return 1
        }

        # 权限设置
        sudo chmod +x "${target_dir}/scrcpy" || {
            log_error "权限设置失败，请手动执行：sudo chmod +x ${target_dir}/scrcpy"
            return 1
        }
        log_info "清理临时目录..."
        rm -rf ${temp_dir}
        log_success "scrcpy 部署成功！版本：$(scrcpy --version 2>&1 | head -1)"

    else
        log_info "scrcpy 已安装：$(which scrcpy)"
    fi
}

# 无线连接切换功能
toggle_wireless_connection() {
    if [ "$mode" == "adb" ]; then
        # 获取当前连接设备中的无线设备数量
        local wireless_list=$(adb devices | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+')
        
        # 判断连接状态并确认操作
        if [[ -n "$wireless_list" ]]; then
            # 当前有无线连接时关闭
            read -rp $'\n检测到无线连接，是否要断开？(y/n) ' confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                adb disconnect ${wireless_list%%:*}:5555 >/dev/null 2>&1
                log_success "无线连接已断开"
            else
                log_info "已取消操作"
            fi
        else
            # 无线连接初始化流程
            read -rp $'\n当前为USB连接，是否切换为无线连接？(y/n) ' confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # 检查USB设备有效性
                if [ -z "$device_id" ]; then
                    log_error "未检测到有效USB设备"
                    return 1
                fi
                
                log_info "正在建立无线连接..."
                
                # 获取设备IP（优先用已缓存的wifi_ip）
                local target_ip=${wifi_ip:-$(adb -s "$device_id" shell "dumpsys wifi | grep 'mWifiInfo' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'" 2>/dev/null)}
                
                # 确保IP有效性
                if [[ ! "$target_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    log_error "无法自动获取IP地址，请手动输入："
                    read -r target_ip
                fi
                
                # 切换TCP模式+连接
                if adb -s "$device_id" tcpip 5555 | grep -q "restarting"; then
                    sleep 3 # 等待端口开放
                    if adb connect "${target_ip}:5555" | grep -q "connected"; then
                        log_success "无线连接成功: ${target_ip}:5555"
                        device_id="${target_ip}:5555" # 更新当前设备ID
                    else
                        log_error "连接失败，请检查：\n1.设备与电脑需在同一网络\n2.防火墙允许5555端口"
                    fi
                else
                    log_error "TCP模式切换失败，请检查USB调试权限"
                fi
            else
                log_info "已取消操作"
            fi
        fi
    # elif [ "$mode" == "hdc" ]; then
    #     # █████████████████████ HDC新增逻辑 因无法像ADB一样断开无线连接，暂时不用 █████████████████████
    #     local tmode_port=6666

    #     # 获取当前连接状态
    #     local conn_status=$(hdc list targets -v | grep -v -F "[Empty]"| awk '! /Offline/ && NF >=3'| grep -v "^$" | cut -d' ' -f1| awk '{print $2}' )
        
    #     if [ "$conn_status" == "USB" ]; then
    #         # USB转无线流程
    #         read -rp $'\n当前为USB连接，是否切换为无线连接？(y/n) ' confirm
    #         if [[ "$confirm" =~ ^[Yy]$ ]]; then
    #             # 获取设备IP
    #             local target_ip=${wifi_ip:-$(hdc shell "ifconfig wlan0 | grep 'inet addr:' | sed 's/.*addr:\([0-9.]*\).*/\1/'" 2>/dev/null)}
    #             if [[ ! "$target_ip" =~ ^[0-9]+\. ]]; then
    #                 log_error "无法自动获取IP地址，请手动输入："
    #                 read -r target_ip
    #             fi
                
    #             # 开启TCP模式
    #             if hdc -t "$device_id" tmode port ${tmode_port} | grep -q "successful"; then
    #                 sleep 2
    #                 # 无线连接
    #                 if hdc -t ${device_id} tconn "${target_ip}:${tmode_port}" | grep -q "OK"; then
    #                     log_success "无线连接成功: ${target_ip}:${tmode_port}"
    #                     # device_id="${target_ip}:${tmode_port}"
    #                 else
    #                     log_error "连接失败，请检查：\n1.设备与电脑需在同一网络\n2.防火墙允许${tmode_port}端口"
    #                 fi
    #             else
    #                 log_error "TCP模式切换失败，请检查HDC权限"
    #             fi
    #         fi
            
    #     elif [ "$conn_status" == "TCP" ]; then
    #         # 无线转USB流程
    #         read -rp $'\n检测到无线连接，是否要断开？(y/n) ' confirm
    #         if [[ "$confirm" =~ ^[Yy]$ ]]; then
    #             hdc -t "$device_id" tmode usb >/dev/null 2>&1
    #             log_success "无线连接已断开"
    #         fi
    #     # fi
    else
        log_warning "HDC暂不支持无线连接"
    fi
}


# 主菜单
main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}======= ADB/HDC 工具箱 =======${RESET}"
        echo -e "1) 显示当前可用设备\t2) 显示设备信息"
        echo -e "3) 获取活动页信息\t4) 获取设备应用列表"
        echo -e "5) 清理应用缓存\t\t6) 屏幕截图"
        echo -e "7) 安装应用\t\t8) 卸载应用"
        echo -e "9) 录屏\t\t\t0) 投屏"
        echo -e "10) 无线模式"

        echo -e "${RED}x) 退出脚本${RESET}"
        echo -e -n "${YELLOW}请选择操作：${RESET} "
        read -r choice

        case $choice in
            1) log_info "获取当前可用设备,当只有一个时自动选择..."; select_device ;;
            2) log_info "获取设备信息..."; get_device_info ;;
            3) log_info "获取当前活动信息..."; get_app_activity ;;
            4) log_info "获取设备应用列表..."; get_device_app_list ;;
            5) 
                read -rp "请输入要清理缓存的包名： " package_name
                clean_app "$package_name"
                ;;
            6) log_info "截取当前屏幕..."; get_screenshot ;;
            7)
                read -rp "请输入 APK 文件路径： " apk_path
                install_app "$apk_path"
                ;;
            8)
                read -rp "请输入要卸载的包名： " package_name
                uninstall_app "$package_name"
                ;;
            9) log_info "即将录屏..."; start_screen_record;;
            0) log_info "开始投屏..."; screen_projection;;
            10) log_info "设置无线模式..."; toggle_wireless_connection;;

            x)  
                log_info "退出脚本，感谢使用！"; exit 0 ;;
            *)  
                log_warning "无效选项，请重试。" ;;
        esac
    done
}

# 脚本入口
echo -e "${GREEN}请选择模式：${RESET}"
echo "1) adb 模式"
echo "2) hdc 模式"
read -rp "请输入数字（1 或 2）： " mode_choice

case $mode_choice in
    1) mode="adb"; check_command "adb"; check_scrcpy ;;
    2) mode="hdc"; check_command "hdc" ;;
    *) log_error "无效选项，请重新运行脚本并选择有效模式！"; exit 1 ;;
esac

select_device
main_menu
