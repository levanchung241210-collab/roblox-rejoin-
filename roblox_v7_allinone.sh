#!/system/bin/sh
# =================================================================
# ROBLOX AUTO REJOIN V11.0 - LIVE RAM PROCESS ISOLATOR
# Patched: Dynamic Tab Scanner + Live RAM Extraction + Auto Connect Termux
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

# ==================== CƠ CHẾ QUÉT TAB TRỰC TIẾP TỪ RAM ====================
setup_wizard() {
    clear
    echo "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║   ROBLOX AUTO REJOIN V11.0 - RAM SCAN   ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}\n"
    
    : > "$LOG_FILE"
    echo "${YELLOW}[!] ĐANG QUÉT ĐỊA CHỈ CÁC TAB ĐANG TREO TRONG RAM...${NC}"
    echo "${RED}⚠️ LƯU Ý: Hãy chắc chắn ông ĐANG MỞ hoặc TREO tất cả các bản clone trước khi bấm!${NC}\n"
    sleep 1

    # Bắt bài địa chỉ ẩn từ Tiến trình RAM (ps) và Trình quản lý Activity Stack độc lập
    local ram_pkgs=$(ps -A -o NAME 2>/dev/null | grep -i "roblox")
    local old_ps_pkgs=$(ps 2>/dev/null | awk '{print $9}' | grep -i "roblox")
    local activity_pkgs=$(dumpsys activity activities 2>/dev/null | grep -oE "com\.[a-zA-Z0-9._]+" | grep -i "roblox")
    
    # Gộp tất cả địa chỉ tìm được và lọc trùng lặp
    local final_detected=$(echo "$ram_pkgs\n$old_ps_pkgs\n$activity_pkgs" | grep -v '^$' | sort -u)

    if [ -n "$final_detected" ]; then
        echo "${GREEN}✅ ĐÃ TÌM THẤY ĐỊA CHỈ ẨN CỦA CÁC TAB ĐANG TREO:${NC}"
        local i=1
        echo "$final_detected" > "$TAB_LIST_FILE"
        while read -r detected_pkg; do
            echo "  👉 Tab $i: $detected_pkg"
            i=$((i + 1))
        done < "$TAB_LIST_FILE"
        echo "----------------------------------------------------------------"
    else
        echo "${RED}❌ Không tìm thấy tab Roblox nào đang chạy trong RAM!${NC}"
        echo "${YELLOW}[!] Tự động nạp cấu hình mặc định (com.roblox.client)...${NC}"
        echo "com.roblox.client" > "$TAB_LIST_FILE"
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
    
    echo "\n${GREEN}✅ CẤU HÌNH HOÀN TẤT! ĐANG STREAM MÀN HÌNH GIÁM SÁT REAL-TIME...${NC}"
    echo "${YELLOW}(Xem mệt rồi thì bấm Ctrl + C để thoát xem, tool vẫn chạy ngầm 24/7)${NC}\n"
    sleep 2
    
    # Kích hoạt chạy ngầm và tự động lôi màn hình giám sát lên Termux luôn theo ý ông
    nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
    sleep 1
    tail -f "$LOG_FILE"
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

get_pid_for_package() {
    local pkg=$1
    local pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
    if [ -z "$pid" ]; then
        pid=$(ps -A 2>/dev/null | grep "$pkg" | awk '{print $2}' | head -1)
        [ -z "$pid" ] && pid=$(ps 2>/dev/null | grep "$pkg" | awk '{print $1}' | head -1)
    fi
    echo "$pid"
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
    local rss_kb=$(grep -i "VmRSS" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    if [ -z "$rss_kb" ] || [ "$rss_kb" -le 0 ]; then
        echo "ZOMBIE_EMPTY_STATUS_RSS" && return 0
    fi
    
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
            local max_allowed_freeze=4
            [ "$fg_app" != "$pkg" ] && max_allowed_freeze=40 
            if [ "$freeze_cnt" -ge "$max_allowed_freeze" ]; then
                echo "ZOMBIE_FROZEN_TICKS" && return 0
            fi
        else
            write_state "$pkg" "FREEZE_COUNT" "0"
        fi
    fi
    return 1
}

# ==================== QUEUE ENGINE ====================
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
    log_msg "QUEUE" "Đã đưa vào hàng đợi xử lý lỗi [$error]" "$pkg"
}

process_queue() {
    local first_queue=$(ls "$QUEUE_DIR"/*_*_*.queue 2>/dev/null | sort | head -1)
    [ -z "$first_queue" ] && return
    local pkg=$(grep "^PKG=" "$first_queue" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$first_queue" | cut -d'=' -f2)
    do_restart "$pkg" "$error"
    local ret_code=$?
    [ "$ret_code" -eq 0 ] || [ "$ret_code" -eq 2 ] && rm -f "$first_queue"
}

# ==================== KHỞI ĐỘNG ĐÍCH DANH CHO CLONE APP ====================
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
        log_msg "ABORT" "Chạm giới hạn restart 24h ($restart/$MAX_RESTARTS)." "$pkg"
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
        log_msg "PROTECT" "Quá giới hạn restart trong 1 giờ. Đang chờ hạ nhiệt..." "$pkg"
        return 1
    fi
    
    restart=$((restart + 1))
    restarts_this_hour=$((restarts_this_hour + 1))
    
    write_state "$pkg" "RESTART_COUNT" "$restart"
    write_state "$pkg" "RESTARTS_THIS_HOUR" "$restarts_this_hour"
    write_state "$pkg" "LAST_ERROR" "$error"
    
    log_msg "RESTART" "Đang khởi động lại tab -> Nguyên nhân: $error" "$pkg"
    
    # Diệt và kích hoạt chính xác địa chỉ app clone
    am force-stop "$pkg" 2>/dev/null
    sleep 2
    
    write_state "$pkg" "LAST_CPU_TICKS" "0"
    write_state "$pkg" "FREEZE_COUNT" "0"
    
    am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    
    local verify_pid=""
    for i in 1 2 3 4 5; do
        sleep 3
        verify_pid=$(get_pid_for_package "$pkg")
        [ -n "$verify_pid" ] && break
    done
    
    if [ "$verify_pid" -z ]; then
        log_msg "CRITICAL" "Không tìm thấy PID sau khi restart!" "$pkg"
        write_state "$pkg" "HEALTH_SCORE" "0"
        return 0
    fi
    
    log_msg "SUCCESS" "Khởi động tab thành công trên PID mới [$verify_pid]." "$pkg"
    write_state "$pkg" "LAST_CHECK" "$now"
    return 0
}

# ==================== MONITOR MAIN LOOP ====================
monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && { echo "Thiếu file cấu hình danh sách tab."; exit 1; }

    while true; do
        clear
        echo "===================================================="
        echo " 🎮 ROBLOX AUTO REJOIN V11.0 - RAM PROCESS ISOLATOR"
        echo "===================================================="
        echo "Thời gian: $(date)\n"

        FG_APP=$(get_foreground_app)
        UI_DUMPED=0 

        while read -r pkg || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            
            echo "[QUÉT RAM] ➜ $pkg"
            init_state "$pkg"
            local main_pid=$(get_pid_for_package "$pkg")
            
            # CHỐT 1: KIỂM TRA SỐNG CHẾT TIẾN TRÌNH
            if [ -z "$main_pid" ]; then
                write_state "$pkg" "HEALTH_SCORE" "0"
                enqueue_restart "$pkg" "PROCESS_MISSING"
                continue
            fi
            
            # CHỐT 2: ĐO ĐỘ ĐÔNG CỨNG CPU CỦA TAB CLONE
            local internal_issue=$(check_process_health "$pkg" "$main_pid" "$FG_APP")
            if [ -n "$internal_issue" ]; then
                write_state "$pkg" "HEALTH_SCORE" "15"
                enqueue_restart "$pkg" "$internal_issue"
                continue
            fi
            
            # CHỐT 3: QUÉT LỖI MÀN HÌNH (NẾU THẰNG CLONE ĐÓ ĐANG HIỂN THỊ CHÍNH)
            if [ "$FG_APP" = "$pkg" ]; then
                local ui_err=$(detect_ui_error "$pkg")
                if [ -n "$ui_err" ]; then
                    write_state "$pkg" "HEALTH_SCORE" "40"
                    enqueue_restart "$pkg" "UI_ERR_$ui_err"
                    continue
                fi
            fi
            
            write_state "$pkg" "HEALTH_SCORE" "100"
            echo "  PID: $main_pid | Sức khỏe: 100/100 | Trạng thái: HOẠT ĐỘNG TỐT"
            echo "----------------------------------------------------"
        done < "$TAB_LIST_FILE"

        process_queue
        generate_dashboard
        sleep "$CHECK_INTERVAL"
    done
}

# ==================== GENERATE DASHBOARD HTML ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S') html="" active=0 dead=0
    for sf in "$STATE_DIR"/*.state; do
        [ ! -f "$sf" ] && continue
        local pkg=$(basename "$sf" .state)
        local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
        local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
        local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
        
        if [ "$score" -eq 100 ]; then active=$((active + 1)); color="4ade80"; else dead=$((dead + 1)); color="f87171"; fi
        html="${html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>Gói: $pkg</b> | Điểm số: $score/100 | Lỗi gần nhất: $error | Số lần restart: $restart</div>"
    done
    
    cat > "$DASHBOARD_HTML.tmp" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>V11.0 Live Dashboard</title><style>body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px}h1{color:#4ade80}.stat{display:inline-block;margin:10px;padding:10px 15px;background:#2a2a2a;border-radius:5px}</style></head><body><h1>🎮 Roblox V11.0 - RAM Live Panel</h1><p>Cập nhật: $timestamp</p><div class="stat">Tab đang chạy: <b style="color:#4ade80;">$active</b></div><div class="stat">Tab đang lỗi/cứu hộ: <b style="color:#f87171;">$dead</b></div><div style="margin-top:20px;">$html</div><script>setTimeout(()=>location.reload(),10000)</script></body></html>
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
