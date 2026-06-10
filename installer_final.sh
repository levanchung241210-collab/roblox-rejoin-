#!/system/bin/sh
echo "UID=$(id -u)"
echo "USER=$(id)"
# ===============================================
# ROBLOX AUTO REJOIN - FINAL INSTALLER V2
# Complete rewrite - Tested & Working
# ===============================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Paths
INSTALL_DIR="$HOME/.roblox_auto_rejoin"
CONFIG_FILE="$INSTALL_DIR/packages.conf"
STATE_DIR="$HOME/.roblox_auto_rejoin/state"
LOG_FILE="$HOME/.roblox_auto_rejoin/executor.log"

echo "${BLUE}================================${NC}"
echo "${BLUE}  ROBLOX AUTO REJOIN INSTALLER${NC}"
echo "${BLUE}================================${NC}"
echo ""

# ==================== STEP 1: DETECT PACKAGES ====================
echo "${YELLOW}[STEP 1] Scanning for Roblox packages...${NC}"
echo ""

PACKAGES=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')

if [ -z "$PACKAGES" ]; then
    echo "${RED}[ERROR] No Roblox packages found!${NC}"
    echo "Please install Roblox first"
    exit 1
fi

echo "${GREEN}[+] Found Roblox apps:${NC}"
echo ""
COUNT=0
COUNT=1
echo "$PACKAGES" | while IFS= read -r pkg; do
    echo "    $COUNT. $pkg"
    COUNT=$(expr $COUNT + 1)
done

TOTAL=$(printf "%s\n" "$PACKAGES" | wc -l)
echo ""
echo "${GREEN}Total: $TOTAL app(s)${NC}"
echo ""

# ==================== STEP 2: AUTO SELECTION ====================
echo "${YELLOW}[STEP 2] Auto selection${NC}"
echo ""

echo "${GREEN}[+] Using all detected apps automatically${NC}"
echo ""

echo ""

# ==================== STEP 3: CREATE DIRECTORIES ====================
echo "${YELLOW}[STEP 3] Setting up directories...${NC}"

mkdir -p "$INSTALL_DIR"
mkdir -p "$STATE_DIR"
mkdir -p "/sdcard/Download"

echo "${GREEN}[+] Directories created${NC}"
echo ""

# ==================== STEP 4: SAVE CONFIG ====================
echo "${YELLOW}[STEP 4] Saving configuration...${NC}"

cat > "$CONFIG_FILE" << EOF
# Auto-detected packages
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
PACKAGES="$PACKAGES"
TOTAL_PACKAGES=$TOTAL
EOF

echo "${GREEN}[+] Config saved: $CONFIG_FILE${NC}"
echo ""

# ==================== STEP 5: DOWNLOAD FILES ====================
echo "${YELLOW}[STEP 5] Downloading files from GitHub...${NC}"
echo ""

GITHUB_RAW="https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main"

# Check download tool
if command -v curl > /dev/null 2>&1; then
    DL_CMD="curl -s -L"
elif command -v wget > /dev/null 2>&1; then
    DL_CMD="wget -q -O"
else
    echo "${RED}[ERROR] No curl or wget found${NC}"
    exit 1
fi

# Download executor
echo "[*] Downloading executor..."
if command -v curl > /dev/null 2>&1; then
    curl -s -L -o "$INSTALL_DIR/executor.sh" "$GITHUB_RAW/roblox_rejoin_v4.0_ULTIMATE_PERFECT-1.sh"
else
    wget -q -O "$INSTALL_DIR/executor.sh" "$GITHUB_RAW/roblox_rejoin_v4.0_ULTIMATE_PERFECT-1.sh"
fi

if [ ! -f "$INSTALL_DIR/executor.sh" ]; then
    echo "${RED}[ERROR] Failed to download executor${NC}"
    exit 1
fi
echo "${GREEN}[+] Executor downloaded${NC}"

# Download control panel
echo "[*] Downloading control panel..."
if command -v curl > /dev/null 2>&1; then
    curl -s -L -o "$INSTALL_DIR/control.sh" "$GITHUB_RAW/control_panel.sh"
else
    wget -q -O "$INSTALL_DIR/control.sh" "$GITHUB_RAW/control_panel.sh"
fi

if [ -f "$INSTALL_DIR/control.sh" ]; then
    echo "${GREEN}[+] Control panel downloaded${NC}"
else
    echo "${YELLOW}[!] Control panel download skipped${NC}"
fi

chmod +x "$INSTALL_DIR/executor.sh"
chmod +x "$INSTALL_DIR/control.sh" 2>/dev/null

echo ""

# ==================== STEP 6: CREATE LAUNCHER ====================
echo "${YELLOW}[STEP 6] Creating launcher script...${NC}"

cat > "$INSTALL_DIR/start.sh" << 'LAUNCHER_SCRIPT'
#!/system/bin/sh
# Auto-reload packages and run executor
PACKAGES=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
if [ -z "$PACKAGES" ]; then
    echo "[ERROR] No Roblox packages found!"
    exit 1
fi
sh "$HOME/.roblox_auto_rejoin/executor.sh" $PACKAGES
LAUNCHER_SCRIPT

chmod +x "$INSTALL_DIR/start.sh"
echo "${GREEN}[+] Launcher created${NC}"
echo ""

# ==================== STEP 7: SETUP ALIASES ====================
echo "${YELLOW}[STEP 7] Setting up shell aliases...${NC}"

PROFILE="$HOME/.bashrc"
if [ ! -f "$PROFILE" ]; then
    PROFILE="$HOME/.profile"
fi

if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'ALIASES_BLOCK'

# ===== Roblox Auto Rejoin Aliases =====
alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/start.sh"
alias roblox-control="sh $HOME/.roblox_auto_rejoin/control.sh"
alias roblox-config="cat $HOME/.roblox_auto_rejoin/packages.conf"
# ====================================
ALIASES_BLOCK
    echo "${GREEN}[+] Aliases added to $PROFILE${NC}"
else
    echo "${GREEN}[+] Aliases already exist${NC}"
fi

echo ""

# ==================== FINAL SUMMARY ====================
echo "${BLUE}================================${NC}"
echo "${GREEN}  ✅ INSTALLATION COMPLETE!${NC}"
echo "${BLUE}================================${NC}"
echo ""

echo "${YELLOW}Quick Start:${NC}"
echo ""
echo "  1. Source your shell:"
echo "     ${GREEN}source ~/.bashrc${NC}"
echo ""
echo "  2. Start executor:"
echo "     ${GREEN}roblox-rejoin${NC}"
echo ""
echo "  3. Control panel (another terminal):"
echo "     ${GREEN}roblox-control${NC}"
echo ""
echo "${YELLOW}Files Location:${NC}"
echo "  Install:  $INSTALL_DIR"
echo "  Config:   $CONFIG_FILE"
echo "  State:    $STATE_DIR"
echo "  Logs:     $LOG_FILE"
echo "  Dashboard: /sdcard/Download/roblox_dashboard.html"
echo ""
echo "${BLUE}================================${NC}"
echo ""

# ==================== AUTO-START EXECUTOR ====================
echo "${YELLOW}[FINAL] Starting executor in 5 seconds...${NC}"
echo ""
sleep 2
echo "3..."
sleep 1
echo "2..."
sleep 1
echo "1..."
sleep 1

echo ""
echo "${GREEN}🚀 Starting...${NC}"
echo ""

# Auto-start executor
sh "$INSTALL_DIR/start.sh"
