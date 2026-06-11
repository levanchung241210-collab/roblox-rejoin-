#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V14 - UNIVERSAL EDITION)
# Tích hợp: Auto-Detect (VNG/Global/APK Clone) | Trích xuất Username | Đếm Tab
# =================================================================

# --- CẤU HÌNH CHIẾN TRƯỜNG ---
CHECK_INTERVAL=15
LAUNCH_TIMEOUT=420        
NET_STAGNANT_THRESHOLD=5  
PROCESS_RECOVERY_COOLDOWN=180
LOG_CHECK_COOLDOWN=120
APP_LAUNCH_GRACE_PERIOD=90 

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="/data/local/tmp/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

log_event() {
    local level=$1 msg=$2 token=$3
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$token] [$level] $msg" >> "$LOG_FILE"
}

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
                
                # Fix phân quyền cho máy anh em
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

# 🎯 MOI TÊN TÀI KHOẢN TỪ BỘ NHỚ APP
extract_roblox_username() {
    local data_path=$1
    local uname=""
    
    # Quét trong shared_prefs
    if [ -d "$data_path/shared_prefs" ]; then
        uname=$(grep -rioA 1 '"Username"' "$data_path/shared_prefs/" 2>/dev/null | grep -i "string" | head -1 | cut -d'>' -f2 | cut -d'<' -f1)
        if [ -z "$uname" ]; then
            uname=$(grep -rioE 'username":"[^"]+' "$data_path/shared_prefs/" 2>/dev/null | head -1 | cut -d'"' -f3)
        fi
    fi
    
    [ -z "$uname" ] && uname="Chưa_Login"
    echo "$uname" | cut -c 1-12 # Cắt gọn tên nếu quá dài
}

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

get_uid_net_bytes() {
    local num_uid=$1
    if [ -f "/proc/uid_stat/$num_uid/tcp_rcv" ]; then
        local rcv=$(cat "/proc/uid_stat/$num_uid/tcp_rcv" 2>/dev/null)
        local snd=$(cat "/proc/uid_stat/$num_uid/tcp_snd" 2>/dev/null)
        echo "$((rcv + snd))" && return
    fi
    if [ -f "/proc/net/xt_qtaguid/stats" ]; then
        local total_bytes=$(awk -v uid="$num_uid" '$4==uid {sum+=$6+$8} END {print sum}' /proc/net/xt_qtaguid/stats 2>/dev/null)
        if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ]; then echo "$total_bytes" && return; fi
    fi
    echo "-1"
}

evaluate_health_matrix() {
    local token=$1 pid=$2 num_uid=$3
    local now=$(date +%s)

    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null)
    [ -z "$launch_time" ] && launch_time=0
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING" && return 0
        fi
    fi

    local score=0
    local status_file="/proc/$pid/status"
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0
    
    local status_data=$(cat "$status_file" 2>/dev/null)
    local state=$(echo "$status_data" | grep "^State:" | awk '{print $2}')
    local rss_kb=$(echo "$status_data" | grep "^VmRSS:" | awk '{print $2}')
    local threads=$(echo "$status_data" | grep "^Threads:" | awk '{print $2}')

    [ -z "$rss_kb" ] && rss_kb=0
    [ -z "$threads" ] && threads=0

    case "$state" in R) score=$((score + 25)) ;; S) score=$((score + 20)) ;; D) score=$((score + 5)) ;; *) score=$((score + 0)) ;; esac
    if [ "$rss_kb" -gt 102400 ]; then score=$((score + 25)); else score=$((score + 10)); fi
    if [ "$threads" -gt 5 ]; then score=$((score + 20)); else score=$((score + 5)); fi

    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    local current_ticks=0
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        current_ticks=$((utime + stime))
    fi
    local last_ticks=$(cat "$CACHE_DIR/${token}_ticks.cache" 2>/dev/null)
    [ -z "$last_ticks" ] && last_ticks=0
    echo "$current_ticks" > "$CACHE_DIR/${token}_ticks.cache"

    local current_net=$(get_uid_net_bytes "$num_uid")
    local last_net=$(cat "$CACHE_DIR/${token}_net.cache" 2>/dev/null)
    [ -z "$last_net" ] && last_net=0

    local net_freeze_cnt=$(cat "$CACHE_DIR/${token}_net_freeze.cnt" 2>/dev/null)
    [ -z "$net_freeze_cnt" ] && net_freeze_cnt=0

    if [ "$current_net" -eq -1 ]; then
        local cpu_drift=$((current_ticks - last_ticks))
        [ "$cpu_drift" -lt 0 ] && cpu_drift=$((cpu_drift * -1))
        if [ "$cpu_drift" -le 1 ]; then net_freeze_cnt=$((net_freeze_cnt + 1)); else net_freeze_cnt=0; fi
    else
        if [ "$current_net" -eq "$last_net" ]; then net_freeze_cnt=$((net_freeze_cnt + 1)); else net_freeze_cnt=0; fi
        echo "$current_net" > "$CACHE_DIR/${token}_net.cache"
    fi
    echo "$net_freeze_cnt" > "$CACHE_DIR/${token}_net_freeze.cnt"
    
    if [ $((now - launch_time)) -gt "$LAUNCH_TIMEOUT" ]; then
        if [ "$net_freeze_cnt" -ge "$NET_STAGNANT_THRESHOLD" ]; then echo "0|LAUNCH_MAP_TIMEOUT" && return 0; fi
    fi

    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null)
        [ -z "$f_cnt" ] && f_cnt=0
        f_cnt=$((f_cnt + 1))
        echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"
        if [ "$f_cnt" -ge 10 ]; then echo "0|ZOMBIE_FROZEN_TICKS" && return 0; else score=$((score + 15)); fi
    else
        score=$((score + 30))
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi

    echo "$score|HEALTHY"
}

strict_nuke_package() {
    local pid=$1 token=$2
    if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
        kill "$pid" 2>/dev/null
        sleep 0.5
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_net.cache" "$CACHE_DIR/${token}_net_freeze.cnt"
}

# 🎯 HÀM CỨU HỘ THÔNG MINH CHO CẢ ANDROID 10 VÀ 12
execute_recovery_pipeline() {
    local pkg=$1 u_id=$2 pid=$3 error_type=$4
    local token="${pkg}_u${u_id}"
    local now=$(date +%s)
    
    strict_nuke_package "$pid" "$token"
    sleep 2
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    # Tìm Launcher Activity
    local LAUNCH_ACTIVITY=$(cmd package resolve-activity --brief $pkg 2>/dev/null | tail -n 1)
    [ -z "$LAUNCH_ACTIVITY" ] || [ "$LAUNCH_ACTIVITY" = "No activity found" ] && LAUNCH_ACTIVITY="$pkg/com.roblox.client.Activity.MainActivity"
    
    # Quyết định chạy theo cờ --user (Android 12 Clone) hay chạy thường (Android 10 APK Clone)
    local START_CMD="am start --user $u_id -n $LAUNCH_ACTIVITY -a android.intent.action.VIEW -d \"roblox://placeId=2753915549\""
    [ "$u_id" -eq 0 ] && START_CMD="am start -n $LAUNCH_ACTIVITY -a android.intent.action.VIEW -d \"roblox://placeId=2753915549\""

    eval "$START_CMD >/dev/null 2>&1"
    
    local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null)
    [ -z "$r_cnt" ] && r_cnt=0
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

display_live_ui() {
    local all_instances=$1
    local total_tabs=$(echo "$all_instances" | wc -w)
    [ -z "$all_instances" ] && total_tabs=0

    printf "\033c" 
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;32m 🤖 NEXUS V14 - UNIVERSAL DASHBOARD (VNG + GLOBAL + CLONE) \033[0m"
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
        
        # Nhận diện loại app hiển thị cho gọn
        local app_type="Global"
        echo "$pkg" | grep -qi "vng" && app_type="VNG"
        echo "$pkg" | grep -qiE "[0-9]$" && app_type="Clone_APK" # Nhận diện modded apk như client2, client3
        local id_show="${app_type}_$u_id"

        local username=$(extract_roblox_username "$d_path")

        local color="\033[0;32m"
        [ "$score" -eq 0 ] && color="\033[0;31m"
        [ "$score" -eq 100 ] && color="\033[1;34m"
        [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && color="\033[1;33m"

        local status_text="Khỏe mạnh"
        [ "$score" -eq 0 ] && status_text="Đang Cứu Hộ"
        [ "$score" -eq 100 ] && status_text="Đang Vào Map"

        printf "${color}%-12s | %-12s | %-6s | %-15s | %-15s\033[0m\n" "$id_show" "$username" "$score" "$status_text" "$l_err"
    done
    
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;37m⚙️  Quét: ${CHECK_INTERVAL}s/lần | 🕒 Cập nhật: $(date '+%H:%M:%S')\033[0m"
}

monitor_core_loop() {
    while true; do
        # 1. Quét tìm toàn bộ môi trường Roblox có trên máy
        local all_instances=$(scan_all_roblox_instances)
        local running_pids=$(discover_active_instances)
        local now=$(date +%s)
        
        # Reset PID
        for inst in $all_instances; do
            local token="$(echo "$inst" | cut -d'|' -f1)_u$(echo "$inst" | cut -d'|' -f2)"
            echo "0" > "$STATE_DIR/${token}_pid.txt"
        done

        # 2. Đánh giá các tiến trình đang chạy
        if [ -n "$running_pids" ]; then
            for r_pid_info in $running_pids; do
                local pid=$(echo "$r_pid_info" | cut -d'|' -f1)
                local num_uid=$(echo "$r_pid_info" | cut -d'|' -f2)
                local pkg=$(echo "$r_pid_info" | cut -d'|' -f3)
                
                # Ánh xạ ngược UID sang User ID
                local u_id="0"
                [ "$num_uid" -ge 100000 ] && u_id=$((num_uid / 100000))
                
                local token="${pkg}_u${u_id}"
                echo "$pid" > "$STATE_DIR/${token}_pid.txt"

                local matrix_result=$(evaluate_health_matrix "$token" "$pid" "$num_uid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                if [ "$current_score" -lt 40 ] && [ "$current_score" -ne 0 ] || [ "$health_status" != "HEALTHY" ] && [ "$health_status" != "LAUNCHING" ]; then
                    execute_recovery_pipeline "$pkg" "$u_id" "$pid" "$health_status"
                fi
            done
        fi

        # 3. Cứu hộ các tab bị Missing (Bị kill mất xác)
        for inst in $all_instances; do
            local pkg=$(echo "$inst" | cut -d'|' -f1)
            local u_id=$(echo "$inst" | cut -d'|' -f2)
            local token="${pkg}_u${u_id}"
            
            local chk_pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null)
            if [ -z "$chk_pid" ] || [ "$chk_pid" = "0" ]; then
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_${token}.ts" 2>/dev/null)
                [ -z "$last_miss_rcv" ] && last_miss_rcv=0
                
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_${token}.ts"
                    echo "0" > "$STATE_DIR/${token}_score.txt"
                    execute_recovery_pipeline "$pkg" "$u_id" "0" "PROCESS_MISSING"
                fi
            fi
        done
        
        display_live_ui "$all_instances"
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
