#!/system/bin/sh
# =================================================================
# ANDROID APPLICATION MONITOR FRAMEWORK (V18.1 - FIXED TERMUX UI)
# Tích hợp: Mở app bằng Monkey 100% thành công | Quét PID bằng lệnh chuẩn
# =================================================================

CHECK_INTERVAL=15
PROCESS_RECOVERY_COOLDOWN=20
FORCE_REJOIN_INTERVAL=180
APP_LAUNCH_GRACE_PERIOD=40

BASE_DIR="/data/local/tmp/.nexus_monitor"
STATE_DIR="$BASE_DIR/state"
CACHE_DIR="$BASE_DIR/cache"

rm -rf "$STATE_DIR"/* "$CACHE_DIR"/*
mkdir -p "$STATE_DIR" "$CACHE_DIR" "/sdcard/Download"

extract_roblox_username() {
    local pkg=$1
    local uname=""
    local data_path="/data/data/$pkg"
    [ ! -d "$data_path" ] && data_path=$(pm path $pkg 2>/dev/null | cut -d':' -f2 | sed 's/\/base.apk//' | sed 's/app/data/')
    
    if [ -d "$data_path/shared_prefs" ]; then
        uname=$(grep -rioA 1 '"Username"' "$data_path/shared_prefs/" 2>/dev/null | grep -i "string" | head -1 | cut -d'>' -f2 | cut -d'<' -f1)
        [ -z "$uname" ] && uname=$(grep -rioE 'username":"[^"]+' "$data_path/shared_prefs/" 2>/dev/null | head -1 | cut -d'"' -f3)
    fi
    [ -z "$uname" ] && uname="Chưa_Login"
    echo "$uname" | cut -c 1-12 
}

# 🎯 DÙNG LỆNH PS CHUẨN ĐỂ TÌM PID
discover_active_instances() {
    local installed_pkgs=$1
    local active_list=""
    for pkg in $installed_pkgs; do
        local pid=$(ps -A 2>/dev/null | grep -w "$pkg" | grep -v ":" | awk '{print $2}' | head -n 1)
        [ -z "$pid" ] && pid=$(ps 2>/dev/null | grep -w "$pkg" | grep -v ":" | awk '{print $2}' | head -n 1)
        
        if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null; then
            active_list="$active_list $pid|$pkg|0"
        fi
    done
    echo "$active_list"
}

evaluate_health_matrix() {
    local token=$1 pid=$2
    local now=$(date +%s)

    local launch_time=$(cat "$CACHE_DIR/${token}_launch.ts" 2>/dev/null || echo "0")
    if [ "$launch_time" -ne 0 ]; then
        if [ $((now - launch_time)) -lt "$APP_LAUNCH_GRACE_PERIOD" ]; then
            echo "100|LAUNCHING" && return 0
        fi
    fi

    local status_file="/proc/$pid/status"
    [ ! -f "$status_file" ] && echo "0|PROCESS_MISSING" && return 0

    local stat_line=$(cat "/proc/$pid/stat" 2>/dev/null)
    local current_ticks=0
    if [ -n "$stat_line" ]; then
        current_ticks=$(echo "$stat_line" | awk '{print $14 + $15}')
    fi

    local last_ticks=$(cat "$CACHE_DIR/${token}_ticks.cache" 2>/dev/null || echo "0")
    echo "$current_ticks" > "$CACHE_DIR/${token}_ticks.cache"

    if [ "$current_ticks" -eq "$last_ticks" ] && [ "$last_ticks" -gt 0 ]; then
        local f_cnt=$(cat "$CACHE_DIR/${token}_freeze.cnt" 2>/dev/null || echo "0")
        f_cnt=$((f_cnt + 1))
        echo "$f_cnt" > "$CACHE_DIR/${token}_freeze.cnt"

        if [ "$f_cnt" -ge 4 ]; then
            echo "0|APP_TREO_CỨNG" && return 0
        fi
    else
        echo "0" > "$CACHE_DIR/${token}_freeze.cnt"
    fi

    echo "95|HEALTHY"
}

execute_recovery_pipeline() {
    local pkg=$1 pid=$2 error_type=$3
    local token="$pkg"
    local now=$(date +%s)
    
    if [ "$error_type" != "Ép_vào_Map" ]; then
        if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$CACHE_DIR/${token}_ticks.cache" "$CACHE_DIR/${token}_freeze.cnt"
        sleep 1
    fi
    
    echo "$now" > "$CACHE_DIR/${token}_launch.ts"
    
    if [ "$error_type" != "Ép_vào_Map" ]; then
        monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        sleep 4
    fi
    
    am start -n "$pkg/com.roblox.client.Activity.MainActivity" -a android.intent.action.VIEW -d "roblox://placeId=2753915549" >/dev/null 2>&1
    
    local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
    echo "$((r_cnt + 1))" > "$STATE_DIR/${token}_restarts.cnt"
    echo "$error_type" > "$STATE_DIR/${token}_last_err.txt"
}

display_live_ui() {
    local installed_pkgs=$1
    local total_tabs=0
    
    printf "\033c" 
    echo "=================================================================="
    echo " ROBLOX V18.1 - NEXUS MONITOR"
    echo "=================================================================="
    printf "%-22s | %-12s | %-6s | %-15s | %-15s\n" "PACKAGE" "ACCOUNT" "SCORE" "STATUS" "NOTE"
    echo "------------------------------------------------------------------"

    for pkg in $installed_pkgs; do
        local token="$pkg"
        local pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "0")
        local score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
        local l_err=$(cat "$STATE_DIR/${token}_last_err.txt" 2>/dev/null || echo "Binh_thuong")
        local username=$(extract_roblox_username "$pkg")
        local r_cnt=$(cat "$STATE_DIR/${token}_restarts.cnt" 2>/dev/null || echo "0")
        
        local status_text="Khoe_Manh"

        if [ "$pid" = "0" ]; then
            score=0
            status_text="Tat/Mat_Tich"
        else
            total_tabs=$((total_tabs + 1))
            [ "$score" -eq 100 ] && status_text="Dang_Mo_Map"
            [ "$score" -lt 90 ] && [ "$score" -gt 0 ] && status_text="Canh_Bao"
        fi

        printf "%-22s | %-12s | %-6s | %-15s | [R:%d] %s\n" "$pkg" "$username" "$score" "$status_text" "$r_cnt" "$l_err"
    done
    
    echo "=================================================================="
    echo " TONG SO TAB DANG CHAY: $total_tabs TAB"
    echo "=================================================================="
    echo ""
}

monitor_core_loop() {
    while true; do
        local installed_roblox=$(pm list packages | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
        local running_pids=$(discover_active_instances "$installed_roblox")
        local now=$(date +%s)

        for pkg in $installed_roblox; do
            local token="$pkg"
            local is_running=$(echo "$running_pids" | tr ' ' '\n' | grep -w "$pkg" | head -1)
            
            if [ -n "$is_running" ]; then
                local pid=$(echo "$is_running" | cut -d'|' -f1)
                echo "$pid" > "$STATE_DIR/${token}_pid.txt"

                local matrix_result=$(evaluate_health_matrix "$token" "$pid")
                local current_score=$(echo "$matrix_result" | cut -d'|' -f1)
                local health_status=$(echo "$matrix_result" | cut -d'|' -f2)
                
                echo "$current_score" > "$STATE_DIR/${token}_score.txt"

                if [ "$current_score" -eq 0 ]; then
                    execute_recovery_pipeline "$pkg" "$pid" "$health_status"
                else
                    local last_rejoin=$(cat "$CACHE_DIR/${token}_last_rejoin.ts" 2>/dev/null || echo "0")
                    if [ $((now - last_rejoin)) -ge "$FORCE_REJOIN_INTERVAL" ]; then
                        echo "$now" > "$CACHE_DIR/${token}_last_rejoin.ts"
                        execute_recovery_pipeline "$pkg" "$pid" "Ép_vào_Map"
                    fi
                fi
            else
                echo "0" > "$STATE_DIR/${token}_pid.txt"
                echo "0" > "$STATE_DIR/${token}_score.txt"
                
                local last_miss_rcv=$(cat "$CACHE_DIR/miss_recovery_${token}.ts" 2>/dev/null || echo "0")
                if [ $((now - last_miss_rcv)) -ge "$PROCESS_RECOVERY_COOLDOWN" ]; then
                    echo "$now" > "$CACHE_DIR/miss_recovery_${token}.ts"
                    execute_recovery_pipeline "$pkg" "0" "MẤT_TIẾN_TRÌNH"
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
        installed_roblox=$(pm list packages 2>/dev/null | grep -i "roblox" | cut -d':' -f2 | tr -d '\r')
        echo "Status check:"
        for pkg in $installed_roblox; do
            token="$pkg"
            pid=$(cat "$STATE_DIR/${token}_pid.txt" 2>/dev/null || echo "0")
            score=$(cat "$STATE_DIR/${token}_score.txt" 2>/dev/null || echo "0")
            echo "  $pkg: PID=$pid Score=$score"
        done
        ;;
    *)
        echo "ROBLOX V18.1 - NEXUS MONITOR"
        echo ""
        echo "Usage: sh roblox_v18.1.sh watch"
        ;;
esac
