#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V7 - ALL-IN-ONE
# 1 File duy nhất: Setup + Monitor + Rejoin
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
VERIFY_TIMEOUT=120

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

# ==================== SETUP MODE ====================
setup_mode() {
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${BLUE}║  ROBLOX AUTO REJOIN V7 - SETUP        ║${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Create directories
    echo "${YELLOW}[1/4] Creating directories...${NC}"
    mkdir -p "$INSTALL_DIR" "$STATE_DIR" "/sdcard/Download"
    : > "$LOG_FILE"
    log_msg "SYSTEM" "V7 All-in-One initialized"
    echo "${GREEN}[+] Done${NC}"
    echo ""
    
    # Detect packages
    echo "${YELLOW}[2/4] Scanning Roblox packages...${NC}"
    local packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo "${RED}[!] No Roblox found! Install first.${NC}"
        exit 1
    fi
    
    echo "${GREEN}[+] Found Roblox packages:${NC}"
    echo ""
    local count=0
    echo "$packages" | while IFS= read -r pkg; do
        count=$((count + 1))
        echo "    ${GREEN}$count.${NC} $pkg"
    done
    echo ""
    
    echo "$packages" > "$TAB_LIST_FILE"
    
    # Interactive menu
    echo "${YELLOW}[3/4] Interactive Setup${NC}"
    echo ""
    
    local selected_tabs=""
    local tab_count=0
    
    echo "$packages" | while IFS= read -r pkg; do
        tab_count=$((tab_count + 1))
        
        while true; do
            echo ""
            echo "${YELLOW}Tab $tab_count: $pkg${NC}"
            echo "  1. Yes - Monitor this tab"
            echo "  2. No - Skip this tab"
            echo "  3. Skip all - Use default (all tabs)"
            echo ""
            printf "${YELLOW}Choose (1-3): ${NC}"
            read -r choice
            
            case "$choice" in
                1)
                    echo "${GREEN}✓ Selected${NC}"
                    echo "$pkg" >> "$TAB_LIST_FILE.tmp"
                    break
                    ;;
                2)
                    echo "${YELLOW}⊘ Skipped${NC}"
                    break
                    ;;
                3)
                    echo "${GREEN}✓ Using all tabs${NC}"
                    cp "$TAB_LIST_FILE" "$TAB_LIST_FILE.tmp"
                    break 2
                    ;;
                *)
                    echo "${RED}Invalid input${NC}"
                    ;;
            esac
        done
    done
    
    # Use selected or all
    if [ -f "$TAB_LIST_FILE.tmp" ] && [ -s "$TAB_LIST_FILE.tmp" ]; then
        mv "$TAB_LIST_FILE.tmp" "$TAB_LIST_FILE"
    fi
    
    echo ""
    
    # Create config
    echo "${YELLOW}[4/4] Creating config...${NC}"
    cat > "$CONFIG_FILE" << EOF
# V7 Config
PLACE_ID="$PLACE_ID"
LINK="$LINK"
CHECK_INTERVAL=$CHECK_INTERVAL
MAX_RESTARTS=$MAX_RESTARTS
VERIFY_TIMEOUT=$VERIFY_TIMEOUT
INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$LOG_FILE"
DASHBOARD="$DASHBOARD_HTML"
EOF
    echo "${GREEN}[+] Done${NC}"
    echo ""
    
    # Create aliases
    PROFILE="$HOME/.bashrc"
    [ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"
    
    if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
        cat >> "$PROFILE" << 'ALIAS'

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_v7_allinone.sh start"
alias roblox-pause="sh $HOME/.roblox_auto_rejoin/roblox_v7_allinone.sh pause"
alias roblox-resume="sh $HOME/.roblox_auto_rejoin/roblox_v7_allinone.sh resume"
ALIAS
    fi
    
    # Show selected tabs
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo "${GREEN}Selected tabs:${NC}"
    echo ""
    cat "$TAB_LIST_FILE" | nl -v 1
    echo ""
    
    # Final instructions
    echo "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo "${GREEN}  ✅ SETUP COMPLETE!${NC}"
    echo "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "${YELLOW}NEXT STEPS:${NC}"
    echo ""
    echo "1. Open selected tabs in Roblox"
    echo "   ${GREEN}Open each + login to Blox Fruits${NC}"
    echo ""
    echo "2. Make sure you're IN-GAME"
    echo "   ${GREEN}Get into the game map (not lobby!)${NC}"
    echo ""
    echo "3. Start monitoring"
    echo "   ${GREEN}roblox-rejoin${NC}"
    echo ""
    echo "4. View dashboard"
    echo "   ${GREEN}File: /sdcard/Download/roblox_dashboard.html${NC}"
    echo ""
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    
    # Ask to continue
    echo ""
    printf "${YELLOW}Ready to start monitor? (y/n): ${NC}"
    read -r start_now
    
    if [ "$start_now" = "y" ] || [ "$start_now" = "Y" ]; then
        sleep 2
        monitor_mode
    else
        echo "${YELLOW}Setup saved. Run 'roblox-rejoin' to start monitor later.${NC}"
    fi
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

# ==================== REJOIN HANDLER ====================
do_rejoin() {
    local pkg=$1
    local error=$2
    
    init_tab_state "$pkg"
    
    local status=$(read_state "$pkg" "STATUS")
    [ "$status" = "PAUSED" ] && return 0
    [ "$status" = "BANNED" ] && return 0
    
    local restart_count=$(read_state "$pkg" "RESTART_COUNT")
    
    case "$error" in
        # Soft rejoin
        277|279)
            log_msg "REJOIN" "Error $error - Soft" "$pkg"
            sleep 5
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
        
        # Hard restart
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
        
        # ANR - Full reset
        ANR)
            log_msg "REJOIN" "ANR - Full reset" "$pkg"
            [ $restart_count -gt $MAX_RESTARTS ] && { write_state "$pkg" "STATUS" "BANNED"; return 1; }
            restart_count=$((restart_count + 1))
            write_state "$pkg" "RESTART_COUNT" "$restart_count"
            
            am force-stop "$pkg" 2>/dev/null
            sleep 1
            pm trim-caches 999M > /dev/null 2>&1
            sleep 3
            am start -a android.intent.action.VIEW -d "$LINK" -p "$pkg" 2>/dev/null
            ;;
        
        # Permanent - Ban
        264|267|273)
            log_msg "REJOIN" "Permanent error $error - Ban" "$pkg"
            write_state "$pkg" "STATUS" "BANNED"
            write_state "$pkg" "LAST_ERROR" "$error"
            return 1
            ;;
        
        # Normal crash
        *)
            log_msg "REJOIN" "Crash - Normal restart" "$pkg"
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
    
    # Check if process alive
    local pid=$(pidof "$pkg" 2>/dev/null)
    
    if [ -z "$pid" ]; then
        log_msg "CRASH" "Process dead" "$pkg"
        do_rejoin "$pkg" "CRASH"
        return 0
    fi
    
    # Update last seen
    write_state "$pkg" "LAST_SEEN" "$(date +%s)"
    
    # Check for UI errors
    local error=$(detect_ui_error)
    
    if [ -n "$error" ]; then
        log_msg "ERROR" "UI error: $error" "$pkg"
        do_rejoin "$pkg" "$error"
        return 0
    fi
}

# ==================== GENERATE DASHBOARD ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local active=0
    local idle=0
    local dead=0
    local banned=0
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
            local uptime=$(grep "^UPTIME=" "$state_file" | cut -d'=' -f2)
            local now=$(date +%s)
            local elapsed=$((now - uptime))
            
            local uptime_str=""
            if [ $elapsed -ge 3600 ]; then
                uptime_str="$((elapsed/3600))h $(($(($elapsed % 3600))/60))m"
            else
                uptime_str="$((elapsed/60))m"
            fi
            
            local icon="▶"
            local color="4ade80"
            
            case $status in
                ACTIVE) icon="▶"; color="4ade80"; active=$((active + 1)) ;;
                IDLE) icon="⏳"; color="fbbf24"; idle=$((idle + 1)) ;;
                DEAD) icon="💀"; color="f87171"; dead=$((dead + 1)) ;;
                BANNED) icon="🚫"; color="ef4444"; banned=$((banned + 1)) ;;
            esac
            
            account_html="${account_html}<div style='padding:10px;margin:5px;background:#2a2a2a;border-left:4px solid #$color;'><b>$icon $pkg</b> [$status] Error: $error Restarts: $restart Uptime: $uptime_str</div>"
        done
    fi
    
    cat > "$DASHBOARD_HTML" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Roblox V7</title>
    <style>
        body { font-family: Arial; background: #1a1a1a; color: #fff; padding: 20px; }
        h1 { color: #4ade80; margin: 0; }
        .info { color: #aaa; font-size: 12px; }
        .stats { display: flex; gap: 10px; margin: 15px 0; }
        .stat { padding: 10px 15px; background: #2a2a2a; border-radius: 5px; }
        .stat b { display: block; color: #4ade80; }
        .tabs { margin-top: 20px; }
    </style>
</head>
<body>
    <h1>🎮 Roblox V7 Monitor</h1>
    <p class="info">Updated: $timestamp</p>
    
    <div class="stats">
        <div class="stat">Active<br><b style="color:#4ade80;">$active</b></div>
        <div class="stat">Idle<br><b style="color:#fbbf24;">$idle</b></div>
        <div class="stat">Dead<br><b style="color:#f87171;">$dead</b></div>
        <div class="stat">Banned<br><b style="color:#ef4444;">$banned</b></div>
    </div>
    
    <div class="tabs">
        $account_html
    </div>
    
    <script>
        setTimeout(() => location.reload(), 10000);
    </script>
</body>
</html>
EOF
}

# ==================== MONITOR MODE ====================
monitor_mode() {
    clear
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo "${GREEN}  ROBLOX MONITOR V7 - RUNNING${NC}"
    echo "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    
    [ ! -f "$TAB_LIST_FILE" ] && { echo "${RED}[!] Run setup first${NC}"; exit 1; }
    
    echo "[+] Monitoring tabs..."
    cat "$TAB_LIST_FILE" | nl -v 1
    echo ""
    echo "Dashboard: /sdcard/Download/roblox_dashboard.html"
    echo "Logs: $LOG_FILE"
    echo ""
    
    # Main loop
    while true; do
        cat "$TAB_LIST_FILE" | while IFS= read -r pkg; do
            monitor_tab "$pkg" &
        done
        
        wait
        generate_dashboard
        
        sleep $CHECK_INTERVAL
    done
}

# ==================== COMMAND MODE ====================
case "$1" in
    setup|init)
        setup_mode
        exit 0
        ;;
    
    pause)
        if [ -z "$2" ]; then
            echo "Usage: $0 pause <package>"
            exit 1
        fi
        write_state "$2" "STATUS" "PAUSED"
        echo "[+] Paused: $2"
        exit 0
        ;;
    
    resume)
        if [ -z "$2" ]; then
            echo "Usage: $0 resume <package>"
            exit 1
        fi
        write_state "$2" "STATUS" "ACTIVE"
        echo "[+] Resumed: $2"
        exit 0
        ;;
    
    status)
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "[!] Not setup yet"
            exit 1
        fi
        echo "Tab Status:"
        if [ -f "$TAB_LIST_FILE" ]; then
            cat "$TAB_LIST_FILE" | while IFS= read -r pkg; do
                local state=$(read_state "$pkg" "STATUS")
                local error=$(read_state "$pkg" "LAST_ERROR")
                local restart=$(read_state "$pkg" "RESTART_COUNT")
                echo "  $pkg | $state | Error: $error | Restarts: $restart"
            done
        fi
        exit 0
        ;;
    
    logs)
        tail -n 50 "$LOG_FILE"
        exit 0
        ;;
    
    *)
        # Default: Check if setup done
        if [ ! -f "$CONFIG_FILE" ]; then
            setup_mode
        else
            monitor_mode
        fi
        ;;
esac
