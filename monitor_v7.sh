#!/system/bin/sh
# ===============================================
# ROBLOX MONITOR V7 - Simple + Efficient
# Activity detector + UI popup detector
# ===============================================

INSTALL_DIR="${INSTALL_DIR:-$HOME/.roblox_auto_rejoin}"
CONFIG_FILE="$INSTALL_DIR/config.conf"
TAB_LIST="$INSTALL_DIR/tabs.list"
STATE_DIR="$INSTALL_DIR/state"
LOG_FILE="$INSTALL_DIR/executor.log"
DASHBOARD_HTML="/sdcard/Download/roblox_dashboard.html"
UI_DUMP="/sdcard/ui_dump.xml"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# ==================== LOGGING ====================
log_msg() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

# ==================== INITIALIZE ====================
init_system() {
    mkdir -p "$STATE_DIR"
    : > "$LOG_FILE"
    log_msg "SYSTEM" "Monitor V7 started"
}

# ==================== DETECT ACTIVE TABS ====================
detect_active_tabs() {
    # Get list from tabs.list
    if [ ! -f "$TAB_LIST" ]; then
        log_msg "ERROR" "Tab list not found"
        return 1
    fi
    
    # Check which tabs have activity
    local active_tabs=""
    
    cat "$TAB_LIST" | while IFS= read -r pkg; do
        # Check if package has process
        local pid=$(pidof "$pkg" 2>/dev/null)
        
        if [ -z "$pid" ]; then
            continue
        fi
        
        # Check if in activity (dumpsys activity activities)
        local has_activity=$(dumpsys activity activities 2>/dev/null | grep -c "$pkg")
        
        if [ "$has_activity" -gt 0 ]; then
            echo "$pkg"
        fi
    done
}

# ==================== UI POPUP DETECTOR ====================
detect_ui_error() {
    local pkg=$1
    
    # Get UI dump
    uiautomator dump "$UI_DUMP" 2>/dev/null
    
    if [ ! -f "$UI_DUMP" ]; then
        return 1
    fi
    
    # Check for error codes in UI
    # Error 277 - Disconnected
    if grep -q "277\|Disconnected" "$UI_DUMP"; then
        echo "277"
        return 0
    fi
    
    # Error 268 - Connection lost
    if grep -q "268\|Connection lost" "$UI_DUMP"; then
        echo "268"
        return 0
    fi
    
    # Error 279 - Network issue
    if grep -q "279\|Network" "$UI_DUMP"; then
        echo "279"
        return 0
    fi
    
    # ANR - Not responding
    if grep -q "responding\|ANR" "$UI_DUMP"; then
        echo "ANR"
        return 0
    fi
    
    return 1
}

# ==================== STATE FILE ====================
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
    
    if grep -q "^${key}=" "$state_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|g" "$state_file"
    else
        echo "${key}=${value}" >> "$state_file"
    fi
}

# ==================== MONITOR LOGIC ====================
monitor_tab() {
    local pkg=$1
    
    init_tab_state "$pkg"
    
    local status=$(read_state "$pkg" "STATUS")
    
    # Skip if paused
    [ "$status" = "PAUSED" ] && return 0
    [ "$status" = "BANNED" ] && return 0
    
    # Check if process still alive
    local pid=$(pidof "$pkg" 2>/dev/null)
    
    if [ -z "$pid" ]; then
        log_msg "CRASH" "Process dead: $pkg"
        write_state "$pkg" "STATUS" "DEAD"
        # Queue for rejoin
        sh "$INSTALL_DIR/rejoin.sh" "$pkg"
        return 0
    fi
    
    # Update last_seen
    write_state "$pkg" "LAST_SEEN" "$(date +%s)"
    
    # Check for UI errors
    local error=$(detect_ui_error "$pkg")
    
    if [ -n "$error" ]; then
        log_msg "ERROR" "UI error $error: $pkg"
        write_state "$pkg" "LAST_ERROR" "$error"
        
        # Queue for rejoin with specific error handling
        sh "$INSTALL_DIR/rejoin.sh" "$pkg" "$error"
        return 0
    fi
    
    # Check heartbeat (no activity for 180s = suspicious)
    local last_seen=$(read_state "$pkg" "LAST_SEEN")
    local now=$(date +%s)
    local idle=$((now - last_seen))
    
    if [ $idle -gt 180 ]; then
        log_msg "WARN" "Idle too long: $pkg (${idle}s)"
        write_state "$pkg" "STATUS" "IDLE"
        return 0
    fi
}

# ==================== GENERATE DASHBOARD ====================
generate_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local active=0
    local idle=0
    local dead=0
    local account_html=""
    
    if [ -f "$TAB_LIST" ]; then
        cat "$TAB_LIST" | while IFS= read -r pkg; do
            local state_file="$STATE_DIR/${pkg}.state"
            
            if [ ! -f "$state_file" ]; then
                continue
            fi
            
            local status=$(grep "^STATUS=" "$state_file" | cut -d'=' -f2)
            local last_error=$(grep "^LAST_ERROR=" "$state_file" | cut -d'=' -f2)
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
            local color="green"
            
            case $status in
                ACTIVE) icon="▶"; color="green"; active=$((active + 1)) ;;
                IDLE) icon="⏳"; color="yellow"; idle=$((idle + 1)) ;;
                DEAD) icon="💀"; color="red"; dead=$((dead + 1)) ;;
            esac
            
            account_html="${account_html}<div style='padding:10px; margin:5px; background:#333; border-left:4px solid #$color;'><b>$pkg</b> [$status] Error: $last_error Uptime: $uptime_str</div>"
        done
    fi
    
    cat > "$DASHBOARD_HTML" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Roblox Monitor V7</title>
    <style>
        body { font-family: Arial; background: #1a1a1a; color: #fff; padding: 20px; }
        h1 { color: #4ade80; }
        .stat { display: inline-block; margin: 10px; padding: 10px; background: #333; border-radius: 5px; }
        .number { font-size: 24px; font-weight: bold; }
    </style>
</head>
<body>
    <h1>🎮 Roblox Monitor V7</h1>
    <p>Updated: $timestamp</p>
    
    <div style='margin: 20px 0;'>
        <div class='stat'>Active: <span class='number' style='color:#4ade80;'>$active</span></div>
        <div class='stat'>Idle: <span class='number' style='color:#fbbf24;'>$idle</span></div>
        <div class='stat'>Dead: <span class='number' style='color:#f87171;'>$dead</span></div>
    </div>
    
    <div style='margin-top: 20px;'>
        $account_html
    </div>
    
    <script>
        setTimeout(() => location.reload(), 10000);
    </script>
</body>
</html>
EOF
}

# ==================== MAIN LOOP ====================
main() {
    clear
    echo "═════════════════════════════════════════"
    echo "  ROBLOX MONITOR V7 - RUNNING"
    echo "═════════════════════════════════════════"
    echo ""
    
    init_system
    
    if [ ! -f "$TAB_LIST" ]; then
        echo "[!] Tab list not found. Run setup first."
        exit 1
    fi
    
    echo "[+] Monitoring tabs..."
    cat "$TAB_LIST" | nl -v 1
    echo ""
    echo "Dashboard: /sdcard/Download/roblox_dashboard.html"
    echo "Logs: $LOG_FILE"
    echo ""
    
    # Main monitoring loop
    while true; do
        # Monitor each tab
        cat "$TAB_LIST" | while IFS= read -r pkg; do
            monitor_tab "$pkg" &
        done
        
        wait
        
        # Update dashboard
        generate_dashboard
        
        sleep ${CHECK_INTERVAL:-15}
    done
}

main
