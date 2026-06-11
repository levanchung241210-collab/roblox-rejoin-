#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V13.7 - LIVE DASHBOARD & GRACE PERIOD)
# Tích hợp: Fix Mountinfo Android 12 | Live UI Termux | Chống Loop Khởi Động
# =================================================================

# --- CẤU HÌNH CHIẾN TRƯỜNG ---
TARGET_PACKAGE="com.roblox.client.vnggames"
CHECK_INTERVAL=15
PID_CACHE_TTL=20          
LAUNCH_TIMEOUT=420        
NET_STAGNANT_THRESHOLD=5  
PROCESS_RECOVERY_COOLDOWN=180
LOG_CHECK_COOLDOWN=120
APP_LAUNCH_GRACE_PERIOD=90 # 🎯 THỜI GIAN MIỄN NHIỄM 90 GIÂY: Chống loop kill lúc app đang load map

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="/data/local/tmp/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"
DASHBOARD_JSON="/sdcard/Download/nexus_status.json"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

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
    
    # [LOGIC MOUNTINFO - ANDROID 12 CỦA ÔNG]
    local running_pids=$(pidof "$pkg" 2>/dev/null)
    if [ -z "$running_pids" ]; then
        running_pids=$(ps -ef | grep "$pkg" | grep -v grep | awk '{print $2}')
    fi

    for pid in $running_pids; do
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        if [ -f "/proc/$pid/mountinfo" ]; then
            local DETECTED_PATH=$(cat "/proc/$pid/mountinfo" | grep -E "/data/user/|/data/data/" | grep "$pkg" | awk '{print $5}' | head -n 1)
            if [ -n "$DETECTED_PATH" ] && [ -d "$DETECTED_PATH" ]; then
                TARGET_PATHS="$TARGET_PATHS $DETECTED_PATH"
            fi
        fi
    done

    TARGET_PATHS=$(echo "$TARGET_PATHS" | tr ' ' '\n' | sort -u)

    local found_users="0"
    for u_dir in /data/user/*; do 
        [ ! -d "$u_dir" ] && continue 
        local u_id=$(basename "$u_dir") 
        case "$u_id" in ''|*[!0-9]*) continue ;; esac 
        [ -d "$u_dir/$TARGET_PACKAGE" ] && found_users="$found_users $u_id" 
    done
    DETECTED_USERS=$(echo "$found_users" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    [ -z "$TARGET_PATHS" ] && return 1

    for CURRENT_DATA_PATH in $TARGET_PATHS; do
        if [ -d "$CURRENT_DATA_PATH" ]; then
            local FOLDER_OWNER=$(stat -c "%U:%G" "$CURRENT_DATA_PATH" 2>/dev/null)
            if [ -n "$FOLDER_OWNER" ]; then
                chown -R "$FOLDER_OWNER" "$CURRENT_DATA_PATH" 2>/dev/null
                chmod -R 755 "$CURRENT_DATA_PATH" 2>/dev/null
                command -v restorecon >/dev/null 2>&1 && restorecon -R "$CURRENT_DATA_PATH" 2>/dev/null
            fi
        fi
    done
}

get_user_id_from_uid() {
    local target_uid=$1
    for u_id in $DETECTED_USERS; do
        local dir_uid=$(stat -c "%u" "/data/user/$u_id/$TARGET_PACKAGE" 2>/dev/null)
        if [ "$dir_uid" = "$target_uid" ]; then
            echo "$u_id"
            return
        fi
    done
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
    local now=$(date +%s)

    # 🎯 FIX LOOP APP CHƯA LOAD XONG: Kích hoạt thời gian miễn nhiễm
    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null)
    [ -z "$launch_time" ] && launch_time=0
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING"
            return 0
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

    if [ "$net_freeze_cnt" -ge 12 ]; then
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

    local system_logs=$(logcat -d --pid="$pid" -t 100 2>/dev/null)
    if [ -z "$system_logs" ]; then
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
    if [ -n "$pid" ] && [ "$pid" -ne 0 ] && [ -d "/proc/$pid" ]; then
        kill "$pid" 2>/dev/null
        sleep 0.5
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_net.cache" "$CACHE_DIR/${token}_net_freeze.cnt"
}

execute_recovery_pipeline() {
    local pkg=$1 pid=$2 num_uid=$3 error_type=$4
    local am_user_id=$(get_user_id_from_uid "$num_uid")
    local token="${pkg}_u${am_user_id}"
    local now=$(date +%s)
    
    strict_nuke_package "$pid" "$token"
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

# 🎯 GIAO DIỆN TERMUX THỜI GIAN THỰC
display_live_ui() {
    printf "\033c" # Lệnh Clear màn hình đa nền tảng
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;32m 🤖 NEXUS V13.7 - HỆ THỐNG GIÁM SÁT ROBLOX TRỰC TIẾP \033[0m"
    echo -e "\033[1;36m=======================================================================\033[0m"
    printf "\033[1;33m%-10s | %-7s | %-6s | %-20s | %-15s\033[0m\n" "TAB (USER)" "PID" "SCORE" "TRẠNG THÁI HIỆN TẠI" "GHI CHÚ LỖI"
    echo "-----------------------------------------------------------------------"

    for u_id in $DETECTED_USERS; do
        local token="${TARGET_PACKAGE}_u${u_id}"
        local pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "N/A")
        local score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
        local l_err=$(cat "$STATE_DIR/${token}_last_err.txt" 2>/dev/null || echo "Đang Khởi Động")
        local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")

        local color="\033[0;32m" # Xanh lá (Khỏe)
        [ "$score" -eq 0 ] && color="\033[0;31m" # Đỏ (Chết/Missing)
        [ "$score" -eq 100 ] && color="\033[1;34m" # Xanh dương (Đang Launch)
        [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && color="\033[1;33m" # Vàng (Cảnh báo)

        local status_text="Khỏe mạnh"
        [ "$score" -eq 0 ] && status_text="Đang Cứu Hộ"
        [ "$score" -eq 100 ] && status_text="Đang Vào Map (Bất Tử)"
        [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && status_text="Đang Quét Log Lỗi"

        printf "${color}%-10s | %-7s | %-6s | %-20s | %-15s\033[0m\n" "User $u_id" "$pid" "$score" "$status_text" "$l_err (Lần $r_cnt)"
    done
    
    echo -e "\033[1;36m=======================================================================\033[0m"
    echo -e "\033[1;37m⚙️  Chu kỳ quét: ${CHECK_INTERVAL}s | 🕒 Lần cập nhật cuối: $(date '+%H:%M:%S')\033[0m"
}

monitor_core_loop() {
    prepare_clone_data_paths "$TARGET_PACKAGE"

    while true; do
        local instances=""
        instances=$(discover_active_instances "$TARGET_PACKAGE")
        local now=$(date +%s)
        
        # Reset PID cache trước khi quét
        for u_id in $DETECTED_USERS; do
            echo "0" > "$STATE_DIR/${TARGET_PACKAGE}_u${u_id}_pid.txt"
        done

        if [ -n "$instances" ]; then
            while read -r instance || [ -n "$instance" ]; do
                [ -z "$instance" ] && continue
                
                local pid=$(echo "$instance" | cut -d'|' -f1)
                local num_uid=$(echo "$instance" | cut -d'|' -f2)
                local am_user_id=$(get_user_id_from_uid "$num_uid")
                local token="${TARGET_PACKAGE}_u${am_user_id}"
                
                echo "$pid" > "$STATE_DIR/${token}_pid.txt"

                local fg_app=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
                local is_fg="false"
                [ "$fg_app" = "$TARGET_PACKAGE" ] && is_fg="true"

                local matrix_result=$(evaluate_health_matrix "$token" "$pid" "$is_fg" "$num_uid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                if [ "$current_score" -lt 40 ] && [ "$current_score" -ne 0 ] || [ "$health_status" != "HEALTHY" ] && [ "$health_status" != "LAUNCHING" ]; then
                    execute_recovery_pipeline "$TARGET_PACKAGE" "$pid" "$num_uid" "$health_status"
                    continue
                fi

                local deferred_issue=$(check_deferred_logs "$pid" "$token" "$current_score")
                if [ -n "$deferred_issue" ]; then
                    echo "0" > "$STATE_DIR/${token}_score.txt"
                    execute_recovery_pipeline "$TARGET_PACKAGE" "$pid" "$num_uid" "$deferred_issue"
                    continue
                fi
            done <<EOF
$instances
EOF
        fi

        # Kiểm tra User bị thiếu (Missing)
        for u_id in $DETECTED_USERS; do
            local chk_pid=$(cat "$STATE_DIR/${TARGET_PACKAGE}_u${u_id}_pid.txt" 2>/dev/null)
            if [ -z "$chk_pid" ] || [ "$chk_pid" = "0" ]; then
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_u${u_id}.ts" 2>/dev/null)
                [ -z "$last_miss_rcv" ] && last_miss_rcv=0
                
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_u${u_id}.ts"
                    echo "0" > "$STATE_DIR/${TARGET_PACKAGE}_u${u_id}_score.txt"
                    local synthetic_uid=$((u_id * 100000))
                    execute_recovery_pipeline "$TARGET_PACKAGE" "0" "$synthetic_uid" "PROCESS_MISSING"
                fi
            fi
        done
        
        display_live_ui
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
