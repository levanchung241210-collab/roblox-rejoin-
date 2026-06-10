#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V4.0 ULTIMATE (FIXED)
# 1 File Complete - Auto Everything!
# ===============================================

STATE_DIR="$HOME/.roblox_auto_rejoin/state"
LOG_FILE="$HOME/.roblox_auto_rejoin/executor.log"
roblox_executor.log"
DASHBOARD_HTML="/sdcard/Download/roblox_dashboard.html"

PLACE_ID="2753915549"
LINK="roblox://placeId=$PLACE_ID"

LOAD_TIME=180
COOLDOWN_TIME=120
CHECK_INTERVAL=15
MAX_RESTARTS=10

# ==================== INITIALIZE ====================
init_system() {
    mkdir -p "$STATE_DIR"
    mkdir -p "/sdcard/Download"
    : > "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === SYSTEM INITIALIZED ===" >> "$LOG_FILE"
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

# ==================== AUTO DETECT PACKAGES ====================
auto_detect_packages() {
    echo "[*] Auto-detecting Roblox packages..."
    
    local packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo "[!] No Roblox packages found!"
        echo ""
        echo "Please install Roblox apps first:"
        echo "  - Clone Roblox app multiple times, OR"
        echo "  - Use app cloner"
        echo ""
        exit 1
    fi
    
    echo "[+] Found packages:"
    echo "$packages" | nl -v 1
    echo ""
    
    echo "$packages"
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
EOF
        log_msg "INIT" "State initialized" "$acc"
    fi
}

read_state() {
    local acc=$1
    local key=$2
    local state_file="$STATE_DIR/${acc}.state"
    
    if [ -f "$state_file" ]; then
        grep "^${key}=" "$state_file" | cut -d'=' -f2
    fi
}

write_state() {
    local acc=$1
    local key=$2
    local value=$3
    local state_file="$STATE_DIR/${acc}.state"
    
    if grep -q "^${key}=" "$state_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|g" "$state_file"
    else
        echo "${key}=${value}" >> "$state_file"
    fi
}

pause_account() {
    local acc=$1
    write_state "$acc" "STATE" "PAUSED"
    write_state "$acc" "PAUSED_TIME" "$(date +%s)"
    log_msg "PAUSE" "Account paused" "$acc"
}

resume_account() {
    local acc=$1
    write_state "$acc" "STATE" "RUNNING"
    write_state "$acc" "PAUSED_TIME" "0"
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

is_recoverable() {
    local error=$1
    local level=$(get_recovery_level "$error")
    [ "$level" -gt 0 ]
}

# ==================== RESTART ====================
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
    
    am force-stop "$acc" 2>/dev/null
    sleep 1
    pm trim-caches 256M > /dev/null 2>&1
    sleep 2
    am start -a android.intent.action.VIEW -d "$LINK" "$acc" 2>/dev/null
    
    write_state "$acc" "LAST_REJOIN" "$(date +%s)"
    write_state "$acc" "UPTIME_START" "$(date +%s)"
    return 0
}

# ==================== ERROR DETECTION ====================
detect_error() {
    local acc=$1
    
    local error_line=$(logcat -d -t 30 2>/dev/null | grep -E "$acc" | grep -oE "Error Code: [0-9]{3}" | head -1)
    
    if [ ! -z "$error_line" ]; then
        echo "$error_line" | grep -oE "[0-9]{3}"
    fi
}

detect_gfx_timeout() {
    local acc=$1
    
    local gfx=$(timeout 3 dumpsys gfxinfo "$acc" 2>/dev/null | grep "Total frames rendered" | awk '{print $4}')
    
    if [ -z "$gfx" ]; then
        return 0
    else
        return 1
    fi
}

detect_frame_freeze() {
    local acc=$1
    
    local current_frames=$(timeout 3 dumpsys gfxinfo "$acc" 2>/dev/null | grep "Total frames rendered" | awk '{print $4}')
    local previous_frames=$(read_state "$acc" "LAST_FRAME_COUNT")
    
    if [ -z "$previous_frames" ]; then
        write_state "$acc" "LAST_FRAME_COUNT" "$current_frames"
        return 1
    fi
    
    if [ "$current_frames" = "$previous_frames" ]; then
        local freeze_count=$(read_state "$acc" "FREEZE_COUNT")
        freeze_count=$((freeze_count + 1))
        write_state "$acc" "FREEZE_COUNT" "$freeze_count"
        
        if [ $freeze_count -ge 5 ]; then
            write_state "$acc" "FREEZE_COUNT" "0"
            return 0
        fi
    else
        write_state "$acc" "FREEZE_COUNT" "0"
        write_state "$acc" "LAST_FRAME_COUNT" "$current_frames"
    fi
    
    return 1
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
        am start -a android.intent.action.VIEW -d "$LINK" "$acc" 2>/dev/null
        write_state "$acc" "LAST_REJOIN" "$(date +%s)"
        return 0
    fi
    
    if [ "$level" -eq 2 ]; then
        log_msg "RECOVERY" "Level 2 - Error: $error" "$acc"
        smart_restart "$acc" "ERROR_$error"
        return 0
    fi
    
    if [ "$level" -eq 3 ]; then
        log_msg "RECOVERY" "Level 3 - Error: $error" "$acc"
        am force-stop "$acc" 2>/dev/null
        sleep 1
        pm trim-caches 999G > /dev/null 2>&1
        sleep 3
        am start -a android.intent.action.VIEW -d "$LINK" "$acc" 2>/dev/null
        write_state "$acc" "LAST_REJOIN" "$(date +%s)"
        write_state "$acc" "UPTIME_START" "$(date +%s)"
        return 0
    fi
}

handle_multi_device_error() {
    local acc=$1
    local error=$2
    local state=$(read_state "$acc" "STATE")
    
    if [ "$error" = "264" ] || [ "$error" = "273" ]; then
        if [ "$state" = "PAUSED" ]; then
            log_msg "INFO" "Multi-device error - Account PAUSED (OK)" "$acc"
            return 0
        else
            log_msg "WARN" "Multi-device error - Force stopping" "$acc"
            am force-stop "$acc" 2>/dev/null
            sleep 5
            am start -a android.intent.action.VIEW -d "$LINK" "$acc" 2>/dev/null
            write_state "$acc" "LAST_REJOIN" "$(date +%s)"
            return 0
        fi
    fi
}

# ==================== MONITORING ====================
monitor_account() {
    local acc=$1
    
    local state=$(read_state "$acc" "STATE")
    if [ "$state" = "PAUSED" ] || [ "$state" = "BANNED" ]; then
        return 0
    fi
    
    local pid=$(pidof "$acc")
    
    if [ -z "$pid" ]; then
        local uptime=$(read_state "$acc" "UPTIME_START")
        local current_time=$(date +%s)
        local elapsed=$((current_time - uptime))
        
        if [ $elapsed -ge $LOAD_TIME ]; then
            log_msg "CRASH" "Process crashed - Auto rejoin" "$acc"
            smart_restart "$acc" "CRASH"
        fi
        return 0
    fi
    
    local uptime=$(read_state "$acc" "UPTIME_START")
    local current_time=$(date +%s)
    local elapsed=$((current_time - uptime))
    
    if [ $elapsed -lt $LOAD_TIME ]; then
        return 0
    fi
    
    if detect_gfx_timeout "$acc" "$pid"; then
        local gfx_timeout=$(read_state "$acc" "GFX_TIMEOUT")
        gfx_timeout=$((gfx_timeout + 1))
        write_state "$acc" "GFX_TIMEOUT" "$gfx_timeout"
        
        if [ $gfx_timeout -ge 3 ]; then
            log_msg "TIMEOUT" "GFX timeout - System freeze" "$acc"
            execute_recovery "$acc" "256"
            write_state "$acc" "GFX_TIMEOUT" "0"
            return 0
        fi
    else
        write_state "$acc" "GFX_TIMEOUT" "0"
    fi
    
    if detect_frame_freeze "$acc" "$pid"; then
        log_msg "FREEZE" "Frame freeze detected" "$acc"
        execute_recovery "$acc" "256"
        return 0
    fi
    
    local error=$(detect_error "$acc" "$pid")
    
    if [ ! -z "$error" ]; then
        log_msg "ERROR" "Error detected: $error" "$acc"
        write_state "$acc" "LAST_ERROR" "$error"
        write_state "$acc" "LAST_ERROR_TIME" "$(date +%s)"
        
        handle_multi_device_error "$acc" "$error"
        
        if is_recoverable "$error"; then
            execute_recovery "$acc" "$error"
        else
            log_msg "PERM_ERROR" "Permanent error $error - Stop" "$acc"
            write_state "$acc" "STATE" "BANNED"
        fi
    fi
}

# ==================== GENERATE HTML DASHBOARD (FIXED) ====================
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
        init_account_state "$acc"
        
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
        
        local pid=$(pidof "$acc")
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
        
        # Tạo chuỗi HTML (bỏ ký tự xuống dòng để sed không lỗi)
        account_html="${account_html} <div class='${card_class}'><div class='account-info'><div class='account-icon'>${icon}</div><div><div class='account-name'>${acc}</div><span class='status-badge ${badge_class}'>${state}</span></div></div><div class='account-detail'><div class='detail-item'><span class='detail-label'>Restarts:</span><span>${restart}</span></div><div class='detail-item'><span class='detail-label'>Last Error:</span><span>${last_error}</span></div><div class='detail-item'><span class='detail-label'>Uptime:</span><span>${uptime_str}</span></div><div class='detail-item'><span class='detail-label'>PID:</span><span>${pid}</span></div></div><div class='account-actions'><button class='btn-pause' onclick='alert(\"Run: sh roblox_rejoin_v4.0_ULTIMATE.sh pause ${acc}\")'>⏸ PAUSE</button><button class='btn-resume' onclick='alert(\"Run: sh roblox_rejoin_v4.0_ULTIMATE.sh resume ${acc}\")'>▶ RESUME</button></div></div>"
    done
    
    # Dùng EOFHTML (không dấu nháy) để điền biến trực tiếp
    cat > "$DASHBOARD_HTML" << EOFHTML
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Roblox Auto Rejoin V4.0</title>
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
            backdrop-filter: blur(10px);
        }
        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5);
        }
        .header .info {
            display: flex;
            justify-content: space-around;
            margin-top: 15px;
            gap: 20px;
            flex-wrap: wrap;
        }
        .info-item {
            background: rgba(255, 255, 255, 0.1);
            padding: 10px 20px;
            border-radius: 5px;
            font-size: 14px;
        }
        .info-item .label { font-weight: bold; color: #ffd700; }
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
            border: 1px solid rgba(255, 255, 255, 0.2);
            backdrop-filter: blur(10px);
        }
        .stat-card .number {
            font-size: 32px;
            font-weight: bold;
            margin: 10px 0;
        }
        .stat-card.active .number { color: #4ade80; }
        .stat-card.farming .number { color: #60a5fa; }
        .stat-card.error .number { color: #f87171; }
        .stat-card.paused .number { color: #fbbf24; }
        .stat-card.banned .number { color: #ef4444; }
        .accounts {
            display: grid;
            gap: 15px;
            margin-bottom: 20px;
        }
        .account-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #4ade80;
            backdrop-filter: blur(10px);
            display: grid;
            grid-template-columns: 1fr 1fr 1fr auto;
            align-items: center;
            gap: 20px;
        }
        .account-card.paused { border-left-color: #fbbf24; }
        .account-card.banned { border-left-color: #ef4444; }
        .account-card.error { border-left-color: #f87171; }
        .account-info {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        .account-icon { font-size: 24px; min-width: 30px; }
        .account-name {
            font-weight: bold;
            font-size: 14px;
            word-break: break-all;
        }
        .account-detail {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            font-size: 13px;
        }
        .detail-item {
            display: flex;
            justify-content: space-between;
        }
        .detail-label {
            color: #bfdbfe;
            font-weight: 500;
        }
        .account-actions {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        button {
            padding: 10px 15px;
            border: none;
            border-radius: 5px;
            font-size: 12px;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s;
            min-width: 80px;
        }
        .btn-pause {
            background: #fbbf24;
            color: #000;
        }
        .btn-pause:hover {
            background: #f59e0b;
            transform: translateY(-2px);
        }
        .btn-resume {
            background: #4ade80;
            color: #000;
        }
        .btn-resume:hover {
            background: #22c55e;
            transform: translateY(-2px);
        }
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            background: rgba(255, 255, 255, 0.2);
        }
        .status-badge.running { background: #4ade80; color: #000; }
        .status-badge.paused { background: #fbbf24; color: #000; }
        .status-badge.banned { background: #ef4444; color: #fff; }
        .status-badge.loading { background: #60a5fa; color: #fff; }
        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        .controls button {
            flex: 1;
            min-width: 120px;
            padding: 12px;
        }
        .btn-refresh {
            background: #10b981;
            color: #fff;
        }
        .btn-refresh:hover {
            background: #059669;
            transform: translateY(-2px);
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            padding: 15px;
            color: #bfdbfe;
            font-size: 12px;
        }
        .loading {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #4ade80;
            border-radius: 50%;
            animation: pulse 1.5s infinite;
            margin-left: 5px;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        @media (max-width: 768px) {
            .account-card {
                grid-template-columns: 1fr;
            }
            .header h1 { font-size: 24px; }
            .stats { grid-template-columns: repeat(2, 1fr); }
            .account-detail { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎮 Roblox Auto Rejoin V4.0</h1>
            <div class="info">
                <div class="info-item">
                    <span class="label">TIME:</span>
                    <span>${timestamp}</span>
                </div>
                <div class="info-item">
                    <span class="label">PLACE_ID:</span>
                    <span>2753915549</span>
                </div>
                <div class="info-item">
                    <span class="label">STATUS:</span>
                    <span id="sysStatus">RUNNING<span class="loading"></span></span>
                </div>
            </div>
        </div>

        <div class="stats">
            <div class="stat-card active">
                <div class="label">ACTIVE</div>
                <div class="number">${active}</div>
            </div>
            <div class="stat-card farming">
                <div class="label">FARMING</div>
                <div class="number">${farming}</div>
            </div>
            <div class="stat-card error">
                <div class="label">ERROR</div>
                <div class="number">${error_count}</div>
            </div>
            <div class="stat-card paused">
                <div class="label">PAUSED</div>
                <div class="number">${paused}</div>
            </div>
            <div class="stat-card banned">
                <div class="label">BANNED</div>
                <div class="number">${banned}</div>
            </div>
        </div>

        <div class="controls">
            <button class="btn-refresh" onclick="location.reload()">🔄 REFRESH</button>
        </div>

        <div class="accounts">
            ${account_html}
        </div>

        <div class="footer">
            📊 Updated: ${timestamp} | V4.0 ULTIMATE - Auto Everything! 🚀
        </div>
    </div>

    <script>
        setInterval(() => {
            location.reload();
        }, 10000);
    </script>
</body>
</html>
EOFHTML
}

# ==================== MAIN LOOP ====================
main() {
    clear
    echo "=================================="
    echo "  ROBLOX AUTO REJOIN V4.0 FIXED"
    echo "=================================="
    echo ""
    
    init_system
    
    # Auto-detect packages
    local accounts=$(auto_detect_packages)
    
    if [ -z "$accounts" ]; then
        echo "[!] Failed to detect packages"
        exit 1
    fi
    
    echo "[*] Initializing accounts..."
    for acc in $accounts; do
        init_account_state "$acc"
        log_msg "INIT" "Starting rejoin service" "$acc"
        smart_restart "$acc" "INITIAL_START"
    done
    
    log_msg "SYSTEM" "=== EXECUTOR STARTED ===" ""
    log_msg "SYSTEM" "Auto-detected accounts: $accounts" ""
    
    echo "[+] EXECUTOR RUNNING!"
    echo ""
    echo "📊 Dashboard: /sdcard/Download/roblox_dashboard.html"
    echo "   Open with Chrome/Firefox to monitor"
    echo ""
    echo "📝 Logs: /data/local/tmp/roblox_executor.log"
    echo ""
    
    # Main loop (Optimized - Generate dashboard after every check cycle)
    while true; do
        # Monitor accounts
        for acc in $accounts; do
            monitor_account "$acc" &
        done
        
        wait
        
        # Generate dashboard immediately after each monitoring cycle for real-time updates
        generate_dashboard "$accounts"
        
        sleep $CHECK_INTERVAL
    done
}

# ==================== SIMPLE COMMANDS ====================
if [ "$1" = "pause" ] && [ ! -z "$2" ]; then
    pause_account "$2"
    exit 0
elif [ "$1" = "resume" ] && [ ! -z "$2" ]; then
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

# ==================== RUN ====================
main
