#!/system/bin/sh
# ===============================================
# ROBLOX AUTO REJOIN - ONE COMMAND INSTALL
# Download từ GitHub + Setup + Run
# ===============================================

echo "=================================="
echo "  ROBLOX AUTO REJOIN INSTALLER"
echo "=================================="
echo ""

# ⚠️ HÃY THAY ĐỔI TÊN USER CỦA BẠN Ở ĐÂY
GITHUB_USER="YOUR_GITHUB_USERNAME"
GITHUB_REPO="roblox-auto-rejoin"
GITHUB_BRANCH="main"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="/data/local/tmp/roblox_state"
LOG_DIR="/data/local/tmp"

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
        echo "[!] Failed to download: $output"
        exit 1
    fi
}

download_files() {
    echo "[*] Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    
    echo "[*] Downloading components from GitHub..."
    
    echo "  -> Downloading Main Executor..."
    download_file "${GITHUB_RAW}/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh" "${INSTALL_DIR}/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    
    echo "  -> Downloading Control Panel..."
    download_file "${GITHUB_RAW}/control_panel.sh" "${INSTALL_DIR}/control_panel.sh"
    
    echo "[+] All files downloaded successfully ✓"
    echo ""
}

# ==================== SETUP PERMISSIONS ====================
setup_permissions() {
    echo "[*] Setting up executable permissions..."
    chmod +x "$INSTALL_DIR/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
    chmod +x "$INSTALL_DIR/control_panel.sh"
    echo "[+] Permissions configured ✓"
    echo ""
}

# ==================== SETUP DIRECTORIES ====================
setup_directories() {
    echo "[*] Preparing system directories..."
    mkdir -p "$STATE_DIR"
    mkdir -p "$LOG_DIR"
    echo "[+] System directories ready ✓"
    echo ""
}

# ==================== CREATE ALIASES ====================
create_aliases() {
    echo "[*] Creating command shortcuts (aliases)..."
    
    local shell_rc=""
    if [ -n "$SHELL" ]; then
        case "$SHELL" in
            *zsh) shell_rc="$HOME/.zshrc" ;;
            *bash) shell_rc="$HOME/.bashrc" ;;
            *) shell_rc="$HOME/.bashrc" ;;
        esac
    else
        shell_rc="$HOME/.bashrc"
    end
    
    [ ! -f "$shell_rc" ] && touch "$shell_rc"
    
    # Kiểm tra xem đã ghi alias chưa, nếu chưa thì ghi vào cuối file cấu hình shell
    if ! grep -q "roblox-rejoin" "$shell_rc"; then
        cat << EOF >> "$shell_rc"

# ROBLOX AUTO REJOIN ALIASES
alias roblox-rejoin="sh \$HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh"
alias roblox-control="sh \$HOME/.roblox_auto_rejoin/control_panel.sh"
alias roblox-status="sh \$HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh status"
alias roblox-logs="sh \$HOME/.roblox_auto_rejoin/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh logs"
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
    
    echo "[*] Please restart Termux or run: source ~/.bashrc (or source ~/.zshrc) to apply shortcuts."
}

main
