#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN - INTERACTIVE SETUP V1.0
# Auto-detect + User config (for any setup)
# ===============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
INSTALL_DIR="$HOME/.roblox_auto_rejoin"
CONFIG_FILE="$INSTALL_DIR/config.conf"
STATE_DIR="/data/local/tmp/roblox_state"
LOG_FILE="/data/local/tmp/roblox_executor.log"

# ==================== BANNER ====================
show_banner() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ROBLOX AUTO REJOIN - SETUP WIZARD   ║${NC}"
    echo -e "${BLUE}║         Auto-Detect & Configure       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

pause_key() {
    echo ""
    echo -n "Press Enter to continue..."
    read -r dummy
}

# ==================== STEP 1: DETECT PACKAGES ====================
step1_detect_packages() {
    show_banner
    echo -e "${CYAN}STEP 1: DETECTING ROBLOX PACKAGES${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo "[*] Scanning device for Roblox apps..."
    echo ""
    
    local packages=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
    
    if [ -z "$packages" ]; then
        echo -e "${RED}[!] No Roblox packages found!${NC}"
        echo ""
        echo "Please install Roblox first:"
        echo "  1. Download Roblox APK from official site"
        echo "  2. Clone the app (multiple instances)"
        echo "  3. Run setup again"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}[+] Found Roblox packages:${NC}"
    echo ""
    
    local count=0
    echo "$packages" | while read pkg; do
        count=$((count + 1))
        echo "  $count. $pkg"
    done
    
    echo ""
    echo "═══════════════════════════════════════════════"
    pause_key
    
    echo "$packages"
}

# ==================== STEP 2: SELECT PACKAGES ====================
step2_select_packages() {
    show_banner
    echo -e "${CYAN}STEP 2: SELECT PACKAGES TO USE${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local packages=$1
    
    echo "Available packages:"
    echo ""
    echo "$packages" | nl -v 1
    echo ""
    
    echo "Options:"
    echo "  [1] Use ALL packages (Auto select)"
    echo "  [2] Select specific packages (Manual)"
    echo ""
    echo -n "Choose (1 or 2): "
    read -r choice
    
    case $choice in
        1)
            echo "$packages"
            ;;
        2)
            echo ""
            echo "Enter package numbers separated by space (e.g: 1 2 3)"
            echo "Or enter package names directly"
            echo ""
            echo -n "Your selection: "
            read -r selection
            
            local selected=""
            local count=1
            echo "$packages" | while read pkg; do
                if echo "$selection" | grep -q -E "^$count$|^$count |$count$| $count "; then
                    echo "$pkg"
                    selected="$selected $pkg"
                fi
                if echo "$selection" | grep -q "$pkg"; then
                    echo "$pkg"
                    selected="$selected $pkg"
                fi
                count=$((count + 1))
            done
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            step2_select_packages "$packages"
            ;;
    esac
}

# ==================== STEP 3: CONFIRM SELECTION ====================
step3_confirm() {
    show_banner
    echo -e "${CYAN}STEP 3: CONFIRM SELECTION${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local accounts=$1
    
    echo "Selected accounts:"
    echo ""
    echo "$accounts" | nl -v 1
    echo ""
    
    local count=$(echo "$accounts" | wc -l)
    echo "Total: $count account(s)"
    echo ""
    
    echo -n "Proceed? (y/n): "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "$accounts"
    else
        return 1
    fi
}

# ==================== STEP 4: CREATE CONFIG ====================
step4_create_config() {
    show_banner
    echo -e "${CYAN}STEP 4: CREATING CONFIGURATION${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local accounts=$1
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$STATE_DIR"
    
    echo "[*] Creating config file..."
    
    cat > "$CONFIG_FILE" << EOF
# Roblox Auto Rejoin - Auto-generated config
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

PLACE_ID="2753915549"
LOAD_TIME=180
COOLDOWN_TIME=120
CHECK_INTERVAL=15
MAX_RESTARTS=10

# Auto-detected accounts:
ACCOUNTS="$(echo "$accounts" | tr '\n' ' ')"

# Account count: $(echo "$accounts" | wc -l)
EOF
    
    echo "[+] Config created ✓"
    echo ""
    echo "Config location: $CONFIG_FILE"
    echo ""
    
    pause_key
}

# ==================== STEP 5: DOWNLOAD FILES ====================
step5_download_files() {
    show_banner
    echo -e "${CYAN}STEP 5: DOWNLOADING FILES${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo "[*] Downloading from GitHub..."
    echo ""
    
    # Try curl first, then wget
    local github_url="https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main"
    
    # Download executor
    echo "[*] Downloading executor..."
    if command -v curl > /dev/null; then
        curl -s -L -o "$INSTALL_DIR/executor.sh" "$github_url/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    elif command -v wget > /dev/null; then
        wget -q -O "$INSTALL_DIR/executor.sh" "$github_url/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    else
        echo -e "${RED}[!] No curl or wget found${NC}"
        exit 1
    fi
    
    if [ ! -f "$INSTALL_DIR/executor.sh" ]; then
        echo -e "${RED}[!] Failed to download executor${NC}"
        exit 1
    fi
    echo "[+] Executor ✓"
    
    # Download control panel
    echo "[*] Downloading control panel..."
    if command -v curl > /dev/null; then
        curl -s -L -o "$INSTALL_DIR/control.sh" "$github_url/control_panel.sh"
    elif command -v wget > /dev/null; then
        wget -q -O "$INSTALL_DIR/control.sh" "$github_url/control_panel.sh"
    fi
    
    if [ ! -f "$INSTALL_DIR/control.sh" ]; then
        echo -e "${YELLOW}[!] Warning: Control panel download failed (optional)${NC}"
    else
        echo "[+] Control panel ✓"
    fi
    
    chmod +x "$INSTALL_DIR/executor.sh" 2>/dev/null
    chmod +x "$INSTALL_DIR/control.sh" 2>/dev/null
    
    echo ""
    echo "[+] All files downloaded ✓"
    echo ""
    
    pause_key
}

# ==================== STEP 6: CREATE LAUNCHER ====================
step6_create_launcher() {
    show_banner
    echo -e "${CYAN}STEP 6: CREATING LAUNCHER${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local config_file=$1
    
    echo "[*] Creating launcher script..."
    
    cat > "$INSTALL_DIR/start.sh" << 'LAUNCHER_EOF'
#!/system/bin/sh
# Load config
CONFIG_FILE="$HOME/.roblox_auto_rejoin/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[!] Config not found. Run setup first!"
    exit 1
fi

. "$CONFIG_FILE"

# Run executor with auto-detected accounts
sh "$HOME/.roblox_auto_rejoin/executor.sh" $ACCOUNTS
LAUNCHER_EOF
    
    chmod +x "$INSTALL_DIR/start.sh"
    
    echo "[+] Launcher created ✓"
    echo ""
    echo "Launcher: $INSTALL_DIR/start.sh"
    echo ""
    
    pause_key
}

# ==================== STEP 7: SETUP ALIASES ====================
step7_setup_aliases() {
    show_banner
    echo -e "${CYAN}STEP 7: SETTING UP ALIASES${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local profile="$HOME/.bashrc"
    
    if [ ! -f "$profile" ]; then
        profile="$HOME/.profile"
    fi
    
    echo "[*] Adding aliases to $profile..."
    
    if ! grep -q "roblox-rejoin" "$profile" 2>/dev/null; then
        cat >> "$profile" << 'ALIAS_EOF'

# Roblox Auto Rejoin Aliases
alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/start.sh"
alias roblox-control="sh $HOME/.roblox_auto_rejoin/control.sh"
alias roblox-config="cat $HOME/.roblox_auto_rejoin/config.conf"
ALIAS_EOF
        echo "[+] Aliases added ✓"
    else
        echo "[+] Aliases already exist ✓"
    fi
    
    echo ""
    pause_key
}

# ==================== FINAL SUCCESS ====================
show_success() {
    show_banner
    echo -e "${GREEN}✅ SETUP COMPLETE!${NC}"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -e "${CYAN}Quick Start:${NC}"
    echo ""
    echo "  Option 1 (Recommended):"
    echo "    ${GREEN}roblox-rejoin${NC}"
    echo ""
    echo "  Option 2 (Full path):"
    echo "    ${GREEN}sh $INSTALL_DIR/start.sh${NC}"
    echo ""
    echo "  Control Panel (in another terminal):"
    echo "    ${GREEN}roblox-control${NC}"
    echo ""
    echo "  View Config:"
    echo "    ${GREEN}roblox-config${NC}"
    echo ""
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo "Configuration saved to:"
    echo "  $CONFIG_FILE"
    echo ""
    
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Source your shell: ${GREEN}source ~/.bashrc${NC}"
    echo "  2. Start executor: ${GREEN}roblox-rejoin${NC}"
    echo "  3. Open control panel in another terminal"
    echo "  4. Open dashboard in browser"
    echo ""
    
    echo "═══════════════════════════════════════════════"
    pause_key
}

# ==================== MAIN FLOW ====================
main() {
    # Step 1: Detect packages
    local packages=$(step1_detect_packages)
    
    if [ -z "$packages" ]; then
        echo -e "${RED}No packages found!${NC}"
        exit 1
    fi
    
    # Step 2: Select packages
    local selected=$(step2_select_packages "$packages")
    
    if [ -z "$selected" ]; then
        echo -e "${RED}No packages selected!${NC}"
        exit 1
    fi
    
    # Step 3: Confirm selection
    local confirmed=$(step3_confirm "$selected")
    
    if [ -z "$confirmed" ]; then
        echo -e "${RED}Setup cancelled${NC}"
        exit 1
    fi
    
    # Step 4: Create config
    step4_create_config "$confirmed"
    
    # Step 5: Download files
    step5_download_files
    
    # Step 6: Create launcher
    step6_create_launcher "$CONFIG_FILE"
    
    # Step 7: Setup aliases
    step7_setup_aliases
    
    # Show success
    show_success
}

# ==================== RUN ====================
main