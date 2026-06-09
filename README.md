[README.md](https://github.com/user-attachments/files/28774743/README.md)
# 🎮 Roblox Auto Rejoin

**One-command installer for automatic Roblox game rejoin with smart detection, real-time dashboard, and control panel.**

---

## ⚡ Quick Start (One Command)

```bash
curl -s https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main/setup_interactive.sh | sh
```

Or with wget:

```bash
wget -O - https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main/setup_interactive.sh | sh
```

---

## 🎯 What It Does

✅ **Auto-detect** all Roblox apps on your device  
✅ **Interactive setup** - automatically configures based on your packages  
✅ **Auto-rejoin** when game crashes  
✅ **Smart recovery** - 3-level intelligent error handling  
✅ **Real-time dashboard** - Beautiful web UI at `/sdcard/Download/roblox_dashboard.html`  
✅ **Control panel** - Full-featured menu system  
✅ **Pause/Resume** - Control individual accounts  
✅ **Live logs** - Real-time monitoring  
✅ **Zero manual config** - Works with any Roblox setup  

---

## 🚀 How It Works

### Setup Flow

1. Run one command
2. Script auto-detects Roblox packages
3. You select which accounts to use
4. Downloads and configures everything
5. Ready to use!

### Usage

**Start the executor:**
```bash
roblox-rejoin
```

**Control panel (in another terminal):**
```bash
roblox-control
```

**Check configuration:**
```bash
roblox-config
```

---

## 📋 Features

### Auto-Detection
- Scans device for all Roblox installations
- Works with:
  - Official Roblox app
  - Cloned apps (app cloner)
  - Multiple APK installations
  - Mixed setups

### Executor (`roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh`)
- Auto-detect and monitor Roblox packages
- Smart crash detection
- 3-level recovery system
  - Level 1: Soft retry (80% success)
  - Level 2: App restart (15% success)
  - Level 3: Full reset (5% success)
- Real-time dashboard generation
- Pause/resume per account
- Multi-device safety (264/273 error handling)
- Detailed logging

### Control Panel (`control_panel.sh`)

Interactive menu with options:
```
1. 📊 Show Statistics
2. 📋 Show All Accounts
3. 🔍 Account Detail
4. ⏸  Pause Single Account
5. ▶  Resume Single Account
6. ⏸  Pause All Accounts
7. ▶  Resume All Accounts
8. 📝 Show Logs
9. 📡 Live Logs (tail -f)
0. 🚪 Exit
```

### Dashboard
- Real-time web UI
- Live statistics (Active, Farming, Error, Paused, Banned)
- Account details and status
- Color-coded indicators
- Auto-refresh every 10 seconds
- Location: `/sdcard/Download/roblox_dashboard.html`

---

## 📁 File Structure

After installation:

```
~/.roblox_auto_rejoin/
├── executor.sh                 (Main executor)
├── control.sh                  (Control panel)
├── start.sh                    (Launcher)
├── config.conf                 (Auto-generated config)

/data/local/tmp/
├── roblox_state/              (Account states)
│   ├── com.roblox.client.*.state
│   └── ...
└── roblox_executor.log        (Logs)

/sdcard/Download/
└── roblox_dashboard.html      (Web UI)
```

---

## ⚙️ Configuration

Config is auto-generated during setup, but you can edit:

```bash
# View config
roblox-config

# Edit if needed
cat ~/.roblox_auto_rejoin/config.conf
```

Default settings:
```bash
PLACE_ID="2753915549"      # Game place ID
LOAD_TIME=180              # Loading timeout (seconds)
COOLDOWN_TIME=120          # Cooldown between rejoin
CHECK_INTERVAL=15          # Monitor check interval (seconds)
MAX_RESTARTS=10            # Max restarts before account ban
```

---

## 🔧 Troubleshooting

### No Roblox apps detected
```bash
# Make sure you have Roblox installed
# Install multiple copies if needed:
# - Official app
# - Cloned app
# - Different APKs
```

### Setup fails
```bash
# Check internet connection
ping google.com

# Manually install
sh ~/.roblox_auto_rejoin/start.sh
```

### Menu not showing
```bash
# Make sure in another terminal
# Don't run both executor and control panel in same terminal
```

### Dashboard not updating
```bash
# Refresh browser (F5)
# Check executor is running
# Check file permissions
```

---

## 🔀 Workflow Example

**Terminal 1 - Start Executor:**
```bash
roblox-rejoin
# Output:
# [+] Found 3 packages
# [*] Initializing accounts...
# [+] EXECUTOR RUNNING!
# 📊 Dashboard: /sdcard/Download/roblox_dashboard.html
```

**Terminal 2 - Control Panel:**
```bash
roblox-control
# Menu appears with 10 options
# Select what you need
```

**Browser - Dashboard:**
```
File Manager → /sdcard/Download/roblox_dashboard.html
Open with Chrome/Firefox
See live stats update
```

---

## 📊 Error Codes

The tool handles these Roblox error codes:

| Code | Type | Action |
|------|------|--------|
| 260-262, 266, 277, 279 | Network | Level 1: Soft retry |
| 268, 271, 278, 525 | Server | Level 2: Restart |
| 256, 274, 275, 280, 286, 292 | Maintenance | Level 3: Full reset |
| 264, 267, 272, 273, 524, 600, 523 | Permanent | Stop rejoin |

---

## ⚠️ Important

- ⚠️ This tool may trigger Roblox anti-cheat detection
- ⚠️ Use at your own risk
- ⚠️ Not affiliated with Roblox Corporation
- ⚠️ Read and respect Roblox Terms of Service
- ⚠️ Use only with accounts you can afford to lose

---

## 🛠️ Manual Setup (Alternative)

If one-command fails:

```bash
# 1. Create directory
mkdir -p ~/.roblox_auto_rejoin

# 2. Download files manually
curl -o ~/.roblox_auto_rejoin/executor.sh https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main/roblox_rejoin_v4.0_ULTIMATE_PERFECT.sh
curl -o ~/.roblox_auto_rejoin/control.sh https://raw.githubusercontent.com/levanchung241210-collab/roblox-rejoin-/main/control_panel.sh

# 3. Make executable
chmod +x ~/.roblox_auto_rejoin/*.sh

# 4. Run setup
sh ~/.roblox_auto_rejoin/start.sh
```

---

## 📞 Support

- Check logs: `sh ~/.roblox_auto_rejoin/start.sh logs`
- View config: `roblox-config`
- View status: Check in control panel option 2
- Read this README

---

## 📝 License

MIT License - Use freely, modify as needed

---

## 🙏 Contributing

Found a bug? Have suggestions? Open an issue on GitHub!

---

**Made with ❤️ for Roblox automation**

**Happy Farming! 🎮🚀**
