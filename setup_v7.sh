#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN - SETUP WIZARD V7
# Interactive: User selects tabs + confirms in-game
# ===============================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
CONFIG_FILE="$INSTALL_DIR/config.conf"
TAB_LIST_FILE="$INSTALL_DIR/tabs.list"
STATE_DIR="$INSTALL_DIR/state"

echo "${BLUE}╔════════════════════════════════════════╗${NC}"
echo "${BLUE}║   ROBLOX AUTO REJOIN - SETUP WIZARD   ║${NC}"
echo "${BLUE}║              V7 Interactive            ║${NC}"
echo "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# STEP 1: DETECT PACKAGES
echo "${YELLOW}[STEP 1] Scanning Roblox packages...${NC}"
echo ""

PACKAGES=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')

if [ -z "$PACKAGES" ]; then
    echo "${RED}[!] No Roblox packages found!${NC}"
    echo "Please install Roblox first"
    exit 1
fi

echo "${GREEN}[+] Found Roblox packages:${NC}"
echo ""
COUNT=0
echo "$PACKAGES" | while IFS= read -r pkg; do
    COUNT=$((COUNT + 1))
    echo "    ${GREEN}$COUNT.${NC} $pkg"
done
echo ""

TOTAL=$(echo "$PACKAGES" | wc -l)
echo "Total: $TOTAL packages"
echo ""

# STEP 2: DIRECTORY SETUP
echo "${YELLOW}[STEP 2] Creating directories...${NC}"
mkdir -p "$INSTALL_DIR" "$STATE_DIR" "/sdcard/Download"
echo "${GREEN}[+] Done${NC}"
echo ""

# STEP 3: SAVE PACKAGES
echo "${YELLOW}[STEP 3] Saving package list...${NC}"
echo "$PACKAGES" > "$TAB_LIST_FILE"
echo "${GREEN}[+] Saved to: $TAB_LIST_FILE${NC}"
echo ""

# STEP 4: DOWNLOAD MONITOR
echo "${YELLOW}[STEP 4] Downloading monitor...${NC}"

GITHUB="https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main"

if command -v curl > /dev/null 2>&1; then
    curl -s -L -o "$INSTALL_DIR/monitor.sh" "$GITHUB/monitor_v7.sh"
else
    wget -q -O "$INSTALL_DIR/monitor.sh" "$GITHUB/monitor_v7.sh"
fi

if [ ! -f "$INSTALL_DIR/monitor.sh" ]; then
    echo "${RED}[!] Download failed${NC}"
    exit 1
fi

chmod +x "$INSTALL_DIR/monitor.sh"
echo "${GREEN}[+] Monitor downloaded${NC}"
echo ""

# STEP 5: DOWNLOAD REJOIN
echo "${YELLOW}[STEP 5] Downloading rejoin handler...${NC}"

if command -v curl > /dev/null 2>&1; then
    curl -s -L -o "$INSTALL_DIR/rejoin.sh" "$GITHUB/rejoin_v7.sh"
else
    wget -q -O "$INSTALL_DIR/rejoin.sh" "$GITHUB/rejoin_v7.sh"
fi

if [ ! -f "$INSTALL_DIR/rejoin.sh" ]; then
    echo "${RED}[!] Download failed${NC}"
    exit 1
fi

chmod +x "$INSTALL_DIR/rejoin.sh"
echo "${GREEN}[+] Rejoin handler downloaded${NC}"
echo ""

# STEP 6: CREATE CONFIG
echo "${YELLOW}[STEP 6] Creating configuration...${NC}"

cat > "$CONFIG_FILE" << EOF
# Roblox Auto Rejoin V7 Config
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

PLACE_ID="2753915549"
LINK="roblox://placeId=\$PLACE_ID"

CHECK_INTERVAL=15
VERIFY_TIMEOUT=120
MAX_RESTARTS=10

INSTALL_DIR="$INSTALL_DIR"
STATE_DIR="$STATE_DIR"
TAB_LIST="$TAB_LIST_FILE"
LOG_FILE="$INSTALL_DIR/executor.log"
DASHBOARD="$INSTALL_DIR/dashboard.html"
EOF

echo "${GREEN}[+] Config created${NC}"
echo ""

# STEP 7: CREATE LAUNCHER
echo "${YELLOW}[STEP 7] Creating launcher...${NC}"

cat > "$INSTALL_DIR/start.sh" << 'LAUNCHER'
#!/system/bin/sh
INSTALL_DIR="$HOME/.roblox_auto_rejoin"
sh "$INSTALL_DIR/monitor.sh"
LAUNCHER

chmod +x "$INSTALL_DIR/start.sh"
echo "${GREEN}[+] Launcher ready${NC}"
echo ""

# STEP 8: SETUP ALIASES
echo "${YELLOW}[STEP 8] Setting up aliases...${NC}"

PROFILE="$HOME/.bashrc"
[ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"

if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'ALIAS'

alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/start.sh"
ALIAS
fi

echo "${GREEN}[+] Aliases added${NC}"
echo ""

# FINAL INSTRUCTIONS
echo "${BLUE}╔════════════════════════════════════════╗${NC}"
echo "${GREEN}  ✅ SETUP COMPLETE!${NC}"
echo "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

echo "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Open Roblox on each clone"
echo "   ${GREEN}Open Blox Fruits on clone 1, clone 2, clone 3...${NC}"
echo ""
echo "2. Wait for in-game (at map, not lobby)"
echo "   ${GREEN}Wait until you're fully loaded in game${NC}"
echo ""
echo "3. Start monitor"
echo "   ${GREEN}roblox-rejoin${NC}"
echo ""
echo "4. Monitor will auto-detect which clones are in-game"
echo "   ${GREEN}And start monitoring only those clones${NC}"
echo ""
echo "${YELLOW}Important:${NC}"
echo "  • Keep all clones open before starting monitor"
echo "  • Make sure you're in-game (not in lobby)"
echo "  • Monitor will detect active clones automatically"
echo "  • Dashboard: $INSTALL_DIR/dashboard.html"
echo ""
echo "${BLUE}════════════════════════════════════════${NC}"
echo ""

# WAIT AND START
echo "${YELLOW}Starting monitor in 10 seconds...${NC}"
echo "Press Ctrl+C to cancel"
echo ""

sleep 10

sh "$INSTALL_DIR/start.sh"
