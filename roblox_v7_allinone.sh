cat << 'EOF' > roblox_auto_rejoin.sh
#!/system/bin/sh
# =================================================================
# ROBLOX AUTO REJOIN V12.0 - UNIVERSAL MULTI-PROFILE RADAR
# Optimized for: Cloud Phone Clones, Multi-User, VNG & Global Versions
# Shareable & Compatible with all Cloner Apps
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
    local level=$1 msg=$2 token=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -z "$token" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [$token] [$level] $msg" >> "$LOG_FILE"
    fi
}

# ==================== PHÂN TÍCH USER ID & CHẾ ĐỘ QUÉT V12.0 ====================
setup_wizard() {
    clear
    echo "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║  ROBLOX AUTO REJOIN V12.0 - RADAR FIX  ║${NC}"
    echo "${BLUE}║     HỖ TRỢ MỌI LOẠI APP CLONE / USER   ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}\n"
    
    echo "${YELLOW}[⚙️] CHỌN CHẾ ĐỘ QUÉT ĐỂ SHARE CHO BẠN BÈ:${NC}"
    echo "  1) Quét siêu sâu (Tự động bới RAM + Tìm User ID ẩn của Cloud Phone) -> Khuyên dùng"
    echo "  2) Chọn thủ công từ danh sách ứng dụng đã cài trên máy"
    echo "  3) Tự nhập tay tên Package Name (Dành cho cloner đặc biệt)"
    echo "--------------------------------------------------------"
    printf "Nhập lựa chọn của ông (1-3): "
    read mode_choice
    
    : > "$TAB_LIST_FILE"
    : > "$LOG_FILE"

    if [ "$mode_choice" = "1" ]; then
        echo "\n${YELLOW}[!] Đang quét toàn bộ phân vùng RAM và không gian Multi-User...${NC}"
        echo "${RED}⚠️ Nhớ MỞ SẴN hoặc TREO toàn bộ các bản sao Roblox lên nhé!${NC}\n"
        sleep 2
        
        # Quét và bóc tách cả tên gói lẫn User ID chạy ngầm (u0_, u10_, u11_...)
        ps -A -o USER,NAME 2>/dev/null | grep -E -i "roblox|vnggames" | while read -r user name; do
            local uid="0"
            if echo "$user" | grep -q "_"; then
                uid=$(echo "$user" | cut -d'_' -f1 | tr -d 'u')
            fi
            case "$uid" in [0-9]*) ;; *) uid="0" ;; esac
            echo "$name|$uid"
        done | sort -u > "$TAB_LIST_FILE"
        
    elif [ "$mode_choice" = "2" ]; then
        echo "\n${YELLOW}[!] Đang tải danh sách ứng dụng hệ thống...${NC}"
        local raw_apps=$(pm list packages -3 | cut -d':' -f2 | sort -u)
        if [ -z "$raw_apps" ]; then raw_apps=$(pm list packages | cut -d':' -f2 | sort -u); fi
        
        echo "--------------------------------------------------------"
        local idx=1
        echo "$raw_apps" | while read -r app; do
            echo "  $idx) $app"
            idx=$((idx + 1))
        done
        echo "--------------------------------------------------------"
        printf "Nhập số thứ tự các app muốn farm (ví dụ nếu chọn nhiều mục thì gõ cách nhau: 1 3 4): "
        read app_choices
        
        local current_idx=1
        echo "$raw_apps" | while read -r app; do
            for choice in $app_choices; do
                if [ "$current_idx" -eq "$choice" ]; then
                    echo "$app|0" >> "$TAB_LIST_FILE"
                fi
            done
            current_idx=$((current_idx + 1))
        done
    else
        echo "\n${YELLOW}[!] Nhập Package Name bằng tay (Cách nhau bằng dấu cách):${NC}"
        printf "Ví dụ (com.roblox.client com.roblox.client.vnggames): "
        read manual_pkgs
        for mpkg in $manual_pkgs; do
            echo "$mpkg|0" >> "$TAB_LIST_FILE"
        done
    fi

    # Hiển thị kết quả kiểm duyệt
    if [ -s "$TAB_LIST_FILE" ]; then
        echo "\n${GREEN}✅ ĐÃ THIẾT LẬP THÀNH CÔNG DANH SÁCH GIÁM SÁT PING BÀI:${NC}"
        local line_idx=1
        while read -r tab_entry || [ -n "$tab_entry" ]; do
            local p=$(echo "$tab_entry" | cut -d'|' -f1)
            local u=$(echo "$tab_entry" | cut -d'|' -f2)
            echo "  👉 Tab $line_idx: Gói [$p] ➜ User Không gian [$u]"
            line_idx=$((line_idx + 1))
        done < "$TAB_LIST_FILE"
    else
        echo "\n${RED}❌ Không tìm thấy hoặc nhập sai cấu hình! Nạp mặc định...${NC}"
        echo "com.roblox.client.vnggames|0" > "$TAB_LIST_FILE"
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
    
    echo "\n${GREEN}🚀 KHỞI CHẠY HỆ THỐNG GIÁM SÁT LIÊN TỤC V12.0...${NC}"
    sleep 2
    nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
    sleep 1
    tail -f "$LOG_FILE"
}

# ==================== STATE ENGINE FOR MULTI-USER ====================
init_state() {
    local token=$1 sf="$STATE_DIR/${token}.state"
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
    local token=$1 key=$2 value=$3 sf="$STATE_DIR/${token}.state" tmp_sf="$sf.tmp"
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
    local pkg=$1 uid=$2 pid=""
    if [ "$uid" -eq 0 ]; then
        pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
        [ -z "$pid" ] && pid=$(ps -A 2>/dev/null | grep "$pkg" | awk '{print $2}' | head -1)
    else
        pid=$(ps -A -o USER,PID,NAME 2>/dev/null | grep "u${uid}_" | grep "$pkg" | awk '{print $2}' | head -1)
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
    local token=$1 pid=$2 fg_app=$3 pkg=$4
    local rss_kb=$(grep -i "VmRSS" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    if [ -z "$rss_kb" ] || [ "$rss_kb" -le 0 ]; then
        echo "ZOMBIE_EMPTY_STATUS_RSS" && return 0
    fi
    
    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    if [ -n "$stat_line" ]; then
        local utime=$(echo "$stat_line" | awk '{print $14}')
        local stime=$(echo "$stat_line" | awk '{print $15}')
        local current_ticks=$((utime + stime))
        local last_ticks=$(read_state "$token" "LAST_CPU_TICKS")
        local freeze_cnt=$(read_state "$token" "FREEZE_COUNT")
        [ -z "$last_ticks" ] && last_ticks=0
        [ -z "$freeze_cnt" ] && freeze_cnt=0
        
        write_state "$token" "LAST_CPU_TICKS" "$current_ticks"
        
        if [ "$last_ticks" -gt 0 ] && [ "$current_ticks" -eq "$last_ticks" ]; then
            freeze_cnt=$((freeze_cnt + 1))
            write_state "$token" "FREEZE_COUNT" "$freeze_cnt"
            local max_allowed_freeze=4
            [ "$fg_app" != "$pkg" ] && max_allowed_freeze=40 
            if [ "$freeze_cnt" -ge "$max_allowed_freeze" ]; then
                echo "ZOMBIE_FROZEN_TICKS" && return 0
            fi
        else
            write_state "$token" "FREEZE_COUNT" "0"
        fi
    fi
    return 1
}

enqueue_restart() {
    local pkg=$1 uid=$2 error=$3 token="${pkg}_u${uid}"
    ls "$QUEUE_DIR"/*_*_"${token}".queue >/dev/null 2>&1 && return
    local now=$(date +%s)
    local seq=$(get_next_sequence "$now")
    local qf="$QUEUE_DIR/${now}_${seq}_${token}.queue"
    {
        echo "PKG=$pkg"
        echo "UID=$uid"
        echo "ERROR=$error"
        echo "TIME=$now"
    } > "$qf.tmp"
    mv "$qf.tmp" "$qf"
    log_msg "QUEUE" "Đã xếp hàng chờ xử lý lỗi [$error]" "$token"
}

process_queue() {
    local first_queue=$(ls "$QUEUE_DIR"/*_*_*.queue 2>/dev/null | sort | head -1)
    [ -z "$first_queue" ] && return
    local pkg=$(grep "^PKG=" "$first_queue" | cut -d'=' -f2)
    local uid=$(grep "^UID=" "$first_queue" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$first_queue" | cut -d'=' -f2)
    do_restart "$pkg" "$uid" "$error"
    local ret_code=$?
    [ "$ret_code" -eq 0 ] || [ "$ret_code" -eq 2 ] && rm -f "$first_queue"
}

do_restart() {
    local pkg=$1 uid=$2 error=$3 now=$(date +%s) token="${pkg}_u${uid}"
    init_state "$token"
    
    local restart_day=$(read_state "$token" "RESTART_DAY")
    local restart=$(read_state "$token" "RESTART_COUNT")
    [ -z "$restart_day" ] && restart_day=$now
    [ -z "$restart" ] && restart=0
    
    if [ $((now - restart_day)) -gt 86400 ]; then
        restart_day=$now; restart=0
        write_state "$token" "RESTART_DAY" "$restart_day"
        write_state "$token" "RESTART_COUNT" "0"
    fi
    
    if [ "$restart" -ge "$MAX_RESTARTS" ]; then
        log_msg "ABORT" "Chạm giới hạn tối đa cứu hộ 24h ($restart/$MAX_RESTARTS)." "$token"
        return 2
    fi

    local restart_hour=$(read_state "$token" "RESTART_HOUR")
    local restarts_this_hour=$(read_state "$token" "RESTARTS_THIS_HOUR")
    [ -z "$restart_hour" ] && restart_hour=$now
    [ -z "$restarts_this_hour" ] && restarts_this_hour=0
    
    if [ $((now - restart_hour)) -gt 3600 ]; then
        restart_hour=$now; restarts_this_hour=0
        write_state "$token" "RESTART_HOUR" "$restart_hour"
        write_state "$token" "RESTARTS_THIS_HOUR" "0"
    fi
    
    if [ "$restarts_this_hour" -ge "$MAX_RESTARTS_PER_HOUR" ]; then
        log_msg "PROTECT" "Tần suất lỗi quá nhanh! Chờ hạ nhiệt..." "$token"
        return 1
    fi
    
    restart=$((restart + 1))
    restarts_this_hour=$((restarts_this_hour + 1))
    
    write_state "$token" "RESTART_COUNT" "$restart"
    write_state "$token" "RESTARTS_THIS_HOUR" "$restarts_this_hour"
    write_state "$token" "LAST_ERROR" "$error"
    
    log_msg "RESTART" "Tiến hành cứu hộ tự động ➜ Lý do: $error" "$token"
    
    # Tiêu diệt chính xác theo từng Không gian (User ID) để không sập tab khác
    if [ "$uid" -eq 0 ]; then
        am force-stop "$pkg" 2>/dev/null
    else
        am force-stop --user "$uid" "$pkg" 2>/dev/null
        local target_pid=$(get_pid_for_package "$pkg" "$uid")
        [ -n "$target_pid" ] && kill -9 "$target_pid" 2>/dev/null
    fi
    sleep 2
    
    write_state "$token" "LAST_CPU_TICKS" "0"
    write_state "$token" "FREEZE_COUNT" "0"
    
    # Kích hoạt biệt lập theo User Space ID
    if [ "$uid" -eq 0 ]; then
        am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    else
        am start --user "$uid" -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    fi
    
    local verify_pid=""
    for i in 1 2 3 4 5; do
        sleep 3
        verify_pid=$(get_pid_for_package "$pkg" "$uid")
        [ -n "$verify_pid" ] && break
    done
    
    if [ "$verify_pid" -z ]; then
        log_msg "CRITICAL" "Không bắt được PID sau khi khởi chạy lại!" "$token"
        write_state "$token" "HEALTH_SCORE" "0"
        return 0
    fi
    
    log_msg "SUCCESS" "Cứu hộ thành công! Đang chạy trên PID: [$verify_pid]." "$token"
    write_state "$token" "LAST_CHECK" "$now"
    return 0
}

# ==================== MONITOR MAIN LOOP ====================
monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && { echo "Thiếu tệp cấu hình danh sách tab farm."; exit 1; }

    while true; do
        clear
        echo "=========================================================="
        echo " 🎮 ROBLOX AUTO REJOIN V12.0 - UNIVERSAL SPACE RADAR"
        echo "=========================================================="
        echo "Thời gian: $(date)\n"

        FG_APP=$(get_foreground_app)
        UI_DUMPED=0 

        while read -r tab_entry || [ -n "$tab_entry" ]; do
            [ -z "$tab_entry" ] && continue
            local pkg=$(echo "$tab_entry" | cut -d'|' -f1)
            local uid=$(echo "$tab_entry" | cut -d'|' -f2)
            [ -z "$uid" ] && uid="0"
            
            local token="${pkg}_u${uid}"
            echo "[🎯 KIỂM TRA RADAR] ➜ Gói: $pkg | Không gian: u$uid"
            
            init_state "$token"
            local main_pid=$(get_pid_for_package "$pkg" "$uid")
            
            if [ -z "$main_pid" ]; then
                write_state "$token" "HEALTH_SCORE" "0"
                enqueue_restart "$pkg" "$uid" "PROCESS_MISSING"
                continue
            fi
            
            local internal_issue=$(check_process_health "$token" "$main_pid" "$FG_APP" "$pkg")
            if [ -n "$internal_issue" ]; then
                write_state "$token" "HEALTH_SCORE" "15"
                enqueue_restart "$pkg" "$uid" "$internal_issue"
                continue
            fi
            
            if [ "$FG_APP" = "$pkg" ]; then
                local ui_err=$(detect_ui_error "$pkg")
                if [ -n "$ui_err" ]; then
                    write_state "$token" "HEALTH_SCORE" "40"
                    enqueue_restart "$pkg" "$uid" "UI_ERR_$ui_err"
                    continue
                fi
            fi
            
            write_state "$token" "HEALTH_SCORE" "100"
            echo "  ➜ PID: $main_pid | Sức khỏe: 100/100 | Trạng thái: ỔN ĐỊNH ✅"
            echo "----------------------------------------------------------"
        done < "$TAB_LIST_FILE"

        process_queue
        generate_dashboard
        sleep "$CHECK_INTERVAL"
    done
}

generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S') html="" active=0 dead=0
    for sf in "$STATE_DIR"/*.state; do
        [ ! -f "$sf" ] && continue
        local token=$(basename "$sf" .state)
        local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
        local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
        local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
        
        if [ "$score" -eq 100 ]; then active=$((active + 1)); color="4ade80"; else dead=$((dead + 1)); color="f87171"; fi
        html="${html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>Phân vùng: $token</b> | Điểm: $score/100 | Lỗi: $error | Cứu hộ: $restart lần</div>"
    done
    
    cat > "$DASHBOARD_HTML.tmp" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>V12.0 Live Dashboard</title><style>body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px}h1{color:#4ade80}.stat{display:inline-block;margin:10px;padding:10px 15px;background:#2a2a2a;border-radius:5px}</style></head><body><h1>🎮 Roblox V12.0 - Universal Panel</h1><p>Cập nhật: $timestamp</p><div class="stat">Đang farm ngon: <b style="color:#4ade80;">$active</b></div><div class="stat">Đang xử lý/Lỗi: <b style="color:#f87171;">$dead</b></div><div style="margin-top:20px;">$html</div><script>setTimeout(()=>location.reload(),10000)</script></body></html>
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
EOF
chmod +x roblox_auto_rejoin.sh
