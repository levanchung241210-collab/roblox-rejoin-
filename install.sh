#!/bin/bash
# ===============================================
# ROBLOX AUTO REJOIN - ONE COMMAND INSTALL
# Download từ GitHub + Setup + Run
# ===============================================

echo "=================================="
echo "  ROBLOX AUTO REJOIN INSTALLER"
echo "=================================="
echo ""

# Config chuẩn theo Kho chứa mới của bạn
# Config chuẩn xác 100%
GITHUB_USER="levanchung241210-collab"
GITHUB_REPO="roblox-rejoin-"
GITHUB_BRANCH="main"

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$HOME/.roblox_auto_rejoin/roblox_state"
LOG_DIR="$HOME/.roblox_auto_rejoin"

# ==================== CHECK DEPENDENCIES ====================
check_dependencies() {
    echo "[*] Checking dependencies..."
    
    # Check curl or wget
    if ! command -v curl > /dev/null && ! command -v wget > /dev/null; then
        echo "[!] Error: Neither curl nor wget found"
        echo "Please install curl or wget first"
        exit 1
    fi
    
    echo "[+] Dependencies OK ✓"
    echo ""
}

# ==================== DOWNLOAD FILES ====================
download_file() {
    local url=$1
    local output=$2
    
    if command -v curl > /dev/null; then
        curl -s -L -o "$output" "$url"
    else
        wget -q -O "$output" "$url"
    fi
    
    if [ ! -f "$output" ]; then
        echo "[!] Failed to download: $url"
        return 1
    fi
    
    return 0
}

download_files() {
    echo "[*] Creating install directory..."
    mkdir -p "$INSTALL_DIR"
    
    echo "[*] Downloading files from GitHub..."
    echo ""
    
    # Download main executor
    echo "  [*] Downloading executor..."
    download_file \
        "$GITHUB_RAW/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh" \
        "$INSTALL_DIR/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    if [ $? -eq 0 ]; then
        echo "  [+] Executor ✓"
    else
        echo "  [!] Executor ✗"
        exit 1
    fi
    
    # Download control panel
    echo "  [*] Downloading control panel..."
    download_file \
        "$GITHUB_RAW/control_panel.sh" \
        "$INSTALL_DIR/control_panel.sh"
    if [ $? -eq 0 ]; then
        echo "  [+] Control panel ✓"
    else
        echo "  [!] Control panel ✗"
        exit 1
    fi
    
    echo ""
    echo "[+] All files downloaded ✓"
    echo ""
}

# ==================== SETUP PERMISSIONS ====================
setup_permissions() {
    echo "[*] Setting up permissions..."
    
    chmod +x "$INSTALL_DIR/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    chmod +x "$INSTALL_DIR/control_panel.sh"
    
    echo "[+] Permissions set ✓"
    echo ""
}

# ==================== CREATE DIRECTORIES ====================
setup_directories() {
    echo "[*] Creating directories..."
    
    mkdir -p "$STATE_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "/sdcard/Download"
    
    echo "[+] Directories created ✓"
    echo ""
}

# ==================== CREATE ALIASES ====================
create_aliases() {
    echo "[*] Creating aliases..."
    
    local profile_file="$HOME/.bashrc"
    if [ ! -f "$profile_file" ]; then
        profile_file="$HOME/.profile"
    fi
    
    # Add aliases
    if ! grep -q "roblox-rejoin" "$profile_file" 2>/dev/null; then
        cat >> "$profile_file" << 'EOF'

# Roblox Auto Rejoin Aliases
alias roblox-rejoin="sh $HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
alias roblox-control="sh $HOME/.roblox_auto_rejoin/control_panel.sh"
alias roblox-status="sh $HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh status"
alias roblox-logs="sh $HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh logs"
EOF
        echo "[+] Aliases created ✓"
    else
        echo "[+] Aliases already exist ✓"
    fi
    
    echo ""
}

# ==================== SHOW SUCCESS ====================
show_success() {
    echo "=================================="
    echo "  ✅ INSTALLATION COMPLETE!"
    echo "=================================="
    echo ""
    echo "📁 Install location: $INSTALL_DIR"
    echo "📝 Logs location: $LOG_DIR/roblox_executor.log"
    echo "⚙️  State location: $STATE_DIR"
    echo ""
    echo "🚀 Quick Start Commands:"
    echo ""
    echo "  Run executor:"
    echo "    roblox-rejoin"
    echo ""
    echo "  Or full path:"
    echo "    sh $INSTALL_DIR/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    echo ""
    echo "  Control panel (open in another terminal):"
    echo "    roblox-control"
    echo ""
    echo "  Check status:"
    echo "    roblox-status"
    echo ""
    echo "  View logs:"
    echo "    roblox-logs"
    echo ""
    echo "=================================="
    echo ""
}

# ==================== MAIN ====================
main() {
    check_dependencies
    download_files
    setup_permissions
    setup_directories
    create_aliases
    show_success
    
    echo "Source your shell profile to use aliases:"
    echo "  source $HOME/.bashrc"
    echo ""
    echo "Or just use full path to start immediately:"
    echo "  sh $INSTALL_DIR/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    echo ""
}

main