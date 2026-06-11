#!/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V13.3 - ANDROID 10-12 HARDENED
# POSIX-only | No local | No GNU-isms
# Compatible: mksh, toybox sh, dash, bash
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
DASHBOARD_JSON="/sdcard/Download/roblox_dashboard.json"
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
    
    # Use wc instead of stat (POSIX compatible)
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$size" -gt "$LOG_MAX_SIZE" ] && rotate_logs
}

rotate_logs() {
    timestamp=$(date +%s)
    mv "$LOG_FILE" "$LOG_FILE.${timestamp}"
    : > "$LOG_FILE"
    
    # Keep only last 3 rotations
    find "$INSTALL_DIR" -name "executor.log.*" -type f 2>/dev/null | sort -r | tail -n +4 | while read f; do
        rm -f "$f"
    done
}

# ==================== ATOMIC LOCK - PER-PACKAGE ====================
acquire_lock() {
    pkg=$1
    lockdir="$LOCK_DIR/${pkg}.lock"
    retry=0
    
    # Atomic mkdir - per-package lock ensures mutual exclusion
    # All PID instances of same package share this lock
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
    echo "${BLUE}║  ROBLOX V13.3 - ANDROID 10-12        ║${NC}"
    echo "${BLUE}║  POSIX-only Hardened                 ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${YELLOW}[1/5] Creating directories...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$QUEUE_DIR" "$CACHE_DIR" "$LOCK_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
    log_msg "SYSTEM" "V13.3 Setup started"
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
    cat > "$CONFIG_FILE" << EOF
PLACE_ID="$PLACE_ID"
LINK="$LINK"
CHECK_INTERVAL=$CHECK_INTERVAL
MAX_RESTARTS=$MAX_RESTARTS
PROCESS_RECOVERY_COOLDOWN=$PROCESS_RECOVERY_COOLDOWN
PROCESS_MISSING_THRESHOLD=$PROCESS_MISSING_THRESHOLD
NET_STAGNANT_THRESHOLD=$NET_STAGNANT_THRESHOLD
LAUNCH_TIMEOUT=$LAUNCH_TIMEOUT
UIAUTOMATOR_CHECK_THRESHOLD=$UIAUTOMATOR_CHECK_THRESHOLD
LOG_MAX_SIZE=$LOG_MAX_SIZE
QUEUE_PROCESSING_TIMEOUT=$QUEUE_PROCESSING_TIMEOUT
RAM_WARN_THRESHOLD=$RAM_WARN_THRESHOLD
RESTART_BACKOFF_MAX=$RESTART_BACKOFF_MAX
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
QUEUE_DIR="$QUEUE_DIR"
CACHE_DIR="$CACHE_DIR"
LOCK_DIR="$LOCK_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$LOG_FILE"
MONITOR_PID_FILE="$MONITOR_PID_FILE"
UI_DUMP="$UI_DUMP"
EOF
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${YELLOW}[5/5] Setup aliases...${NC}"
    PROFILE="$HOME/.bashrc"
    [ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"
    
    if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
        cat >> "$PROFILE" << 'ALIAS'

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_v13.sh"
alias roblox-status="sh $HOME/.roblox_auto_rejoin/roblox_v13.sh status"
alias roblox-logs="sh $HOME/.roblox_auto_rejoin/roblox_v13.sh logs"
ALIAS
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
        echo "${GREEN}✓ V13.3 running!${NC}"
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
    
    cat > "$sf" << EOF
HEALTH_SCORE=100
CPU_TICKS=0
NET_BYTES=0
NET_FREEZE_COUNT=0
PROCESS_MISSING_COUNT=0
RESTART_PENDING=0
RESTART_COUNT=0
LAST_RESTART=0
RESTART_FAIL_COUNT=0
BACKOFF_UNTIL=0
LAST_ERROR=NONE
LAUNCH_TIME=$(date +%s)
START_TIME=$(date +%s)
PID_START_TIME=$(cat /proc/$instance/stat 2>/dev/null | awk '{print $22}')
EOF
}

# ==================== DISCOVERY - HANDLES CLONES ====================
discover_instances() {
    pkg=$1
    
    # Method 1: pidof
    pids=$(pidof "$pkg" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "$pids" | tr ' ' '\n'
        return
    fi
    
    # Method 2: ps + grep with -F for literal match
    ps -A 2>/dev/null | grep -F "$pkg" | awk '{print $2}' | while read pid; do
        [ -z "$pid" ] && continue
        
        # Verify package name
        cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
        
        case "$cmd" in
            "$pkg"|"$pkg":*)
                echo "$pid"
                ;;
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

# ==================== VERIFY RESTART - CHECK STARTTIME ====================
verify_restart() {
    pkg=$1
    old_pid=$2
    
    # Snapshot current PIDs before restart
    pids_before=$(discover_instances "$pkg" 2>/dev/null)
    
    retry=0
    while [ "$retry" -lt 30 ]; do
        sleep 1
        
        pids_after=$(discover_instances "$pkg" 2>/dev/null)
        
        # Find new PID (exists in after but not in before)
        new_pid=$(echo "$pids_after" | while read pid; do
            echo "$pids_before" | grep -q "^$pid$" || echo "$pid"
        done | head -1)
        
        if [ -n "$new_pid" ] && [ -d "/proc/$new_pid" ]; then
            # Verify it's a new process (different starttime)
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
    cat > "$qf" << EOF
PKG=$pkg
PID=$instance
ERROR=$error
TIME=$(date +%s)
EOF
    log_msg "QUEUE" "Enqueued - Error: $error" "$pkg"
}

process_queue() {
    first=$(find "$QUEUE_DIR" -name "*.queue" -type f 2>/dev/null | head -1)
    [ -z "$first" ] && return
    
    # Lock the queue item to prevent race
    queue_lock="${first}.lock"
    if ! mkdir "$queue_lock" 2>/dev/null; then
        return  # Queue locked by other process
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
    
    rmdir "$queue_lock" 2>/dev/null  # Release lock before restart
    
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
    [ "$restart" -gt "$MAX_RESTARTS" ] && {
        log_msg "BANNED" "Max restarts exceeded" "$pkg"
        release_lock
        return 1
    }
    
    restart=$((restart + 1))
    write_state_atomic "$pkg" "$old_pid" "RESTART_COUNT" "$restart"
    write_state_atomic "$pkg" "$old_pid" "LAST_RESTART" "$(date +%s)"
    write_state_atomic "$pkg" "$old_pid" "LAST_ERROR" "$error"
    write_state_atomic "$pkg" "$old_pid" "LAUNCH_TIME" "$(date +%s)"
    write_state_atomic "$pkg" "$old_pid" "PROCESS_MISSING_COUNT" "0"
    write_state_atomic "$pkg" "$old_pid" "RESTART_PENDING" "0"
    
    release_lock
    
    log_msg "RESTART" "Restart #$restart - Error: $error" "$pkg"
    
    [ "$old_pid" -ne 0 ] && [ -d "/proc/$old_pid" ] && {
        kill "$old_pid" 2>/dev/null
        sleep 1
        kill -9 "$old_pid" 2>/dev/null
    }
    
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
        
        [ "$missing" -ge "$PROCESS_MISSING_THRESHOLD" ] && enqueue_restart "$pkg" "$pid" "PROCESS_MISSING"
        return
    fi
    
    acquire_lock "$pkg" || return
    write_state_atomic "$pkg" "$pid" "PROCESS_MISSING_COUNT" "0"
    release_lock
    
    free_mem=$(check_free_memory)
    [ "$free_mem" -lt "$RAM_WARN_THRESHOLD" ] && log_msg "WARN" "Low memory: ${free_mem}KB" "$pkg"
    
    score=$(calculate_health_score "$pkg" "$pid")
    state=$(score_to_state "$score")
    
    acquire_lock "$pkg" || return
    write_state_atomic "$pkg" "$pid" "HEALTH_SCORE" "$score"
    release_lock
    
    case "$state" in
        ACTIVE)
            ui_error=$(detect_ui_error "$pkg" "$score")
            [ -n "$ui_error" ] && enqueue_restart "$pkg" "$pid" "ERROR_$ui_error"
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
    [ -z "$pids" ] && {
        log_msg "NO_INSTANCE" "No running instance" "$pkg"
        return
    }
    
    echo "$pids" | while read pid; do
        [ -z "$pid" ] && continue
        monitor_instance "$pkg" "$pid" &
    done
}

monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && exit 1
    
    echo $$ > "$MONITOR_PID_FILE"
    log_msg "SYSTEM" "V13.3 Monitor started (PID: $$)"
    
    while true; do
        while read pkg; do
            monitor_tab "$pkg" &
        done < "$TAB_LIST_FILE"
        
        wait
        
        recover_stuck_queue
        cleanup_dead_states
        process_queue
        update_dashboard
        
        sleep "$CHECK_INTERVAL"
    done
}

# ==================== WATCHDOG ====================
watchdog_loop() {
    log_msg "SYSTEM" "V13.3 Watchdog started (PID: $$)"
    
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

# ==================== DASHBOARD ====================
update_dashboard() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    active=0
    suspect=0
    dead=0
    
    echo "{" > "${DASHBOARD_JSON}.tmp"
    echo "  \"timestamp\": \"$timestamp\"," >> "${DASHBOARD_JSON}.tmp"
    echo "  \"instances\": [" >> "${DASHBOARD_JSON}.tmp"
    
    first=true
    while read pkg; do
        for sf in "$STATE_DIR"/${pkg}_*.state; do
            [ ! -f "$sf" ] && continue
            
            score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2-)
            state=$(score_to_state "$score")
            error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2-)
            restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2-)
            
            # Escape quotes in error for JSON
            error=$(printf '%s' "$error" | sed 's/"/\\"/g')
            
            case "$state" in
                ACTIVE) active=$((active + 1)) ;;
                SUSPECT) suspect=$((suspect + 1)) ;;
                DEAD) dead=$((dead + 1)) ;;
            esac
            
            [ "$first" = true ] && first=false || echo "," >> "${DASHBOARD_JSON}.tmp"
            
            filename=$(basename "$sf" .state)
            pid=$(echo "$filename" | sed 's/.*_//')
            
            cat >> "${DASHBOARD_JSON}.tmp" <<EOFR
    {
      "package": "$pkg",
      "pid": "$pid",
      "state": "$state",
      "health_score": $score,
      "last_error": "$error",
      "restarts": $restart
    }
EOFR
        done
    done < "$TAB_LIST_FILE"
    
    echo "" >> "${DASHBOARD_JSON}.tmp"
    echo "  ]," >> "${DASHBOARD_JSON}.tmp"
    echo "  \"summary\": {" >> "${DASHBOARD_JSON}.tmp"
    echo "    \"active\": $active," >> "${DASHBOARD_JSON}.tmp"
    echo "    \"suspect\": $suspect," >> "${DASHBOARD_JSON}.tmp"
    echo "    \"dead\": $dead" >> "${DASHBOARD_JSON}.tmp"
    echo "  }" >> "${DASHBOARD_JSON}.tmp"
    echo "}" >> "${DASHBOARD_JSON}.tmp"
    
    mv "${DASHBOARD_JSON}.tmp" "$DASHBOARD_JSON"
}

# ==================== MAIN ====================
case "$1" in
    setup) setup_wizard ;;
    monitor) monitor_loop ;;
    watchdog) watchdog_loop ;;
    status)
        [ ! -f "$CONFIG_FILE" ] && { echo "Not setup"; exit 1; }
        echo "${BLUE}V13.3 Status:${NC}"
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
            echo "${GREEN}Starting V13.4 with watchdog...${NC}"
            
            # Check if monitor already running
            if [ -f "$MONITOR_PID_FILE" ]; then
                monitor_pid=$(cat "$MONITOR_PID_FILE")
                if kill -0 "$monitor_pid" 2>/dev/null; then
                    echo "${GREEN}✓ Monitor already running (PID: $monitor_pid)${NC}"
                    exit 0
                fi
            fi
            
            # Check if watchdog already running
            watchdog_pidfile="$INSTALL_DIR/watchdog.pid"
            if [ -f "$watchdog_pidfile" ]; then
                watchdog_pid=$(cat "$watchdog_pidfile")
                if kill -0 "$watchdog_pid" 2>/dev/null; then
                    echo "${GREEN}✓ Watchdog already running (PID: $watchdog_pid)${NC}"
                    exit 0
                fi
            fi
            
            # Start fresh
            nohup sh "$0" watchdog > /dev/null 2>&1 &
            echo $! > "$watchdog_pidfile"
            
            nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
            
            sleep 2
            echo "${GREEN}✓ V13.4 running!${NC}"
            echo "Dashboard: /sdcard/Download/roblox_dashboard.json"
        }
        ;;
esac