#!/system/bin/sh
# ===============================================
# ROBLOX CONTROL PANEL V1.0
# Menu điều khiển đầy đủ chức năng
# ===============================================

STATE_DIR="/data/local/tmp/roblox_state"
LOG_FILE="/data/local/tmp/roblox_executor.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ==================== UTILITY FUNCTIONS ====================
clear_screen() {
    clear
}

pause_key() {
    echo ""
    echo -n "Press Enter to continue..."
    read -r
}

show_header() {
    clear_screen
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  🎮 ROBLOX AUTO REJOIN CONTROL PANEL  ║${NC}"
    echo -e "${BLUE}║              V4.0 PERFECT             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# ==================== STATS FUNCTIONS ====================
show_stats() {
    show_header
    echo -e "${CYAN}📊 LIVE STATISTICS${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local active=0
    local farming=0
    local error=0
    local paused=0
    local banned=0
    
    for state_file in "$STATE_DIR"/*.state; do
        if [ -f "$state_file" ]; then
            local state=$(grep "^STATE=" "$state_file" | cut -d'=' -f2)
            local pid_check=$(grep "^STATE=" "$state_file" | head -1)
            
            case $state in
                RUNNING)
                    local acc=$(basename "$state_file" .state)
                    local pid=$(pidof "$acc" 2>/dev/null)
                    if [ -z "$pid" ]; then
                        error=$((error + 1))
                    else
                        farming=$((farming + 1))
                        active=$((active + 1))
                    fi
                    ;;
                PAUSED) paused=$((paused + 1)) ;;
                BANNED) banned=$((banned + 1)) ;;
            esac
        fi
    done
    
    echo -e "${GREEN}  ✅ ACTIVE:${NC}   $active"
    echo -e "${BLUE}  🚜 FARMING:${NC}  $farming"
    echo -e "${RED}  ⚠️  ERROR:${NC}    $error"
    echo -e "${YELLOW}  ⏸  PAUSED:${NC}  $paused"
    echo -e "${MAGENTA}  🚫 BANNED:${NC}  $banned"
    echo ""
    echo "═══════════════════════════════════════════════"
    pause_key
}

# ==================== ACCOUNTS FUNCTIONS ====================
show_all_accounts() {
    show_header
    echo -e "${CYAN}📋 ALL ACCOUNTS STATUS${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    if [ ! -d "$STATE_DIR" ] || [ -z "$(ls -A $STATE_DIR 2>/dev/null)" ]; then
        echo -e "${YELLOW}No accounts found${NC}"
        pause_key
        return
    fi
    
    local count=0
    for state_file in "$STATE_DIR"/*.state; do
        if [ -f "$state_file" ]; then
            count=$((count + 1))
            local acc=$(basename "$state_file" .state)
            local state=$(grep "^STATE=" "$state_file" | cut -d'=' -f2)
            local restart=$(grep "^RESTART_COUNT=" "$state_file" | cut -d'=' -f2)
            local error=$(grep "^LAST_ERROR=" "$state_file" | cut -d'=' -f2)
            local uptime_start=$(grep "^UPTIME_START=" "$state_file" | cut -d'=' -f2)
            local current_time=$(date +%s)
            local uptime=$((current_time - uptime_start))
            
            local uptime_str=""
            if [ $uptime -ge 3600 ]; then
                uptime_str="$((uptime/3600))h $(($(($uptime % 3600))/60))m"
            else
                uptime_str="$((uptime/60))m $((uptime%60))s"
            fi
            
            local icon=""
            local color=""
            case $state in
                RUNNING)
                    local pid=$(pidof "$acc" 2>/dev/null)
                    if [ -z "$pid" ]; then
                        icon="⏳"
                        color="$YELLOW"
                    else
                        icon="▶"
                        color="$GREEN"
                    fi
                    ;;
                PAUSED) icon="⏸"; color="$YELLOW" ;;
                BANNED) icon="🚫"; color="$RED" ;;
                *) icon="❓"; color="$CYAN" ;;
            esac
            
            printf "${color}%2d. %s %s | State: %-7s | Restart: %2s | Error: %-3s | Uptime: %s${NC}\n" \
                "$count" "$icon" "$acc" "$state" "$restart" "$error" "$uptime_str"
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════"
    pause_key
}

# ==================== PAUSE/RESUME FUNCTIONS ====================
pause_single() {
    show_header
    echo -e "${CYAN}⏸  PAUSE ACCOUNT${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    show_all_accounts
    
    echo ""
    echo -n "Enter account name to pause (or press Enter to cancel): "
    read -r acc
    
    if [ -z "$acc" ]; then
        return
    fi
    
    local state_file="$STATE_DIR/${acc}.state"
    if [ ! -f "$state_file" ]; then
        echo -e "${RED}❌ Account not found: $acc${NC}"
        pause_key
        return
    fi
    
    sed -i "s|^STATE=.*|STATE=PAUSED|g" "$state_file" 2>/dev/null
    echo -e "${GREEN}✅ Account PAUSED: $acc${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$acc] PAUSED by user" >> "$LOG_FILE"
    pause_key
}

resume_single() {
    show_header
    echo -e "${CYAN}▶  RESUME ACCOUNT${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    show_all_accounts
    
    echo ""
    echo -n "Enter account name to resume (or press Enter to cancel): "
    read -r acc
    
    if [ -z "$acc" ]; then
        return
    fi
    
    local state_file="$STATE_DIR/${acc}.state"
    if [ ! -f "$state_file" ]; then
        echo -e "${RED}❌ Account not found: $acc${NC}"
        pause_key
        return
    fi
    
    sed -i "s|^STATE=.*|STATE=RUNNING|g" "$state_file" 2>/dev/null
    echo -e "${GREEN}✅ Account RESUMED: $acc${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$acc] RESUMED by user" >> "$LOG_FILE"
    pause_key
}

pause_all() {
    show_header
    echo -e "${CYAN}⏸  PAUSE ALL ACCOUNTS${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -n "Are you sure? (y/n): "
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return
    fi
    
    local count=0
    for state_file in "$STATE_DIR"/*.state; do
        if [ -f "$state_file" ]; then
            sed -i "s|^STATE=.*|STATE=PAUSED|g" "$state_file" 2>/dev/null
            local acc=$(basename "$state_file" .state)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$acc] PAUSED (all)" >> "$LOG_FILE"
            count=$((count + 1))
        fi
    done
    
    echo -e "${GREEN}✅ All $count accounts PAUSED${NC}"
    pause_key
}

resume_all() {
    show_header
    echo -e "${CYAN}▶  RESUME ALL ACCOUNTS${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -n "Are you sure? (y/n): "
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return
    fi
    
    local count=0
    for state_file in "$STATE_DIR"/*.state; do
        if [ -f "$state_file" ]; then
            sed -i "s|^STATE=.*|STATE=RUNNING|g" "$state_file" 2>/dev/null
            local acc=$(basename "$state_file" .state)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$acc] RESUMED (all)" >> "$LOG_FILE"
            count=$((count + 1))
        fi
    done
    
    echo -e "${GREEN}✅ All $count accounts RESUMED${NC}"
    pause_key
}

# ==================== LOGS FUNCTIONS ====================
show_logs() {
    show_header
    echo -e "${CYAN}📝 RECENT LOGS (Last 50 lines)${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}No logs found${NC}"
        pause_key
        return
    fi
    
    tail -n 50 "$LOG_FILE"
    echo ""
    echo "═══════════════════════════════════════════════"
    pause_key
}

show_live_logs() {
    show_header
    echo -e "${CYAN}📡 LIVE LOGS (Press Ctrl+C to stop)${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}No logs found${NC}"
        pause_key
        return
    fi
    
    tail -f "$LOG_FILE"
}

# ==================== ACCOUNT DETAIL FUNCTION ====================
show_account_detail() {
    show_header
    echo -e "${CYAN}🔍 ACCOUNT DETAIL${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -n "Enter account name (or press Enter to cancel): "
    read -r acc
    
    if [ -z "$acc" ]; then
        return
    fi
    
    local state_file="$STATE_DIR/${acc}.state"
    if [ ! -f "$state_file" ]; then
        echo -e "${RED}❌ Account not found: $acc${NC}"
        pause_key
        return
    fi
    
    clear_screen
    echo -e "${CYAN}📊 ACCOUNT: $acc${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    cat "$state_file" | while read line; do
        key=$(echo "$line" | cut -d'=' -f1)
        value=$(echo "$line" | cut -d'=' -f2)
        
        case $key in
            STATE) echo -e "${GREEN}State:${NC} $value" ;;
            RESTART_COUNT) echo -e "${YELLOW}Restarts:${NC} $value" ;;
            LAST_ERROR) echo -e "${RED}Last Error:${NC} $value" ;;
            UPTIME_START) 
                local current=$(date +%s)
                local uptime=$((current - value))
                if [ $uptime -ge 3600 ]; then
                    uptime_str="$((uptime/3600))h $(($(($uptime % 3600))/60))m"
                else
                    uptime_str="$((uptime/60))m $((uptime%60))s"
                fi
                echo -e "${BLUE}Uptime:${NC} $uptime_str"
                ;;
            LAST_REJOIN) echo -e "${CYAN}Last Rejoin:${NC} $(date -d @$value '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $value)" ;;
            GFX_TIMEOUT) echo -e "${MAGENTA}GFX Timeout:${NC} $value" ;;
            FREEZE_COUNT) echo -e "${RED}Freeze Count:${NC} $value" ;;
        esac
    done
    
    echo ""
    echo "═══════════════════════════════════════════════"
    pause_key
}

# ==================== MAIN MENU ====================
show_menu() {
    show_header
    echo -e "${YELLOW}Main Menu:${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 📊 Show Statistics"
    echo -e "  ${GREEN}2.${NC} 📋 Show All Accounts"
    echo -e "  ${GREEN}3.${NC} 🔍 Account Detail"
    echo -e "  ${GREEN}4.${NC} ⏸  Pause Single Account"
    echo -e "  ${GREEN}5.${NC} ▶  Resume Single Account"
    echo -e "  ${GREEN}6.${NC} ⏸  Pause All Accounts"
    echo -e "  ${GREEN}7.${NC} ▶  Resume All Accounts"
    echo -e "  ${GREEN}8.${NC} 📝 Show Logs"
    echo -e "  ${GREEN}9.${NC} 📡 Live Logs (tail -f)"
    echo -e "  ${GREEN}0.${NC} 🚪 Exit"
    echo ""
    echo "═══════════════════════════════════════════════"
    echo -n "Choose option: "
    read -r choice
    
    case $choice in
        1) show_stats ;;
        2) show_all_accounts ;;
        3) show_account_detail ;;
        4) pause_single ;;
        5) resume_single ;;
        6) pause_all ;;
        7) resume_all ;;
        8) show_logs ;;
        9) show_live_logs ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) 
            echo -e "${RED}Invalid option${NC}"
            pause_key
            ;;
    esac
}

# ==================== MAIN LOOP ====================
main() {
    while true; do
        show_menu
    done
}

main
