#!/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN V14 - NEXUS TERMINAL
# Professional Termux Display + Bulletproof Logic
# ===============================================

CHECK_INTERVAL=15
PROCESS_RECOVERY_COOLDOWN=20
FORCE_REJOIN_INTERVAL=180
APP_LAUNCH_GRACE_PERIOD=40

BASE_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"

# ==================== INIT ====================
setup_dirs() {
    rm -rf "$STATE_DIR"/* "$CACHE_DIR"/* 2>/dev/null
    mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"
}

# ==================== EXTRACT USERNAME ====================
extract_roblox_username() {
    pkg=$1
    uname=""
    data_path="/data/data/$pkg"
    
    if [ ! -d "$data_path" ]; then
        data_path=$(pm path "$pkg" 2>/dev/null | cut -d':' -f2 | sed 's/\/base.apk//' | sed 's/app/data/')
    fi
    
    if [ -d "$data_path/shared_prefs" ]; then
        uname=$(grep -rioA 1 '"Username"' "$data_path/shared_prefs/" 2>/dev/null | grep -i "string" | head -1 | cut -d'>' -f2 | cut -d'<' -f1)
        [ -z "$uname" ] && uname=$(grep -rioE 'username":"[^"]+' "$data_path/shared_prefs/" 2>/dev/null | head -1 | cut -d'"' -f3)
    fi
    
    [ -z "$uname" ] && uname="Chua_Login"
    echo "$uname" | cut -c 1-12
}

# ==================== DISCOVER RUNNING INSTANCES ====================
discover_active_instances() {
    installed_pkgs=$1
    active_list=""
    
    for pkg in $installed_pkgs; do
        # Method 1: pidof (fastest)
        pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
        
        # Method 2: ps if pidof fails
        if [ -z "$pid" ]; then
            pid=$(ps -A 2>/dev/null | grep -w "$pkg" | grep -v ":" | awk '{print $2}' | head -1)
        fi
        
        # Method 3: ps fallback for old Android
        if [ -z "$pid" ]; then
            pid=$(ps 2>/dev/null | grep -w "$pkg" | grep -v ":" | awk '{print $2}' | head -1)
        fi
        
        # Validate PID is numeric
        if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null; then
            active_list="$active_list|$pid|$pkg"
        fi
    done
    
    echo "$active_list"
}

# ==================== HEALTH MATRIX ====================
evaluate_health_matrix() {
    token=$1
    pid=$2
    now=$(date +%s)
    
    # Check launch grace period
    launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null || echo "0")
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING"
            return 0
        fi
    fi
    
    # Check process exists
    status_file="/proc/$pid/status"
    if [ ! -f "$status_file" ]; then
        echo "0|PROCESS_MISSING"
        return 0
    fi
    
    # Check CPU ticks (detect freeze)
    stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    current_ticks=0
    if [ -n "$stat_line" ]; then
        current_ticks=$(echo "$stat_line" | awk '{print $14 + $15}')
    fi
    
    last_ticks=$(cat "$CACHE_DIR/${token}_ticks.cache" 2>/dev/null || echo "0")
    echo "$current_ticks" > "$CACHE_DIR/${token}_ticks.cache"
    
    # Freeze detection
    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null || echo "0")
        f_cnt=$((f_cnt + 1))
        echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"
        
        if [ "$f_cnt" -ge 4 ]; then
            echo "0|APP_TREO_CUNG"
            return 0
        fi
    else
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi
    
    echo "95|HEALTHY"
}

# ==================== RECOVERY PIPELINE ====================
execute_recovery_pipeline() {
    pkg=$1
    pid=$2
    error_type=$3
    token="$pkg"
    now=$(date +%s)
    
    # Kill old process
    if [ "$error_type" != "Ep_vao_Map" ]; then
        if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_freeze.cnt"
        sleep 1
    fi
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    # Launch app with Monkey
    if [ "$error_type" != "Ep_vao_Map" ]; then
        monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        sleep 4
    fi
    
    # Deep link to place
    am start -a android.intent.action.VIEW -d "roblox://placeId=2753915549" -p "$pkg" >/dev/null 2>&1
    
    r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

# ==================== LIVE TERMINAL UI ====================
display_live_ui() {
    installed_pkgs=$1
    total_tabs=0
    
    printf "\033c"
    echo -e "\033[1;36m════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;32m 🤖 ROBLOX V14 - NEXUS TERMINAL EDITION \033[0m"
    echo -e "\033[1;36m════════════════════════════════════════════════════════════════════════\033[0m"
    printf "\033[1;33m%-25s | %-15s | %-6s | %-15s | %-20s\033[0m\n" "PACKAGE" "ACCOUNT" "SCORE" "STATUS" "NOTE"
    echo "────────────────────────────────────────────────────────────────────────"
    
    for pkg in $installed_pkgs; do
        token="$pkg"
        pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "0")
        score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
        l_err=$(cat "$STATE_DIR/${token}_last_err.txt" 2>/dev/null || echo "Binh_thuong")
        username=$(extract_roblox_username "$pkg")
        r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
        
        color="\033[0;32m"
        status_text="Khoe_Manh"
        
        if [ "$pid" = "0" ]; then
            score=0
            color="\033[0;31m"
            status_text="Tat_Mat_Tich"
        else
            total_tabs=$((total_tabs + 1))
            if [ "$score" -eq 100 ]; then
                color="\033[1;34m"
                status_text="Mo_Map"
            elif [ "$score" -lt 90 ] && [ "$score" -gt 0 ]; then
                color="\033[1;33m"
                status_text="Canh_Bao"
            fi
        fi
        
        printf "${color}%-25s | %-15s | %-6s | %-15s | [%s] %s\033[0m\n" \
            "$pkg" "$username" "$score" "$status_text" "R:$r_cnt" "$l_err"
    done
    
    echo "════════════════════════════════════════════════════════════════════════"
    echo -e "\033[1;37m 📊 TONG SO TAB DANG CHAY: \033[1;33m$total_tabs TAB\033[0m"
    echo -e "\033[1;36m════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;32mCommands:\033[0m"
    echo -e "  sh \$0 watch    - Live status (updates every 15s)"
    echo -e "  sh \$0 status   - Quick check"
    echo -e "  sh \$0 logs     - View logs"
    echo ""
}

# ==================== MONITOR LOOP ====================
monitor_core_loop() {
    setup_dirs
    
    while true; do
        installed_roblox=$(pm list packages 2>/dev/null | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
        
        if [ -z "$installed_roblox" ]; then
            echo "No Roblox packages found!"
            sleep 10
            continue
        fi
        
        running_pids=$(discover_active_instances "$installed_roblox")
        now=$(date +%s)
        
        for pkg in $installed_roblox; do
            token="$pkg"
            is_running=$(echo "$running_pids" | grep -o "|[0-9]*|$pkg" | head -1)
            
            if [ -n "$is_running" ]; then
                pid=$(echo "$is_running" | cut -d'|' -f2)
                echo "$pid" > "$STATE_DIR/${token}_pid.txt"
                
                matrix_result=$(evaluate_health_matrix "$token" "$pid")
                current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"
                
                if [ "$current_score" -eq 0 ]; then
                    execute_recovery_pipeline "$pkg" "$pid" "$health_status"
                else
                    last_rejoin=$(cat "$CACHE_DIR/${token}_last_rejoin.ts" 2>/dev/null || echo "0")
                    if [ $((now - last_rejoin)) -ge "$FORCE_REJOIN_INTERVAL" ]; then
                        echo "$now" > "$CACHE_DIR/${token}_last_rejoin.ts"
                        execute_recovery_pipeline "$pkg" "$pid" "Ep_vao_Map"
                    fi
                fi
            else
                echo "0" > "$STATE_DIR/${token}_pid.txt"
                echo "0" > "$STATE_DIR/${token}_score.txt"
                
                last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_${token}.ts" 2>/dev/null || echo "0")
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_${token}.ts"
                    execute_recovery_pipeline "$pkg" "0" "MAT_TIEN_TRINH"
                fi
            fi
        done
        
        display_live_ui "$installed_roblox"
        sleep "$CHECK_INTERVAL"
    done
}

# ==================== MAIN ====================
case "$1" in
    watch)
        monitor_core_loop
        ;;
    status)
        setup_dirs
        installed_roblox=$(pm list packages 2>/dev/null | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
        for pkg in $installed_roblox; do
            token="$pkg"
            pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
            [ -z "$pid" ] && pid="0"
            echo "$pkg: PID=$pid"
        done
        ;;
    logs)
        [ -f "$BASE_DIR/executor.log" ] && tail -n 50 "$BASE_DIR/executor.log" || echo "No logs"
        ;;
    *)
        echo "ROBLOX V14 - NEXUS TERMINAL"
        echo ""
        echo "Usage:"
        echo "  sh \$0 watch    - Start live monitor (shows real-time status)"
        echo "  sh \$0 status   - Quick status check"
        echo "  sh \$0 logs     - View logs"
        echo ""
        echo "Install alias:"
        echo "  echo 'alias roblox-watch=\"sh \$HOME/.roblox_auto_rejoin/roblox_v14.sh watch\"' >> \$HOME/.profile"
        echo ""
        ;;
esac
