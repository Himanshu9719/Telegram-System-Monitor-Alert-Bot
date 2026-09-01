#!/usr/bin/env bash

# ================= Configuration =================
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-xxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
CHAT_ID="${TELEGRAM_CHAT_ID:-xxxxxxxxxxxxxxxxx}"

# Alert Thresholds & Cooldowns
ALERT_CPU_THRESH=90     # Alert if CPU exceeds 90%
ALERT_DISK_THRESH=90    # Alert if Disk exceeds 90%
ALERT_COOLDOWN=3600     # 3600 seconds (1 hour) before repeating an alert
THREAT_CHECK_INTERVAL=60 # Run threat check every 60 seconds (prevents CPU lag)
# =================================================

set -o pipefail

# ----------------- Prerequisite Check -----------------
for cmd in jq curl vnstat vnstati; do
    if ! command -v $cmd &> /dev/null; then
        echo "Warning: Optional dependency '$cmd' is not installed." >&2
    fi
done

# ----------------- State Variables -----------------
LAST_CPU_ALERT=0
LAST_DISK_ALERT=0
LAST_THREAT_CHECK=0

# ----------------- Helper Functions -----------------
html_escape() {
    local text="$1"
    text="${text//&/&amp;}"
    text="${text//</&lt;}"
    text="${text//>/&gt;}"
    echo "$text"
}

render_progress_bar() {
    local perc="${1%.*}"
    [[ ! "$perc" =~ ^[0-9]+$ ]] && perc=0
    [ "$perc" -gt 100 ] && perc=100
    
    local filled=$((perc / 10))
    local empty=$((10 - filled))
    local bar=""
    
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    echo "<code>[${bar}] ${perc}%</code>"
}

format_bytes() {
    local bytes="$1"
    if [ -z "$bytes" ] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 MB"
        return
    fi
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
    else
        awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b/1048576}'
    fi
}

calc_exact_uptime() {
    local start_time="$1"
    local start_sec=$(date -d "$start_time" +%s 2>/dev/null)
    
    if [ -z "$start_sec" ]; then
        echo "N/A"
        return
    fi
    
    local now_sec=$(date +%s)
    local diff=$((now_sec - start_sec))
    [ "$diff" -lt 0 ] && diff=0
    
    local d=$((diff / 86400))
    local h=$(( (diff % 86400) / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    
    local parts=()
    [ $d -gt 0 ] && parts+=("${d}d")
    [ $h -gt 0 ] && parts+=("${h}h")
    [ $m -gt 0 ] && parts+=("${m}m")
    
    if [ ${#parts[@]} -eq 0 ]; then
        echo "Up <1m"
    else
        echo "Up ${parts[*]}"
    fi
}

get_cpu_usage() {
    local stat1=($(grep '^cpu ' /proc/stat))
    sleep 1
    local stat2=($(grep '^cpu ' /proc/stat))
    
    local idle1=${stat1[4]}
    local idle2=${stat2[4]}
    
    local total1=0
    for i in "${stat1[@]:1}"; do total1=$((total1 + i)); done
    
    local total2=0
    for i in "${stat2[@]:1}"; do total2=$((total2 + i)); done
    
    local diff_idle=$((idle2 - idle1))
    local diff_total=$((total2 - total1))
    
    if [ "$diff_total" -eq 0 ]; then echo 0; return; fi
    echo $((100 * (diff_total - diff_idle) / diff_total))
}

# ----------------- Telegram Sending -----------------
send_telegram_msg() {
    local message="$1"
    local http_status
    http_status=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        --data-urlencode "text=${message}" | tail -n1)

    if [ "$http_status" -ne 200 ]; then
        echo "[$(date)] Failed to send message. HTTP Status: $http_status" >&2
    fi
}

send_telegram_photo() {
    local photo_path="$1"
    local caption="$2"
    local http_status
    http_status=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        -F chat_id="${CHAT_ID}" \
        -F photo="@${photo_path}" \
        -F caption="${caption}" \
        -F parse_mode="HTML" | tail -n1)

    if [ "$http_status" -ne 200 ]; then
        echo "[$(date)] Failed to send photo. HTTP Status: $http_status" >&2
    fi
}

# ----------------- Threat Monitoring -----------------
check_threats() {
    local current_time=$(date +%s)
    
    # Run threat check only once every THREAT_CHECK_INTERVAL seconds
    if [ $((current_time - LAST_THREAT_CHECK)) -lt "$THREAT_CHECK_INTERVAL" ]; then
        return
    fi
    LAST_THREAT_CHECK=$current_time

    # 1. Check Disk Space
    local disk_perc=$(df / | awk 'NR==2 {sub(/%/,"",$5); print $5}')
    if [ "$disk_perc" -ge "$ALERT_DISK_THRESH" ]; then
        if [ $((current_time - LAST_DISK_ALERT)) -ge "$ALERT_COOLDOWN" ]; then
            local msg="🚨 <b>CRITICAL ALERT: DISK FULL</b> 🚨

Disk space on root (/) has reached <b>${disk_perc}%</b>! Immediate action required."
            send_telegram_msg "$msg"
            LAST_DISK_ALERT=$current_time
        fi
    fi

    # 2. Check CPU Usage
    local cpu_usage=$(get_cpu_usage)
    if [ "$cpu_usage" -ge "$ALERT_CPU_THRESH" ]; then
        if [ $((current_time - LAST_CPU_ALERT)) -ge "$ALERT_COOLDOWN" ]; then
            local msg="🚨 <b>CRITICAL ALERT: CPU SPIKE</b> 🚨

Host CPU usage has spiked to <b>${cpu_usage}%</b>!"
            send_telegram_msg "$msg"
            LAST_CPU_ALERT=$current_time
        fi
    fi
}

# ----------------- Reporting Logic -----------------
send_status_report() {
    echo "[$(date)] Generating system status report..."
    
    HOSTNAME=$(hostname)
    UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F'( |,|:)+' '{print $6,"hrs,", $7,"min"}')
    LOAD_AVG=$(awk '{printf "%.2f, %.2f, %.2f", $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "N/A")
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    if command -v vcgencmd &>/dev/null; then
        RAW_TEMP=$(vcgencmd measure_temp | tr -cd '0-9.')
        RAW_THROTTLE=$(vcgencmd get_throttled | cut -d'=' -f2)
    else
        RAW_TEMP=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
        RAW_THROTTLE="0x0"
    fi

    CPU_TEMP="${RAW_TEMP:-0}°C"
    TEMP_INT="${RAW_TEMP%.*}"

    if [ "$TEMP_INT" -ge 80 ]; then
        TEMP_BADGE="🔴 Critical"
    elif [ "$TEMP_INT" -ge 70 ]; then
        TEMP_BADGE="🟡 Warm"
    else
        TEMP_BADGE="🟢 Normal"
    fi

    THROTTLE_STATUS="🟢 Healthy"
    if [ "$RAW_THROTTLE" != "0x0" ] && [ -n "$RAW_THROTTLE" ]; then
        THROTTLE_HEX=$((RAW_THROTTLE))
        ISSUES=()
        (( THROTTLE_HEX & 0x1 ))     && ISSUES+=("Under-voltage detected")
        (( THROTTLE_HEX & 0x2 ))     && ISSUES+=("Arm frequency capped")
        (( THROTTLE_HEX & 0x4 ))     && ISSUES+=("Currently throttled")
        (( THROTTLE_HEX & 0x8 ))     && ISSUES+=("Soft temp limit reached")
        
        if [ ${#ISSUES[@]} -gt 0 ]; then
            THROTTLE_STATUS="⚠️ <b>Issues:</b> $(IFS=, ; echo "${ISSUES[*]}")"
        fi
    fi

    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PERC=$(free | awk '/Mem:/ {if ($2 > 0) printf("%.0f", ($3/$2)*100); else print "0"}')
    RAM_BAR=$(render_progress_bar "$RAM_PERC")

    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    DISK_PERC_RAW=$(df / | awk 'NR==2 {sub(/%/,"",$5); print $5}')
    DISK_BAR=$(render_progress_bar "$DISK_PERC_RAW")

    LOCAL_IP=$(hostname -I | awk '{print $1}')
    NET_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    NET_IFACE="${NET_IFACE:-eth0}"

    if [ -d "/sys/class/net/$NET_IFACE/statistics" ]; then
        RX_BYTES=$(cat "/sys/class/net/$NET_IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX_BYTES=$(cat "/sys/class/net/$NET_IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)
        NET_RX=$(format_bytes "$RX_BYTES")
        NET_TX=$(format_bytes "$TX_BYTES")
    else
        NET_RX="N/A"
        NET_TX="N/A"
    fi

    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
        TOTAL_CONTAINERS=$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
            CONTAINER_LIST=""
            for cid in $(docker ps -q 2>/dev/null | head -n 10); do
                c_info=$(docker inspect --format '{{.Name}} {{.State.StartedAt}}' "$cid" 2>/dev/null)
                c_name=$(echo "$c_info" | awk '{print $1}' | sed 's/^\///')
                c_start=$(echo "$c_info" | awk '{print $2}')
                
                c_uptime=$(calc_exact_uptime "$c_start")
                
                if [ -z "$CONTAINER_LIST" ]; then
                    CONTAINER_LIST="• <code>${c_name}</code> (${c_uptime})"
                else
                    CONTAINER_LIST="${CONTAINER_LIST}"$'\n'"• <code>${c_name}</code> (${c_uptime})"
                fi
            done
            
            if [ "$RUNNING_CONTAINERS" -gt 10 ]; then
                CONTAINER_LIST="${CONTAINER_LIST}"$'\n'"• <i>...and $((RUNNING_CONTAINERS - 10)) more</i>"
            fi
        else
            CONTAINER_LIST="<i>No active containers</i>"
        fi
    else
        RUNNING_CONTAINERS="0"
        TOTAL_CONTAINERS="0"
        CONTAINER_LIST="<i>Docker offline/not installed</i>"
    fi

    MESSAGE="📊 <b>System Health Report</b>
───────────────
🖥 <b>Host:</b> <code>$HOSTNAME</code> ($LOCAL_IP)
⏱ <b>Uptime:</b> $UPTIME
⚙️ <b>Load (1/5/15m):</b> <code>$LOAD_AVG</code>

🌡 <b>CPU Temp:</b> <code>$CPU_TEMP</code> ($TEMP_BADGE)
⚡️ <b>Throttle:</b> $THROTTLE_STATUS

🧠 <b>RAM:</b> <code>${RAM_USED}MB / ${RAM_TOTAL}MB</code>
$RAM_BAR

💾 <b>Disk (/):</b> <code>${DISK_USED} / ${DISK_TOTAL} (${DISK_FREE} free)</code>
$DISK_BAR

🌐 <b>Live Traffic (${NET_IFACE}):</b>
• ↓ Total RX: <code>$NET_RX</code>
• ↑ Total TX: <code>$NET_TX</code>

🐳 <b>Docker (${RUNNING_CONTAINERS}/${TOTAL_CONTAINERS} Running):</b>
$CONTAINER_LIST
───────────────
🕒 <i>$TIMESTAMP</i>"

    send_telegram_msg "$MESSAGE"
}

send_vnstat_report() {
    local flag="$1"
    local vflag="-s"
    
    case "$flag" in
        -h) vflag="-h" ;;
        -d) vflag="-d" ;;
        -m) vflag="-m" ;;
        -w) vflag="-w" ;;
        *) vflag="-s" ;;
    esac
    
    echo "[$(date)] Generating visual vnstati report with flag: $vflag"

    if command -v vnstati &>/dev/null; then
        local img_path="/tmp/vnstat_report_${RANDOM}.png"
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        vnstati $vflag -o "$img_path"
        
        if [ -f "$img_path" ]; then
            send_telegram_photo "$img_path" "📶 <b>Bandwidth Graph</b> (<code>vnstati $vflag</code>)
🕒 <i>$TIMESTAMP</i>"
            rm -f "$img_path"
        else
            send_telegram_msg "⚠️ <b>Error:</b> Failed to generate vnstati image."
        fi
    else
        send_telegram_msg "⚠️ <b>Error:</b> <code>vnstati</code> is not installed."
    fi
}

# ----------------- Main Bot Loop -----------------
echo "Telegram Bot & System Monitor started..."
OFFSET=0
LAST_HOUR=$(date +%-H)

while true; do
    # 1. Proactive Threat Checks (Throttled via interval)
    check_threats

    # 2. 3-Hour Check Trigger
    CURRENT_HOUR=$(date +%-H)
    if [ $((CURRENT_HOUR % 3)) -eq 0 ] && [ "$CURRENT_HOUR" != "$LAST_HOUR" ]; then
        echo "[$(date)] 3-Hour interval reached ($CURRENT_HOUR:00). Triggering automated report."
        send_status_report
        LAST_HOUR=$CURRENT_HOUR
    fi

    # 3. Poll Telegram updates (robust parsing with jq)
    POLL_RESPONSE=$(curl -s --max-time 30 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=20&limit=1")
    
    UPDATE_ID=$(echo "$POLL_RESPONSE" | jq -r '.result[0].update_id // empty')

    if [ -n "$UPDATE_ID" ]; then
        SENDER_ID=$(echo "$POLL_RESPONSE" | jq -r '.result[0].message.chat.id // .result[0].edited_message.chat.id // empty')
        
        if [ -n "$SENDER_ID" ] && [ "$SENDER_ID" != "$CHAT_ID" ]; then
            echo "[$(date)] ⚠️ SECURITY BLOCK: Unauthorized access attempt from Chat ID: $SENDER_ID. Ignoring."
            OFFSET=$((UPDATE_ID + 1))
            continue
        fi

        MESSAGE_TEXT=$(echo "$POLL_RESPONSE" | jq -r '.result[0].message.text // empty')

        if [ -n "$MESSAGE_TEXT" ]; then
            echo "[$(date)] Authorized Command Received: $MESSAGE_TEXT"
            
            if [[ "$MESSAGE_TEXT" == "/test" || "$MESSAGE_TEXT" == "/status" ]]; then
                send_status_report
                
            elif [[ "$MESSAGE_TEXT" == /vnstat* ]]; then
                FLAG=$(echo "$MESSAGE_TEXT" | awk '{print $2}')
                send_vnstat_report "$FLAG"
            fi
        fi

        OFFSET=$((UPDATE_ID + 1))
    fi

done
