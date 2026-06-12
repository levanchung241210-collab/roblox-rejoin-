#!/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V13.4 - ANDROID 10-12 FINAL
# POSIX-only | No local | No GNU-isms
# Production 24/7 Ready
# ===============================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$INSTALL_DIR/state"
QUEUE_DIR="$INSTALL_DIR/queue"
CACHE_DIR="$INSTALL_DIR/cache"
LOCK_DIR="$INSTALL_DIR/locks"
CONFIG_FILE="$INSTALL_DIR/config.conf"
TAB_LIST_FILE="$INSTALL_DIR/tabs.list"
LOG_FILE="$INSTALL_DIR/executor.log"
MONITOR_PID_FILE="$INSTALL_DIR/monitor.pid"
WATCHDOG_PID_FILE="$INSTALL_DIR/watchdog.pid"
UI_DUMP="/sdcard/ui_dump.xml"

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"
CHECK_INTERVAL=20
MAX_RESTARTS=10
PROCESS_RECOVERY_COOLDOWN=180
PROCESS_MISSING_THRESHOLD=3
NET_STAGNANT_THRESHOLD=5
LAUNCH_TIMEOUT=420
UIAUTOMATOR_CHECK_THRESHOLD=70
LOG_MAX_SIZE=$((10 * 1024 * 1024))
QUEUE_PROCESSING_TIMEOUT=300
RAM_WARN_THRESHOLD=300000
RESTART_BACKOFF_MAX=3600

# ==================== LOGGING ====================
log_msg() {
    level=$1
    msg=$2
    pkg=$3
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -z "$pkg" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [$pkg] [$level] $msg" >> "$LOG_FILE"
    fi
    
    check_log_rotation
}

check_log_rotation() {
    [ ! -f "$LOG_FILE" ] && return
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$size" -gt "$LOG_MAX_SIZE" ] && rotate_logs
}

rotate_logs() {
    timestamp=$(date +%s)
    mv "$LOG_FILE" "$LOG_FILE.${timestamp}"
    : > "$LOG_FILE"
    find "$INSTALL_DIR" -name "executor.log.*" -type f 2>/dev/null | sort -r | tail -n +4 | while read f; do
        rm -f "$f"
    done
}

# ==================== ATOMIC LOCK - PER-PACKAGE ====================
acquire_lock() {
    pkg=$1
    lockdir="$LOCK_DIR/${pkg}.lock"
    retry=0
    
    while ! mkdir "$lockdir" 2>/dev/null; do
        retry=$((retry + 1))
        [ "$retry" -gt 50 ] && return 1
        sleep 1
    done
    
    return 0
}

release_lock() {
    pkg=$1
    lockdir="$LOCK_DIR/${pkg}.lock"
    rmdir "$lockdir" 2>/dev/null || true
}

# ==================== ATOMIC STATE WRITE ====================
write_state_atomic() {
    pkg=$1
    instance=$2
    key=$3
    value=$4
    
    state_key="${pkg}_${instance}"
    sf="$STATE_DIR/${state_key}.state"
    temp_sf="${sf}.tmp$$"
    
    if [ ! -f "$sf" ]; then
        echo "${key}=${value}" > "$temp_sf"
    else
        if grep -q "^${key}=" "$sf" 2>/dev/null; then
            sed "s|^${key}=.*|${key}=${value}|g" "$sf" > "$temp_sf"
        else
            cat "$sf" > "$temp_sf"
            echo "${key}=${value}" >> "$temp_sf"
        fi
    fi
    
    mv "$temp_sf" "$sf" 2>/dev/null || return 1
}

read_state() {
    pkg=$1
    instance=$2
    key=$3
    
    state_key="${pkg}_${instance}"
    grep "^${key}=" "$STATE_DIR/${state_key}.state" 2>/dev/null | cut -d'=' -f2-
}

# ==================== SETUP ====================
setup_wizard() {
    clear
    echo ""
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║  ROBLOX V13.4 - ANDROID 10-12        ║${NC}"
    echo "${BLUE}║  Production 24/7 Ready                ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${YELLOW}[1/5] Creating directories...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$QUEUE_DIR" "$CACHE_DIR" "$LOCK_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
    log_msg "SYSTEM" "V13.4 Setup started"
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${YELLOW}[2/5] Scanning packages...${NC}"
    packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo "${RED}✗ No Roblox found!${NC}"
        exit 1
    fi
    
    echo "${GREEN}✓ Found:${NC}"
    echo ""
    echo "$packages" | while read pkg; do
        pids=$(pidof "$pkg" 2>/dev/null)
        if [ -n "$pids" ]; then
            count=$(echo "$pids" | wc -w)
            echo "  ${GREEN}✓${NC} $pkg ($count instances)"
        else
            echo "  ${RED}✗${NC} $pkg"
        fi
    done
    echo ""
    
    echo "${YELLOW}[3/5] Select tabs...${NC}"
    > "$TAB_LIST_FILE.tmp"
    
    echo "$packages" | while read pkg; do
        pids=$(pidof "$pkg" 2>/dev/null)
        default="n"
        [ -n "$pids" ] && default="y"
        
        printf "  Monitor $pkg? ($default): "
        read -r choice
        [ -z "$choice" ] && choice="$default"
        
        case "$choice" in
            y|Y) echo "$pkg" >> "$TAB_LIST_FILE.tmp" ;;
        esac
    done
    
    if [ -s "$TAB_LIST_FILE.tmp" ]; then
        mv "$TAB_LIST_FILE.tmp" "$TAB_LIST_FILE"
    else
        echo "$packages" > "$TAB_LIST_FILE"
    fi
    echo ""
    
    echo "${YELLOW}[4/5] Creating config...${NC}"
    cat > "$CONFIG_FILE" << 'CONFIGEOF'
PLACE_ID="2753915549"
LINK="roblox://placeId=2753915549"
CHECK_INTERVAL=20
MAX_RESTARTS=10
PROCESS_RECOVERY_COOLDOWN=180
PROCESS_MISSING_THRESHOLD=3
NET_STAGNANT_THRESHOLD=5
LAUNCH_TIMEOUT=420
UIAUTOMATOR_CHECK_THRESHOLD=70
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
QUEUE_DIR="$QUEUE_DIR"
LOCK_DIR="$LOCK_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$LOG_FILE"
CONFIGEOF
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${YELLOW}[5/5] Setup aliases...${NC}"
    PROFILE="$HOME/.bashrc"
    [ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"
    
    if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
        echo "" >> "$PROFILE"
        echo "alias roblox-rejoin=\"sh \$HOME/.roblox_auto_rejoin/roblox_v13.4_final.sh\"" >> "$PROFILE"
        echo "alias roblox-status=\"sh \$HOME/.roblox_auto_rejoin/roblox_v13.4_final.sh status\"" >> "$PROFILE"
        echo "alias roblox-logs=\"sh \$HOME/.roblox_auto_rejoin/roblox_v13.4_final.sh logs\"" >> "$PROFILE"
        echo "alias roblox-watch=\"sh \$HOME/.roblox_auto_rejoin/roblox_v13.4_final.sh watch\"" >> "$PROFILE"
    fi
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo "${GREEN}✅ SETUP COMPLETE!${NC}"
    echo ""
    
    printf "${YELLOW}Start monitor? (y/n): ${NC}"
    read -r choice
    
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
        sleep 2
        echo "${GREEN}✓ V13.4 running!${NC}"
        echo "Dashboard: /sdcard/Download/roblox_dashboard.json"
    fi
    echo ""
}

# ==================== INIT STATE ====================
init_state() {
    pkg=$1
    instance=$2
    
    state_key="${pkg}_${instance}"
    sf="$STATE_DIR/${state_key}.state"
    [ -f "$sf" ] && return
    
    {
        echo "HEALTH_SCORE=100"
        echo "CPU_TICKS=0"
        echo "NET_BYTES=0"
        echo "NET_FREEZE_COUNT=0"
        echo "PROCESS_MISSING_COUNT=0"
        echo "RESTART_PENDING=0"
        echo "RESTART_COUNT=0"
        echo "LAST_RESTART=0"
        echo "RESTART_FAIL_COUNT=0"
        echo "BACKOFF_UNTIL=0"
        echo "LAST_ERROR=NONE"
        echo "LAUNCH_TIME=$(date +%s)"
        echo "START_TIME=$(date +%s)"
        echo "PID_START_TIME=$(cat /proc/$instance/stat 2>/dev/null | awk '{print $22}')"
    } > "$sf"
}

# ==================== DISCOVERY - HANDLES CLONES ====================
discover_instances() {
    pkg=$1
    
    pids=$(pidof "$pkg" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "$pids" | tr ' ' '\n'
        return
    fi
    
    ps -A 2>/dev/null | grep -F "$pkg" | awk '{print $2}' | while read pid; do
        [ -z "$pid" ] && continue
        cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
        case "$cmd" in
            "$pkg"|"$pkg":*) echo "$pid" ;;
        esac
    done
}

# ==================== FOREGROUND DETECTION ====================
detect_foreground_app() {
    fg=$(dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    [ -n "$fg" ] && [ "$fg" != "null" ] && { echo "$fg"; return; }
    
    fg=$(dumpsys activity top 2>/dev/null | grep -E "TASK" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    [ -n "$fg" ] && { echo "$fg"; return; }
    
    fg=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    echo "$fg"
}

is_foreground() {
    pkg=$1
    [ "$(detect_foreground_app)" = "$pkg" ] && echo "true" || echo "false"
}

# ==================== MEMORY CHECK ====================
check_free_memory() {
    free=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)
    [ -z "$free" ] && free=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null)
    [ -n "$free" ] && echo "$free" || echo "0"
}

# ==================== CPU TICKS ====================
get_cpu_ticks() {
    pid=$1
    stat=$(cat "/proc/$pid/stat" 2>/dev/null)
    [ -n "$stat" ] && echo "$stat" | awk '{print $14+$15}' || echo "0"
}

# ==================== NETWORK ====================
get_net_bytes() {
    pkg=$1
    pid=$2
    
    uid=$(grep "^Uid:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    [ -z "$uid" ] && echo "-1" && return
    
    if [ -f "/proc/uid_stat/$uid/tcp_rcv" ]; then
        rcv=$(cat "/proc/uid_stat/$uid/tcp_rcv" 2>/dev/null)
        snd=$(cat "/proc/uid_stat/$uid/tcp_snd" 2>/dev/null)
        echo $((rcv + snd))
        return
    fi
    
    if [ -f "/proc/net/xt_qtaguid/stats" ]; then
        total=$(awk -v u="$uid" '$4==u {sum+=$6+$8} END {print sum}' /proc/net/xt_qtaguid/stats 2>/dev/null)
        [ -n "$total" ] && [ "$total" -gt 0 ] && { echo "$total"; return; }
    fi
    
    echo "-1"
}

# ==================== UI ERROR ====================
detect_ui_error() {
    pkg=$1
    score=$2
    
    [ "$score" -ge "$UIAUTOMATOR_CHECK_THRESHOLD" ] && return 1
    [ "$(is_foreground "$pkg")" != "true" ] && return 1
    
    uiautomator dump "$UI_DUMP" 2>/dev/null || return 1
    [ ! -f "$UI_DUMP" ] && return 1
    
    code=$(grep -oE "Error Code: [0-9]{3}" "$UI_DUMP" | head -1 | grep -oE "[0-9]{3}")
    [ -n "$code" ] && echo "$code" && return 0
    
    return 1
}

# ==================== HEALTH SCORE ====================
calculate_health_score() {
    pkg=$1
    pid=$2
    
    [ ! -d "/proc/$pid" ] && return 0
    
    status=$(cat "/proc/$pid/status" 2>/dev/null)
    [ -z "$status" ] && return 0
    
    state=$(echo "$status" | grep "^State:" | awk '{print $2}')
    rss=$(echo "$status" | grep "^VmRSS:" | awk '{print $2}')
    threads=$(echo "$status" | grep "^Threads:" | awk '{print $2}')
    
    [ -z "$rss" ] && rss=0
    [ -z "$threads" ] && threads=0
    
    score=0
    case "$state" in
        R) score=$((score + 25)) ;;
        S) score=$((score + 20)) ;;
        D) score=$((score + 5)) ;;
    esac
    
    [ "$rss" -gt 102400 ] && score=$((score + 25)) || score=$((score + 10))
    [ "$threads" -gt 5 ] && score=$((score + 20)) || score=$((score + 5))
    
    current_ticks=$(get_cpu_ticks "$pid")
    last_ticks=$(read_state "$pkg" "$pid" "CPU_TICKS")
    [ -z "$last_ticks" ] && last_ticks=0
    
    if [ "$current_ticks" -ne "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        score=$((score + 20))
    fi
    write_state_atomic "$pkg" "$pid" "CPU_TICKS" "$current_ticks"
    
    current_net=$(get_net_bytes "$pkg" "$pid")
    last_net=$(read_state "$pkg" "$pid" "NET_BYTES")
    [ -z "$last_net" ] && last_net=0
    
    if [ "$current_net" -eq -1 ]; then
        [ "$current_ticks" -gt "$last_ticks" ] && score=$((score + 15))
    else
        if [ "$current_net" -ne "$last_net" ]; then
            score=$((score + 20))
            write_state_atomic "$pkg" "$pid" "NET_FREEZE_COUNT" "0"
        else
            freeze=$(read_state "$pkg" "$pid" "NET_FREEZE_COUNT")
            [ -z "$freeze" ] && freeze=0
            freeze=$((freeze + 1))
            write_state_atomic "$pkg" "$pid" "NET_FREEZE_COUNT" "$freeze"
            [ "$freeze" -ge "$NET_STAGNANT_THRESHOLD" ] && score=$((score - 30))
        fi
        write_state_atomic "$pkg" "$pid" "NET_BYTES" "$current_net"
    fi
    
    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 100 ] && score=100
    
    echo "$score"
}

score_to_state() {
    score=$1
    [ "$score" -ge 80 ] && echo "ACTIVE" && return
    [ "$score" -ge 50 ] && echo "SUSPECT" && return
    echo "DEAD"
}

# ==================== BACKOFF ====================
get_backoff_time() {
    fail_count=$1
    case "$fail_count" in
        1) echo 60 ;;
        2) echo 300 ;;
        3) echo 900 ;;
        4) echo 1800 ;;
        *) echo "$RESTART_BACKOFF_MAX" ;;
    esac
}

check_backoff() {
    pkg=$1
    instance=$2
    now=$(date +%s)
    
    backoff_until=$(read_state "$pkg" "$instance" "BACKOFF_UNTIL")
    [ -z "$backoff_until" ] && backoff_until=0
    
    [ "$now" -lt "$backoff_until" ] && return 1
    return 0
}

# ==================== VERIFY RESTART ====================
verify_restart() {
    pkg=$1
    old_pid=$2
    
    pids_before=$(discover_instances "$pkg" 2>/dev/null)
    
    retry=0
    while [ "$retry" -lt 30 ]; do
        sleep 1
        
        pids_after=$(discover_instances "$pkg" 2>/dev/null)
        
        new_pid=$(echo "$pids_after" | while read pid; do
            echo "$pids_before" | grep -q "^$pid$" || echo "$pid"
        done | head -1)
        
        if [ -n "$new_pid" ] && [ -d "/proc/$new_pid" ]; then
            old_starttime=$(cat "/proc/$old_pid/stat" 2>/dev/null | awk '{print $22}')
            new_starttime=$(cat "/proc/$new_pid/stat" 2>/dev/null | awk '{print $22}')
            
            if [ -n "$new_starttime" ] && [ "$old_starttime" != "$new_starttime" ]; then
                log_msg "VERIFY" "Restart successful - New PID: $new_pid" "$pkg"
                return 0
            fi
        fi
        
        retry=$((retry + 1))
    done
    
    log_msg "VERIFY" "Restart failed - No new PID after 30s" "$pkg"
    return 1
}

# ==================== QUEUE ====================
enqueue_restart() {
    pkg=$1
    instance=$2
    error=$3
    
    pending=$(read_state "$pkg" "$instance" "RESTART_PENDING")
    [ "$pending" = "1" ] && return
    
    acquire_lock "$pkg" || return
    write_state_atomic "$pkg" "$instance" "RESTART_PENDING" "1"
    release_lock
    
    qf="$QUEUE_DIR/${pkg}_${instance}_$(date +%s).queue"
    {
        echo "PKG=$pkg"
        echo "PID=$instance"
        echo "ERROR=$error"
        echo "TIME=$(date +%s)"
    } > "$qf"
    log_msg "QUEUE" "Enqueued - Error: $error" "$pkg"
}

process_queue() {
    first=$(find "$QUEUE_DIR" -name "*.queue" -type f 2>/dev/null | head -1)
    [ -z "$first" ] && return
    
    queue_lock="${first}.lock"
    if ! mkdir "$queue_lock" 2>/dev/null; then
        return
    fi
    
    processing="${first}.processing"
    mv "$first" "$processing" 2>/dev/null || {
        rmdir "$queue_lock" 2>/dev/null
        return
    }
    
    pkg=$(grep "^PKG=" "$processing" | cut -d'=' -f2-)
    pid=$(grep "^PID=" "$processing" | cut -d'=' -f2-)
    error=$(grep "^ERROR=" "$processing" | cut -d'=' -f2-)
    
    echo "START_TIME=$(date +%s)" >> "$processing"
    
    rmdir "$queue_lock" 2>/dev/null
    
    do_restart "$pkg" "$pid" "$error"
    rm -f "$processing"
}

recover_stuck_queue() {
    now=$(date +%s)
    
    find "$QUEUE_DIR" -name "*.queue.processing" -type f 2>/dev/null | while read processing; do
        [ -z "$processing" ] && continue
        
        start_time=$(grep "^START_TIME=" "$processing" 2>/dev/null | cut -d'=' -f2-)
        
        if [ -z "$start_time" ]; then
            start_time=$(stat -c %Y "$processing" 2>/dev/null || stat -f %m "$processing" 2>/dev/null)
        fi
        
        [ -z "$start_time" ] && start_time=0
        
        if [ $((now - start_time)) -gt "$QUEUE_PROCESSING_TIMEOUT" ]; then
            queue="${processing%.processing}"
            mv "$processing" "$queue" 2>/dev/null
            log_msg "RECOVERY" "Recovered stuck queue: $(basename $queue)" "GLOBAL"
        fi
    done
}

# ==================== CLEANUP ====================
cleanup_dead_states() {
    for sf in "$STATE_DIR"/*.state; do
        [ ! -f "$sf" ] && continue
        
        filename=$(basename "$sf" .state)
        pid=$(echo "$filename" | sed 's/.*_//')
        
        case "$pid" in
            ''|*[!0-9]*) continue ;;
        esac
        
        if [ ! -d "/proc/$pid" ]; then
            rm -f "$sf"
            log_msg "CLEANUP" "Removed dead state: $(basename $sf)" "GLOBAL"
            continue
        fi
        
        stored_starttime=$(grep "^PID_START_TIME=" "$sf" 2>/dev/null | cut -d'=' -f2-)
        current_starttime=$(cat "/proc/$pid/stat" 2>/dev/null | awk '{print $22}')
        
        if [ -n "$stored_starttime" ] && [ -n "$current_starttime" ] && [ "$stored_starttime" != "$current_starttime" ]; then
            rm -f "$sf"
            log_msg "CLEANUP" "Removed state for reused PID: $pid" "GLOBAL"
        fi
    done
}

# ==================== RESTART ====================
do_restart() {
    pkg=$1
    old_pid=$2
    error=$3
    
    acquire_lock "$pkg" || return 1
    init_state "$pkg" "$old_pid"
    
    backoff_until=$(read_state "$pkg" "$old_pid" "BACKOFF_UNTIL")
    [ -z "$backoff_until" ] && backoff_until=0
    now=$(date +%s)
    
    if [ "$now" -lt "$backoff_until" ]; then
        release_lock
        log_msg "BACKOFF" "Still in backoff, skipping restart" "$pkg"
        return 1
    fi
    
    restart=$(read_state "$pkg" "$old_pid" "RESTART_COUNT")
    [ -z "$restart" ] && restart=0
    if [ "$restart" -gt "$MAX_RESTARTS" ]; then
        log_msg "BANNED" "Max restarts exceeded" "$pkg"
        release_lock
        return 1
    fi
    
    restart=$((restart + 1))
    write_state_atomic "$pkg" "$old_pid" "RESTART_COUNT" "$restart"
    write_state_atomic "$pkg" "$old_pid" "LAST_RESTART" "$(date +%s)"
    write_state_atomic "$pkg" "$old_pid" "LAST_ERROR" "$error"
    write_state_atomic "$pkg" "$old_pid" "LAUNCH_TIME" "$(date +%s)"
    write_state_atomic "$pkg" "$old_pid" "PROCESS_MISSING_COUNT" "0"
    write_state_atomic "$pkg" "$old_pid" "RESTART_PENDING" "0"
    
    release_lock
    
    log_msg "RESTART" "Restart #$restart - Error: $error" "$pkg"
    
    if [ "$old_pid" -ne 0 ] && [ -d "/proc/$old_pid" ]; then
        kill "$old_pid" 2>/dev/null
        sleep 1
        kill -9 "$old_pid" 2>/dev/null
    fi
    
    sleep 1
    am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    
    if ! verify_restart "$pkg" "$old_pid"; then
        fail=$(read_state "$pkg" "$old_pid" "RESTART_FAIL_COUNT")
        [ -z "$fail" ] && fail=0
        fail=$((fail + 1))
        
        acquire_lock "$pkg" || return 1
        write_state_atomic "$pkg" "$old_pid" "RESTART_FAIL_COUNT" "$fail"
        
        backoff=$(get_backoff_time "$fail")
        write_state_atomic "$pkg" "$old_pid" "BACKOFF_UNTIL" "$(($(date +%s) + backoff))"
        
        release_lock
        
        log_msg "BACKOFF" "Restart failed, backoff ${backoff}s" "$pkg"
    else
        acquire_lock "$pkg" || return 1
        write_state_atomic "$pkg" "$old_pid" "RESTART_FAIL_COUNT" "0"
        release_lock
    fi
}

# ==================== MONITOR ====================
monitor_instance() {
    pkg=$1
    pid=$2
    
    acquire_lock "$pkg" || return
    init_state "$pkg" "$pid"
    release_lock
    
    if ! check_backoff "$pkg" "$pid"; then
        return
    fi
    
    if [ ! -d "/proc/$pid" ]; then
        missing=$(read_state "$pkg" "$pid" "PROCESS_MISSING_COUNT")
        [ -z "$missing" ] && missing=0
        missing=$((missing + 1))
        
        acquire_lock "$pkg" || return
        write_state_atomic "$pkg" "$pid" "PROCESS_MISSING_COUNT" "$missing"
        release_lock
        
        if [ "$missing" -ge "$PROCESS_MISSING_THRESHOLD" ]; then
            enqueue_restart "$pkg" "$pid" "PROCESS_MISSING"
        fi
        return
    fi
    
    acquire_lock "$pkg" || return
    write_state_atomic "$pkg" "$pid" "PROCESS_MISSING_COUNT" "0"
    release_lock
    
    free_mem=$(check_free_memory)
    if [ "$free_mem" -lt "$RAM_WARN_THRESHOLD" ]; then
        log_msg "WARN" "Low memory: ${free_mem}KB" "$pkg"
    fi
    
    score=$(calculate_health_score "$pkg" "$pid")
    state=$(score_to_state "$score")
    
    acquire_lock "$pkg" || return
    write_state_atomic "$pkg" "$pid" "HEALTH_SCORE" "$score"
    release_lock
    
    case "$state" in
        ACTIVE)
            ui_error=$(detect_ui_error "$pkg" "$score")
            if [ -n "$ui_error" ]; then
                enqueue_restart "$pkg" "$pid" "ERROR_$ui_error"
            fi
            ;;
        SUSPECT)
            log_msg "SUSPECT" "Score: $score" "$pkg"
            ;;
        DEAD)
            log_msg "DEAD" "Score: $score" "$pkg"
            enqueue_restart "$pkg" "$pid" "HEALTH_CRITICAL"
            ;;
    esac
}

monitor_tab() {
    pkg=$1
    
    pids=$(discover_instances "$pkg")
    if [ -z "$pids" ]; then
        log_msg "NO_INSTANCE" "No running instance" "$pkg"
        return
    fi
    
    echo "$pids" | while read pid; do
        [ -z "$pid" ] && continue
        monitor_instance "$pkg" "$pid" &
    done
}

monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && exit 1
    
    echo $$ > "$MONITOR_PID_FILE"
    log_msg "SYSTEM" "V13.5 Monitor started (PID: $$)"
    
    while true; do
        while read pkg; do
            monitor_tab "$pkg" &
        done < "$TAB_LIST_FILE"
        
        wait
        
        recover_stuck_queue
        cleanup_dead_states
        process_queue
        
        sleep "$CHECK_INTERVAL"
    done
}

# ==================== WATCHDOG ====================
watchdog_loop() {
    echo $$ > "$WATCHDOG_PID_FILE"
    log_msg "SYSTEM" "V13.5 Watchdog started (PID: $$)"
    
    while true; do
        sleep 60
        
        if [ -f "$MONITOR_PID_FILE" ]; then
            monitor_pid=$(cat "$MONITOR_PID_FILE")
            
            if ! kill -0 "$monitor_pid" 2>/dev/null; then
                log_msg "WATCHDOG" "Monitor died (PID: $monitor_pid), restarting..."
                
                rm -f "$MONITOR_PID_FILE"
                nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
                
                sleep 10
            fi
        fi
    done
}

# ==================== LIVE STATUS DISPLAY ====================
display_live_status() {
    clear
    echo ""
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║  ROBLOX V13.5 - LIVE MONITOR         ║${NC}"
    echo "${BLUE}║  Termux Real-time Status             ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${YELLOW}Updated: $timestamp${NC}"
    echo ""
    
    if [ ! -f "$TAB_LIST_FILE" ]; then
        echo "${RED}No packages configured${NC}"
        return
    fi
    
    total_active=0
    total_suspect=0
    total_dead=0
    
    echo "${BLUE}Instance Status:${NC}"
    echo ""
    
    while read pkg; do
        pkg_active=0
        pkg_suspect=0
        pkg_dead=0
        
        for sf in "$STATE_DIR"/${pkg}_*.state; do
            [ ! -f "$sf" ] && continue
            
            pid=$(basename "$sf" .state | sed 's/.*_//')
            score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2-)
            state=$(score_to_state "$score")
            error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2-)
            restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2-)
            
            [ -z "$score" ] && score=0
            [ -z "$restart" ] && restart=0
            
            case "$state" in
                ACTIVE)
                    color="$GREEN"
                    pkg_active=$((pkg_active + 1))
                    total_active=$((total_active + 1))
                    ;;
                SUSPECT)
                    color="$YELLOW"
                    pkg_suspect=$((pkg_suspect + 1))
                    total_suspect=$((total_suspect + 1))
                    ;;
                DEAD)
                    color="$RED"
                    pkg_dead=$((pkg_dead + 1))
                    total_dead=$((total_dead + 1))
                    ;;
            esac
            
            printf "  ${color}%-8s${NC} PID:%-6s | Score:%-3s | %s | Error: %s | Restarts: %d\n" \
                "$state" "$pid" "$score" "$pkg" "$error" "$restart"
        done
    done < "$TAB_LIST_FILE"
    
    echo ""
    echo "${BLUE}Summary:${NC}"
    echo "  ${GREEN}Active:${NC}  $total_active"
    echo "  ${YELLOW}Suspect:${NC} $total_suspect"
    echo "  ${RED}Dead:${NC}    $total_dead"
    echo ""
    echo "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
}

# ==================== MAIN ====================
case "$1" in
    setup)
        setup_wizard
        ;;
    monitor)
        monitor_loop
        ;;
    watchdog)
        watchdog_loop
        ;;
    watch)
        if [ ! -f "$TAB_LIST_FILE" ]; then
            echo "Not setup yet"
            exit 1
        fi
        while true; do
            display_live_status
            sleep 3
        done
        ;;
    status)
        [ ! -f "$CONFIG_FILE" ] && { echo "Not setup"; exit 1; }
        echo "${BLUE}V13.5 Status:${NC}"
        while read pkg; do
            for sf in "$STATE_DIR"/${pkg}_*.state; do
                [ ! -f "$sf" ] && continue
                pid=$(basename "$sf" .state | sed 's/.*_//')
                score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2-)
                state=$(score_to_state "$score")
                error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2-)
                restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2-)
                echo "  $pkg(PID:$pid) | $state ($score) | Error: $error | Restarts: $restart"
            done
        done < "$TAB_LIST_FILE"
        ;;
    logs)
        [ ! -f "$LOG_FILE" ] && { echo "No logs"; exit 1; }
        tail -n 50 "$LOG_FILE"
        ;;
    *)
        [ ! -f "$CONFIG_FILE" ] && setup_wizard || {
            echo "${GREEN}Starting V13.5 with watchdog...${NC}"
            
            if [ -f "$MONITOR_PID_FILE" ]; then
                monitor_pid=$(cat "$MONITOR_PID_FILE")
                if kill -0 "$monitor_pid" 2>/dev/null; then
                    echo "${GREEN}✓ Monitor already running (PID: $monitor_pid)${NC}"
                    echo ""
                    echo "View live status:"
                    echo "  sh $0 watch"
                    echo ""
                    echo "View logs:"
                    echo "  sh $0 logs"
                    exit 0
                fi
            fi
            
            if [ -f "$WATCHDOG_PID_FILE" ]; then
                watchdog_pid=$(cat "$WATCHDOG_PID_FILE")
                if kill -0 "$watchdog_pid" 2>/dev/null; then
                    echo "${GREEN}✓ Watchdog already running (PID: $watchdog_pid)${NC}"
                    exit 0
                fi
            fi
            
            nohup sh "$0" watchdog > /dev/null 2>&1 &
            nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
            
            sleep 2
            echo "${GREEN}✓ V13.5 running!${NC}"
            echo ""
            echo "Commands:"
            echo "  sh $0 watch    - View live status (updates every 3s)"
            echo "  sh $0 status   - Quick status check"
            echo "  sh $0 logs     - View last 50 log lines"
            echo ""
        }
        ;;
esac
