#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V7 - SIMPLE & CLEAR
# Show everything step by step
# ===============================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$INSTALL_DIR/state"
CONFIG_FILE="$INSTALL_DIR/config.conf"
TAB_LIST_FILE="$INSTALL_DIR/tabs.list"
LOG_FILE="$INSTALL_DIR/executor.log"
DASHBOARD_HTML="/sdcard/Download/roblox_dashboard.html"
UI_DUMP="/sdcard/ui_dump.xml"

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"
CHECK_INTERVAL=15
MAX_RESTARTS=10

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

# ==================== SETUP WIZARD ====================
setup_wizard() {
    clear
    
    echo ""
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║   ROBLOX AUTO REJOIN - SETUP WIZARD   ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Step 1: Create folders
    echo "${YELLOW}[STEP 1] Creating folders...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
    echo "${GREEN}✓ Folders created${NC}"
    echo "   $INSTALL_DIR"
    echo "   $STATE_DIR"
    echo ""
    
    # Step 2: Scan packages
    echo "${YELLOW}[STEP 2] Scanning Roblox packages...${NC}"
    local packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo "${RED}✗ No Roblox packages found!${NC}"
        echo "  Please install Roblox first"
        exit 1
    fi
    
    echo "${GREEN}✓ Found packages:${NC}"
    echo ""
    local count=0
    echo "$packages" | while IFS= read -r pkg; do
        count=$((count + 1))
        local pid=$(pidof "$pkg" 2>/dev/null)
        
        if [ -n "$pid" ]; then
            echo "  ${GREEN}$count. $pkg${NC} [RUNNING]"
        else
            echo "  ${RED}$count. $pkg${NC} [NOT RUNNING]"
        fi
    done
    echo ""
    
    # Save all packages first
    echo "$packages" > "$TAB_LIST_FILE"
    
    # Step 3: Choose which to monitor
    echo "${YELLOW}[STEP 3] Which tabs do you want to monitor?${NC}"
    echo ""
    echo "Pick each tab:"
    echo ""
    
    local selected=""
    local count=0
    
    echo "$packages" | while IFS= read -r pkg; do
        count=$((count + 1))
        local pid=$(pidof "$pkg" 2>/dev/null)
        
        # Auto-suggest running ones
        local suggestion="(y)"
        if [ -z "$pid" ]; then
            suggestion="(n)"
        fi
        
        while true; do
            printf "  $count. Monitor ${YELLOW}$pkg${NC}? $suggestion: "
            read -r choice
            
            # Use suggestion if empty
            if [ -z "$choice" ]; then
                if [ -z "$pid" ]; then
                    choice="n"
                else
                    choice="y"
                fi
            fi
            
            case "$choice" in
                y|Y)
                    echo "     ${GREEN}✓ Will monitor this${NC}"
                    echo "$pkg" >> "$TAB_LIST_FILE.tmp"
                    break
                    ;;
                n|N)
                    echo "     ${YELLOW}✗ Skip this${NC}"
                    break
                    ;;
                *)
                    echo "     ${RED}Type y or n${NC}"
                    ;;
            esac
        done
    done
    
    # Use selected or all if none selected
    if [ -f "$TAB_LIST_FILE.tmp" ] && [ -s "$TAB_LIST_FILE.tmp" ]; then
        mv "$TAB_LIST_FILE.tmp" "$TAB_LIST_FILE"
        echo ""
        echo "${GREEN}✓ Selected tabs:${NC}"
        cat "$TAB_LIST_FILE" | nl -v 1
    else
        echo ""
        echo "${YELLOW}! No tabs selected, using all${NC}"
    fi
    echo ""
    
    # Step 4: Create config
    echo "${YELLOW}[STEP 4] Creating config...${NC}"
    cat > "$CONFIG_FILE" << EOF
PLACE_ID="$PLACE_ID"
LINK="$LINK"
CHECK_INTERVAL=$CHECK_INTERVAL
MAX_RESTARTS=$MAX_RESTARTS
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$LOG_FILE"
DASHBOARD="$DASHBOARD_HTML"
EOF
    echo "${GREEN}✓ Config saved${NC}"
    echo "   $CONFIG_FILE"
    echo ""
    
    # Step 5: Setup aliases
    echo "${YELLOW}[STEP 5] Setting up shortcuts...${NC}"
    PROFILE="$HOME/.bashrc"
    [ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"
    
    if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
        cat >> "$PROFILE" << 'ALIAS'

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_v7_final.sh"
alias roblox-status="sh $HOME/.roblox_auto_rejoin/roblox_v7_final.sh status"
alias roblox-logs="sh $HOME/.roblox_auto_rejoin/roblox_v7_final.sh logs"
ALIAS
        echo "${GREEN}✓ Aliases created${NC}"
        echo "   roblox-rejoin (start monitor)"
        echo "   roblox-status (check status)"
        echo "   roblox-logs (view logs)"
    else
        echo "${GREEN}✓ Aliases already exist${NC}"
    fi
    echo ""
    
    # Final confirmation
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    echo "${GREEN}✅ SETUP COMPLETE!${NC}"
    echo ""
    echo "Tabs to monitor:"
    cat "$TAB_LIST_FILE" | nl -v 1
    echo ""
    echo "Dashboard: /sdcard/Download/roblox_dashboard.html"
    echo "Logs: $LOG_FILE"
    echo ""
    
    # Ask to start
    printf "${YELLOW}Start monitoring now? (y/n): ${NC}"
    read -r choice
    
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        echo ""
        echo "${YELLOW}Starting monitor...${NC}"
        
        # Start in background
        nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
        
        sleep 2
        
        echo "${GREEN}✓ Monitor started!${NC}"
        echo ""
        echo "Monitor is running in background"
        echo "Roblox tabs can stay open"
        echo "Dashboard will update every 15 seconds"
        echo ""
        
        # Don't exit - show logs
        tail -n 5 "$LOG_FILE"
        
    else
        echo ""
        echo "${YELLOW}Setup saved!${NC}"
        echo "Run: ${GREEN}roblox-rejoin${NC} to start later"
    fi
    
    echo ""
}

# ==================== STATE MANAGEMENT ====================
init_tab_state() {
    local pkg=$1
    local state_file="$STATE_DIR/${pkg}.state"
    
    if [ ! -f "$state_file" ]; then
        cat > "$state_file" << EOF
STATUS=ACTIVE
LAST_SEEN=$(date +%s)
RESTART_COUNT=0
LAST_ERROR=NONE
UPTIME=$(date +%s)
EOF
        log_msg "INIT" "State initialized" "$pkg"
    fi
}

read_state() {
    local pkg=$1
    local key=$2
    local state_file="$STATE_DIR/${pkg}.state"
    
    grep "^${key}=" "$state_file" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local pkg=$1
    local key=$2
    local value=$3
    local state_file="$STATE_DIR/${pkg}.state"
    
    if [ -f "$state_file" ]; then
        if grep -q "^${key}=" "$state_file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|g" "$state_file"
        else
            echo "${key}=${value}" >> "$state_file"
        fi
    fi
}

# ==================== DETECT UI ERROR ====================
detect_ui_error() {
    uiautomator dump "$UI_DUMP" 2>/dev/null
    
    if [ ! -f "$UI_DUMP" ]; then
        return 1
    fi
    
    if grep -q "277\|Disconnected" "$UI_DUMP"; then echo "277"; return 0; fi
    if grep -q "268\|Connection" "$UI_DUMP"; then echo "268"; return 0; fi
    if grep -q "279\|Network" "$UI_DUMP"; then echo "279"; return 0; fi
    if grep -q "ANR\|responding" "$UI_DUMP"; then echo "ANR"; return 0; fi
    
    return 1
}

# ==================== REJOIN ====================
do_rejoin() {
    local pkg=$1
    local error=$2
    
    init_tab_state "$pkg"
    
    local status=$(read_state "$pkg" "STATUS")
    [ "$status" = "PAUSED" ] && return 0
    [ "$status" = "BANNED" ] && return 0
    
    local restart_count=$(read_state "$pkg" "RESTART_COUNT")
    
    case "$error" in
        277|279)
            log_msg "REJOIN" "Error $error - Soft" "$pkg"
            sleep 5
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
        
        268|271)
            log_msg "REJOIN" "Error $error - Restart" "$pkg"
            [ $restart_count -gt $MAX_RESTARTS ] && { write_state "$pkg" "STATUS" "BANNED"; return 1; }
            restart_count=$((restart_count + 1))
            write_state "$pkg" "RESTART_COUNT" "$restart_count"
            
            am force-stop "$pkg" 2>/dev/null
            sleep 1
            pm trim-caches 256M > /dev/null 2>&1
            sleep 2
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
        
        ANR)
            log_msg "REJOIN" "ANR - Reset" "$pkg"
            [ $restart_count -gt $MAX_RESTARTS ] && { write_state "$pkg" "STATUS" "BANNED"; return 1; }
            restart_count=$((restart_count + 1))
            write_state "$pkg" "RESTART_COUNT" "$restart_count"
            
            am force-stop "$pkg" 2>/dev/null
            sleep 1
            pm trim-caches 999M > /dev/null 2>&1
            sleep 3
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
        
        264|267|273)
            log_msg "REJOIN" "Permanent error $error - BAN" "$pkg"
            write_state "$pkg" "STATUS" "BANNED"
            return 1
            ;;
        
        *)
            log_msg "REJOIN" "Crash - Restart" "$pkg"
            [ $restart_count -gt $MAX_RESTARTS ] && { write_state "$pkg" "STATUS" "BANNED"; return 1; }
            restart_count=$((restart_count + 1))
            write_state "$pkg" "RESTART_COUNT" "$restart_count"
            
            am force-stop "$pkg" 2>/dev/null
            sleep 1
            pm trim-caches 256M > /dev/null 2>&1
            sleep 2
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
    esac
    
    write_state "$pkg" "UPTIME" "$(date +%s)"
    write_state "$pkg" "LAST_SEEN" "$(date +%s)"
    write_state "$pkg" "STATUS" "ACTIVE"
    [ -n "$error" ] && write_state "$pkg" "LAST_ERROR" "$error"
}

# ==================== MONITOR TAB ====================
monitor_tab() {
    local pkg=$1
    
    init_tab_state "$pkg"
    
    local status=$(read_state "$pkg" "STATUS")
    [ "$status" = "PAUSED" ] && return 0
    [ "$status" = "BANNED" ] && return 0
    
    local pid=$(pidof "$pkg" 2>/dev/null)
    
    if [ -z "$pid" ]; then
        log_msg "CRASH" "Dead" "$pkg"
        do_rejoin "$pkg" "CRASH"
        return 0
    fi
    
    write_state "$pkg" "LAST_SEEN" "$(date +%s)"
    
    local error=$(detect_ui_error)
    if [ -n "$error" ]; then
        log_msg "ERROR" "Error $error" "$pkg"
        do_rejoin "$pkg" "$error"
    fi
}

# ==================== MONITOR LOOP ====================
monitor_loop() {
    echo ""
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo "${GREEN}MONITOR RUNNING${NC}"
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    
    [ ! -f "$TAB_LIST_FILE" ] && { echo "No tabs configured"; exit 1; }
    
    echo "Monitoring:"
    cat "$TAB_LIST_FILE" | nl -v 1
    echo ""
    
    log_msg "SYSTEM" "Monitor started"
    
    while true; do
        cat "$TAB_LIST_FILE" | while IFS= read -r pkg; do
            monitor_tab "$pkg" &
        done
        
        wait
        
        sleep $CHECK_INTERVAL
    done
}

# ==================== DASHBOARD ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local active=0
    local dead=0
    local account_html=""
    
    if [ -f "$TAB_LIST_FILE" ]; then
        cat "$TAB_LIST_FILE" | while IFS= read -r pkg; do
            local state_file="$STATE_DIR/${pkg}.state"
            
            if [ ! -f "$state_file" ]; then
                continue
            fi
            
            local status=$(grep "^STATUS=" "$state_file" | cut -d'=' -f2)
            local error=$(grep "^LAST_ERROR=" "$state_file" | cut -d'=' -f2)
            local restart=$(grep "^RESTART_COUNT=" "$state_file" | cut -d'=' -f2)
            
            if [ "$status" = "ACTIVE" ]; then
                active=$((active + 1))
            else
                dead=$((dead + 1))
            fi
            
            account_html="${account_html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #4ade80;'><b>$pkg</b> [$status] Error: $error Restarts: $restart</div>"
        done
    fi
    
    cat > "$DASHBOARD_HTML" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Roblox Monitor</title>
    <style>
        body { font-family: Arial; background: #1a1a1a; color: #fff; padding: 20px; }
        h1 { color: #4ade80; }
        .stat { display: inline-block; margin: 10px; padding: 10px 15px; background: #2a2a2a; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>🎮 Roblox Monitor</h1>
    <p>Updated: $timestamp</p>
    <div class="stat">Active: <b style="color:#4ade80;">$active</b></div>
    <div class="stat">Dead: <b style="color:#f87171;">$dead</b></div>
    <div style='margin-top: 20px;'>
        $account_html
    </div>
    <script>
        setTimeout(() => location.reload(), 15000);
    </script>
</body>
</html>
EOF
}

# ==================== COMMAND ====================
case "$1" in
    setup)
        setup_wizard
        ;;
    
    monitor)
        monitor_loop
        ;;
    
    status)
        [ ! -f "$CONFIG_FILE" ] && { echo "Not setup yet"; exit 1; }
        echo "Status:"
        cat "$TAB_LIST_FILE" | while IFS= read -r pkg; do
            local state=$(read_state "$pkg" "STATUS")
            local error=$(read_state "$pkg" "LAST_ERROR")
            echo "  $pkg | $state | Error: $error"
        done
        ;;
    
    logs)
        [ ! -f "$LOG_FILE" ] && { echo "No logs yet"; exit 1; }
        tail -n 20 "$LOG_FILE"
        ;;
    
    *)
        # Default
        if [ ! -f "$CONFIG_FILE" ]; then
            setup_wizard
        else
            # Start monitor
            echo "${GREEN}Starting monitor...${NC}"
            nohup sh "$0" monitor > "$LOG_FILE" 2>&1 &
            sleep 1
            echo "${GREEN}✓ Monitor running${NC}"
            echo "Dashboard: /sdcard/Download/roblox_dashboard.html"
        fi
        ;;
esac
