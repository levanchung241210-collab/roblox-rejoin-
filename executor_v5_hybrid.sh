#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V5.0 - HYBRID
# Merged: Installer detection + Executor + Watchdog logic
# ===============================================

STATE_DIR="$HOME/.roblox_auto_rejoin/state"
LOG_FILE="$HOME/.roblox_auto_rejoin/executor.log"
DASHBOARD_HTML="/sdcard/Download/roblox_dashboard.html"
PACKAGE_MAP="$HOME/.roblox_auto_rejoin/package_map.db"

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"

LOAD_TIME=180
CHECK_INTERVAL=15
MAX_RESTARTS=10

# ==================== INITIALIZATION ====================
init_system() {
    mkdir -p "$STATE_DIR"
    mkdir -p "/sdcard/Download"
    : > "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === EXECUTOR V5.0 STARTED ===" >> "$LOG_FILE"
}

log_msg() {
    local level=$1
    local msg=$2
    local acc=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -z "$acc" ]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] [$acc] [$level] $msg" >> "$LOG_FILE"
    fi
}

# ==================== PACKAGE DETECTION & MAPPING ====================
detect_packages() {
    # Accept packages from command line argument
    if [ -n "$1" ]; then
        echo "$1"
    else
        # Fallback: auto-detect
        pm list packages 2>/dev/null | grep -i roblox | sed 's/package://'
    fi
}

create_package_map() {
    local accounts=$1
    
    echo "# Package map - Auto-generated $(date '+%Y-%m-%d %H:%M:%S')" > "$PACKAGE_MAP"
    echo "$accounts" | while IFS= read -r pkg; do
        # Extract basename for pattern matching
        basename=$(echo "$pkg" | grep -oE '[^.]+$')
        echo "$pkg|$basename" >> "$PACKAGE_MAP"
    done
    
    log_msg "SYSTEM" "Package map created with $(echo "$accounts" | wc -l) packages" ""
}

# ==================== STATE MANAGEMENT ====================
init_account_state() {
    local acc=$1
    local state_file="$STATE_DIR/${acc}.state"
    
    if [ ! -f "$state_file" ]; then
        cat > "$state_file" << EOF
STATE=RUNNING
RESTART_COUNT=0
ERROR_COUNT=0
LAST_ERROR=NONE
LAST_ERROR_TIME=0
UPTIME_START=$(date +%s)
LAST_REJOIN=0
GFX_TIMEOUT=0
FREEZE_COUNT=0
PAUSED_TIME=0
LAST_FRAME_COUNT=0
STREAK=0
ANR_COUNT=0
EOF
        log_msg "INIT" "State file created" "$acc"
    fi
}

read_state() {
    local acc=$1
    local key=$2
    local state_file="$STATE_DIR/${acc}.state"
    
    if [ -f "$state_file" ]; then
        grep "^${key}=" "$state_file" 2>/dev/null | cut -d'=' -f2
    fi
}

write_state() {
    local acc=$1
    local key=$2
    local value=$3
    local state_file="$STATE_DIR/${acc}.state"
    
    if [ -f "$state_file" ]; then
        if grep -q "^${key}=" "$state_file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|g" "$state_file"
        else
            echo "${key}=${value}" >> "$state_file"
        fi
    fi
}

pause_account() {
    local acc=$1
    write_state "$acc" "STATE" "PAUSED"
    log_msg "PAUSE" "Account paused" "$acc"
}

resume_account() {
    local acc=$1
    write_state "$acc" "STATE" "RUNNING"
    log_msg "RESUME" "Account resumed" "$acc"
}

# ==================== ERROR CLASSIFICATION ====================
get_recovery_level() {
    local error=$1
    case $error in
        260|261|262|266|277|279) echo "1" ;;
        268|271|278|525) echo "2" ;;
        256|274|275|280|286|292) echo "3" ;;
        264|267|272|273|524|600|523) echo "0" ;;
        *) echo "2" ;;
    esac
}

# ==================== SMART RESTART (Watchdog Logic) ====================
smart_restart() {
    local acc=$1
    local reason=$2
    
    local restart_count=$(read_state "$acc" "RESTART_COUNT")
    restart_count=$((restart_count + 1))
    
    if [ $restart_count -gt $MAX_RESTARTS ]; then
        log_msg "ERROR" "Max restarts exceeded - BLACKLISTING" "$acc"
        write_state "$acc" "STATE" "BANNED"
        return 1
    fi
    
    write_state "$acc" "RESTART_COUNT" "$restart_count"
    log_msg "RESTART" "Restarting - $reason (Count: $restart_count)" "$acc"
    
    # Force stop
    am force-stop "$acc" 2>/dev/null
    sleep 1
    
    # Trim cache
    pm trim-caches 256M > /dev/null 2>&1
    sleep 2
    
    # Start app with Place ID link
    am start -a android.intent.action.VIEW -d "$LINK" -p "$acc" 2>/dev/null
    
    write_state "$acc" "LAST_REJOIN" "$(date +%s)"
    write_state "$acc" "UPTIME_START" "$(date +%s)"
    write_state "$acc" "STREAK" "$(($(read_state "$acc" "STREAK") + 1))"
    
    return 0
}

# ==================== ERROR DETECTION ====================
detect_error() {
    local acc=$1
    
    # Try logcat first
    local error_line=$(logcat -d -t 30 2>/dev/null | grep -i "$acc" | grep -oE "Error Code: [0-9]{3}" | head -1)
    
    if [ ! -z "$error_line" ]; then
        echo "$error_line" | grep -oE "[0-9]{3}"
        return 0
    fi
    
    # Fallback: check dumpsys
    local dump=$(timeout 3 dumpsys activity processes 2>/dev/null | grep -A 5 "$acc")
    if echo "$dump" | grep -q "ANR\|ANT"; then
        echo "256"
        write_state "$acc" "ANR_COUNT" "$(($(read_state "$acc" "ANR_COUNT") + 1))"
        return 0
    fi
    
    return 1
}

detect_gfx_timeout() {
    local acc=$1
    
    local gfx=$(timeout 3 dumpsys gfxinfo "$acc" 2>/dev/null | grep "Total frames rendered" | awk '{print $4}')
    
    if [ -z "$gfx" ] || [ "$gfx" = "0" ]; then
        return 0  # timeout detected
    else
        return 1  # OK
    fi
}

detect_process_alive() {
    local acc=$1
    local pid=$(pidof "$acc" 2>/dev/null)
    
    if [ -z "$pid" ]; then
        return 1  # process dead
    else
        return 0  # process alive
    fi
}

# ==================== RECOVERY ====================
execute_recovery() {
    local acc=$1
    local error=$2
    local level=$(get_recovery_level "$error")
    
    if [ "$level" -eq 0 ]; then
        log_msg "ERROR" "PERMANENT ERROR $error - STOP" "$acc"
        write_state "$acc" "STATE" "BANNED"
        return 1
    fi
    
    if [ "$level" -eq 1 ]; then
        log_msg "RECOVERY" "Level 1 - Error: $error" "$acc"
        sleep 5
        am start -a android.intent.action.VIEW -d "$LINK" -p "$acc" 2>/dev/null
        write_state "$acc" "LAST_REJOIN" "$(date +%s)"
        return 0
    fi
    
    if [ "$level" -eq 2 ]; then
        log_msg "RECOVERY" "Level 2 - Error: $error (Restart)" "$acc"
        smart_restart "$acc" "ERROR_$error"
        return 0
    fi
    
    if [ "$level" -eq 3 ]; then
        log_msg "RECOVERY" "Level 3 - Error: $error (Full Reset)" "$acc"
        am force-stop "$acc" 2>/dev/null
        sleep 1
        pm trim-caches 999M > /dev/null 2>&1
        sleep 3
        am start -a android.intent.action.VIEW -d "$LINK" -p "$acc" 2>/dev/null
        write_state "$acc" "LAST_REJOIN" "$(date +%s)"
        write_state "$acc" "UPTIME_START" "$(date +%s)"
        return 0
    fi
}

# ==================== MONITORING ====================
monitor_account() {
    local acc=$1
    
    local state=$(read_state "$acc" "STATE")
    if [ "$state" = "PAUSED" ] || [ "$state" = "BANNED" ]; then
        return 0
    fi
    
    # Check if process is alive
    if ! detect_process_alive "$acc"; then
        local uptime_start=$(read_state "$acc" "UPTIME_START")
        local current_time=$(date +%s)
        local elapsed=$((current_time - uptime_start))
        
        if [ $elapsed -ge $LOAD_TIME ]; then
            log_msg "CRASH" "Process crashed - Auto rejoin" "$acc"
            smart_restart "$acc" "CRASH"
        fi
        return 0
    fi
    
    # Process is alive - check for errors
    local uptime_start=$(read_state "$acc" "UPTIME_START")
    local current_time=$(date +%s)
    local elapsed=$((current_time - uptime_start))
    
    # Skip check during loading
    if [ $elapsed -lt $LOAD_TIME ]; then
        return 0
    fi
    
    # Check GFX timeout
    if detect_gfx_timeout "$acc"; then
        log_msg "TIMEOUT" "GFX timeout detected" "$acc"
        execute_recovery "$acc" "256"
        return 0
    fi
    
    # Check error codes
    local error=$(detect_error "$acc")
    if [ -n "$error" ]; then
        log_msg "ERROR" "Error detected: $error" "$acc"
        write_state "$acc" "LAST_ERROR" "$error"
        write_state "$acc" "LAST_ERROR_TIME" "$(date +%s)"
        execute_recovery "$acc" "$error"
        return 0
    fi
}

# ==================== GENERATE DASHBOARD ====================
generate_dashboard() {
    local accounts=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local active=0
    local farming=0
    local error_count=0
    local paused=0
    local banned=0
    local account_html=""
    
    for acc in $accounts; do
        local state=$(read_state "$acc" "STATE")
        local restart=$(read_state "$acc" "RESTART_COUNT")
        local last_error=$(read_state "$acc" "LAST_ERROR")
        local uptime_start=$(read_state "$acc" "UPTIME_START")
        local current_time=$(date +%s)
        local uptime=$((current_time - uptime_start))
        
        local uptime_str=""
        if [ $uptime -ge 3600 ]; then
            uptime_str="$((uptime/3600))h $(($(($uptime % 3600))/60))m"
        else
            uptime_str="$((uptime/60))m $((uptime%60))s"
        fi
        
        local pid=$(pidof "$acc" 2>/dev/null)
        if [ -z "$pid" ]; then
            pid="N/A"
        fi
        
        local icon="▶"
        local badge_class="running"
        local card_class="account-card"
        
        case $state in
            RUNNING)
                if [ "$pid" = "N/A" ]; then
                    icon="⏳"
                    badge_class="loading"
                    card_class="account-card error"
                    error_count=$((error_count + 1))
                else
                    icon="▶"
                    badge_class="running"
                    farming=$((farming + 1))
                    active=$((active + 1))
                fi
                ;;
            PAUSED)
                icon="⏸"
                badge_class="paused"
                card_class="account-card paused"
                paused=$((paused + 1))
                ;;
            BANNED)
                icon="🚫"
                badge_class="banned"
                card_class="account-card banned"
                banned=$((banned + 1))
                ;;
        esac
        
        account_html="${account_html} <div class='${card_class}'><div class='account-info'><div class='account-icon'>${icon}</div><div><div class='account-name'>${acc}</div><span class='status-badge ${badge_class}'>${state}</span></div></div><div class='account-detail'><div class='detail-item'><span class='detail-label'>Restarts:</span><span>${restart}</span></div><div class='detail-item'><span class='detail-label'>Last Error:</span><span>${last_error}</span></div><div class='detail-item'><span class='detail-label'>Uptime:</span><span>${uptime_str}</span></div><div class='detail-item'><span class='detail-label'>PID:</span><span>${pid}</span></div></div></div>"
    done
    
    cat > "$DASHBOARD_HTML" << EOFHTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Roblox Auto Rejoin V5.0</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            padding: 20px;
            color: #fff;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding: 20px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 10px;
        }
        .header h1 { font-size: 32px; margin-bottom: 10px; }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-card .number { font-size: 32px; font-weight: bold; margin: 10px 0; }
        .accounts {
            display: grid;
            gap: 15px;
        }
        .account-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #4ade80;
            display: grid;
            grid-template-columns: 1fr 1fr 1fr;
            gap: 20px;
        }
        .account-card.paused { border-left-color: #fbbf24; }
        .account-card.banned { border-left-color: #ef4444; }
        .account-card.error { border-left-color: #f87171; }
        .account-info { display: flex; align-items: center; gap: 15px; }
        .account-detail { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; font-size: 13px; }
        .detail-item { display: flex; justify-content: space-between; }
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-badge.running { background: #4ade80; color: #000; }
        .status-badge.paused { background: #fbbf24; color: #000; }
        .status-badge.banned { background: #ef4444; color: #fff; }
        .footer {
            text-align: center;
            margin-top: 30px;
            padding: 15px;
            color: #bfdbfe;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎮 Roblox Auto Rejoin V5.0</h1>
            <p>Updated: ${timestamp}</p>
        </div>
        <div class="stats">
            <div class="stat-card">
                <div class="label">ACTIVE</div>
                <div class="number">${active}</div>
            </div>
            <div class="stat-card">
                <div class="label">FARMING</div>
                <div class="number">${farming}</div>
            </div>
            <div class="stat-card">
                <div class="label">ERROR</div>
                <div class="number">${error_count}</div>
            </div>
            <div class="stat-card">
                <div class="label">PAUSED</div>
                <div class="number">${paused}</div>
            </div>
            <div class="stat-card">
                <div class="label">BANNED</div>
                <div class="number">${banned}</div>
            </div>
        </div>
        <div class="accounts">
            ${account_html}
        </div>
        <div class="footer">
            V5.0 HYBRID - Merged Detection + Smart Restart 🚀
        </div>
    </div>
    <script>
        setInterval(() => location.reload(), 10000);
    </script>
</body>
</html>
EOFHTML
}

# ==================== MAIN ====================
main() {
    clear
    echo "=================================="
    echo "  ROBLOX AUTO REJOIN V5.0 HYBRID"
    echo "=================================="
    echo ""
    
    init_system
    
    # Get packages from argument or auto-detect
    local accounts="$*"
    
    if [ -z "$accounts" ]; then
        echo "[*] Auto-detecting packages..."
        accounts=$(detect_packages)
    fi
    
    if [ -z "$accounts" ]; then
        echo "[!] No packages found!"
        exit 1
    fi
    
    echo "[+] Found packages:"
    echo "$accounts" | nl -v 1
    echo ""
    
    # Create package map
    create_package_map "$accounts"
    
    # Initialize accounts
    echo "[*] Initializing accounts..."
    for acc in $accounts; do
        init_account_state "$acc"
        smart_restart "$acc" "INITIAL_START"
    done
    
    echo "[+] EXECUTOR RUNNING!"
    echo ""
    echo "📊 Dashboard: /sdcard/Download/roblox_dashboard.html"
    echo "📝 Logs: $LOG_FILE"
    echo ""
    
    # Main loop
    while true; do
        for acc in $accounts; do
            monitor_account "$acc" &
        done
        
        wait
        generate_dashboard "$accounts"
        sleep $CHECK_INTERVAL
    done
}

# ==================== COMMANDS ====================
if [ "$1" = "pause" ] && [ -n "$2" ]; then
    pause_account "$2"
    exit 0
elif [ "$1" = "resume" ] && [ -n "$2" ]; then
    resume_account "$2"
    exit 0
elif [ "$1" = "status" ]; then
    echo "Account Status:"
    for state_file in "$STATE_DIR"/*.state; do
        if [ -f "$state_file" ]; then
            acc=$(basename "$state_file" .state)
            state=$(grep "^STATE=" "$state_file" | cut -d'=' -f2)
            restart=$(grep "^RESTART_COUNT=" "$state_file" | cut -d'=' -f2)
            error=$(grep "^LAST_ERROR=" "$state_file" | cut -d'=' -f2)
            echo "  $acc | $state | Restarts: $restart | Error: $error"
        fi
    done
    exit 0
elif [ "$1" = "logs" ]; then
    tail -n 50 "$LOG_FILE"
    exit 0
fi

# Run main with all arguments as packages
main "$@"
