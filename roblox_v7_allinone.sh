#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V12.9 - NEXUS ULTIMATE)
# Kiến trúc: Đa luồng V12.7 + Ma trận V12.8 + Mạng UID Android + Trùng tu Đa User
# =================================================================

# --- THÔNG SỐ ĐIỀU CHỈNH CHIẾN TRƯỜNG ---
TARGET_PACKAGE="com.roblox.client.vnggames"
CHECK_INTERVAL=20
PID_CACHE_TTL=20          # 🎯 FIX BUG 4: Hạ xuống 20s để phát hiện crash tức thì
LAUNCH_TIMEOUT=420        # 🎯 FIX BUG 3: Tăng lên 7 phút thích ứng thời gian nạp map dài
NET_STAGNANT_THRESHOLD=3
LOG_CHECK_COOLDOWN=120

# --- HỆ THỐNG ĐƯỜNG DẪN ---
BASE_DIR="$HOME/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"
LOG_FILE="$BASE_DIR/nexus_monitor.log"
DASHBOARD_JSON="/sdcard/Download/nexus_status.json"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

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

# Động cơ lấy UID số nguyên của Android phục vụ giám sát mạng phân tách
get_numeric_uid_by_pid() {
    local pid=$1
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        ps -An 2>/dev/null | awk -v p="$pid" '$2 == p {print $1}'
    fi
}

get_cached_pid() {
    local pkg=$1 uid=$2 token="${pkg}_u${uid}"
    local cache_file="$CACHE_DIR/${token}.pid"
    local ts_file="$CACHE_DIR/${token}.ts"
    local now=$(date +%s)
    
    if [ -f "$cache_file" ] && [ -f "$ts_file" ]; then
        local last_cached=$(cat "$ts_file" 2>/dev/null)
        [ -z "$last_cached" ] && last_cached=0
        if [ $((now - last_cached)) -lt "$PID_CACHE_TTL" ]; then
            local pid=$(cat "$cache_file" 2>/dev/null)
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                echo "$pid"
                return 0
            fi
        fi
    fi

    local raw_pids="" main_pid="" max_rss=0
    # Động cơ V12.7 quay trở lại: Bắt chặt chẽ tiền tố user
    raw_pids=$(ps -A 2>/dev/null | grep -E "u${uid}_" | grep "$pkg" | awk '{print $2}')
    [ -z "$raw_pids" ] && [ "$uid" -eq 0 ] && raw_pids=$(pidof "$pkg" 2>/dev/null)

    for p in $raw_pids; do
        [ ! -d "/proc/$p" ] && continue
        local cmd=$(cat "/proc/$p/cmdline" 2>/dev/null | tr -d '\0')
        case "$cmd" in
            "$pkg"|"$pkg":*)
                local rss=$(grep -i "VmRSS" "/proc/$p/status" 2>/dev/null | awk '{print $2}')
                [ -z "$rss" ] && rss=0
                if [ "$rss" -gt "$max_rss" ]; then
                    max_rss=$rss
                    main_pid=$p
                fi
                ;;
        esac
    done

    if [ -n "$main_pid" ]; then
        echo "$main_pid" > "$cache_file"
        echo "$now" > "$ts_file"
        echo "$main_pid"
    fi
}

# 🎯 FIX BUG 1: GIÁM SÁT LƯU LƯỢNG MẠNG THEO INTERNET TRAFFIC UID CHUẨN ANDROID
get_uid_net_bytes() {
    local pid=$1
    local num_uid=$(get_numeric_uid_by_pid "$pid")
    
    if [ -n "$num_uid" ] && [ -f "/proc/uid_stat/$num_uid/tcp_rcv" ]; then
        local rcv=$(cat "/proc/uid_stat/$num_uid/tcp_rcv" 2>/dev/null)
        local snd=$(cat "/proc/uid_stat/$num_uid/tcp_snd" 2>/dev/null)
        [ -z "$rcv" ] && rcv=0
        [ -z "$snd" ] && snd=0
        echo "$((rcv + snd))"
    else
        echo "0"
    fi
}

evaluate_health_matrix() {
    local token=$1 pid=$2 is_foreground=$3 pkg=$4
    local score=0
    local status_file="/proc/$pid/status"
    local now=$(date +%s)
    
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0
    
    # 1. Khảo sát Trạng thái (Max: 25 điểm)
    local state=$(grep -i "State:" "$status_file" 2>/dev/null | awk '{print $2}')
    case "$state" in
        R) score=$((score + 25)) ;;
        S) score=$((score + 20)) ;;
        D) score=$((score + 5)) ;;
        *) score=$((score + 0)) ;;
    esac

    # 2. Khảo sát Bộ nhớ RAM VmRSS (Max: 25 điểm)
    local rss_kb=$(grep -i "VmRSS" "$status_file" 2>/dev/null | awk '{print $2}')
    [ -z "$rss_kb" ] && rss_kb=0
    if [ "$rss_kb" -gt 102400 ]; then
        score=$((score + 25))
    else
        score=$((score + 10))
    fi

    # 3. Khảo sát Tiểu luồng Threads (Max: 20 điểm)
    local threads=$(grep -i "Threads:" "$status_file" 2>/dev/null | awk '{print $2}')
    [ -z "$threads" ] && threads=0
    if [ "$threads" -gt 5 ]; then
        score=$((score + 20))
    else
        score=$((score + 5))
    fi

    # 4. Đo lường Xung nhịp CPU Ticks
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

    # 5. Khảo sát Mạng chuẩn UID Android
    local current_net=$(get_uid_net_bytes "$pid")
    local last_net=$(cat "$CACHE_DIR/${token}_net.cache" 2>/dev/null)
    [ -z "$last_net" ] && last_net=0
    echo "$current_net" > "$CACHE_DIR/${token}_net.cache"

    local net_freeze_cnt=$(cat "$CACHE_DIR/${token}_net_freeze.cnt" 2>/dev/null)
    [ -z "$net_freeze_cnt" ] && net_freeze_cnt=0

    # Nếu data thu nhận không tăng sau các chu kỳ -> Tích lũy điểm đơ mạng
    if [ "$current_net" -eq "$last_net" ] && [ "$current_net" -gt 0 ]; then
        net_freeze_cnt=$((net_freeze_cnt + 1))
    else
        net_freeze_cnt=0
    fi
    echo "$net_freeze_cnt" > "$CACHE_DIR/${token}_net_freeze.cnt"

    # KIỂM TRA LỚP BẢO VỆ I: LAUNCH MAP TIMEOUT (7 PHÚT)
    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null)
    [ -z "$launch_time" ] && launch_time=$now
    if [ $((now - launch_time)) -gt "$LAUNCH_TIMEOUT" ]; then
        if [ "$net_freeze_cnt" -ge "$NET_STAGNANT_THRESHOLD" ]; then
            echo "0|LAUNCH_MAP_TIMEOUT" && return 0
        fi
    fi

    # KIỂM TRA LỚP BẢO VỆ II: INFINITE LOOP FREEZE (CPU ĐIÊN CUỒNG NHƯNG MẠNG TỊT)
    if [ "$net_freeze_cnt" -ge "$NET_STAGNANT_THRESHOLD" ]; then
        if [ "$current_ticks" -ne "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
            echo "0|INFINITE_LOOP_FREEZE" && return 0
        fi
    fi

    # Phòng ngừa đóng băng Tab ngầm hợp lệ của Android OS
    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        if [ "$is_foreground" = "false" ] && [ "$rss_kb" -gt 102400 ] && [ "$threads" -gt 5 ]; then
            score=$((score + 30))
            echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
        else
            local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null)
            [ -z "$f_cnt" ] && f_cnt=0
            f_cnt=$((f_cnt + 1))
            echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"
            
            if [ "$f_cnt" -ge 10 ]; then
                echo "0|ZOMBIE_FROZEN_TICKS" && return 0
            else
                score=$((score + 15))
            fi
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
    if echo "$system_logs" | grep -qE "Connection lost|Disconnected|Timeout|Fatal|NullPointerException"; then
        echo "BG_ERR_DISCONNECT"
        return 0
    fi
    return 1
}

# 🎯 FIX BUG 2: TRUY QUÉT ĐA USER/CLONE APP CHẶT CHẼ THEO ĐỘNG CƠ V12.7
strict_nuke_package() {
    local pkg=$1 uid=$2
    # Quét toàn diện theo User prefix cấp phát của Android kết hợp kiểm tra cmdline đích danh
    local target_pids=$(ps -A 2>/dev/null | grep -E "u${uid}_" | grep "$pkg" | awk '{print $2}')
    
    if [ -z "$target_pids" ] && [ "$uid" -eq 0 ]; then
        target_pids=$(pidof "$pkg" 2>/dev/null)
    fi

    for p in $target_pids; do
        [ ! -d "/proc/$p" ] && continue
        local cmd=$(cat "/proc/$p/cmdline" 2>/dev/null | tr -d '\0')
        case "$cmd" in
            "$pkg"|"$pkg":*)
                log_event "NUKE" "Giải phóng triệt để tiến trình Clone: PID=$p ($cmd)" "${pkg}_u${uid}"
                kill "$p" 2>/dev/null
                sleep 0.5
                kill -9 "$p" 2>/dev/null
                ;;
        esac
    done
    
    rm -f "$CACHE_DIR/${pkg}_u${uid}_ticks.cache"
    rm -f "$CACHE_DIR/${pkg}_u${uid}_net.cache"
    rm -f "$CACHE_DIR/${pkg}_u${uid}_net_freeze.cnt"
}

execute_recovery_pipeline() {
    local pkg=$1 uid=$2 error_type=$3 token="${pkg}_u${uid}"
    local now=$(date +%s)
    local note_id=$(get_error_note_id "$error_type")
    
    log_event "RECOVERY" "Kích hoạt Rejoin tối thượng. Lý do: $error_type (Note ID: $note_id)" "$token"
    
    strict_nuke_package "$pkg" "$uid"
    sleep 2
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    # Động cơ định tuyến mở app đa user đa luồng của V12.7
    local am_cmd="am start"
    [ "$uid" -ne 0 ] && am_cmd="am start --user $uid"
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

    for f in "$CACHE_DIR"/*.pid; do
        [ ! -f "$f" ] && continue
        local fname=$(basename "$f" .pid)
        local c_pid=$(cat "$f" 2>/dev/null)
        local score=$(cat "$STATE_DIR/${fname}_score.txt" 2>/dev/null)
        local l_err=$(cat "$STATE_DIR/${fname}_last_err.txt" 2>/dev/null)
        local r_cnt=$(cat "$STATE_DIR/${fname}_restarts.cnt" 2>/dev/null)
        
        [ -z "$score" ] && score=0
        case "$score" in ''|*[!0-9]*) score=0 ;; esac
        [ -z "$l_err" ] && l_err="NONE"
        [ -z "$r_cnt" ] && r_cnt=0

        if [ "$first" = true ]; then first=false; else echo "," >> "${DASHBOARD_JSON}.tmp"; fi
        cat << EOF >> "${DASHBOARD_JSON}.tmp"
    {
      "token": "$fname",
      "pid": "$c_pid",
      "health_score": $score,
      "last_error": "$l_err",
      "total_restarts": $r_cnt
    }EOF
    done
    echo "\n  ]" >> "${DASHBOARD_JSON}.tmp"
    echo "}" >> "${DASHBOARD_JSON}.tmp"
    mv "${DASHBOARD_JSON}.tmp" "$DASHBOARD_JSON"
}

monitor_core_loop() {
    log_event "SYSTEM" "Lõi Nexus Ultimate V12.9 đã nạp cấu trúc lai thành công." "GLOBAL"
    
    while true; do
        # 🎯 ĐỘNG CƠ HỖ TRỢ ĐA USER - DANH SÁCH DUYỆT TỰ ĐỘNG
        # Thêm cấu hình vào đây theo dạng: "Package|User_ID" (Ví dụ: user chính = 0, song song = 10, Island = 999)
        printf "%s\n" "${TARGET_PACKAGE}|0" "${TARGET_PACKAGE}|10" | while read -r entry || [ -n "$entry" ]; do
            [ -z "$entry" ] && continue
            local pkg=$(echo "$entry" | cut -d'|' -f1)
            local uid=$(echo "$entry" | cut -d'|' -f2)
            local token="${pkg}_u${uid}"
            
            local fg_app=$(dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
            local is_fg="false"
            [ "$fg_app" = "$pkg" ] && is_fg="true"

            local pid=$(get_cached_pid "$pkg" "$uid")
            if [ -z "$pid" ]; then
                echo "0" > "$STATE_DIR/${token}_score.txt"
                echo "PROCESS_MISSING" > "$STATE_DIR/${token}_last_err.txt"
                execute_recovery_pipeline "$pkg" "$uid" "PROCESS_MISSING"
                continue
            fi

            local matrix_result=$(evaluate_health_matrix "$token" "$pid" "$is_fg" "$pkg")
            local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
            local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
            
            echo "$current_score" > "$STATE_DIR/${token}_score.txt"

            if [ "$current_score" -lt 40 ] || [ "$health_status" != "HEALTHY" ]; then
                execute_recovery_pipeline "$pkg" "$uid" "$health_status"
                continue
            fi

            local deferred_issue=$(check_deferred_logs "$pid" "$token" "$current_score")
            if [ -n "$deferred_issue" ]; then
                echo "35" > "$STATE_DIR/${token}_score.txt"
                echo "$deferred_issue" > "$STATE_DIR/${token}_last_err.txt"
                execute_recovery_pipeline "$pkg" "$uid" "$deferred_issue"
                continue
            fi
        done
        
        update_json_dashboard
        sleep "$CHECK_INTERVAL"
    done
}

monitor_core_loop
