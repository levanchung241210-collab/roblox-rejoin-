#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V16 - EMULATOR CORE REWRITE)
# Tích hợp: Fix Lỗi Chia UID Giả Lập | Quản Lý PID Thực Tế | Chống Treo Cứng 0%
# =================================================================

# --- CẤU HÌNH CHIẾN TRƯỜNG ---
CHECK_INTERVAL=15
LAUNCH_TIMEOUT=420        
PROCESS_RECOVERY_COOLDOWN=30  # Chờ 30s sau khi tắt app mới bật lại
FORCE_REJOIN_INTERVAL=60     # Đúng 1 phút (60s) ép lệnh Rejoin tránh kẹt Menu
APP_LAUNCH_GRACE_PERIOD=90 

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="/data/local/tmp/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"

# Dọn dẹp cache cũ để tránh xung đột cấu trúc dữ liệu mới
rm -rf "$STATE_DIR"/* "$CACHE_DIR"/*
mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

# 🎯 TRÍCH XUẤT USERNAME TỪ FILE HỆ THỐNG (HỖ TRỢ CẢ THƯ MỤC PHẲNG)
extract_roblox_username() {
    local pkg=$1
    local uname=""
    # Tự động tìm đường dẫn dữ liệu chuẩn của Package
    local data_path="/data/data/$pkg"
    [ ! -d "$data_path" ] && data_path=$(pm path $pkg 2>/dev/null | cut -d':' -f2 | sed 's/\/base.apk//' | sed 's/app/data/')
    
    if [ -d "$data_path/shared_prefs" ]; then
        uname=$(grep -rioA 1 '"Username"' "$data_path/shared_prefs/" 2>/dev/null | grep -i "string" | head -1 | cut -d'>' -f2 | cut -d'<' -f1)
        if [ -z "$uname" ]; then
            uname=$(grep -rioE 'username":"[^"]+' "$data_path/shared_prefs/" 2>/dev/null | head -1 | cut -d'"' -f3)
        fi
    fi
    [ -z "$uname" ] && uname="Chưa_Login"
    echo "$uname" | cut -c 1-12 
}

# 🎯 ENGINE MỚI: QUÉT VÀ PHÂN TÍCH TIẾN TRÌNH THỰC TẾ (KHÔNG CHƠI PID ẢO)
discover_active_instances() {
    local active_list=""
    for pid_dir in /proc/[0-9]*; do
        [ ! -d "$pid_dir" ] && continue
        local pid=$(basename "$pid_dir")
        local cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr -d '\0')
        
        # Lọc chính xác tiến trình Roblox, loại bỏ các tiến trình phụ như UnityMain nếu có
        if echo "$cmd" | grep -qi "roblox" && ! echo "$cmd" | grep -qi ":"; then
            local pkg_name=$(echo "$cmd" | cut -d':' -f1)
            # Lấy UID thực tế từ hệ thống, không xử lý chia tách phức tạp
            local num_uid=$(grep "^Uid:" "$pid_dir/status" 2>/dev/null | awk '{print $2}')
            [ -z "$num_uid" ] && num_uid="0"
            
            active_list="$active_list $pid|$pkg_name|$num_uid"
        fi
    done
    echo "$active_list"
}

# 🎯 RADAR ĐẾM NHỊP CPU (GIỮ NGUYÊN KIẾN TRÚC PHÁT HIỆN TREO CỨNG 0%)
evaluate_health_matrix() {
    local token=$1 pid=$2
    local now=$(date +%s)

    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null || echo "0")
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING" && return 0
        fi
    fi

    local status_file="/proc/$pid/status"
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0

    # Đếm Ticks CPU thực tế của tiến trình
    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    local current_ticks=0
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        current_ticks=$((utime + stime))
    fi

    local last_ticks=$(cat "$CACHE_DIR/${token}_ticks.cache" 2>/dev/null || echo "0")
    echo "$current_ticks" > "$CACHE_DIR/${token}_ticks.cache"

    # Nếu CPU đứng im hoàn toàn (0%) qua nhiều chu kỳ quét
    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null || echo "0")
        f_cnt=$((f_cnt + 1))
        echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"

        if [ "$f_cnt" -ge 4 ]; then
            echo "0|APP_TREO_CỨNG" && return 0
        fi
    else
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi

    echo "95|HEALTHY"
}

strict_nuke_package() {
    local pid=$1 token=$2
    if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
        kill "$pid" 2>/dev/null
        sleep 0.5
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_freeze.cnt"
}

# 🎯 HÀM KHỞI CHẠY KHÔNG PHỤ THUỘC USER_ID PHỨC TẠP
execute_recovery_pipeline() {
    local pkg=$1 pid=$2 error_type=$3
    local token="$pkg"
    local now=$(date +%s)
    
    if [ "$error_type" != "Ép_vào_Map" ]; then
        strict_nuke_package "$pid" "$token"
        sleep 1
    fi
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    # Tự động phân giải Launcher Activity của giả lập
    local LAUNCH_ACTIVITY=$(cmd package resolve-activity --brief $pkg 2>/dev/null | tail -n 1)
    [ -z "$LAUNCH_ACTIVITY" ] || [ "$LAUNCH_ACTIVITY" = "No activity found" ] && LAUNCH_ACTIVITY="$pkg/com.roblox.client.Activity.MainActivity"
    
    # Sử dụng cờ ép lôi cửa sổ lên trên giả lập (0x14000000)
    local START_CMD="am start -f 0x14000000 -n $LAUNCH_ACTIVITY -a android.intent.action.VIEW -d \"roblox://placeId=2753915549\""
    eval "$START_CMD >/dev/null 2>&1"
    
    local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

# 🎯 UI MỚI: CHỈ HIỂN THỊ CÁC TAB THỰC SỰ ĐANG CHẠY HOẶC ĐƯỢC CHỈ ĐỊNH
display_live_ui() {
    local active_instances=$1
    local total_tabs=0
    
    # Đếm số lượng token thực tế dựa trên danh sách phần mềm Roblox cài trong máy
    local installed_roblox=$(pm list packages | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
    
    printf "\033c" 
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;32m 🤖 NEXUS V16 - EMULATOR ENGINE (REAL-TIME INSTANCE) \033[0m"
    echo -e "\033[1;36m=======================================================================\033[0m"
    
    printf "\033[1;33m%-20s | %-12s | %-6s | %-15s | %-15s\033[0m\n" "PACKAGE NAME" "TÊN ACCOUNT" "SCORE" "TRẠNG THÁI" "GHI CHÚ"
    echo "-----------------------------------------------------------------------"

    for pkg in $installed_roblox; do
        local token="$pkg"
        # Kiểm tra xem package này có nằm trong danh sách đang chạy không
        local is_running=$(echo "$active_instances" | grep -w "$pkg")
        
        local pid="0"
        if [ -n "$is_running" ]; then
            pid=$(echo "$is_running" | tr ' ' '\n' | grep -w "$pkg" | head -1 | cut -d'|' -f1)
        fi
        
        # Ghi nhận trạng thái PID vào file để đồng bộ
        echo "$pid" > "$STATE_DIR/${token}_pid.txt"

        local score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
        local l_err=$(cat "$STATE_DIR/${token}_last_err.txt" 2>/dev/null || echo "Bình thường")
        local username=$(extract_roblox_username "$pkg")
        
        local color="\033[0;32m"
        local status_text="Khỏe mạnh"

        if [ "$pid" = "0" ]; then
            score=0
            color="\033[0;31m"
            status_text="Tắt/Mất Tích"
        else
            total_tabs=$((total_tabs + 1))
            [ "$score" -eq 100 ] && color="\033[1;34m" && status_text="Đang Mở Map"
            [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && color="\033[1;33m"
        fi

        printf "${color}%-20s | %-12s | %-6s | %-15s | %-15s\033[0m\n" "$pkg" "$username" "$score" "$status_text" "$l_err"
    done
    
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;37m 📊 TỔNG SỐ TAB THỰC TẾ ĐANG CHẠY: \033[1;33m$total_tabs TAB\033[0m"
    echo -e "\033[1;36m=======================================================================\033[0m"
}

# 🎯 VÒNG LẶP ĐIỀU KHIỂN ĐÃ ĐƯỢC FIX LỖI LOGIC GIẢ LẬP
monitor_core_loop() {
    while true; do
        # 1. Quét tìm toàn bộ tiến trình thực tế đang chạy trên RAM
        local running_pids=$(discover_active_instances)
        local now=$(date +%s)
        
        # 2. Phân tích sức khỏe của các tiến trình thực tế
        if [ -n "$running_pids" ]; then
            for r_pid_info in $running_pids; do
                local pid=$(echo "$r_pid_info" | cut -d'|' -f1)
                local pkg=$(echo "$r_pid_info" | cut -d'|' -f2)
                local token="$pkg"
                
                local matrix_result=$(evaluate_health_matrix "$token" "$pid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                # Phát hiện treo cứng CPU 0%
                if [ "$current_score" -eq 0 ]; then
                    execute_recovery_pipeline "$pkg" "$pid" "$health_status"
                fi
            done
        fi

        # 3. Quét danh sách phần mềm cài đặt để xử lý Mất Tiến Trình hoặc Ép Rejoin
        local installed_roblox=$(pm list packages | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
        for pkg in $installed_roblox; do
            local token="$pkg"
            local chk_pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "0")
            
            # TRƯỜNG HỢP A: Tab bị tắt hẳn (Mất tiến trình)
            if [ "$chk_pid" = "0" ]; then
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_${token}.ts" 2>/dev/null || echo "0")
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_${token}.ts"
                    echo "0" > "$STATE_DIR/${token}_score.txt"
                    execute_recovery_pipeline "$pkg" "0" "MẤT_TIẾN_TRÌNH"
                fi
            else
                # TRƯỜNG HỢP B: Tab đang chạy ổn định -> Kích hoạt cưỡng chế Rejoin tránh kẹt Menu
                local last_rejoin=$(cat "$CACHE_DIR/${token}_last_rejoin.ts" 2>/dev/null || echo "0")
                if [ $((now - last_rejoin)) -ge "$FORCE_REJOIN_INTERVAL" ]; then
                    echo "$now" > "$CACHE_DIR/${token}_last_rejoin.ts"
                    execute_recovery_pipeline "$pkg" "$chk_pid" "Ép_vào_Map"
                fi
            fi
        done
        
        display_live_ui "$running_pids"
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
