#!/bin/bash

# ==========================
# ADB/HDC 工具脚本
# Version: v0.2
# Author: Soner
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
    log_success "当前选择的设备：$device_id"
}

# 获取设备信息
get_device_info() {
    local system_name
    local udid

    if [ "$mode" == "adb" ]; then
        system_name=$(adb -s "$device_id" shell getprop ro.build.version.release 2>/dev/null)
        udid="$device_id"
    elif [ "$mode" == "hdc" ]; then
        system_name=$(hdc -t "$device_id" shell param get const.product.software.version 2>/dev/null)
        udid=$(hdc -t "$device_id" shell bm get --udid | sed 's/udid of current device is ://')
    fi

    system_name=${system_name:-未知}
    echo -e "${CYAN}设备ID:${RESET} $device_id"
    echo -e "${CYAN}系统版本:${RESET} $system_name"
    echo -e "${CYAN}UDID:${RESET} $udid"
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
        adb -s "$device_id" shell dumpsys activity | grep "mResumedActivity"
    elif [ "$mode" == "hdc" ]; then
        hdc -t "$device_id" shell aa dump -l
    fi
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

# 主菜单
main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}======= ADB/HDC 工具脚本 =======${RESET}"
        echo "1) 显示设备信息"
        echo "2) 获取设备应用列表"
        echo "3) 获取当前活动信息"
        echo "4) 截取屏幕截图"
        echo "5) 清理应用缓存"
        echo "6) 安装应用"
        echo "7) 卸载应用"
        echo -e "${RED}x) 退出脚本${RESET}"
        echo -e -n "${YELLOW}请选择操作：${RESET} "
        read -r choice

        case $choice in
        1) log_info "获取设备信息..."; get_device_info ;;
        2) log_info "获取设备应用列表..."; get_device_app_list ;;
        3) log_info "获取当前活动信息..."; get_app_activity ;;
        4) log_info "截取屏幕截图..."; get_screenshot ;;
        5) 
            read -rp "请输入要清理缓存的包名： " package_name
            clean_app "$package_name"
            ;;
        6)
            read -rp "请输入 APK 文件路径： " apk_path
            install_app "$apk_path"
            ;;
        7)
            read -rp "请输入要卸载的包名： " package_name
            uninstall_app "$package_name"
            ;;
        x) log_info "退出脚本，感谢使用！"; exit 0 ;;
        *) log_warning "无效选项，请重试。" ;;
        esac
    done
}

# 脚本入口
echo -e "${GREEN}请选择模式：${RESET}"
echo "1) adb 模式"
echo "2) hdc 模式"
read -rp "请输入数字（1 或 2）： " mode_choice

case $mode_choice in
    1) mode="adb"; check_command "adb" ;;
    2) mode="hdc"; check_command "hdc" ;;
    *) log_error "无效选项，请重新运行脚本并选择有效模式！"; exit 1 ;;
esac

select_device
main_menu
