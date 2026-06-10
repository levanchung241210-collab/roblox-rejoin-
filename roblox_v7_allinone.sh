#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V9 - PRODUCTION ARCHITECTURE
# 7 Modules + Score System + Restart Queue
# ===============================================

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

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"
CHECK_INTERVAL=15
MAX_RESTARTS=10
MAX_RESTARTS_PER_HOUR=20

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
    echo "${BLUE}║  ROBLOX AUTO REJOIN V9 - SETUP        ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${YELLOW}[1/5] Creating directories...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$QUEUE_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
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
        local pid=$(pidof "$pkg" 2>/dev/null)
        [ -n "$pid" ] && echo "  ${GREEN}✓${NC} $pkg" || echo "  ${RED}✗${NC} $pkg"
    done
    echo ""
    
    echo "${YELLOW}[3/5] Select tabs...${NC}"
    > "$TAB_LIST_FILE.tmp"
    
    echo "$packages" | while read pkg; do
        local pid=$(pidof "$pkg" 2>/dev/null)
        local default="n"
        [ -n "$pid" ] && default="y"
        
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
MAX_RESTARTS_PER_HOUR=$MAX_RESTARTS_PER_HOUR
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
QUEUE_DIR="$QUEUE_DIR"
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

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_v9.sh"
alias roblox-status="sh $HOME/.roblox_auto_rejoin/roblox_v9.sh status"
alias roblox-logs="sh $HOME/.roblox_auto_rejoin/roblox_v9.sh logs"
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
        echo "${GREEN}✓ Monitor running!${NC}"
        echo "Dashboard: /sdcard/Download/roblox_dashboard.html"
    fi
    echo ""
}

# ==================== MODULE 1: STATE CACHE ====================
init_state() {
    local pkg=$1
    local sf="$STATE_DIR/${pkg}.state"
    [ -f "$sf" ] && return
    
    cat > "$sf" << EOF
HEALTH_SCORE=100
LAST_CHECK=$(date +%s)
LAST_UI=$(date +%s)
LAST_ERROR=NONE
RESTART_COUNT=0
RESTART_HOUR=$(date +%s)
RESTARTS_THIS_HOUR=0
EOF
}

read_state() {
    local pkg=$1
    local key=$2
    grep "^${key}=" "$STATE_DIR/${pkg}.state" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local pkg=$1
    local key=$2
    local value=$3
    local sf="$STATE_DIR/${pkg}.state"
    
    if grep -q "^${key}=" "$sf" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|g" "$sf"
    else
        echo "${key}=${value}" >> "$sf"
    fi
}

# ==================== MODULE 2: ACTIVITY DETECTOR ====================
detect_activity() {
    local pkg=$1
    dumpsys activity activities 2>/dev/null | grep -q "$pkg"
}

# ==================== MODULE 3: TASK DETECTOR ====================
detect_task() {
    local pkg=$1
    dumpsys activity recents 2>/dev/null | grep -q "$pkg"
}

# ==================== MODULE 4: PID DETECTOR ====================
check_pid() {
    local pkg=$1
    pidof "$pkg" 2>/dev/null
}

# ==================== MODULE 5: UI ERROR DETECTOR ====================
detect_ui_error() {
    local pkg=$1
    
    # Only dump if app is foreground (to avoid overhead)
    uiautomator dump "$UI_DUMP" 2>/dev/null
    [ ! -f "$UI_DUMP" ] && return 1
    
    # Extract error code
    grep -oE "Error Code: [0-9]{3}" "$UI_DUMP" | head -1 | grep -oE "[0-9]{3}"
}

# ==================== MODULE 6: ANR DETECTOR ====================
detect_anr() {
    local pkg=$1
    
    dumpsys activity processes 2>/dev/null | \
    grep -A 20 "$pkg" | \
    grep -q "not responding\|NOT RESPONDING"
}

# ==================== MODULE 7: SCORE ENGINE ====================
calculate_score() {
    local pkg=$1
    local score=0
    
    # PID check (+20)
    [ -n "$(check_pid "$pkg")" ] && score=$((score + 20))
    
    # Activity check (+30)
    detect_activity "$pkg" && score=$((score + 30))
    
    # Task check (+20)
    detect_task "$pkg" && score=$((score + 20))
    
    # Memory check (+20)
    dumpsys activity processes 2>/dev/null | \
    grep -A 5 "$pkg" | \
    grep -q "TOP\|FOREGROUND\|VISIBLE" && score=$((score + 20))
    
    # UI check (+10) - only if foreground
    local error=$(detect_ui_error "$pkg")
    if [ -z "$error" ]; then
        score=$((score + 10))
    fi
    
    echo $score
}

score_to_state() {
    local score=$1
    
    if [ $score -ge 80 ]; then
        echo "ACTIVE"
    elif [ $score -ge 50 ]; then
        echo "SUSPECT"
    else
        echo "DEAD"
    fi
}

# ==================== MODULE 8: RESTART QUEUE ====================
enqueue_restart() {
    local pkg=$1
    local error=$2
    
    local qf="$QUEUE_DIR/${pkg}.queue"
    cat > "$qf" << EOF
PKG=$pkg
ERROR=$error
TIME=$(date +%s)
EOF
    log_msg "QUEUE" "Enqueued" "$pkg"
}

process_queue() {
    # Process 1 restart per cycle
    local first_queue=$(find "$QUEUE_DIR" -name "*.queue" -type f | head -1)
    [ -z "$first_queue" ] && return
    
    local pkg=$(grep "^PKG=" "$first_queue" | cut -d'=' -f2)
    local error=$(grep "^ERROR=" "$first_queue" | cut -d'=' -f2)
    
    do_restart "$pkg" "$error"
    rm -f "$first_queue"
}

# ==================== RESTART HANDLER ====================
do_restart() {
    local pkg=$1
    local error=$2
    
    init_state "$pkg"
    
    local restart=$(read_state "$pkg" "RESTART_COUNT")
    [ $restart -gt $MAX_RESTARTS ] && return 1
    
    restart=$((restart + 1))
    write_state "$pkg" "RESTART_COUNT" "$restart"
    write_state "$pkg" "LAST_ERROR" "$error"
    
    log_msg "RESTART" "Error $error" "$pkg"
    
    case "$error" in
        277|279) sleep 3 ;;
        268|271) sleep 1 ;;
        ANR) sleep 2 ;;
    esac
    
    am force-stop "$pkg" 2>/dev/null
    sleep 1
    am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
    
    write_state "$pkg" "LAST_CHECK" "$(date +%s)"
}

# ==================== MONITOR LOGIC ====================
monitor_tab() {
    local pkg=$1
    
    init_state "$pkg"
    
    # Calculate health score
    local score=$(calculate_score "$pkg")
    local state=$(score_to_state $score)
    
    write_state "$pkg" "HEALTH_SCORE" "$score"
    
    case $state in
        ACTIVE)
            # Check for UI error
            local error=$(detect_ui_error "$pkg")
            if [ -n "$error" ]; then
                log_msg "ERROR" "UI Error $error" "$pkg"
                enqueue_restart "$pkg" "$error"
            fi
            
            # Check for ANR
            if detect_anr "$pkg"; then
                log_msg "ANR" "Detected" "$pkg"
                enqueue_restart "$pkg" "ANR"
            fi
            ;;
        
        SUSPECT)
            # Wait for next check
            log_msg "SUSPECT" "Score: $score" "$pkg"
            ;;
        
        DEAD)
            log_msg "DEAD" "Score: $score" "$pkg"
            enqueue_restart "$pkg" "CRASH"
            ;;
    esac
}

monitor_loop() {
    [ ! -f "$TAB_LIST_FILE" ] && exit 1
    
    log_msg "SYSTEM" "V9 Monitor started"
    
    while true; do
        # Monitor all tabs
        while read -r pkg; do
            monitor_tab "$pkg" &
        done < "$TAB_LIST_FILE"
        
        wait
        
        # Process restart queue
        process_queue
        
        # Generate dashboard
        generate_dashboard
        
        sleep $CHECK_INTERVAL
    done
}

# ==================== DASHBOARD ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local active=0
    local suspect=0
    local dead=0
    local html=""
    
    while read -r pkg; do
        local sf="$STATE_DIR/${pkg}.state"
        [ ! -f "$sf" ] && continue
        
        local score=$(grep "^HEALTH_SCORE=" "$sf" | cut -d'=' -f2)
        local state=$(score_to_state $score)
        local error=$(grep "^LAST_ERROR=" "$sf" | cut -d'=' -f2)
        local restart=$(grep "^RESTART_COUNT=" "$sf" | cut -d'=' -f2)
        
        case $state in
            ACTIVE) active=$((active + 1)); color="4ade80" ;;
            SUSPECT) suspect=$((suspect + 1)); color="fbbf24" ;;
            DEAD) dead=$((dead + 1)); color="f87171" ;;
        esac
        
        html="${html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>$pkg</b> [$state] Score:$score Error:$error Restarts:$restart</div>"
    done < "$TAB_LIST_FILE"
    
    cat > "$DASHBOARD_HTML" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Roblox V9</title><style>body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px}h1{color:#4ade80}.stat{display:inline-block;margin:10px;padding:10px 15px;background:#2a2a2a;border-radius:5px}</style></head><body><h1>🎮 Roblox V9 - Score System</h1><p>$timestamp</p><div class="stat">Active: <b style="color:#4ade80;">$active</b></div><div class="stat">Suspect: <b style="color:#fbbf24;">$suspect</b></div><div class="stat">Dead: <b style="color:#f87171;">$dead</b></div><div style="margin-top:20px;">$html</div><script>setTimeout(()=>location.reload(),15000)</script></body></html>
EOF
}

# ==================== MAIN ====================
case "$1" in
    setup) setup_wizard ;;
    monitor) monitor_loop ;;
    status)
        [ ! -f "$CONFIG_FILE" ] && { echo "Not setup"; exit 1; }
        echo "Status:"
        while read -r pkg; do
            local score=$(read_state "$pkg" "HEALTH_SCORE")
            local state=$(score_to_state $score)
            local error=$(read_state "$pkg" "LAST_ERROR")
            echo "  $pkg | $state (score:$score) | Error: $error"
        done < "$TAB_LIST_FILE"
        ;;
    logs)
        [ ! -f "$LOG_FILE" ] && { echo "No logs"; exit 1; }
        tail -n 20 "$LOG_FILE"
        ;;
    *)
        [ ! -f "$CONFIG_FILE" ] && setup_wizard || {
            nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
            sleep 1
            echo "${GREEN}✓ V9 Monitor running${NC}"
        }
        ;;
esac
