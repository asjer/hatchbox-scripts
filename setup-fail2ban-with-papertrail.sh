#!/usr/bin/env bash
# =============================================================================
# Fail2ban Security Setup Script v1.3.4
#
# This script sets up comprehensive security monitoring with fail2ban and
# integrates it with an existing Papertrail configuration.
#
# v1.3.4 Changes:
# - Caddy bot detection filter is now more robust and specific.
# - Bot detection jail correctly monitors Caddy logs via systemd journal.
# - All other jails and logging configurations are stable.
#
# Prerequisites:
# - Papertrail must already be configured via their setup script.
# - UFW firewall should be active.
#
# Compatible with: Ubuntu/Debian systems using systemd.
# =============================================================================

set -e  # Exit on any error

echo "🛡️ === Fail2ban Security Setup Script v1.3.4 ==="
echo "🔧 Setting up fail2ban with Papertrail integration and smart detection"
echo ""

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

echo "🔍 [1/7] Checking prerequisites..."

# Check if Papertrail is configured
if ! ls /etc/rsyslog.d/*papertrail*.conf >/dev/null 2>&1; then
    echo "❌ ERROR: Papertrail is not configured on this system!"
    echo ""
    echo "Please run the Papertrail setup script first:"
    echo "wget -qO - --header=\"X-Papertrail-Token: YOUR_TOKEN\" \\"
    echo "https://papertrailapp.com/destinations/YOUR_ID/setup.sh | sudo bash"
    echo ""
    echo "Then run this script again."
    exit 1
fi
echo "✅ Papertrail configuration found"

# Check if UFW is installed and active
if ! command -v ufw >/dev/null 2>&1; then
    echo "⚠️  WARNING: UFW is not installed. Port scan detection will not work."
    echo "   Install with: sudo apt-get install ufw"
elif ! ufw status | grep -q "Status: active"; then
    echo "⚠️  WARNING: UFW is not active. Port scan detection will not work."
    echo "   Enable with: sudo ufw enable"
fi

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "❌ ERROR: This script must be run as root or with sudo"
   exit 1
fi

echo "✅ All prerequisites checked"
echo ""

# =============================================================================
# SERVER TYPE DETECTION
# =============================================================================

echo "🔍 [2/7] Detecting server type and installed services..."

# Detect web servers
WEB_SERVER="none"
if systemctl is-active --quiet nginx 2>/dev/null; then
    WEB_SERVER="nginx"
elif systemctl is-active --quiet caddy 2>/dev/null; then
    WEB_SERVER="caddy"
elif systemctl is-active --quiet apache2 2>/dev/null; then
    WEB_SERVER="apache"
fi

# Detect database servers
DB_SERVER="none"
if systemctl is-active --quiet postgresql 2>/dev/null; then
    DB_SERVER="postgresql"
elif systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    DB_SERVER="mysql"
elif systemctl is-active --quiet mongodb 2>/dev/null; then
    DB_SERVER="mongodb"
elif systemctl is-active --quiet redis 2>/dev/null; then
    DB_SERVER="redis"
fi

echo "✅ Server type detection complete:"
echo "   • Web server: $WEB_SERVER"
echo "   • Database server: $DB_SERVER"
if [ "$WEB_SERVER" = "caddy" ]; then
    echo "   • Bot protection: Will be enabled (Caddy detected)"
elif [ "$WEB_SERVER" != "none" ]; then
    echo "   • Bot protection: Limited support for $WEB_SERVER"
fi
echo ""

# =============================================================================
# SECTION 1: Fail2ban Basic Configuration
# =============================================================================

echo "🔧 [3/7] Configuring Fail2ban logging..."

# Configure fail2ban to log to a dedicated file instead of syslog
cat > /etc/fail2ban/fail2ban.local << 'EOF'
[Definition]
logtarget = /var/log/fail2ban.log
loglevel = INFO
EOF

# =============================================================================
# SECTION 2: Fail2ban Jails Configuration (Dynamic)
# =============================================================================

echo "🔒 [4/7] Setting up Fail2ban security jails..."

# Determine where UFW logs (varies by system)
UFW_LOG_PATH="/var/log/kern.log"

# Create jail.local with dynamic configuration
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# IPs to never ban (localhost and IPv6 localhost)
ignoreip = 127.0.0.1/8 ::1
# Use iptables to block IPs across multiple ports
banaction = iptables-multiport
# Use systemd journal for log reading (more efficient)
backend = systemd

# ===== SSH Protection (Always enabled) =====
[sshd]
enabled = true
# Ban after 3 failed attempts
maxretry = 3
# Within 10 minutes
findtime = 600
# Ban for 1 hour
bantime = 3600

# ===== Port Scan Detection (Always enabled) =====
[ufw-portscan]
enabled = true
filter = ufw-portscan
logpath = $UFW_LOG_PATH
# Ban after 3 blocked connections
maxretry = 3
# Within 30 minutes
findtime = 1800
# Initial ban: 10 minutes
bantime = 600
# Increase ban time for repeat offenders
bantime.increment = true
# Max ban: 30 days
bantime.maxtime = 2592000
# Block ALL ports
action = iptables-allports[name=ufw-portscan]

# ===== Bad Port Access Detection (Always enabled) =====
[ufw-bad-ports]
enabled = true
filter = ufw-bad-ports
logpath = $UFW_LOG_PATH
# Ban on first attempt (zero tolerance)
maxretry = 1
# Within 10 minutes
findtime = 600
# Initial ban: 24 hours
bantime = 86400
# Increase ban time for repeat offenders
bantime.increment = true
# Max ban: 30 days
bantime.maxtime = 2592000
# Block ALL ports
action = iptables-allports[name=ufw-bad-ports]
EOF

# Add bot protection for Caddy servers
if [ "$WEB_SERVER" = "caddy" ]; then
    cat >> /etc/fail2ban/jail.local << EOF

# ===== Caddy Bot Scanner Detection =====
# Auto-enabled: Caddy web server detected
# Monitors Caddy's JSON logs for bot/scanner activity
[caddy-bots]
enabled = true
filter = caddy-bots
# Monitor Caddy logs via systemd journal
backend = systemd
journalmatch = _SYSTEMD_UNIT=caddy.service
# Ban after 5 suspicious requests
maxretry = 5
# Within 60 seconds
findtime = 60
# Ban for 7 days (these are definitely malicious)
bantime = 604800
# Increase ban time for repeat offenders
bantime.increment = true
# Max ban: 30 days
bantime.maxtime = 2592000
# Block ALL ports - these are attackers
action = iptables-allports[name=caddy-bots]
EOF
elif [ "$WEB_SERVER" = "nginx" ]; then
    cat >> /etc/fail2ban/jail.local << EOF

# ===== Web Bot Scanner Detection =====
# Note: Nginx detected but bot detection requires access log configuration
# To enable: Configure nginx to log in a parseable format
[nginx-bots]
enabled = false
EOF
else
    cat >> /etc/fail2ban/jail.local << EOF

# ===== Web Bot Scanner Detection =====
# No supported web server detected for bot protection
[web-bots]
enabled = false
EOF
fi

# Add database-specific protection if DB server detected
if [ "$DB_SERVER" != "none" ]; then
    cat >> /etc/fail2ban/jail.local << EOF

# ===== Database Connection Protection =====
# Auto-enabled: $DB_SERVER detected
[db-auth]
enabled = true
filter = db-auth
logpath = /var/log/auth.log
          /var/log/syslog
# Ban after 5 failed attempts
maxretry = 5
# Within 10 minutes
findtime = 600
# Ban for 1 hour
bantime = 3600
# Increase ban time for repeat offenders
bantime.increment = true
# Max ban: 7 days
bantime.maxtime = 604800
EOF
fi

# =============================================================================
# SECTION 3: Fail2ban Filters
# =============================================================================

echo "🔍 [5/7] Creating Fail2ban detection filters..."

# Create filter for general port scanning detection
cat > /etc/fail2ban/filter.d/ufw-portscan.conf <<'EOF'
[Definition]
# Match any UFW BLOCK log entry and extract the source IP
failregex = .*\[UFW BLOCK\].*SRC=<HOST>.*
EOF

# Create filter for bad port access detection
cat > /etc/fail2ban/filter.d/ufw-bad-ports.conf <<'EOF'
[Definition]
# Match UFW BLOCK entries for specific vulnerable ports:
# 21=FTP, 22=SSH, 23=Telnet, 25=SMTP, 110=POP3, 143=IMAP, 445=SMB,
# 993=IMAPS, 995=POP3S, 1433=MSSQL, 1521=Oracle, 3306=MySQL,
# 3389=RDP, 5432=PostgreSQL, 5900=VNC, 6379=Redis, 8080/8443=Web,
# 27017=MongoDB, 11211=Memcached, 9200=Elasticsearch
failregex = .*\[UFW BLOCK\].*SRC=<HOST>.*DPT=(?:21|22|23|25|110|143|445|993|995|1433|1521|3306|3389|5432|5900|6379|8080|8443|27017|11211|9200).*
EOF

# Create Caddy bot filter if Caddy is detected
if [ "$WEB_SERVER" = "caddy" ]; then
    cat > /etc/fail2ban/filter.d/caddy-bots.conf <<'EOF'
[Definition]
# Match bot/scanner requests in Caddy's JSON logs
# Caddy logs are JSON formatted via journald

# PHP/ASP/JSP files and common attack vectors
failregex = ^.*"remote_ip":"<HOST>".*"uri":"[^"]*\.(?:php|asp|aspx|jsp|cgi|pl|py|sh|bash|exe|dll)".*"status":(?:404|406).*$
            ^.*"client_ip":"<HOST>".*"uri":"[^"]*\.(?:php|asp|aspx|jsp|cgi|pl|py|sh|bash|exe|dll)".*"status":(?:404|406).*$

# WordPress/CMS paths
            ^.*"remote_ip":"<HOST>".*"uri":"[^"]*(?:wp-content|wp-admin|wp-includes|wp-login|xmlrpc\.php|phpmyadmin|pma|admin\.php)".*"status":(?:404|406).*$
            ^.*"client_ip":"<HOST>".*"uri":"[^"]*(?:wp-content|wp-admin|wp-includes|wp-login|xmlrpc\.php|phpmyadmin|pma|admin\.php)".*"status":(?:404|406).*$

# Sensitive files and configs
            ^.*"remote_ip":"<HOST>".*"uri":"[^"]*(?:\.env|\.git|config\.php|database\.yml|\.htaccess|\.htpasswd|\.ssh|id_rsa)".*"status":(?:404|406).*$
            ^.*"client_ip":"<HOST>".*"uri":"[^"]*(?:\.env|\.git|config\.php|database\.yml|\.htaccess|\.htpasswd|\.ssh|id_rsa)".*"status":(?:404|406).*$

# Common scanners and vulnerability probes
            ^.*"remote_ip":"<HOST>".*"uri":"[^"]*(?:joomla|drupal|magento|prestashop|opencart|bitrix|typo3)".*"status":(?:404|406).*$
            ^.*"client_ip":"<HOST>".*"uri":"[^"]*(?:joomla|drupal|magento|prestashop|opencart|bitrix|typo3)".*"status":(?:404|406).*$

# Web shells and backdoors
            ^.*"remote_ip":"<HOST>".*"uri":"[^"]*(?:shell|c99|r57|wso|b374k|webshell|backdoor|filemanager)".*"status":(?:404|406).*$
            ^.*"client_ip":"<HOST>".*"uri":"[^"]*(?:shell|c99|r57|wso|b374k|webshell|backdoor|filemanager)".*"status":(?:404|406).*$

# Ignore legitimate requests
ignoreregex = "uri":"/(?:assets|packs|rails/active_storage|cable|favicon\.ico|robots\.txt|sitemap\.xml|apple-touch-icon)"
EOF
fi

# Create database auth filter if DB server detected
if [ "$DB_SERVER" != "none" ]; then
    cat > /etc/fail2ban/filter.d/db-auth.conf <<'EOF'
[Definition]
# Detect repeated failed authentication attempts
failregex = .*authentication failure.*rhost=<HOST>.*
            .*Failed password for.*from <HOST>.*
            .*Connection from <HOST> rejected.*
            .*Access denied for.*from <HOST>.*
            .*Connection refused.*from <HOST>.*
EOF
fi

# =============================================================================
# SECTION 4: Rsyslog Integration for Fail2ban Logs
# =============================================================================

echo "📤 [6/7] Configuring rsyslog to forward fail2ban logs to Papertrail..."

# Configure rsyslog to watch the fail2ban log file and forward to Papertrail
cat > /etc/rsyslog.d/22-fail2ban.conf << 'EOF'
# Load the imfile input module
module(load="imfile" mode="inotify")

# Configure file watching for fail2ban.log
input(type="imfile"
      File="/var/log/fail2ban.log"
      Tag="fail2ban"
      Severity="warning"
      StateFile="fail2ban-log-state")
EOF

# Create rsyslog spool directory if it doesn't exist
sudo mkdir -p /var/spool/rsyslog

# =============================================================================
# SECTION 5: Service Restart and Verification
# =============================================================================

echo "🔄 [7/7] Restarting services to apply all changes..."

# Restart fail2ban to apply jail configurations
systemctl restart fail2ban

# Restart rsyslog to apply forwarding rules
systemctl restart rsyslog

# Give services a moment to start
sleep 2

# Verify fail2ban is running
if ! systemctl is-active --quiet fail2ban; then
    echo "❌ ERROR: fail2ban failed to start!"
    echo "Check logs with: journalctl -u fail2ban -n 50"
    exit 1
fi

# =============================================================================
# SECTION 6: Completion Message (Dynamic)
# =============================================================================

echo ""
echo "🎉 === Security Setup Complete! ==="
echo ""

# Determine server type for display
SERVER_TYPE=""
if [ "$WEB_SERVER" != "none" ] && [ "$DB_SERVER" != "none" ]; then
    SERVER_TYPE="Web + Database Server ($WEB_SERVER + $DB_SERVER)"
elif [ "$WEB_SERVER" != "none" ]; then
    SERVER_TYPE="Web Server ($WEB_SERVER)"
elif [ "$DB_SERVER" != "none" ]; then
    SERVER_TYPE="Database Server ($DB_SERVER)"
else
    SERVER_TYPE="Application Server"
fi

echo "🖥️  Server type: $SERVER_TYPE"
echo ""
echo "📊 What's now active on this server:"
echo "   ✅ SSH brute-force protection (3 attempts = 1 hour ban)"
echo "   ✅ Port scan detection (3 scans = escalating bans)"
echo "   ✅ Bad port access detection (1 attempt = 24 hour ban)"

if [ "$WEB_SERVER" = "caddy" ]; then
    echo "   ✅ Bot/scanner protection (5 attempts = 7 day ban)"
    echo "      📁 Monitoring Caddy JSON logs for malicious patterns"
    echo "      🎯 Detecting: PHP files, WordPress paths, config files, etc."
fi

if [ "$DB_SERVER" != "none" ]; then
    echo "   ✅ Database authentication monitoring"
fi

echo "   ✅ All security events forwarded to Papertrail"
echo ""

if [ "$WEB_SERVER" = "caddy" ]; then
    echo "🧪 To test bot detection:"
    echo "   # Watch the jail status"
    echo "   watch 'sudo fail2ban-client status caddy-bots'"
    echo ""
    echo "   # Test the filter against recent logs"
    echo "   sudo fail2ban-regex \"$(sudo journalctl -u caddy -n 100)\" /etc/fail2ban/filter.d/caddy-bots.conf"
    echo ""
fi

echo "🧪 To test the integration:"
echo "   sudo fail2ban-client set sshd banip 8.8.8.8"
echo "   Then check Papertrail for: 'fail2ban ... NOTICE [sshd] Ban 8.8.8.8'"
echo "   Cleanup: sudo fail2ban-client set sshd unbanip 8.8.8.8"
echo ""

echo "📊 Current jail status:"
sudo fail2ban-client status | grep "Jail list" | sed 's/^/   /'
echo ""

echo "⚠️  IMPORTANT: Add your admin IPs to /etc/fail2ban/jail.local"
echo "   in the 'ignoreip' line to prevent accidental lockouts!"
echo ""
echo "📝 Useful commands:"
echo "   • View banned IPs: sudo fail2ban-client status <jail-name>"
echo "   • Unban an IP: sudo fail2ban-client set <jail-name> unbanip <IP>"
echo "   • Check all jails: sudo fail2ban-client status"
if [ "$WEB_SERVER" = "caddy" ]; then
    echo "   • Test Caddy filter: sudo fail2ban-regex \"\$(sudo journalctl -u caddy -n 100)\" /etc/fail2ban/filter.d/caddy-bots.conf"
fi
echo ""
echo "📝 Log locations:"
echo "   • Fail2ban activity: /var/log/fail2ban.log"
echo "   • System logs: journalctl -u fail2ban"
if [ "$WEB_SERVER" = "caddy" ]; then
    echo "   • Caddy logs: journalctl -u caddy"
fi
echo "   • All events: Papertrail dashboard"
