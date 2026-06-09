#!/bin/bash
# ==============================================================================
# ROBLOX AUTO REJOIN - VERSION 4.0 PERFECT FIXED
# Developed by levanchung241210-collab
# ==============================================================================

# --- Cấu hình thư mục lưu trữ an toàn trong ổ nhà ($HOME) ---
INSTALL_DIR="$HOME/.roblox_auto_rejoin"
STATE_DIR="$INSTALL_DIR/roblox_state"
LOG_FILE="$INSTALL_DIR/roblox_executor.log"
DASHBOARD_FILE="$INSTALL_DIR/dashboard.html"

mkdir -p "$STATE_DIR"

# --- Khởi tạo các biến trạng thái mặc định ---
PLACE_ID="2753915549" # Mặc định Blox Fruits hoặc ID bạn cấu hình
MAX_ATTEMPTS=3
COOLDOWN_BASE=5
FREEZE_THRESHOLD=60

# ==================== HÀM QUÉT PACKAGE CHUẨN XÁC ====================
# Sửa triệt để lỗi nuốt nhầm chữ log hiển thị [!] hay [*] ở ảnh 71923a45-4a44-488a-9253-9be21499ca46
get_roblox_package() {
    if pm list packages 2>/dev/null | grep -q "com.roblox.client.vng"; then
        echo "com.roblox.client.vng"
    elif pm list packages 2>/dev/null | grep -q "com.roblox.client"; then
        echo "com.roblox.client"
    else
        # Nếu thiết bị không lấy được danh sách package (do phân quyền pm), mặc định trả về bản quốc tế
        echo "com.roblox.client"
    fi
}

ROBLOX_PKG=$(get_roblox_package)

# ==================== TIẾN TRÌNH THEO DÕI & XỬ LÝ GAME ====================
log_message() {
    local level=$1
    local msg=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

launch_roblox() {
    log_message "INFO" "Đang khởi động Roblox ($ROBLOX_PKG) với Place ID: $PLACE_ID..."
    
    # Kích hoạt Intent chính xác bằng cấu trúc app android VIEW
    am start -a android.intent.action.VIEW \
             -d "roblox://placeId=$PLACE_ID" \
             -p "$ROBLOX_PKG" > /dev/null 2>&1
             
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Gửi lệnh mở game thành công!"
        echo "$(date +%s)" > "$STATE_DIR/last_launch"
    else
        log_message "ERROR" "Thất bại khi gửi lệnh am start."
    fi
}

check_game_status() {
    # Kiểm tra xem app Roblox có đang chạy ngầm hay không
    if pidof "$ROBLOX_PKG" > /dev/null; then
        return 0 # Game đang chạy bình thường
    else
        return 1 # Game đã bị văng hoặc chưa bật
    fi
}

monitor_freeze() {
    if [ ! -f "$STATE_DIR/last_launch" ]; then
        return 0
    fi
    
    local last_launch=$(cat "$STATE_DIR/last_launch")
    local now=$(date +%s)
    local elapsed=$((now - last_launch))
    
    # Nếu game đứng hình hoặc treo quá thời gian quy định, tiến hành dọn dẹp để hồi sinh
    if [ $elapsed -gt $FREEZE_THRESHOLD ] && check_game_status; then
        log_message "WARNING" "Phát hiện game có dấu hiệu bị đóng băng (Freeze). Tiến hành khởi động lại..."
        pkill -f "$ROBLOX_PKG" > /dev/null 2>&1
        sleep 2
        return 1
    fi
    return 0
}

# ==================== RENDER GIAO DIỆN DASHBOARD HTML ====================
generate_dashboard() {
    local status_text="Đang hoạt động"
    local bg_color="bg-green-500"
    
    if ! check_game_status; then
        status_text="Đang ngoại tuyến / Lỗi"
        bg_color="bg-red-500"
    fi

    cat <<EOF > "$DASHBOARD_FILE"
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Roblox Auto Rejoin Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
</head>
<body class="bg-slate-900 text-white font-sans min-h-screen flex flex-col items-center justify-center p-4">
    <div class="w-full max-w-md bg-slate-800 rounded-2xl shadow-xl border border-slate-700 p-6 text-center">
        <h1 class="text-xl font-bold tracking-wide mb-2 text-indigo-400">ROBLOX AUTO REJOIN V4.0</h1>
        <p class="text-xs text-slate-400 mb-6">Hệ thống giám sát trạng thái tự động</p>
        
        <div class="flex items-center justify-between bg-slate-800 border border-slate-700 p-4 rounded-xl mb-4">
            <span class="text-sm font-medium text-slate-300">Trạng thái Game:</span>
            <span class="px-3 py-1 text-xs font-semibold rounded-full ${bg_color} text-white animate-pulse">${status_text}</span>
        </div>
        
        <div class="text-left bg-slate-950 p-3 rounded-lg border border-slate-800 mb-4 h-32 overflow-y-auto text-xs font-mono text-emerald-400">
            <p>• Thư mục cài đặt gốc: $INSTALL_DIR</p>
            <p>• Package nhận diện: $ROBLOX_PKG</p>
            <p>• Tiến trình đang quét chu kỳ nền...</p>
        </div>
        
        <p class="text-[10px] text-slate-500">Cập nhật tự động: $(date "+%H:%M:%S")</p>
    </div>
</body>
</html>
EOF
}

# ==================== VÒNG LẶP CHÍNH (MAIN LOOP) ====================
clear
echo "=================================================="
echo "      ROBLOX AUTO REJOIN V4.0 FIXED CHUẨN       "
echo "=================================================="
log_message "START" "Hệ thống giám sát bắt đầu chạy..."
log_message "INFO" "Package nhận diện được cấu hình: $ROBLOX_PKG"

# Nếu tham số truyền vào là status hoặc logs thì xử lý nhanh rồi thoát
case "$1" in
    status)
        if check_game_status; then
            echo "Roblox đang CHẠY."
        else
            echo "Roblox đang ĐÓNG."
        fi
        exit 0
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -n 50 "$LOG_FILE"
        else
            echo "Chưa có file log nào được tạo."
        fi
        exit 0
        ;;
esac

# Vòng lặp quét vô hạn kiểm tra trạng thái
while true; do
    generate_dashboard
    monitor_freeze
    
    if ! check_game_status; then
        log_message "CRITICAL" "Phát hiện game bị văng hoặc chưa chạy! Tiến hành Rejoin..."
        launch_roblox
        
        # Đợi một chút xem game có lên thành công không
        attempts=1
        while [ $attempts -le $MAX_ATTEMPTS ]; do
            sleep $COOLDOWN_BASE
            if check_game_status; then
                log_message "SUCCESS" "Game đã được khôi phục thành công ở lần thử $attempts."
                break
            fi
            log_message "RETRY" "Thử lại lần $attempts..."
            launch_roblox
            attempts=$((attempts + 1))
        done
    fi
    
    # Nghỉ 15 giây trước khi thực hiện chu kỳ quét tiếp theo
    sleep 15
done
