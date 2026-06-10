#!/system/bin/sh
# ===============================================
# ROBLOX REJOIN V7 - Smart Rejoin Handler
# Handles different error types with appropriate actions
# ===============================================

pkg=$1
error_code=$2

INSTALL_DIR="${INSTALL_DIR:-$HOME/.roblox_auto_rejoin}"
CONFIG_FILE="$INSTALL_DIR/config.conf"
STATE_DIR="$INSTALL_DIR/state"
LOG_FILE="$INSTALL_DIR/executor.log"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# ==================== LOGGING ====================
log_msg() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$pkg] [$level] $msg" >> "$LOG_FILE"
}

# ==================== STATE MANAGEMENT ====================
init_state() {
    mkdir -p "$STATE_DIR"
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
    local key=$1
    local state_file="$STATE_DIR/${pkg}.state"
    grep "^${key}=" "$state_file" 2>/dev/null | cut -d'=' -f2
}

write_state() {
    local key=$1
    local value=$2
    local state_file="$STATE_DIR/${pkg}.state"
    
    if grep -q "^${key}=" "$state_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|g" "$state_file"
    else
        echo "${key}=${value}" >> "$state_file"
    fi
}

# ==================== RESTART LOGIC ====================
do_restart() {
    local reason=$1
    
    local restart_count=$(read_state "RESTART_COUNT")
    restart_count=$((restart_count + 1))
    
    # Check max restarts
    if [ $restart_count -gt ${MAX_RESTARTS:-10} ]; then
        log_msg "ERROR" "Max restarts exceeded - BANNED"
        write_state "STATUS" "BANNED"
        return 1
    fi
    
    write_state "RESTART_COUNT" "$restart_count"
    log_msg "RESTART" "$reason (Count: $restart_count)"
    
    # Force stop
    am force-stop "$pkg" 2>/dev/null
    sleep 1
    
    # Trim cache
    pm trim-caches 256M > /dev/null 2>&1
    sleep 2
    
    # Restart
    am start -a android.intent.action.VIEW -d "${LINK:-roblox://placeId=2753915549}" -p "$pkg" 2>/dev/null
    
    write_state "UPTIME" "$(date +%s)"
    write_state "LAST_SEEN" "$(date +%s)"
    
    return 0
}

# ==================== REJOIN HANDLER ====================
handle_rejoin() {
    init_state
    
    local status=$(read_state "STATUS")
    
    # Skip if paused/banned
    if [ "$status" = "PAUSED" ] || [ "$status" = "BANNED" ]; then
        return 0
    fi
    
    # Handle specific errors
    case "$error_code" in
        # Soft errors - just rejoin
        277|279)
            log_msg "HANDLE" "Error $error_code - Soft rejoin"
            sleep 5
            am start -a android.intent.action.VIEW -d "${LINK:-roblox://placeId=2753915549}" -p "$pkg" 2>/dev/null
            write_state "LAST_ERROR" "$error_code"
            write_state "STATUS" "ACTIVE"
            ;;
        
        # Hard errors - restart app
        268|271)
            log_msg "HANDLE" "Error $error_code - Force restart"
            do_restart "ERROR_$error_code"
            write_state "LAST_ERROR" "$error_code"
            write_state "STATUS" "ACTIVE"
            ;;
        
        # ANR - full reset
        ANR)
            log_msg "HANDLE" "ANR detected - Full reset"
            am force-stop "$pkg" 2>/dev/null
            sleep 1
            pm trim-caches 999M > /dev/null 2>&1
            sleep 3
            am start -a android.intent.action.VIEW -d "${LINK:-roblox://placeId=2753915549}" -p "$pkg" 2>/dev/null
            write_state "LAST_ERROR" "ANR"
            write_state "STATUS" "ACTIVE"
            ;;
        
        # Permanent errors - stop
        264|267|273)
            log_msg "ERROR" "Permanent error $error_code - BANNED"
            write_state "STATUS" "BANNED"
            write_state "LAST_ERROR" "$error_code"
            ;;
        
        # Process crash - normal restart
        *)
            log_msg "HANDLE" "Process crash - Normal restart"
            do_restart "CRASH"
            write_state "STATUS" "ACTIVE"
            ;;
    esac
}

# ==================== PAUSE/RESUME COMMANDS ====================
case "$pkg" in
    pause)
        pkg=$2
        init_state
        write_state "STATUS" "PAUSED"
        log_msg "CMD" "Tab paused"
        ;;
    
    resume)
        pkg=$2
        init_state
        write_state "STATUS" "ACTIVE"
        log_msg "CMD" "Tab resumed"
        ;;
    
    *)
        # Normal rejoin
        handle_rejoin
        ;;
esac
