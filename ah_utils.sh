#!/bin/bash

# ==========================
# ADB/HDC 工具脚本
# Version: v0.3
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
}

# 获取设备信息
get_device_info() {
    local system_name
    local udid

    if [ "$mode" == "adb" ]; then
        system_name=$(adb -s "$device_id" shell getprop ro.build.version.release 2>/dev/null)
        udid="$device_id"
        wm_size=$(adb -s "$device_id" shell wm size | awk -F': ' '{print $2}' 2>/dev/null)
        wifi_ip=$(adb -s "$device_id" shell "dumpsys wifi | grep -A10 'mWifiInfo' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1" 2>/dev/null)
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
                # 系统架构检测
        local system_name=$(uname -s)
        local machine_arch=$(uname -m)
        local base_url="https://github.moeyy.xyz/https://github.com/Genymobile/scrcpy/releases/download"
        local scrcpy_url=""
        # 定义版本变量（方便后续升级）
        local scrcpy_version="3.1"
        
        # 智能匹配下载地址
        case "$system_name" in
            Darwin)
                case "$machine_arch" in
                    arm64 | aarch64)
                        scrcpy_url="${base_url}/v${scrcpy_version}/scrcpy-macos-aarch64-v${scrcpy_version}.tar.gz"
                        ;;
                    x86_64)
                        scrcpy_url="${base_url}/v${scrcpy_version}/scrcpy-macos-x86_64-v${scrcpy_version}.tar.gz"
                        ;;
                    *)
                        log_error "不支持的Mac架构：$machine_arch"
                        return 1
                        ;;
                esac
                ;;
            Linux)
                case "$machine_arch" in
                    x86_64)
                        scrcpy_url="${base_url}/v${scrcpy_version}/scrcpy-linux-x86_64-v${scrcpy_version}.tar.gz"
                        ;;
                    *)
                        log_error "不支持的Linux架构：$machine_arch"
                        return 1
                        ;;
                esac
                ;;
            *)
                log_error "不支持的操作系统：$system_name"
                return 1
                ;;
        esac
        
        # 创建临时目录
        local temp_dir
        temp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'scrcpy_temp')
        trap 'rm -rf "$temp_dir"' EXIT
        
        # 下载地址配置（可替换镜像源）
        local scrcpy_url="https://github.moeyy.xyz/https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-macos-aarch64-v3.1.tar.gz"
        local scrcpy_tar="${temp_dir}/scrcpy.tar.gz"
        
        # 下载文件
        log_info "开始下载 scrcpy (v3.1 macos aarch64)..."
        if ! curl -L "$scrcpy_url" -o "$scrcpy_tar" --progress-bar; then
            log_error "下载失败，请检查网络连接"
            return 1
        fi
        
        # 验证文件完整性
        if ! tar tf "$scrcpy_tar" &> /dev/null; then
            log_error "文件损坏，请重新下载"
            return 1
        fi
        
        # 解压文件
        log_info "正在解压安装包..."
        tar -xzf "$scrcpy_tar" -C "$temp_dir" || {
            log_error "解压失败，请检查磁盘空间"
            return 1
        }
        
        # 定位可执行文件（适配新版目录结构）
        local scrcpy_bin
        scrcpy_bin=$(find "$temp_dir" -name "scrcpy" -type f -print -quit)
        if [[ -z "$scrcpy_bin" ]]; then
            log_error "未找到可执行文件"
            return 1
        fi
        
        # 获取adb目录
        local adb_path target_dir
        adb_path=$(command -v adb)
        if [[ -z "$adb_path" ]]; then
            log_error "未找到adb，请先安装Android Platform Tools"
            return 1
        fi
        target_dir=$(dirname "$adb_path")
        
        # 部署文件
        log_info "正在部署到系统目录：$target_dir"
        if ! sudo cp "$scrcpy_bin" "$target_dir/scrcpy"; then
            log_error "权限不足，请手动输入密码"
            sudo cp "$scrcpy_bin" "$target_dir/scrcpy" || {
                log_error "部署失败，请尝试手动安装"
                return 1
            }
        fi
        
        # 设置权限
        sudo chmod +x "$target_dir/scrcpy"
        log_success "scrcpy 部署成功！"
        
    else
        log_info "scrcpy 已安装：$(which scrcpy)"
    fi
}



# 主菜单
main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}======= ADB/HDC 工具箱 =======${RESET}"
        echo -e "1) 显示当前可用设备\t2) 显示设备信息"
        echo -e "3) 获取当前活动信息\t4) 获取设备应用列表"
        echo -e "5) 清理应用缓存\t\t6) 安装应用"
        echo -e "7) 屏幕截图\t\t8) 录屏"
        echo -e "9) 卸载应用"

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
            6)
                read -rp "请输入 APK 文件路径： " apk_path
                install_app "$apk_path"
                ;;
            7) log_info "截取当前屏幕..."; get_screenshot ;;
            8) log_info "即将录屏..."; start_screen_record;;
            9)
                read -rp "请输入要卸载的包名： " package_name
                uninstall_app "$package_name"
                ;;
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
