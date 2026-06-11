#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V12 - FINAL PERFECTION
# All V11 bugs fixed + Multi-instance + Optimized
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
DASHBOARD_JSON="/sdcard/Download/roblox_dashboard.json"
UI_DUMP="/sdcard/ui_dump.xml"
FG_CACHE="$CACHE_DIR/foreground.cache"
FG_CACHE_TTL=5

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"
CHECK_INTERVAL=20
MAX_RESTARTS=10
PROCESS_RECOVERY_COOLDOWN=180
PROCESS_MISSING_THRESHOLD=3
NET_STAGNANT_THRESHOLD=5
LAUNCH_TIMEOUT=420
UIAUTOMATOR_CHECK_THRESHOLD=70

# ==================== LOCKING SYSTEM ====================
# Fix: Check for flock, fallback to mkdir if needed
USE_FLOCK=true
if ! command -v flock >/dev/null 2>&1; then
    USE_FLOCK=false
    mkdir -p "$LOCK_DIR"
fi

acquire_lock() {
    local pkg=$1
    local lockfile="$LOCK_DIR/${pkg}.lock"
    
    if [ "$USE_FLOCK" = true ]; then
        exec 201>"$lockfile"
        flock -x 201 || return 1
        return 0
    else
        # Fallback: mkdir-based lock (atomic on most filesystems)
        if mkdir "$lockfile" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

release_lock() {
    local pkg=$1
    local lockfile="$LOCK_DIR/${pkg}.lock"
    
    if [ "$USE_FLOCK" = true ]; then
        flock -u 201
        exec 201>&-
    else
        rmdir "$lockfile" 2>/dev/null || true
    fi
}

# ==================== LOGGING ====================
log_msg() {
    local level=$1
    local msg=$2
    local pkg=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -z "$pkg" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [$pkg] [$level] $msg" >> "$LOG_FILE"
    fi
}

# ==================== SETUP ====================
setup_wizard() {
    clear
    echo ""
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║   ROBLOX AUTO REJOIN V12 - ULTIMATE   ║${NC}"
    echo "${BLUE}║   Multi-Instance | Optimized | Stable ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${YELLOW}[1/5] Creating directories...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$QUEUE_DIR" "$CACHE_DIR" "$LOCK_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
    
    if [ "$USE_FLOCK" = true ]; then
        log_msg "SYSTEM" "V12 Setup started (flock available)"
    else
        log_msg "SYSTEM" "V12 Setup started (using mkdir fallback)"
    fi
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${YELLOW}[2/5] Scanning packages...${NC}"
    local packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo "${RED}✗ No Roblox found!${NC}"
        exit 1
    fi
    
    echo "${GREEN}✓ Found:${NC}"
    echo ""
    echo "$packages" | while read pkg; do
        local pids=$(pidof "$pkg" 2>/dev/null)
        if [ -n "$pids" ]; then
            local count=$(echo "$pids" | wc -w)
            echo "  ${GREEN}✓${NC} $pkg ($count instances)"
        else
            echo "  ${RED}✗${NC} $pkg"
        fi
    done
    echo ""
    
    echo "${YELLOW}[3/5] Select tabs...${NC}"
    > "$TAB_LIST_FILE.tmp"
    
    echo "$packages" | while read pkg; do
        local pids=$(pidof "$pkg" 2>/dev/null)
        local default="n"
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
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
QUEUE_DIR="$QUEUE_DIR"
CACHE_DIR="$CACHE_DIR"
LOCK_DIR="$LOCK_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$LOG_FILE"
UI_DUMP="$UI_DUMP"
EOF
    echo "${GREEN}✓${NC}"
    echo ""
    
    echo "${YELLOW}[5/5] Setup aliases...${NC}"
    PROFILE="$HOME/.bashrc"
    [ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"
    
    if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
        cat >> "$PROFILE" << 'ALIAS'

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_v12.sh"
alias roblox-status="sh $HOME/.roblox_auto_rejoin/roblox_v12.sh status"
alias roblox-logs="sh $HOME/.roblox_auto_rejoin/roblox_v12.sh logs"
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
        echo "${GREEN}✓ V12 running!${NC}"
        echo "Dashboard: /sdcard/Download/roblox_dashboard.json"
    fi
    echo ""
}

# ==================== STATE MANAGEMENT ====================
init_state() {
    local pkg=$1
    local instance=$2
    
    local state_key="${pkg}_${instance}"
    local sf="$STATE_DIR/${state_key}.state"
    [ -f "$sf" ] && return
    
    cat > "$sf" << EOF
HEALTH_SCORE=100
CPU_TICKS=0
NET_BYTES=0
NET_FREEZE_COUNT=0
PROCESS_MISSING_COUNT=0
RESTART_PENDING=0
LAST_CHECK=$(date +%s)
LAST_RESTART=0
RESTART_COUNT=0
LAST_ERROR=NONE
LAUNCH_TIME=$(date +%s)
EOF
}

read_state() {
    local pkg=$1
    local instance=$2
    local key=$3
    
    local state_key="${pkg}_${instance}"
    grep "^${key}=" "$STATE_DIR/${state_key}.state" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local pkg=$1
    local instance=$2
    local key=$3
    local value=$4
    
    local state_key="${pkg}_${instance}"
    local sf="$STATE_DIR/${state_key}.state"
    
    if grep -q "^${key}=" "$sf" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|g" "$sf"
    else
        echo "${key}=${value}" >> "$sf"
    fi
}

# ==================== DISCOVERY - MULTI-INSTANCE FIX ====================
discover_instances() {
    local pkg=$1
    pidof "$pkg" 2>/dev/null | tr ' ' '\n'
}

# ==================== FOREGROUND CACHE ====================
get_cached_foreground() {
    local now=$(date +%s)
    local cache_time=$(cat "$FG_CACHE.time" 2>/dev/null)
    [ -z "$cache_time" ] && cache_time=0
    
    if [ $((now - cache_time)) -lt "$FG_CACHE_TTL" ]; then
        cat "$FG_CACHE" 2>/dev/null
        return 0
    fi
    return 1
}

update_foreground_cache() {
    local fg=$1
    echo "$fg" > "$FG_CACHE"
    echo "$(date +%s)" > "$FG_CACHE.time"
}

detect_foreground_app() {
    # Check cache first
    local cached=$(get_cached_foreground)
    [ -n "$cached" ] && { echo "$cached"; return; }
    
    # Layer 1: Window manager (fastest)
    local fg=$(dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    [ -n "$fg" ] && [ "$fg" != "null" ] && { update_foreground_cache "$fg"; echo "$fg"; return; }
    
    # Layer 2: Activity top
    fg=$(dumpsys activity top 2>/dev/null | grep -E "TASK" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    [ -n "$fg" ] && { update_foreground_cache "$fg"; echo "$fg"; return; }
    
    # Layer 3: Activity stack (slowest)
    fg=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | grep -oE "com\.[a-zA-Z0-9._]+" | head -1)
    [ -n "$fg" ] && { update_foreground_cache "$fg"; echo "$fg"; return; }
    
    echo ""
}

is_foreground() {
    local pkg=$1
    local fg=$(detect_foreground_app)
    [ "$fg" = "$pkg" ] && echo "true" || echo "false"
}

# ==================== CPU ANALYSIS ====================
get_cpu_ticks() {
    local pid=$1
    local stat=$(cat "/proc/$pid/stat" 2>/dev/null)
    if [ -n "$stat" ]; then
        local utime=$(echo "$stat" | awk '{print $14}')
        local stime=$(echo "$stat" | awk '{print $15}')
        echo $((utime + stime))
    else
        echo "0"
    fi
}

# ==================== NETWORK - FIX xt_qtaguid ====================
get_net_bytes() {
    local pkg=$1
    local pid=$2
    
    local uid=$(grep "^Uid:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    [ -z "$uid" ] && echo "-1" && return
    
    # Try uid_stat first
    if [ -f "/proc/uid_stat/$uid/tcp_rcv" ]; then
        local rcv=$(cat "/proc/uid_stat/$uid/tcp_rcv" 2>/dev/null)
        local snd=$(cat "/proc/uid_stat/$uid/tcp_snd" 2>/dev/null)
        echo $((rcv + snd))
        return
    fi
    
    # Fallback xt_qtaguid - fix format (UID is column 4)
    if [ -f "/proc/net/xt_qtaguid/stats" ]; then
        local total=$(awk -v u="$uid" '$4==u {sum+=$6+$8} END {print sum}' /proc/net/xt_qtaguid/stats 2>/dev/null)
        [ -n "$total" ] && [ "$total" -gt 0 ] && { echo "$total"; return; }
    fi
    
    echo "-1"
}

# ==================== UI ERROR - FOREGROUND CHECK ====================
detect_ui_error() {
    local pkg=$1
    local score=$2
    
    # Only dump if low score AND foreground
    [ "$score" -ge "$UIAUTOMATOR_CHECK_THRESHOLD" ] && return 1
    
    local is_fg=$(is_foreground "$pkg")
    [ "$is_fg" != "true" ] && return 1
    
    uiautomator dump "$UI_DUMP" 2>/dev/null
    [ ! -f "$UI_DUMP" ] && return 1
    
    local code=$(grep -oE "Error Code: [0-9]{3}" "$UI_DUMP" | head -1 | grep -oE "[0-9]{3}")
    [ -n "$code" ] && echo "$code" && return 0
    
    return 1
}

# ==================== ANR DETECTION ====================
detect_anr() {
    local pid=$1
    dumpsys activity processes 2>/dev/null | \
    grep -A 5 "pid $pid" | \
    grep -q "not responding"
}

# ==================== HEALTH SCORING ====================
calculate_health_score() {
    local pkg=$1
    local pid=$2
    local is_fg=$3
    
    local score=0
    local now=$(date +%s)
    
    [ -d "/proc/$pid" ] || return 0
    
    local status=$(cat "/proc/$pid/status" 2>/dev/null)
    [ -z "$status" ] && return 0
    
    local state=$(echo "$status" | grep "^State:" | awk '{print $2}')
    local rss=$(echo "$status" | grep "^VmRSS:" | awk '{print $2}')
    local threads=$(echo "$status" | grep "^Threads:" | awk '{print $2}')
    
    [ -z "$rss" ] && rss=0
    [ -z "$threads" ] && threads=0
    
    # State scoring
    case "$state" in
        R) score=$((score + 25)) ;;
        S) score=$((score + 20)) ;;
        D) score=$((score + 5)) ;;
    esac
    
    # Memory scoring
    [ "$rss" -gt 102400 ] && score=$((score + 25)) || score=$((score + 10))
    
    # Thread scoring
    [ "$threads" -gt 5 ] && score=$((score + 20)) || score=$((score + 5))
    
    # CPU check
    local current_ticks=$(get_cpu_ticks "$pid")
    local last_ticks=$(read_state "$pkg" "$pid" "CPU_TICKS")
    [ -z "$last_ticks" ] && last_ticks=0
    
    if [ "$current_ticks" -ne "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        score=$((score + 20))
    elif [ "$is_fg" = "true" ]; then
        score=$((score + 5))
    fi
    write_state "$pkg" "$pid" "CPU_TICKS" "$current_ticks"
    
    # Network check
    local current_net=$(get_net_bytes "$pkg" "$pid")
    local last_net=$(read_state "$pkg" "$pid" "NET_BYTES")
    [ -z "$last_net" ] && last_net=0
    
    if [ "$current_net" -eq -1 ]; then
        [ "$current_ticks" -gt "$last_ticks" ] && score=$((score + 15))
    else
        if [ "$current_net" -ne "$last_net" ]; then
            score=$((score + 20))
            write_state "$pkg" "$pid" "NET_FREEZE_COUNT" "0"
        else
            local freeze=$(read_state "$pkg" "$pid" "NET_FREEZE_COUNT")
            [ -z "$freeze" ] && freeze=0
            freeze=$((freeze + 1))
            write_state "$pkg" "$pid" "NET_FREEZE_COUNT" "$freeze"
            
            [ "$freeze" -ge "$NET_STAGNANT_THRESHOLD" ] && score=$((score - 30))
        fi
        write_state "$pkg" "$pid" "NET_BYTES" "$current_net"
    fi
    
    # Launch timeout
    local launch_time=$(read_state "$pkg" "$pid" "LAUNCH_TIME")
    [ -z "$launch_time" ] && launch_time=$now
    local elapsed=$((now - launch_time))
    if [ "$elapsed" -gt "$LAUNCH_TIMEOUT" ]; then
        local freeze=$(read_state "$pkg" "$pid" "NET_FREEZE_COUNT")
        [ -z "$freeze" ] && freeze=0
        [ "$freeze" -ge "$NET_STAGNANT_THRESHOLD" ] && score=$((score - 50))
    fi
    
    # Bounds
    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 100 ] && score=100
    
    echo "$score"
}

score_to_state() {
    local score=$1
    [ "$score" -ge 80 ] && echo "ACTIVE" && return
    [ "$score" -ge 50 ] && echo "SUSPECT" && return
    echo "DEAD"
}

# ==================== QUEUE - DUPLICATE FIX ====================
enqueue_restart() {
    local pkg=$1
    local instance=$2
    local error=$3
    
    # Check if already pending restart
    local pending=$(read_state "$pkg" "$instance" "RESTART_PENDING")
    [ "$pending" = "1" ] && { log_msg "SKIP" "Restart already pending" "$pkg"; return; }
    
    acquire_lock "$pkg" || return
    write_state "$pkg" "$instance" "RESTART_PENDING" "1"
    release_lock
    
    local qf="$QUEUE_DIR/${pkg}_${instance}_$(date +%s).queue"
    cat > "$qf" << EOF
PKG=$pkg
PID=$instance
ERROR=$error
TIME=$(date +%s)
EOF
    log_msg "QUEUE" "Enqueued - Error: $error" "$pkg"
}

process_queue() {
    local first=$(find "$QUEUE_DIR" -name "*.queue" -type f 2>/dev/null | head -1)
    [ -z "$first" ] && return
    
    local processing="${first}.processing"
    mv "$first" "$processing" 2>/dev/null || return
    
    local pkg=$(grep "^PKG=" "$processing" | cut -d'=' -f2)
    local pid=$(grep "^PID=" "$processing" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$processing" | cut -d'=' -f2)
    
    do_restart "$pkg" "$pid" "$error"
    rm -f "$processing"
}

# ==================== RESTART ====================
check_cooldown() {
    local pkg=$1
    local instance=$2
    local now=$(date +%s)
    
    local last_restart=$(read_state "$pkg" "$instance" "LAST_RESTART")
    [ -z "$last_restart" ] && last_restart=0
    
    [ $((now - last_restart)) -ge "$PROCESS_RECOVERY_COOLDOWN" ] && return 0 || return 1
}

do_restart() {
    local pkg=$1
    local pid=$2
    local error=$3
    
    acquire_lock "$pkg" || return 1
    
    init_state "$pkg" "$pid"
    
    local restart=$(read_state "$pkg" "$pid" "RESTART_COUNT")
    [ -z "$restart" ] && restart=0
    [ "$restart" -gt "$MAX_RESTARTS" ] && {
        log_msg "BANNED" "Max restarts exceeded" "$pkg"
        release_lock
        return 1
    }
    
    restart=$((restart + 1))
    write_state "$pkg" "$pid" "RESTART_COUNT" "$restart"
    write_state "$pkg" "$pid" "LAST_RESTART" "$(date +%s)"
    write_state "$pkg" "$pid" "LAST_ERROR" "$error"
    write_state "$pkg" "$pid" "LAUNCH_TIME" "$(date +%s)"
    write_state "$pkg" "$pid" "PROCESS_MISSING_COUNT" "0"
    write_state "$pkg" "$pid" "RESTART_PENDING" "0"
    
    log_msg "RESTART" "Error: $error (Count: $restart)" "$pkg"
    
    release_lock
    
    # Kill
    [ "$pid" -ne 0 ] && [ -d "/proc/$pid" ] && {
        kill "$pid" 2>/dev/null
        sleep 1
        kill -9 "$pid" 2>/dev/null
    }
    
    sleep 1
    
    # Start
    am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
}

# ==================== MONITOR ====================
monitor_instance() {
    local pkg=$1
    local pid=$2
    
    acquire_lock "$pkg" || return
    init_state "$pkg" "$pid"
    release_lock
    
    if ! check_cooldown "$pkg" "$pid"; then
        return
    fi
    
    # Check if still alive
    [ ! -d "/proc/$pid" ] && {
        local missing=$(read_state "$pkg" "$pid" "PROCESS_MISSING_COUNT")
        [ -z "$missing" ] && missing=0
        missing=$((missing + 1))
        
        acquire_lock "$pkg" || return
        write_state "$pkg" "$pid" "PROCESS_MISSING_COUNT" "$missing"
        release_lock
        
        [ "$missing" -ge "$PROCESS_MISSING_THRESHOLD" ] && {
            enqueue_restart "$pkg" "$pid" "PROCESS_MISSING"
        }
        return
    }
    
    # Reset missing
    acquire_lock "$pkg" || return
    write_state "$pkg" "$pid" "PROCESS_MISSING_COUNT" "0"
    release_lock
    
    # Health check
    local is_fg=$(is_foreground "$pkg")
    local score=$(calculate_health_score "$pkg" "$pid" "$is_fg")
    local state=$(score_to_state "$score")
    
    acquire_lock "$pkg" || return
    write_state "$pkg" "$pid" "HEALTH_SCORE" "$score"
    release_lock
    
    case "$state" in
        ACTIVE)
            local ui_error=$(detect_ui_error "$pkg" "$score")
            [ -n "$ui_error" ] && enqueue_restart "$pkg" "$pid" "ERROR_$ui_error"
            
            detect_anr "$pid" && enqueue_restart "$pkg" "$pid" "ANR"
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
    local pkg=$1
    
    local pids=$(discover_instances "$pkg")
    
    if [ -z "$pids" ]; then
        log_msg "NO_INSTANCE" "No running instance" "$pkg"
        return
    fi
    
    echo "$pids" | while read -r pid; do
        [ -z "$pid" ] && continue
        monitor_instance "$pkg" "$pid" &
    done
}

monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && exit 1
    
    log_msg "SYSTEM" "V12 Monitor started"
    
    while true; do
        while read -r pkg; do
            monitor_tab "$pkg" &
        done < "$TAB_LIST_FILE"
        
        wait
        process_queue
        update_dashboard
        
        sleep "$CHECK_INTERVAL"
    done
}

# ==================== DASHBOARD ====================
update_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local active=0
    local suspect=0
    local dead=0
    
    echo "{" > "${DASHBOARD_JSON}.tmp"
    echo "  \"timestamp\": \"$timestamp\"," >> "${DASHBOARD_JSON}.tmp"
    echo "  \"instances\": [" >> "${DASHBOARD_JSON}.tmp"
    
    local first=true
    while read -r pkg; do
        for sf in "$STATE_DIR"/${pkg}_*.state; do
            [ ! -f "$sf" ] && continue
            
            local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
            local state=$(score_to_state "$score")
            local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
            local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
            
            case "$state" in
                ACTIVE) active=$((active + 1)) ;;
                SUSPECT) suspect=$((suspect + 1)) ;;
                DEAD) dead=$((dead + 1)) ;;
            esac
            
            [ "$first" = true ] && first=false || echo "," >> "${DASHBOARD_JSON}.tmp"
            
            local pid=$(basename "$sf" .state | cut -d'_' -f2-)
            cat >> "${DASHBOARD_JSON}.tmp" <<EOF
    {
      "package": "$pkg",
      "pid": "$pid",
      "state": "$state",
      "health_score": $score,
      "last_error": "$error",
      "restarts": $restart
    }
EOF
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
    status)
        [ ! -f "$CONFIG_FILE" ] && { echo "Not setup"; exit 1; }
        echo "${BLUE}V12 Status:${NC}"
        while read -r pkg; do
            for sf in "$STATE_DIR"/${pkg}_*.state; do
                [ ! -f "$sf" ] && continue
                local pid=$(basename "$sf" .state | cut -d'_' -f2-)
                local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
                local state=$(score_to_state "$score")
                local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
                local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
                echo "  $pkg(PID:$pid) | $state ($score) | Error: $error | Restarts: $restart"
            done
        done < "$TAB_LIST_FILE"
        ;;
    logs)
        [ ! -f "$LOG_FILE" ] && { echo "No logs"; exit 1; }
        tail -n 30 "$LOG_FILE"
        ;;
    *)
        [ ! -f "$CONFIG_FILE" ] && setup_wizard || {
            echo "${GREEN}Starting V12...${NC}"
            nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
            sleep 2
            echo "${GREEN}✓ V12 Monitor running${NC}"
            echo "Dashboard: /sdcard/Download/roblox_dashboard.json"
        }
        ;;
esac
