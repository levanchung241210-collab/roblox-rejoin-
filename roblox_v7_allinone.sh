#!/system/bin/sh
# =================================================================
# ROBLOX AUTO REJOIN V10.0 - MULTI-USER ENTERPRISE (FARM READY)
# Patched: Multi-User Process Isolator + Command User Router + Live Tail
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$INSTALL_DIR/state"
QUEUE_DIR="$INSTALL_DIR/queue"
CONFIG_FILE="$INSTALL_DIR/config.conf"
TAB_LIST_FILE="$INSTALL_DIR/tabs.list"
LOG_FILE="$INSTALL_DIR/executor.log"
DASHBOARD_HTML="/sdcard/Download/roblox_dashboard.html"
UI_DUMP="/sdcard/ui_dump.xml"
LOCK_FILE="/data/local/tmp/roblox_monitor.lock"
SEQ_FILE="$STATE_DIR/queue_sequence.seq"

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"
CHECK_INTERVAL=15
MAX_RESTARTS=10
MAX_RESTARTS_PER_HOUR=20

# ==================== INITIALIZATION & SAFE SEQUENCER ====================
mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$QUEUE_DIR" "/sdcard/Download"
[ ! -f "$SEQ_FILE" ] && echo "0" > "$SEQ_FILE"

get_next_sequence() {
    local current_time=$1
    local last_time=$(cat "$STATE_DIR/last_seq_time.ts" 2>/dev/null)
    local seq=$(cat "$SEQ_FILE" 2>/dev/null)
    [ -z "$seq" ] && seq=0
    
    if [ "$current_time" != "$last_time" ]; then
        seq=0
        echo "$current_time" > "$STATE_DIR/last_seq_time.ts"
    else
        seq=$((seq + 1))
    fi
    echo "$seq" > "$SEQ_FILE"
    printf "%05d" "$seq"
}

log_msg() {
    local level=$1 msg=$2 pkg=$3 user_id=$4
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -z "$pkg" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [${pkg}_u${user_id}] [$level] $msg" >> "$LOG_FILE"
    fi
}

# ==================== SETUP WIZARD (LIVE DISPLAY INCLUDED) ====================
setup_wizard() {
    clear
    echo "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║   ROBLOX AUTO REJOIN V10.0 - ENTERPRISE ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}\n"
    
    : > "$LOG_FILE"
    echo "${YELLOW}[KHỞI TẠO HỆ THỐNG FARM CHUYÊN NGHIỆP]${NC}"
    echo " 1) Tự động quét và nhận diện các bản ghi Roblox"
    echo " 2) Khởi tạo cấu hình trống để tự điền thủ công (Khuyên dùng)"
    echo "----------------------------------------------------------------"
    echo -n "Lựa chọn của bạn: "
    read -r setup_mode

    if [ "$setup_mode" = "1" ]; then
        echo "\n${YELLOW}[!] Đang đồng bộ hóa dữ liệu từ hệ thống...${NC}"
        local verified_intents=$(dumpsys package intents 2>/dev/null | grep -B 1 "roblox://" | grep "Package" | cut -d' ' -f5)
        local root_pm_pkgs=$(pm list packages 2>/dev/null | cut -d':' -f2 | grep -i "roblox")
        local root_data_pkgs=$(ls /data/data/ 2>/dev/null | grep -i "roblox")
        local active_roblox_pkgs=$(ps -A -o NAME 2>/dev/null | grep -i "roblox" || ps | awk '{print $9}' | grep -i "roblox")
        
        local final_detected=$(echo "$verified_intents\n$root_pm_pkgs\n$root_data_pkgs\n$active_roblox_pkgs" | grep -v '^$' | sort -u)

        if [ -n "$final_detected" ]; then
            echo "${GREEN}✓ Khảo sát phát hiện hệ thống các Package sau:${NC}"
            local i=1
            echo "$final_detected" > "$TAB_LIST_FILE.tmp"
            while read -r detected_pkg; do
                echo "  $i) $detected_pkg"
                i=$((i + 1))
            done < "$TAB_LIST_FILE.tmp"
            rm -f "$TAB_LIST_FILE.tmp"
            
            echo -n "${YELLOW}Nạp danh sách này vào giám sát? (y/n): ${NC}"
            read -r choice
            if [ "$choice" = "y" ] || [ "$choice" = "Y" ] || [ -z "$choice" ]; then
                echo "$final_detected" > "$TAB_LIST_FILE"
            fi
        else
            setup_mode="2"
        fi
    fi

    if [ "$setup_mode" = "2" ] || [ ! -f "$TAB_LIST_FILE" ]; then
        echo "com.roblox.client" > "$TAB_LIST_FILE"
        echo "\n${GREEN}✓ Đã tự động nạp package gốc cấu hình tại: ${YELLOW}$TAB_LIST_FILE${NC}"
        echo "${YELLOW}[!] Hệ thống Multi-User V10.0 sẽ tự động phân tách 4 tab từ package này.${NC}"
        echo "----------------------------------------------------------------"
        echo -n "Nhấn [ENTER] tại đây để kích hoạt Monitor hiển thị trực tiếp..."
        read -r ready_signal
    fi
    
    {
        echo "PLACE_ID=\"$PLACE_ID\""
        echo "LINK=\"$LINK\""
        echo "CHECK_INTERVAL=$CHECK_INTERVAL"
        echo "MAX_RESTARTS=$MAX_RESTARTS"
        echo "MAX_RESTARTS_PER_HOUR=$MAX_RESTARTS_PER_HOUR"
        echo "INSTALL_DIR=\"$INSTALL_DIR\""
        echo "STATE_DIR=\"$STATE_DIR\""
        echo "QUEUE_DIR=\"$QUEUE_DIR\""
        echo "TAB_LIST=\"$TAB_LIST_FILE\""
        echo "LOG_FILE=\"$LOG_FILE\""
    } > "$CONFIG_FILE"
    
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo "${GREEN}✅ SETUP V10.0 SUCCESSFUL! ĐANG KẾT NỐI MÀN HÌNH GIÁM SÁT REAL-TIME...${NC}\n"
    
    # Kích hoạt chạy ngầm cố định và tự động Stream Log ra màn hình chính Termux theo yêu cầu của bạn
    nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
    sleep 1
    tail -f "$LOG_FILE"
}

# ==================== STATE ENGINE (MULTI-USER ISOLATED) ====================
init_state() {
    local pkg=$1 user_id=$2 sf="$STATE_DIR/${pkg}_u${user_id}.state"
    [ -f "$sf" ] && return
    local now=$(date +%s)
    {
        echo "HEALTH_SCORE=100"
        echo "LAST_CHECK=$now"
        echo "LAST_ERROR=NONE"
        echo "RESTART_COUNT=0"
        echo "RESTART_DAY=$now"
        echo "RESTART_HOUR=$now"
        echo "RESTARTS_THIS_HOUR=0"
        echo "LAST_CPU_TICKS=0"
        echo "FREEZE_COUNT=0"
    } > "$sf"
}

read_state() {
    grep "^${3}=" "$STATE_DIR/${1}_u${2}.state" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local pkg=$1 user_id=$2 key=$3 value=$4 sf="$STATE_DIR/${pkg}_u${user_id}.state" tmp_sf="$sf.tmp"
    if [ -f "$sf" ]; then
        if grep -q "^${key}=" "$sf" 2>/dev/null; then
            sed "s|^${key}=.*|${key}=${value}|g" "$sf" > "$tmp_sf"
        else
            cp "$sf" "$tmp_sf" && echo "${key}=${value}" >> "$tmp_sf"
        fi
    else
        echo "${key}=${value}" > "$tmp_sf"
    fi
    mv "$tmp_sf" "$sf"
}

# ==================== MULTI-USER CORE INTERFACE ====================
get_all_users() {
    echo "0" # Mặc định luôn có user gốc
    pm list users 2>/dev/null | grep -oE "UserInfo\{[0-9]+" | cut -d'{' -f2
}

get_user_id_of_pid() {
    local pid=$1
    local user_str=$(ps -A 2>/dev/null | awk -v p="$pid" '$2==p {print $1}')
    [ -z "$user_str" ] && user_str=$(ps 2>/dev/null | awk -v p="$pid" '$1==p {print $2}')
    
    if echo "$user_str" | grep -q "^u[0-9]"; then
        echo "$user_str" | cut -d'_' -f1 | sed 's/u//'
    else
        # Fallback tối cao: Tính toán trực tiếp từ cấu trúc UID phân vùng nhân Linux
        local uid=$(stat -c "%u" "/proc/$pid" 2>/dev/null)
        if [ -n "$uid" ] && [ "$uid" -ge 100000 ]; then
            echo $((uid / 100000))
        else
            echo "0"
        fi
    fi
}

get_pid_for_package_and_user() {
    local pkg=$1 target_user=$2
    local pids=$(pidof "$pkg" 2>/dev/null)
    
    if [ -z "$pids" ]; then
        pids=$(ps -A 2>/dev/null | grep "$pkg" | awk '{print $2}')
        [ -z "$pids" ] && pids=$(ps 2>/dev/null | grep "$pkg" | awk '{print $1}')
    fi
    [ -z "$pids" ] && return
    
    # Lọc kép: Khớp chính xác cả package name và User ID sở hữu tiến trình đó
    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        local cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | awk '{print $1}')
        if [ "$cmd" = "$pkg" ] || [ -z "$cmd" ]; then
            local current_user=$(get_user_id_of_pid "$pid")
            if [ "$current_user" = "$target_user" ]; then
                echo "$pid" && return
            fi
        fi
    done
}

get_foreground_app() {
    local window_dump="$(dumpsys window windows 2>/dev/null)"
    echo "$window_dump" | grep -E "mCurrentFocus|mFocusedApp|mTopActivityComponent" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1
}

detect_ui_error() {
    local pkg=$1
    [ "$FG_APP" != "$pkg" ] && return 1
    
    if [ "$UI_DUMPED" -eq 0 ]; then
        uiautomator dump "$UI_DUMP" >/dev/null 2>&1
        UI_DUMPED=1
    fi
    [ ! -f "$UI_DUMP" ] && return 1
    
    if grep -qE "Error Code: (277|279|268|271)" "$UI_DUMP"; then
        if grep -qE "Disconnected|Reconnect|Leave|Connection" "$UI_DUMP"; then
            grep -oE "Error Code: [0-9]{3}" "$UI_DUMP" | head -1 | grep -oE "[0-9]{3}"
            return 0
        fi
    fi
    return 1
}

check_process_health() {
    local pkg=$1 user_id=$2 pid=$3 fg_app=$4
    
    local rss_kb=$(grep -i "VmRSS" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    if [ -z "$rss_kb" ] || [ "$rss_kb" -le 0 ]; then
        echo "ZOMBIE_EMPTY_STATUS_RSS" && return 0
    fi
    
    # [QUÉT ACTIVITY THEO USER] Kiểm tra kẹt cứng màn hình Splash độc lập theo từng không gian User
    if ! dumpsys activity activities 2>/dev/null | grep "User=$user_id" | grep -q "$pkg"; then
        echo "ZOMBIE_NO_ACTIVITY" && return 0
    fi
    
    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        local current_ticks=$((utime + stime))
        
        local last_ticks=$(read_state "$pkg" "$user_id" "LAST_CPU_TICKS")
        local freeze_cnt=$(read_state "$pkg" "$user_id" "FREEZE_COUNT")
        [ -z "$last_ticks" ] && last_ticks=0
        [ -z "$freeze_cnt" ] && freeze_cnt=0
        
        write_state "$pkg" "$user_id" "LAST_CPU_TICKS" "$current_ticks"
        
        if [ "$last_ticks" -gt 0 ] && [ "$current_ticks" -eq "$last_ticks" ]; then
            freeze_cnt=$((freeze_cnt + 1))
            write_state "$pkg" "$user_id" "FREEZE_COUNT" "$freeze_cnt"
            
            local max_allowed_freeze=4
            if [ "$fg_app" != "$pkg" ]; then
                max_allowed_freeze=40 
            fi
            
            if [ "$freeze_cnt" -ge "$max_allowed_freeze" ]; then
                echo "ZOMBIE_FROZEN_TICKS" && return 0
            fi
        else
            write_state "$pkg" "$user_id" "FREEZE_COUNT" "0"
        fi
    fi
    return 1
}

# ==================== PURE POSIX FIFO QUEUE (MULTI-USER) ====================
enqueue_restart() {
    local pkg=$1 user_id=$2 error=$3
    ls "$QUEUE_DIR"/*_*_${pkg}_u${user_id}.queue >/dev/null 2>&1 && return
    
    local now=$(date +%s)
    local seq=$(get_next_sequence "$now")
    local qf="$QUEUE_DIR/${now}_${seq}_${pkg}_u${user_id}.queue"
    
    {
        echo "PKG=$pkg"
        echo "USER_ID=$user_id"
        echo "ERROR=$error"
        echo "TIME=$now"
    } > "$qf.tmp"
    
    mv "$qf.tmp" "$qf"
    log_msg "QUEUE" "Enqueued recovery task for User [$user_id] via sequence [$seq]" "$pkg" "$user_id"
}

process_queue() {
    local first_queue=$(ls "$QUEUE_DIR"/*_*_*.queue 2>/dev/null | sort | head -1)
    [ -z "$first_queue" ] && return
    
    local pkg=$(grep "^PKG=" "$first_queue" | cut -d'=' -f2)
    local user_id=$(grep "^USER_ID=" "$first_queue" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$first_queue" | cut -d'=' -f2)
    
    do_restart "$pkg" "$user_id" "$error"
    local ret_code=$?
    
    if [ "$ret_code" -eq 0 ] || [ "$ret_code" -eq 2 ]; then
        rm -f "$first_queue"
    fi
}

# ==================== RESTART HANDLER (ROUTED TO SPECIFIC USER) ====================
do_restart() {
    local pkg=$1 user_id=$2 error=$3 now=$(date +%s)
    init_state "$pkg" "$user_id"
    
    local restart_day=$(read_state "$pkg" "$user_id" "RESTART_DAY")
    local restart=$(read_state "$pkg" "$user_id" "RESTART_COUNT")
    [ -z "$restart_day" ] && restart_day=$now
    [ -z "$restart" ] && restart=0
    
    if [ $((now - restart_day)) -gt 86400 ]; then
        restart_day=$now; restart=0
        write_state "$pkg" "$user_id" "RESTART_DAY" "$restart_day"
        write_state "$pkg" "$user_id" "RESTART_COUNT" "0"
    fi
    
    if [ "$restart" -ge "$MAX_RESTARTS" ]; then
        log_msg "ABORT" "24h Ceiling boundary reached ($restart/$MAX_RESTARTS)." "$pkg" "$user_id"
        return 2
    fi

    local restart_hour=$(read_state "$pkg" "$user_id" "RESTART_HOUR")
    local restarts_this_hour=$(read_state "$pkg" "$user_id" "RESTARTS_THIS_HOUR")
    [ -z "$restart_hour" ] && restart_hour=$now
    [ -z "$restarts_this_hour" ] && restarts_this_hour=0
    
    if [ $((now - restart_hour)) -gt 3600 ]; then
        restart_hour=$now; restarts_this_hour=0
        write_state "$pkg" "$user_id" "RESTART_HOUR" "$restart_hour"
        write_state "$pkg" "$user_id" "RESTARTS_THIS_HOUR" "0"
    fi
    
    if [ "$restarts_this_hour" -ge "$MAX_RESTARTS_PER_HOUR" ]; then
        log_msg "PROTECT" "Hourly quota exhausted. Postponing target." "$pkg" "$user_id"
        return 1
    fi
    
    restart=$((restart + 1))
    restarts_this_hour=$((restarts_this_hour + 1))
    
    write_state "$pkg" "$user_id" "RESTART_COUNT" "$restart"
    write_state "$pkg" "$user_id" "RESTARTS_THIS_HOUR" "$restarts_this_hour"
    write_state "$pkg" "$user_id" "LAST_ERROR" "$error"
    
    log_msg "RESTART" "Executing targeted re-launch loop -> Trigger: $error" "$pkg" "$user_id"
    
    # Điều hướng lệnh Force-stop đích danh đến User sở hữu tab lỗi
    am force-stop --user "$user_id" "$pkg" 2>/dev/null
    sleep 2
    
    write_state "$pkg" "$user_id" "LAST_CPU_TICKS" "0"
    write_state "$pkg" "$user_id" "FREEZE_COUNT" "0"
    
    # Điều hướng lệnh Khởi động đích danh đến User sở hữu tab lỗi
    am start --user "$user_id" -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    
    local verify_pid=""
    for i in 1 2 3 4 5; do
        sleep 3
        verify_pid=$(get_pid_for_package_and_user "$pkg" "$user_id")
        [ -n "$verify_pid" ] && break
    done
    
    if [ "$verify_pid" -z ]; then
        log_msg "CRITICAL" "Post-start verification dropped. Target user missing from process table." "$pkg" "$user_id"
        write_state "$pkg" "$user_id" "HEALTH_SCORE" "0"
        return 0
    fi
    
    log_msg "SUCCESS" "Active process linked and stable on core PID [$verify_pid]." "$pkg" "$user_id"
    write_state "$pkg" "$user_id" "LAST_CHECK" "$now"
    return 0
}

# ==================== MAIN AUTOMATION LOOP ====================
monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && { echo "Missing target configurations."; exit 1; }

    while true; do
        clear
        echo "===================================================="
        echo " 🎮 ROBLOX AUTO REJOIN V10.0 - MULTI-USER ENTERPRISE"
        echo "===================================================="
        echo "Time: $(date)\n"

        FG_APP=$(get_foreground_app)
        UI_DUMPED=0 
        local system_users=$(get_all_users | sort -u)

        while read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            
            for user_id in $system_users; do
                local state_file="$STATE_DIR/${pkg}_u${user_id}.state"
                local main_pid=$(get_pid_for_package_and_user "$pkg" "$user_id")
                
                # Cơ chế tự động dò tìm thông minh: Chỉ giám sát các không gian User đang bật Roblox clone
                if [ "$user_id" -gt 0 ] && [ -z "$main_pid" ] && [ ! -f "$state_file" ]; then
                    continue
                fi
                
                echo "[MONITORING] ➜ $pkg (User $user_id)"
                init_state "$pkg" "$user_id"
                
                # CHỐT 1: ĐỊNH DANH TIẾN TRÌNH THEO KHÔNG GIAN SỞ HỮU
                if [ -z "$main_pid" ]; then
                    write_state "$pkg" "$user_id" "HEALTH_SCORE" "0"
                    enqueue_restart "$pkg" "$user_id" "PROCESS_MISSING"
                    continue
                fi
                
                # CHỐT 2: KIỂM TRA SỨC KHỎE SÂU TỪNG USER SPACE ĐỘC LẬP
                local internal_issue=$(check_process_health "$pkg" "$user_id" "$main_pid" "$FG_APP")
                if [ -n "$internal_issue" ]; then
                    write_state "$pkg" "$user_id" "HEALTH_SCORE" "15"
                    enqueue_restart "$pkg" "$user_id" "$internal_issue"
                    continue
                fi
                
                # CHỐT 3: TRÍCH XUẤT LỖI GIAO DIỆN (NẾU TAB ĐÓ ĐANG NỔI TRÊN MÀN HÌNH)
                if [ "$FG_APP" = "$pkg" ]; then
                    local ui_err=$(detect_ui_error "$pkg")
                    if [ -n "$ui_err" ]; then
                        write_state "$pkg" "$user_id" "HEALTH_SCORE" "40"
                        enqueue_restart "$pkg" "$user_id" "UI_ERR_$ui_err"
                        continue
                    fi
                fi
                
                write_state "$pkg" "$user_id" "HEALTH_SCORE" "100"
                echo "  PID: $main_pid | Score: 100/100 | Status: RUNNING EXCELLENT"
                echo "----------------------------------------------------"
            done
        done < "$TAB_LIST_FILE"

        process_queue
        generate_dashboard

        sleep "$CHECK_INTERVAL"
    done
}

# ==================== DASHBOARD GENERATOR (DYNAMIC MAP) ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S') html="" active=0 dead=0
    
    for sf in "$STATE_DIR"/*_u*.state; do
        [ ! -f "$sf" ] && continue
        local filename=$(basename "$sf" .state)
        local pkg=$(echo "$filename" | cut -d'_' -f1)
        local user_id=$(echo "$filename" | cut -d'_' -f2 | sed 's/u//')
        
        local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
        local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
        local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
        
        if [ "$score" -eq 100 ]; then active=$((active + 1)); color="4ade80"; else dead=$((dead + 1)); color="f87171"; fi
        html="${html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>$pkg (User ID: $user_id)</b> | Score: $score/100 | Event: $error | Restarts: $restart</div>"
    done
    
    cat > "$DASHBOARD_HTML.tmp" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>V10.0 Enterprise</title><style>body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px}h1{color:#4ade80}.stat{display:inline-block;margin:10px;padding:10px 15px;background:#2a2a2a;border-radius:5px}</style></head><body><h1>🎮 Roblox V10.0 - Enterprise Panel</h1><p>Sync: $timestamp</p><div class="stat">Active Instances: <b style="color:#4ade80;">$active</b></div><div class="stat">Recovering Pipeline: <b style="color:#f87171;">$dead</b></div><div style="margin-top:20px;">$html</div><script>setTimeout(()=>location.reload(),10000)</script></body></html>
EOF
    mv "$DASHBOARD_HTML.tmp" "$DASHBOARD_HTML"
}

if [ "$1" = "monitor" ]; then
    if [ -f "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then exit 1; fi
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' EXIT INT TERM
fi

case "$1" in
    setup) setup_wizard ;;
    monitor) monitor_loop ;;
    *) [ ! -f "$CONFIG_FILE" ] && setup_wizard || sh "$0" monitor ;;
esac
