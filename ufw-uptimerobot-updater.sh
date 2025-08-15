#!/usr/bin/env bash
set -e

echo "🤖 === Adding UptimeRobot IPs to UFW ==="
echo "👤 Running as: $(whoami)"
echo "📅 Date: $(date)"
echo ""

# Define which ports UptimeRobot should access
PORTS=("80" "443")
echo "🔌 Will allow access to ports: ${PORTS[*]}"

# Check if required tools are installed
echo "🔧 Checking dependencies..."
if ! command -v curl &> /dev/null; then
    echo "📦 Installing curl..."
    apt-get update
    apt-get install curl -y
fi

if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq for JSON parsing..."
    apt-get update
    apt-get install jq -y
fi
echo "✅ Dependencies ready!"

echo ""
echo "🌐 Fetching UptimeRobot IPs from API..."
TEMP_FILE="/tmp/uptimerobot_ips.json"

# Fetch the IP list
if curl -s "https://api.uptimerobot.com/meta/ips" -o "$TEMP_FILE"; then
    echo "✅ API response received!"
else
    echo "❌ Failed to fetch IPs from UptimeRobot API"
    exit 1
fi

# Parse and validate JSON
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo "❌ Invalid JSON response from API"
    exit 1
fi

# Extract IPv4 addresses from JSON
echo "🔍 Extracting IPv4 addresses from JSON..."
IPS=$(jq -r '.prefixes[] | select(has("ip_prefix")) | .ip_prefix' "$TEMP_FILE" 2>/dev/null)

if [ -z "$IPS" ]; then
    echo "❌ No IPv4 addresses found in API response"
    exit 1
fi

echo "📋 Found $(echo "$IPS" | wc -l) IPv4 addresses"

echo ""
echo "🔥 Updating UFW firewall rules..."

# Check if UFW is installed and active
if ! command -v ufw &> /dev/null; then
    echo "❌ UFW is not installed"
    exit 1
fi

# Remove existing UptimeRobot rules to avoid duplicates
echo "🧹 Removing old UptimeRobot rules..."
ufw --force delete allow from any comment 'uptimerobot' 2>/dev/null || echo "ℹ️ No existing rules to remove"

# Add new rules for each IP and each port
COUNTER=0
while IFS= read -r ip_prefix; do
    if [ -n "$ip_prefix" ]; then
        for port in "${PORTS[@]}"; do
            echo "➕ Adding rule: $ip_prefix -> port $port"
            if ufw allow from "$ip_prefix" to any port "$port" comment 'uptimerobot'; then
                COUNTER=$((COUNTER + 1))
            else
                echo "⚠️ Failed to add rule for $ip_prefix:$port"
            fi
        done
    fi
done <<< "$IPS"

echo "✅ Added $COUNTER UFW rules for HTTP/HTTPS access!"

echo ""
echo "🔍 Verifying UFW rules..."
echo "Sample UptimeRobot rules:"
ufw status numbered | grep -i uptimerobot | head -5

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "🎉 === UptimeRobot UFW Setup Complete! ==="
echo "✨ UptimeRobot can now access ports 80 (HTTP) and 443 (HTTPS) only!"
echo "🔒 All other ports remain blocked for these IPs."
