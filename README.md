# Telegram System Monitor & Alert Bot

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

---

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
• web-app (Up 2d 4h)
• postgres-db (Up 2d 4h)
• redis-cache (Up 2d 4h)
───────────────
🕒 2026-09-01 12:00:00
