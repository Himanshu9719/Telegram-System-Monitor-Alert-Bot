# Telegram System Monitor & Alert Bot (telemon)

A lightweight, zero-overhead Bash daemon that monitors Linux host metrics, triggers proactive alerts for resource spikes, and delivers interactive health reports with visual bandwidth charts directly to your Telegram chat.

Designed specifically for Linux servers, VPSs, and Raspberry Pi / single-board computers.

---

## Features

- **Proactive Threat Alerts:** Real-time background detection for CPU spikes (>90%) and root disk exhaustion (>90%) with built-in cooldowns (1h) to prevent alert fatigue.
- **Scheduled Status Reports:** Automatically delivers comprehensive system summaries every 3 hours.
- **Interactive On-Demand Commands:**
  - `/status` or `/test`: Instantly fetch current health metrics.
  - `/vnstat [flag]`: Generate and send graphical bandwidth statistics using `vnstati` (`-h` hourly, `-d` daily, `-m` monthly, `-w` weekly).
- **Raspberry Pi Telemetry:** Native support for `vcgencmd` reading exact SoC temperatures, undervoltage states, and throttling flags.
- **Docker Container Inspection:** Lists active containers alongside calculated precise uptimes.
- **Resource Breakdown:** Terminal-style visual progress bars for RAM and Disk usage.
- **Access Control:** Automatically ignores and logs requests from unauthorized Telegram `chat_id`s.

---

## Preview

```text
📊 System Health Report
───────────────
🖥 Host: server-01 (192.168.1.50)
⏱ Uptime: 14 days, 3 hrs, 22 min
⚙️ Load (1/5/15m): 0.42, 0.38, 0.35

🌡 CPU Temp: 44.5°C (🟢 Normal)
⚡️ Throttle: 🟢 Healthy

🧠 RAM: 1840MB / 7820MB
[██░░░░░░░░] 23%

💾 Disk (/): 18G / 110G (87G free)
[██░░░░░░░░] 17%

🌐 Live Traffic (eth0):
• ↓ Total RX: 12.45 GB
• ↑ Total TX: 4.80 GB

🐳 Docker (3/3 Running):
• web-app (Up 2d 4h)
• postgres-db (Up 2d 4h)
• redis-cache (Up 2d 4h)
───────────────
🕒 2026-09-01 12:00:00
```
## 1. Install System Dependencies

Update package lists and install required tools:

```bash
# Update package lists
sudo apt update

# Install required core packages and tools
sudo apt install -y curl jq vnstat vnstati gawk

# Start and enable the vnstat bandwidth monitor daemon
sudo systemctl enable --now vnstat

# Verify vnstat service status
sudo systemctl status vnstat --no-pager
```
## 2. Deploy the Monitor Script

Place the script in /usr/local/bin and set execution permissions:

```bash
# Copy the script to the global binary directory
sudo cp telemon.env /usr/local/bin/telemon.sh

# Make the script executable
sudo chmod +x /usr/local/bin/telemon.sh

# Verify the file is in place
ls -l /usr/local/bin/telemon.sh
```
## 3. Create Configuration & Environment File

Store your Telegram bot token and chat ID in a dedicated directory with restricted file permissions (600):

```bash
# Create dedicated configuration directory
sudo mkdir -p /etc/telemon

# Write credentials to the environment file
sudo tee /etc/telemon/telemon.env > /dev/null << 'EOF'
TELEGRAM_BOT_TOKEN="123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"
TELEGRAM_CHAT_ID="123456789"
EOF

# Lock down permissions so only root can read credentials
sudo chmod 600 /etc/telemon/telemon.env
sudo chown root:root /etc/telemon/telemon.env
```

## 4. Set Up Systemd Service

Create a persistent service unit to ensure the script starts on boot and restarts automatically if it crashes:

```bash
# Create the systemd service file
sudo tee /etc/systemd/system/telemon.service > /dev/null << 'EOF'
[Unit]
Description=Telegram System Monitor and Alert Daemon
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/telemon/telemon.env
ExecStart=/usr/local/bin/telemon.sh
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
```

## 5. Enable and Start the Service

Reload systemd, start the daemon, and check its operational status:

```bash
# Reload systemd to detect the new service unit
sudo systemctl daemon-reload

# Enable the service on boot and start it immediately
sudo systemctl enable --now telemon.service

# Verify the service is running
sudo systemctl status telemon.service --no-pager
```

## 6. Maintenance & Management Commands

Useful daily administration commands for managing the daemon:

```bash
# View live real-time output logs
journalctl -u telemon.service -f

# View the last 50 log entries
journalctl -u telemon.service -n 50 --no-pager

# Restart the daemon (e.g., after editing telemon.env)
sudo systemctl restart telemon.service

# Stop the daemon
sudo systemctl stop telemon.service

# Disable service from starting on boot
sudo systemctl disable telemon.service
```
## 7. Complete Uninstallation

To completely remove all installed components and configs:

```bash
# Stop and disable the service
sudo systemctl stop telemon.service
sudo systemctl disable telemon.service

# Remove system files
sudo rm -f /etc/systemd/system/telemon.service
sudo rm -rf /etc/telemon
sudo rm -f /usr/local/bin/telemon.sh

# Reload daemon registry
sudo systemctl daemon-reload
```
