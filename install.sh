#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN - SMART INSTALLER
# Auto-detect + Simple confirm (1 question only)
# ===============================================

echo "=================================="
echo "  ROBLOX AUTO REJOIN"
echo "=================================="
echo ""

# Paths
INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="/data/local/tmp/roblox_state"

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$STATE_DIR"
mkdir -p "/sdcard/Download"

# AUTO-DETECT packages
echo "[*] Scanning for Roblox apps..."
PACKAGES=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')

if [ -z "$PACKAGES" ]; then
    echo "[!] No Roblox packages found!"
    echo "Please install Roblox first"
    exit 1
fi

echo ""
echo "[+] Found these Roblox apps:"
echo ""
PACKAGE_COUNT=0
echo "$PACKAGES" | while read pkg; do
    PACKAGE_COUNT=$((PACKAGE_COUNT + 1))
    echo "  $PACKAGE_COUNT. $pkg"
done

TOTAL=$(echo "$PACKAGES" | wc -l)
echo ""
echo "Total: $TOTAL app(s)"
echo ""

# ASK USER - Simple yes/no
echo "Use all detected apps? (y/n)"
read -r answer

if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Cancelled"
    exit 1
fi

echo ""
echo "[*] Setting up..."

# Download files
GITHUB_RAW="https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main"

if command -v curl > /dev/null; then
    DL="curl -s -L -o"
elif command -v wget > /dev/null; then
    DL="wget -q -O"
else
    echo "[!] No curl or wget!"
    exit 1
fi

echo "[*] Downloading executor..."
$DL "$INSTALL_DIR/executor.sh" "$GITHUB_RAW/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
if [ ! -f "$INSTALL_DIR/executor.sh" ]; then
    echo "[!] Download failed"
    exit 1
fi

echo "[*] Downloading control panel..."
$DL "$INSTALL_DIR/control.sh" "$GITHUB_RAW/control_panel.sh"

chmod +x "$INSTALL_DIR/executor.sh"
chmod +x "$INSTALL_DIR/control.sh"

echo ""
echo "[+] Files downloaded ✓"
echo ""

# Create launcher
cat > "$INSTALL_DIR/start.sh" << 'LAUNCHER'
#!/system/bin/sh
PACKAGES=$(pm list packages 2>/dev/null | grep -i roblox | sed 's/package://')
sh "$HOME/.roblox_auto_rejoin/executor.sh" $PACKAGES
LAUNCHER

chmod +x "$INSTALL_DIR/start.sh"

# Create aliases
PROFILE="$HOME/.bashrc"
[ ! -f "$PROFILE" ] && PROFILE="$HOME/.profile"

if ! grep -q "roblox-rejoin" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'ALIASES'

# Roblox Auto Rejoin
alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/start.sh"
alias roblox-control="sh $HOME/.roblox_auto_rejoin/control.sh"
ALIASES
fi

echo "=================================="
echo "  ✅ INSTALLATION COMPLETE"
echo "=================================="
echo ""
echo "Quick commands:"
echo "  roblox-rejoin    (start executor)"
echo "  roblox-control   (control panel)"
echo ""
echo "Or run directly:"
echo "  sh $INSTALL_DIR/start.sh"
echo ""
echo "=================================="
