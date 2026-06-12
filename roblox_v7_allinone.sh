#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V15.1 - ANTI-FREEZE)
# Tích hợp: Ép vào Map | Diệt Treo Cứng CPU 0% | Xuyên Android 12
# =================================================================

# --- CẤU HÌNH CHIẾN TRƯỜNG ---
CHECK_INTERVAL=15
LAUNCH_TIMEOUT=420        
PROCESS_RECOVERY_COOLDOWN=30  # Chờ 30s sau khi tắt app mới bật lại (để test cho lẹ)
FORCE_REJOIN_INTERVAL=180     # Đúng 3 phút (180s) ép lệnh Rejoin tránh kẹt Menu
APP_LAUNCH_GRACE_PERIOD=90 

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="/data/local/tmp/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"

# Tự động dọn rác của bản cũ khi khởi chạy để không bị kẹt PID ảo
rm -rf "$STATE_DIR"/* "$CACHE_DIR"/*
mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

# 🎯 HỆ THỐNG QUÉT TOÀN CẦU (TÌM MỌI BẢN ROBLOX VÀ CLONE)
scan_all_roblox_instances() {
    local all_pkgs=$(pm list packages | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
    local sys_users=$(pm list users 2>/dev/null | grep -E "UserInfo" | awk -F'{' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
    [ -z "$sys_users" ] && sys_users="0"

    local detected_list=""
    for pkg in $all_pkgs; do
        for u_id in $sys_users; do
            local data_path="/data/user/$u_id/$pkg"
            [ "$u_id" = "0" ] && [ -d "/data/data/$pkg" ] && data_path="/data/data/$pkg"
            
            if [ -d "$data_path" ]; then
                detected_list="$detected_list ${pkg}|${u_id}|${data_path}"
                local owner=$(stat -c "%U:%G" "$data_path" 2>/dev/null)
                if [ -n "$owner" ]; then
                    chown -R "$owner" "$data_path" 2>/dev/null
                    chmod -R 755 "$data_path" 2>/dev/null
                fi
            fi
        done
    done
    echo "$detected_list"
}

# 🎯 TRÍCH XUẤT USERNAME TỪ FILE HỆ THỐNG
extract_roblox_username() {
    local data_path=$1
    local uname=""
    if [ -d "$data_path/shared_prefs" ]; then
        uname=$(grep -rioA 1 '"Username"' "$data_path/shared_prefs/" 2>/dev/null | grep -i "string" | head -1 | cut -d'>' -f2 | cut -d'<' -f1)
        if [ -z "$uname" ]; then
            uname=$(grep -rioE 'username":"[^"]+' "$data_path/shared_prefs/" 2>/dev/null | head -1 | cut -d'"' -f3)
        fi
    fi
    [ -z "$uname" ] && uname="Chưa_Login"
    echo "$uname" | cut -c 1-12 
}

# 🎯 PHÁT HIỆN TIẾN TRÌNH ĐANG HOẠT ĐỘNG
discover_active_instances() {
    local active_list=""
    for pid_dir in /proc/[0-9]*; do
        [ ! -d "$pid_dir" ] && continue
        local pid=$(basename "$pid_dir")
        local cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr -d '\0')
        if echo "$cmd" | grep -qi "roblox"; then
            local num_uid=$(grep "^Uid:" "$pid_dir/status" 2>/dev/null | awk '{print $2}')
            local pkg_name=$(echo "$cmd" | cut -d':' -f1)
            [ -n "$num_uid" ] && active_list="$active_list $pid|$num_uid|$pkg_name"
        fi
    done
    echo "$active_list"
}

# 🎯 RADAR CHẨN ĐOÁN SỨC KHỎE (TÍCH HỢP ĐẾM NHỊP CPU ĐỂ DIỆT TREO CỨNG)
evaluate_health_matrix() {
    local token=$1 pid=$2
    local now=$(date +%s)

    # 1. Bỏ qua kiểm tra nếu app đang trong thời gian chờ khởi động (Grace Period)
    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null || echo "0")
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING" && return 0
        fi
    fi

    local status_file="/proc/$pid/status"
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0

    # ==========================================
    # 🔥 MODULE ĐẾM NHỊP CPU (PHÁT HIỆN TREO 0%)
    # ==========================================
    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    local current_ticks=0
    
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        current_ticks=$((utime + stime))
    fi

    local last_ticks=$(cat "$CACHE_DIR/${token}_ticks.cache" 2>/dev/null || echo "0")
    echo "$current_ticks" > "$CACHE_DIR/${token}_ticks.cache"

    # Nếu nhịp đập CPU đứng im (CPU 0%) -> Tăng biến đếm án tử
    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null || echo "0")
        f_cnt=$((f_cnt + 1))
        echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"

        # Nếu kẹt 4 lần liên tiếp (15s x 4 = 1 phút bất động) -> Trả về điểm 0 để Nuke!
        if [ "$f_cnt" -ge 4 ]; then
            echo "0|APP_TREO_CỨNG" && return 0
        fi
    else
        # CPU nhảy nhịp bình thường -> Xóa án tử
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi
    # ==========================================

    local status_data=$(cat "$status_file" 2>/dev/null)
    local state=$(echo "$status_data" | grep "^State:" | awk '{print $2}')
    local score=95

    case "$state" in 
        Z|T) score=0 ;; 
        D) score=50 ;;  
    esac

    echo "$score|HEALTHY"
}

strict_nuke_package() {
    local pid=$1 token=$2
    if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
        kill "$pid" 2>/dev/null
        sleep 0.5
        kill -9 "$pid" 2>/dev/null
    fi
    # Xóa sạch bộ đếm CPU cũ của tab này khi bị nuke
    rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_freeze.cnt"
}

# 🎯 HÀM KHỞI CHẠY CỨU HỘ VÀ ÉP MAP XUYÊN NỀN ANDROID 12
execute_recovery_pipeline() {
    local pkg=$1 u_id=$2 pid=$3 error_type=$4
    local token="${pkg}_u${u_id}"
    local now=$(date +%s)
    
    # Nếu không phải hành động Ép vào map định kỳ, hãy xử tử tiến trình cũ trước
    if [ "$error_type" != "Ép_vào_Map" ]; then
        strict_nuke_package "$pid" "$token"
        sleep 1
    fi
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    local LAUNCH_ACTIVITY="$pkg/com.roblox.client.Activity.MainActivity"
    
    # SỬ DỤNG CỜ 0x14000000: Ép Android 12 lôi app lên màn hình chính và nhận Deep Link
    local START_CMD="am start --user $u_id -f 0x14000000 -n $LAUNCH_ACTIVITY -a android.intent.action.VIEW -d \"roblox://placeId=2753915549\""
    [ "$u_id" -eq 0 ] && START_CMD="am start -f 0x14000000 -n $LAUNCH_ACTIVITY -a android.intent.action.VIEW -d \"roblox://placeId=2753915549\""

    eval "$START_CMD >/dev/null 2>&1"
    
    local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

# 🎯 GIAO DIỆN THEO DÕI TRỰC QUAN
display_live_ui() {
    local all_instances=$1
    local total_tabs=$(echo "$all_instances" | wc -w)
    [ -z "$all_instances" ] && total_tabs=0

    printf "\033c" 
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;32m 🤖 NEXUS V15.1 - ANTI-FREEZE DASHBOARD (UNIVERSAL) \033[0m"
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;37m 📊 TỔNG SỐ TAB ĐANG THEO DÕI: \033[1;33m$total_tabs TAB\033[0m"
    echo -e "\033[1;36m-----------------------------------------------------------------------\033[0m"
    printf "\033[1;33m%-12s | %-12s | %-6s | %-15s | %-15s\033[0m\n" "LOẠI/UID" "TÊN ACCOUNT" "SCORE" "TRẠNG THÁI" "GHI CHÚ"
    echo "-----------------------------------------------------------------------"

    for inst in $all_instances; do
        local pkg=$(echo "$inst" | cut -d'|' -f1)
        local u_id=$(echo "$inst" | cut -d'|' -f2)
        local d_path=$(echo "$inst" | cut -d'|' -f3)
        local token="${pkg}_u${u_id}"

        local pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "N/A")
        local score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
        local l_err=$(cat "$STATE_DIR/${token}_last_err.txt" 2>/dev/null || echo "Bình thường")
        
        local app_type="Global"
        echo "$pkg" | grep -qi "vng" && app_type="VNG"
        echo "$pkg" | grep -qiE "[0-9]$" && app_type="Clone"
        local id_show="${app_type}_$u_id"

        local username=$(extract_roblox_username "$d_path")

        local color="\033[0;32m"
        [ "$score" -eq 0 ] && color="\033[0;31m"
        [ "$score" -eq 100 ] && color="\033[1;34m"
        [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && color="\033[1;33m"

        local status_text="Khỏe mạnh"
        [ "$score" -eq 0 ] && status_text="Đang Cứu Hộ"
        [ "$score" -eq 100 ] && status_text="Đang Mở Map"

        printf "${color}%-12s | %-12s | %-6s | %-15s | %-15s\033[0m\n" "$id_show" "$username" "$score" "$status_text" "$l_err"
    done
    
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;37m⚙️  Quét: ${CHECK_INTERVAL}s | Thử lại: ${PROCESS_RECOVERY_COOLDOWN}s | Ép Rejoin: ${FORCE_REJOIN_INTERVAL}s\033[0m"
}

# 🎯 VÒNG LẶP ĐIỀU KHIỂN TRUNG TÂM
monitor_core_loop() {
    while true; do
        local all_instances=$(scan_all_roblox_instances)
        local running_pids=$(discover_active_instances)
        local now=$(date +%s)
        
        for inst in $all_instances; do
            local token="$(echo "$inst" | cut -d'|' -f1)_u$(echo "$inst" | cut -d'|' -f2)"
            echo "0" > "$STATE_DIR/${token}_pid.txt"
        done

        # 1. KIỂM TRA TOÀN DIỆN CÁC TAB ĐANG CHẠY
        if [ -n "$running_pids" ]; then
            for r_pid_info in $running_pids; do
                local pid=$(echo "$r_pid_info" | cut -d'|' -f1)
                local num_uid=$(echo "$r_pid_info" | cut -d'|' -f2)
                local pkg=$(echo "$r_pid_info" | cut -d'|' -f3)
                
                local u_id="0"
                [ "$num_uid" -ge 100000 ] && u_id=$((num_uid / 100000))
                
                local token="${pkg}_u${u_id}"
                echo "$pid" > "$STATE_DIR/${token}_pid.txt"

                local matrix_result=$(evaluate_health_matrix "$token" "$pid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                # Nếu điểm = 0 (Do treo cứng hoặc đứng im), kích hoạt cứu hộ khẩn cấp
                if [ "$current_score" -eq 0 ]; then
                    execute_recovery_pipeline "$pkg" "$u_id" "$pid" "$health_status"
                fi
            done
        fi

        # 2. XỬ LÝ QUÁ TRÌNH MẤT TIẾN TRÌNH HOẶC ÉP REJOIN TRÁNH KẸT MENU
        for inst in $all_instances; do
            local pkg=$(echo "$inst" | cut -d'|' -f1)
            local u_id=$(echo "$inst" | cut -d'|' -f2)
            local token="${pkg}_u${u_id}"
            
            local chk_pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "0")
            
            # TRƯỜNG HỢP A: Bị văng hẳn, mất sạch tiến trình
            if [ "$chk_pid" = "0" ]; then
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_${token}.ts" 2>/dev/null || echo "0")
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_${token}.ts"
                    echo "0" > "$STATE_DIR/${token}_score.txt"
                    execute_recovery_pipeline "$pkg" "$u_id" "0" "MẤT_TIẾN_TRÌNH"
                fi
            else
                # TRƯỜNG HỢP B: Tab vẫn chạy nhưng kích hoạt Ép Rejoin định kỳ (Fix lỗi kẹt Menu)
                local last_rejoin=$(cat "$CACHE_DIR/${token}_last_rejoin.ts" 2>/dev/null || echo "0")
                if [ $((now - last_rejoin)) -ge "$FORCE_REJOIN_INTERVAL" ]; then
                    echo "$now" > "$CACHE_DIR/${token}_last_rejoin.ts"
                    execute_recovery_pipeline "$pkg" "$u_id" "$chk_pid" "Ép_vào_Map"
                fi
            fi
        done
        
        display_live_ui "$all_instances"
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
