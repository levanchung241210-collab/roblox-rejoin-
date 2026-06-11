#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V13.6 - SOVEREIGN PERFECTION)
# Tối ưu: Fix Cú Pháp Heredoc | Diệt Tận Gốc Subshell | Cooldown Cứu Hộ | Tránh Hoàn Toàn Báo Động Giả
# =================================================================

# --- CẤU HÌNH CHIẾN TRƯỜNG ---
TARGET_PACKAGE="com.roblox.client.vnggames"
CHECK_INTERVAL=20
PID_CACHE_TTL=20          
LAUNCH_TIMEOUT=420        
NET_STAGNANT_THRESHOLD=5  
PROCESS_RECOVERY_COOLDOWN=180 # 🎯 VÁ LỖI 5: Cấu hình thời gian chờ chống spam am start vô hạn
LOG_CHECK_COOLDOWN=120

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="$HOME/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"
DASHBOARD_JSON="/sdcard/Download/nexus_status.json"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

# Biến toàn cục lưu danh sách User ID phát hiện động trên thiết bị
DETECTED_USERS="0"

log_event() {
    local level=$1 msg=$2 token=$3
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$token] [$level] $msg" >> "$LOG_FILE"
}

get_error_note_id() {
    case "$1" in
        "PROCESS_MISSING") echo "1" ;;
        "ZOMBIE_EMPTY_STATUS") echo "2" ;;
        "ZOMBIE_FROZEN_TICKS") echo "3" ;;
        "INFINITE_LOOP_FREEZE") echo "4" ;;
        "LAUNCH_MAP_TIMEOUT") echo "11" ;;
        *BG_ERR_DISCONNECT*|*UI_ERR_277*) echo "5" ;;
        *UI_ERR_279*) echo "6" ;;
        *) echo "99" ;;
    esac
}

prepare_clone_data_paths() {
    local pkg=$1
    log_event "SYSTEM" "Khởi động tiền xử lý dữ liệu Sandbox và quét danh sách User..." "GLOBAL"

    local TARGET_PATHS=$(ls -d /data/user/*/"$pkg" 2>/dev/null)
    [ -d "/data/data/$pkg" ] && TARGET_PATHS="$TARGET_PATHS /data/data/$pkg"
    TARGET_PATHS=$(echo "$TARGET_PATHS" | tr ' ' '\n' | sort -u)

    local found_users="0"
    for u_dir in /data/user/*; do 
        [ ! -d "$u_dir" ] && continue 
        local u_id=$(basename "$u_dir") 
        case "$u_id" in 
            ''|*[!0-9]*) continue ;; 
        esac 
        if [ -d "$u_dir/$TARGET_PACKAGE" ]; then 
            found_users="$found_users $u_id" 
        fi 
    done
    DETECTED_USERS=$(echo "$found_users" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    [ -z "$TARGET_PATHS" ] && return 1

    for CURRENT_DATA_PATH in $TARGET_PATHS; do
        if [ -d "$CURRENT_DATA_PATH" ]; then
            local FOLDER_OWNER=$(stat -c "%U:%G" "$CURRENT_DATA_PATH" 2>/dev/null)
            if [ -n "$FOLDER_OWNER" ] && command -v restorecon >/dev/null 2>&1; then
                restorecon -R "$CURRENT_DATA_PATH" 2>/dev/null
            fi
        fi
    done
}

# 🎯 VÁ LỖI 2: ĐỊNH DANH USER ID CHUẨN XÁC QUA ĐƯỜNG DẪN FILE SYSTEM (BẺ GÃY CÔNG THỨC TOÁN HỌC MẶC ĐỊNH)
get_user_id_from_uid() {
    local target_uid=$1
    for u_id in $DETECTED_USERS; do
        local dir_uid=$(stat -c "%u" "/data/user/$u_id/$TARGET_PACKAGE" 2>/dev/null)
        if [ "$dir_uid" = "$target_uid" ]; then
            echo "$u_id"
            return
        fi
    done
    # Khôi phục cơ chế Fallback nếu thiết bị chạy phân vùng ảo đặc biệt không có map thư mục vật lý
    if [ "$target_uid" -ge 100000 ]; then
        echo $((target_uid / 100000))
    else
        echo "0"
    fi
}

discover_active_instances() {
    local pkg=$1
    for pid_dir in /proc/[0-9]*; do
        [ ! -d "$pid_dir" ] && continue
        local pid=$(basename "$pid_dir")
        local cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr -d '\0')
        
        case "$cmd" in
            "$pkg"|"$pkg":*)
                local num_uid=$(grep "^Uid:" "$pid_dir/status" 2>/dev/null | awk '{print $2}')
                [ -n "$num_uid" ] && echo "$pid|$num_uid"
                ;;
        esac
    done
}

get_uid_net_bytes() {
    local num_uid=$1
    if [ -f "/proc/uid_stat/$num_uid/tcp_rcv" ]; then
        local rcv=$(cat "/proc/uid_stat/$num_uid/tcp_rcv" 2>/dev/null)
        # 🎯 FIX LỖI RUNTIME: Loại bỏ dấu $ thừa trước đường dẫn /proc
        local snd=$(cat "/proc/uid_stat/$num_uid/tcp_snd" 2>/dev/null)
        echo "$((rcv + snd))"
        return
    fi
    if [ -f "/proc/net/xt_qtaguid/stats" ]; then
        local total_bytes=$(awk -v uid="$num_uid" '$4==uid {sum+=$6+$8} END {print sum}' /proc/net/xt_qtaguid/stats 2>/dev/null)
        if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ]; then
            echo "$total_bytes"
            return
        fi
    fi
    echo "-1"
}

evaluate_health_matrix() {
    local token=$1 pid=$2 is_foreground=$3 num_uid=$4
    local score=0
    local now=$(date +%s)
    
    local status_file="/proc/$pid/status"
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0
    
    local status_data=$(cat "$status_file" 2>/dev/null)
    local state=$(echo "$status_data" | grep "^State:" | awk '{print $2}')
    local rss_kb=$(echo "$status_data" | grep "^VmRSS:" | awk '{print $2}')
    local threads=$(echo "$status_data" | grep "^Threads:" | awk '{print $2}')

    [ -z "$rss_kb" ] && rss_kb=0
    [ -z "$threads" ] && threads=0

    case "$state" in
        R) score=$((score + 25)) ;;
        S) score=$((score + 20)) ;;
        D) score=$((score + 5)) ;;
        *) score=$((score + 0)) ;;
    esac

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

    if [ "$current_net" -eq -1 ]; then
        local cpu_drift=$((current_ticks - last_ticks))
        [ "$cpu_drift" -lt 0 ] && cpu_drift=$((cpu_drift * -1))
        
        local net_freeze_cnt=$(cat "$CACHE_DIR/${token}_net_freeze.cnt" 2>/dev/null)
        [ -z "$net_freeze_cnt" ] && net_freeze_cnt=0

        if [ "$cpu_drift" -le 1 ]; then
            net_freeze_cnt=$((net_freeze_cnt + 1))
        else
            net_freeze_cnt=0
        fi
        echo "$net_freeze_cnt" > "$CACHE_DIR/${token}_net_freeze.cnt"
    else
        local net_freeze_cnt=$(cat "$CACHE_DIR/${token}_net_freeze.cnt" 2>/dev/null)
        [ -z "$net_freeze_cnt" ] && net_freeze_cnt=0
        if [ "$current_net" -eq "$last_net" ]; then
            net_freeze_cnt=$((net_freeze_cnt + 1))
        else
            net_freeze_cnt=0
        fi
        echo "$current_net" > "$CACHE_DIR/${token}_net.cache"
        echo "$net_freeze_cnt" > "$CACHE_DIR/${token}_net_freeze.cnt"
    fi

    local net_freeze_cnt_final=$(cat "$CACHE_DIR/${token}_net_freeze.cnt" 2>/dev/null)
    [ -z "$net_freeze_cnt_final" ] && net_freeze_cnt_final=0
    
    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null)
    [ -z "$launch_time" ] && launch_time=$now
    
    if [ $((now - launch_time)) -gt "$LAUNCH_TIMEOUT" ]; then
        if [ "$net_freeze_cnt_final" -ge "$NET_STAGNANT_THRESHOLD" ]; then echo "0|LAUNCH_MAP_TIMEOUT" && return 0; fi
    fi

    # 🎯 VÁ LỖI 3: SIẾT CHẶT ĐIỀU KIỆN INFINITE_LOOP_FREEZE (TĂNG NGƯỠNG LÊN CHU KỲ 12 VÀ CHỈ PHẠT KHI ĐANG Ở FOREGROUND)
    if [ "$net_freeze_cnt_final" -ge 12 ]; then
        if [ "$is_foreground" = "true" ] && [ "$current_ticks" -ne "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then 
            echo "0|INFINITE_LOOP_FREEZE" && return 0
        fi
    fi

    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        if [ "$is_foreground" = "false" ] && [ "$rss_kb" -gt 102400 ] && [ "$threads" -gt 5 ]; then
            score=$((score + 30))
            echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
        else
            local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null)
            [ -z "$f_cnt" ] && f_cnt=0
            f_cnt=$((f_cnt + 1))
            echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"
            if [ "$f_cnt" -ge 10 ]; then echo "0|ZOMBIE_FROZEN_TICKS" && return 0; else score=$((score + 15)); fi
        fi
    else
        score=$((score + 30))
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi

    echo "$score|HEALTHY"
}

check_deferred_logs() {
    local pid=$1 token=$2 current_score=$3
    [ "$current_score" -ge 90 ] && return 1

    local last_log_chk=$(cat "$CACHE_DIR/${token}_log_chk.ts" 2>/dev/null)
    local now=$(date +%s)
    [ -z "$last_log_chk" ] && last_log_chk=0
    [ $((now - last_log_chk)) -lt "$LOG_CHECK_COOLDOWN" ] && return 1
    echo "$now" > "$CACHE_DIR/${token}_log_chk.ts"

    local system_logs=""
    system_logs=$(logcat -d --pid="$pid" -t 100 2>/dev/null)
    
    if [ -z "$system_logs" ]; then
        # 🎯 VÁ LỖI 4: DÙNG GREP GIỚI HẠN KHÔNG GIAN TỪ (-w) TRÁNH TRÙNG KHỚP SAI GIỮA CÁC CHUỖI PID CON
        system_logs=$(logcat -d -t 300 2>/dev/null | grep -w "$pid")
    fi

    if echo "$system_logs" | grep -qE "Connection lost|Disconnected|Timeout|Fatal|NullPointerException"; then
        echo "BG_ERR_DISCONNECT"
        return 0
    fi
    return 1
}

strict_nuke_package() {
    local pid=$1 token=$2
    if [ -d "/proc/$pid" ]; then
        log_event "NUKE" "Giai phong tien trinh: PID=$pid" "$token"
        kill "$pid" 2>/dev/null
        sleep 0.5
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_net.cache" "$CACHE_DIR/${token}_net_freeze.cnt"
}

execute_recovery_pipeline() {
    local pkg=$1 pid=$2 num_uid=$3 error_type=$4
    local now=$(date +%s)
    
    local am_user_id=$(get_user_id_from_uid "$num_uid")
    local token="${pkg}_u${am_user_id}"
    
    log_event "RECOVERY" "Khoi dong Rejoin tai User $am_user_id. Ly do: $error_type" "$token"
    
    [ "$pid" -ne 0 ] && strict_nuke_package "$pid" "$token"
    sleep 2
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    local am_cmd="am start"
    [ "$am_user_id" -ne 0 ] && am_cmd="am start --user $am_user_id"
    $am_cmd -a android.intent.action.VIEW -d "roblox://placeId=2753915549" -p "$pkg" >/dev/null 2>&1
    
    local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null)
    [ -z "$r_cnt" ] && r_cnt=0
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

update_json_dashboard() {
    local first=true
    echo "{" > "${DASHBOARD_JSON}.tmp"
    echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"," >> "${DASHBOARD_JSON}.tmp"
    echo "  \"instances\": [" >> "${DASHBOARD_JSON}.tmp"

    for f in "$STATE_DIR"/*_score.txt; do
        [ ! -f "$f" ] && continue
        local fname=$(basename "$f" _score.txt)
        local score=$(cat "$f" 2>/dev/null)
        local l_err=$(cat "$STATE_DIR/${fname}_last_err.txt" 2>/dev/null)
        local r_cnt=$(cat "$STATE_DIR/${fname}_restarts.cnt" 2>/dev/null)
        
        [ -z "$score" ] && score=0
        case "$score" in ''|*[!0-9]*) score=0 ;; esac
        [ -z "$l_err" ] && l_err="NONE"
        [ -z "$r_cnt" ] && r_cnt=0

        local escaped_err=$(printf '%s' "$l_err" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r\n')

        if [ "$first" = true ]; then first=false; else printf ",\n" >> "${DASHBOARD_JSON}.tmp"; fi
        
        # 🎯 VÁ LỖI 1: BẺ THẲNG HÀNG DELIMITER EOF ĐỨNG RIÊNG LẬP KHÔNG DÍNH DẤU NGOẶC TRÁNH LỖI PHÂN TÍCH CÚ PHÁP
        cat <<EOF >> "${DASHBOARD_JSON}.tmp"
    {
      "token": "$fname",
      "health_score": $score,
      "last_error": "$escaped_err",
      "total_restarts": $r_cnt
    }
EOF
    done
    printf "\n  ]\n}\n" >> "${DASHBOARD_JSON}.tmp"
    mv "${DASHBOARD_JSON}.tmp" "$DASHBOARD_JSON"
}

monitor_core_loop() {
    log_event "SYSTEM" "Loi V13.6 Sovereign Perfection chinh thuc nap chi thi." "GLOBAL"
    prepare_clone_data_paths "$TARGET_PACKAGE"

    while true; do
        local instances=""
        instances=$(discover_active_instances "$TARGET_PACKAGE")
        local now=$(date +%s)
        
        if [ -z "$instances" ]; then
            for u_id in $DETECTED_USERS; do
                # 🎯 VÁ LỖI 5: THIẾT LẬP BỘ ĐẾM GIỮ COOLDOWN CHO SỰ CỐ KHÔNG TÌM THẤY TIẾN TRÌNH (PROCESS_MISSING)
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_u${u_id}.ts" 2>/dev/null)
                [ -z "$last_miss_rcv" ] && last_miss_rcv=0
                
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_u${u_id}.ts"
                    log_event "SYSTEM" "Phat hien thieu thuc the tai User $u_id. Dang gui cuu ho..." "GLOBAL"
                    local synthetic_uid=$((u_id * 100000))
                    execute_recovery_pipeline "$TARGET_PACKAGE" "0" "$synthetic_uid" "PROCESS_MISSING"
                else
                    log_event "SYSTEM" "User $u_id trong trang thai trong, bo qua cuu ho do dang giu Cooldown an toan." "GLOBAL"
                fi
            done
        else
            # 🎯 VÁ LỖI 6: LOẠI BỎ TOÀN BỘ HOÀN TOÀN ĐƯỜNG ỐNG DẪN PIPE ĐỂ TRÁNH BẪY SUBSHELL TRÊN MKSH/ASH CỦA ANDROID
            while read -r instance || [ -n "$instance" ]; do
                [ -z "$instance" ] && continue
                
                local pid=$(echo "$instance" | cut -d'|' -f1)
                local num_uid=$(echo "$instance" | cut -d'|' -f2)
                
                local am_user_id=$(get_user_id_from_uid "$num_uid")
                local token="${TARGET_PACKAGE}_u${am_user_id}"
                
                local fg_app=$(dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
                if [ -z "$fg_app" ] || [ "$fg_app" = "null" ]; then
                    fg_app=$(dumpsys activity top 2>/dev/null | grep -E "TASK.*id=" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
                fi
                if [ -z "$fg_app" ] ; then
                    fg_app=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
                fi

                local is_fg="false"
                [ "$fg_app" = "$TARGET_PACKAGE" ] && is_fg="true"

                local matrix_result=$(evaluate_health_matrix "$token" "$pid" "$is_fg" "$num_uid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                if [ "$current_score" -lt 40 ] || [ "$health_status" != "HEALTHY" ]; then
                    execute_recovery_pipeline "$TARGET_PACKAGE" "$pid" "$num_uid" "$health_status"
                    continue
                fi

                local deferred_issue=$(check_deferred_logs "$pid" "$token" "$current_score")
                if [ -n "$deferred_issue" ]; then
                    echo "35" > "$STATE_DIR/${token}_score.txt"
                    execute_recovery_pipeline "$TARGET_PACKAGE" "$pid" "$num_uid" "$deferred_issue"
                    continue
                fi
            done <<EOF
$instances
EOF
        fi
        
        update_json_dashboard
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
