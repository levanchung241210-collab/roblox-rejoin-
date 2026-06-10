#!/system/bin/sh
# =================================================================
# ROBLOX AUTO REJOIN V9.9 - FINAL EMPIRE UNLEASHED (FARM READY)
# Patched Verify Loop + Fallback PS Matcher + Activity Stack Monitor
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
    local level=$1 msg=$2 pkg=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -z "$pkg" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [$pkg] [$level] $msg" >> "$LOG_FILE"
    fi
}

# ==================== SETUP WIZARD (STRICT HANDSHAKE) ====================
setup_wizard() {
    clear
    echo "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║   ROBLOX AUTO REJOIN V9.9 - FINAL EMPIRE  ║${NC}"
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
        : > "$TAB_LIST_FILE"
        echo "\n${GREEN}✓ Đã tạo file danh sách trống tại: ${YELLOW}$TAB_LIST_FILE${NC}"
        echo "${YELLOW}➜ HƯỚNG DẪN THỦ CÔNG:${NC} Truy cập file bằng vi/nano hoặc chỉnh sửa bên ngoài."
        echo "Điền chính xác tên Package Name của 4 bản clone (mỗi bản 1 dòng) rồi lưu lại."
        echo "----------------------------------------------------------------"
        echo -n "Sau khi điền xong, nhấn [ENTER] tại đây để kích hoạt Monitor..."
        read -r ready_signal
    fi
    
    echo "${YELLOW}\n[2/2] Đồng bộ biến môi trường vận hành...${NC}"
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
    echo "${GREEN}✅ SETUP V9.9 SUCCESSFUL! MONITOR IS RUNNING NGHIỆM TÚC...${NC}\n"
    nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
}

# ==================== STATE ENGINE ====================
init_state() {
    local pkg=$1 sf="$STATE_DIR/${pkg}.state"
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
    grep "^${2}=" "$STATE_DIR/${1}.state" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local pkg=$1 key=$2 value=$3 sf="$STATE_DIR/${pkg}.state" tmp_sf="$sf.tmp"
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

# ==================== ADVANCED /PROC INTERFACE ====================
get_safe_pid() {
    local pkg=$1
    local pids=$(pidof "$pkg" 2>/dev/null)
    
    # [FIX BUG THỰC CHIẾN #2] Cơ chế Fallback PS cứu nguy khi pidof trên ROM Cloud bị lỗi/trả rỗng
    if [ -z "$pids" ]; then
        pids=$(ps -A 2>/dev/null | grep "$pkg" | awk '{print $2}')
        # Dự phòng cho một số dòng lệnh ps cũ hơn trên Android cổ
        [ -z "$pids" ] && pids=$(ps 2>/dev/null | grep "$pkg" | awk '{print $1}')
    fi
    [ -z "$pids" ] && return
    
    # Bộ lọc kép tìm Main Process chính xác dựa trên cmdline hoặc dung lượng RAM cao nhất
    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        local cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | awk '{print $1}')
        if [ "$cmd" = "$pkg" ]; then
            echo "$pid" && return
        fi
    done
    
    local max_rss=0 main_pid=""
    for pid in $pids; do
        [ ! -d "/proc/$pid" ] && continue
        local rss=$(grep -i "VmRSS" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
        [ -z "$rss" ] && rss=0
        if [ "$rss" -gt "$max_rss" ]; then
            max_rss=$rss
            main_pid=$pid
        fi
    done
    
    [ -n "$main_pid" ] && echo "$main_pid" || echo "$pids" | awk '{print $1}'
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
    local pkg=$1 pid=$2 fg_app=$3
    
    # Tuyến 1: Đo dung lượng bộ nhớ thực tế VmRSS từ nhân Linux
    local rss_kb=$(grep -i "VmRSS" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    if [ -z "$rss_kb" ] || [ "$rss_kb" -le 0 ]; then
        echo "ZOMBIE_EMPTY_STATUS_RSS" && return 0
    fi
    
    # [FIX BUG THỰC CHIẾN #3] Quét Activity chống kẹt cứng màn hình Splash (Splash Screen Deadlock)
    # Nếu PID tồn tại, RAM còn nhưng Activity của Package hoàn toàn bốc hơi khỏi stack hệ thống -> Chết treo
    if ! dumpsys activity activities 2>/dev/null | grep -q "$pkg"; then
        echo "ZOMBIE_NO_ACTIVITY" && return 0
    fi
    
    # Tuyến 3: CPU Ticks Watchdog + Freeze Counter Thích Ứng Môi Trường
    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        local current_ticks=$((utime + stime))
        
        local last_ticks=$(read_state "$pkg" "LAST_CPU_TICKS")
        local freeze_cnt=$(read_state "$pkg" "FREEZE_COUNT")
        [ -z "$last_ticks" ] && last_ticks=0
        [ -z "$freeze_cnt" ] && freeze_cnt=0
        
        write_state "$pkg" "LAST_CPU_TICKS" "$current_ticks"
        
        if [ "$last_ticks" -gt 0 ] && [ "$current_ticks" -eq "$last_ticks" ]; then
            freeze_cnt=$((freeze_cnt + 1))
            write_state "$pkg" "FREEZE_COUNT" "$freeze_cnt"
            
            # Điều tốc động: Tiền cảnh cho đơ 60 giây (4 chu kỳ). Hậu cảnh cho đơ hẳn 10 phút (40 chu kỳ) để loại trừ throttle.
            local max_allowed_freeze=4
            if [ "$fg_app" != "$pkg" ]; then
                max_allowed_freeze=40 
            fi
            
            if [ "$freeze_cnt" -ge "$max_allowed_freeze" ]; then
                echo "ZOMBIE_FROZEN_TICKS" && return 0
            fi
        else
            write_state "$pkg" "FREEZE_COUNT" "0"
        fi
    fi
    return 1
}

# ==================== PURE POSIX FIFO QUEUE ====================
enqueue_restart() {
    local pkg=$1 error=$2
    ls "$QUEUE_DIR"/*_*_${pkg}.queue >/dev/null 2>&1 && return
    
    local now=$(date +%s)
    local seq=$(get_next_sequence "$now")
    local qf="$QUEUE_DIR/${now}_${seq}_${pkg}.queue"
    
    {
        echo "PKG=$pkg"
        echo "ERROR=$error"
        echo "TIME=$now"
    } > "$qf.tmp"
    
    mv "$qf.tmp" "$qf"
    log_msg "QUEUE" "Enqueued recovery task via sequence [$seq]" "$pkg"
}

process_queue() {
    local first_queue=$(ls "$QUEUE_DIR"/*_*_*.queue 2>/dev/null | sort | head -1)
    [ -z "$first_queue" ] && return
    
    local pkg=$(grep "^PKG=" "$first_queue" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$first_queue" | cut -d'=' -f2)
    
    do_restart "$pkg" "$error"
    local ret_code=$?
    
    if [ "$ret_code" -eq 0 ] || [ "$ret_code" -eq 2 ]; then
        rm -f "$first_queue"
    fi
}

# ==================== RESTART HANDLER ====================
do_restart() {
    local pkg=$1 error=$2 now=$(date +%s)
    init_state "$pkg"
    
    local restart_day=$(read_state "$pkg" "RESTART_DAY")
    local restart=$(read_state "$pkg" "RESTART_COUNT")
    [ -z "$restart_day" ] && restart_day=$now
    [ -z "$restart" ] && restart=0
    
    if [ $((now - restart_day)) -gt 86400 ]; then
        restart_day=$now; restart=0
        write_state "$pkg" "RESTART_DAY" "$restart_day"
        write_state "$pkg" "RESTART_COUNT" "0"
    fi
    
    if [ "$restart" -ge "$MAX_RESTARTS" ]; then
        log_msg "ABORT" "24h Ceiling boundary reached ($restart/$MAX_RESTARTS)." "$pkg"
        return 2
    fi

    local restart_hour=$(read_state "$pkg" "RESTART_HOUR")
    local restarts_this_hour=$(read_state "$pkg" "RESTARTS_THIS_HOUR")
    [ -z "$restart_hour" ] && restart_hour=$now
    [ -z "$restarts_this_hour" ] && restarts_this_hour=0
    
    if [ $((now - restart_hour)) -gt 3600 ]; then
        restart_hour=$now; restarts_this_hour=0
        write_state "$pkg" "RESTART_HOUR" "$restart_hour"
        write_state "$pkg" "RESTARTS_THIS_HOUR" "0"
    fi
    
    if [ "$restarts_this_hour" -ge "$MAX_RESTARTS_PER_HOUR" ]; then
        log_msg "PROTECT" "Hourly quota exhausted. Postponing target." "$pkg"
        return 1
    fi
    
    restart=$((restart + 1))
    restarts_this_hour=$((restarts_this_hour + 1))
    
    write_state "$pkg" "RESTART_COUNT" "$restart"
    write_state "$pkg" "RESTARTS_THIS_HOUR" "$restarts_this_hour"
    write_state "$pkg" "LAST_ERROR" "$error"
    
    log_msg "RESTART" "Executing hard re-launch sequence -> Trigger: $error" "$pkg"
    
    am force-stop "$pkg" 2>/dev/null
    sleep 2
    
    write_state "$pkg" "LAST_CPU_TICKS" "0"
    write_state "$pkg" "FREEZE_COUNT" "0"
    
    am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    
    # [FIX BUG THỰC CHIẾN #1] Vòng lặp verify động thay thế cho lệnh sleep cố định cũ.
    # Thử quét liên tục 5 lần, mỗi lần cách nhau 3 giây (Tổng thời gian bọc lót tối đa lên tới 15 giây).
    # Chấp nhận mọi độ trễ khởi động bạo lực nhất từ tài nguyên Cloud Phone bị bóp nghẹt.
    local verify_pid=""
    for i in 1 2 3 4 5; do
        sleep 3
        verify_pid=$(get_safe_pid "$pkg")
        [ -n "$verify_pid" ] && break
    done
    
    if [ "$verify_pid" -z ]; then
        log_msg "CRITICAL" "Post-start verification dropped. Target missing from process table." "$pkg"
        write_state "$pkg" "HEALTH_SCORE" "0"
        return 0
    fi
    
    log_msg "SUCCESS" "Active process linked and stable on core PID [$verify_pid]." "$pkg"
    write_state "$pkg" "LAST_CHECK" "$now"
    return 0
}

# ==================== MAIN PURE NATIVE LOOP ====================
monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && { echo "Missing target configurations."; exit 1; }

    while true; do
        clear
        echo "===================================================="
        echo " 🎮 ROBLOX AUTO REJOIN V9.9 - FINAL EMPIRE UNLEASHED"
        echo "===================================================="
        echo "Time: $(date)\n"

        FG_APP=$(get_foreground_app)
        UI_DUMPED=0 

        while read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            echo "[MONITORING] ➜ $pkg"
            init_state "$pkg"
            
            # CHỐT 1: ĐỊNH DANH TIẾN TRÌNH GỐC LÕI (CÓ FALLBACK PS BỌC LÓT)
            local main_pid=$(get_safe_pid "$pkg")
            if [ -z "$main_pid" ]; then
                write_state "$pkg" "HEALTH_SCORE" "0"
                enqueue_restart "$pkg" "PROCESS_MISSING"
                continue
            fi
            
            # CHỐT 2: KIỂM TRA SỨC KHỎE SÂU (Bao gồm VmRSS + Activity Stack + CPU Ticks Động)
            local internal_issue=$(check_process_health "$pkg" "$main_pid" "$FG_APP")
            if [ -n "$internal_issue" ]; then
                write_state "$pkg" "HEALTH_SCORE" "15"
                enqueue_restart "$pkg" "$internal_issue"
                continue
            fi
            
            # CHỐT 3: TRÍCH XUẤT LỖI GIAO DIỆN (DÀNH CHO TIỀN CẢNH)
            if [ "$FG_APP" = "$pkg" ]; then
                local ui_err=$(detect_ui_error "$pkg")
                if [ -n "$ui_err" ]; then
                    write_state "$pkg" "HEALTH_SCORE" "40"
                    enqueue_restart "$pkg" "UI_ERR_$ui_err"
                    continue
                fi
            fi
            
            write_state "$pkg" "HEALTH_SCORE" "100"
            echo "  PID: $main_pid | Score: 100/100 | Status: METRIC EXCELLENT"
            echo "----------------------------------------------------"
        done < "$TAB_LIST_FILE"

        process_queue
        generate_dashboard

        sleep "$CHECK_INTERVAL"
    done
}

# ==================== DASHBOARD GENERATOR ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S') html="" active=0 dead=0
    while read -r pkg || [ -n "$pkg" ]; do
        [ -z "$pkg" ] && continue
        local sf="$STATE_DIR/${pkg}.state"
        [ ! -f "$sf" ] && continue
        
        local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
        local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
        local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
        
        if [ "$score" -eq 100 ]; then active=$((active + 1)); color="4ade80"; else dead=$((dead + 1)); color="f87171"; fi
        html="${html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>$pkg</b> | Score: $score/100 | Event: $error | Restarts: $restart</div>"
    done < "$TAB_LIST_FILE"
    
    cat > "$DASHBOARD_HTML.tmp" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Final Empire</title><style>body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px}h1{color:#4ade80}.stat{display:inline-block;margin:10px;padding:10px 15px;background:#2a2a2a;border-radius:5px}</style></head><body><h1>🎮 Roblox V9.9 - Final Empire Panel</h1><p>Sync: $timestamp</p><div class="stat">Active Core: <b style="color:#4ade80;">$active</b></div><div class="stat">Recovering Pipeline: <b style="color:#f87171;">$dead</b></div><div style="margin-top:20px;">$html</div><script>setTimeout(()=>location.reload(),10000)</script></body></html>
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
