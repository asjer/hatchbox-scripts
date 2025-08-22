#!/usr/bin/env bash
# =============================================================================
# Package Installation Script v1.0.0
# 
# This script installs essential packages for server management and monitoring.
#
# Packages included:
# - ET (Eternal Terminal): Persistent SSH connections
# - btop: Modern system resource monitor
# 
# Compatible with: Ubuntu/Debian systems
# =============================================================================

set -e  # Exit on any error

echo "🚀 === Package Installation Script v1.0.0 ==="
echo "👤 Running as: $(whoami)"
echo "📅 Date: $(date)"
echo ""

# =============================================================================
# SECTION 1: Package Repositories Setup
# =============================================================================

echo "📦 [1/4] Setting up package repositories..."

# Add ET (Eternal Terminal) PPA repository
echo "🔗 Adding ET PPA repository..."
add-apt-repository ppa:jgmath2000/et -y
echo "✅ ET PPA repository added successfully!"

echo ""
echo "🔄 Updating package lists..."
apt-get update
echo "✅ Package lists updated!"

# =============================================================================
# SECTION 2: Essential Tools Installation
# =============================================================================

echo "⬇️  [2/4] Installing essential packages..."

# Install btop (modern system monitor)
echo "📊 Installing btop (system monitor)..."
apt-get install btop -y
echo "✅ btop installed successfully!"

echo ""
# Install ET (Eternal Terminal)
echo "🌐 Installing ET (Eternal Terminal)..."
apt-get install et -y
echo "✅ ET installed successfully!"

# =============================================================================
# SECTION 3: Configuration Notes
# =============================================================================

echo "🔧 [3/4] Package configuration notes..."

echo "📋 ET (Eternal Terminal) Configuration:"
echo "   • Default port: 2022"
echo "   • Connection: et user@hostname"
echo "   • Config file: ~/.config/et/et.cfg"
echo ""

echo "📋 btop Configuration:"
echo "   • Run: btop"
echo "   • Config file: ~/.config/btop/btop.conf"
echo "   • Hotkey: q to quit"

# =============================================================================
# SECTION 4: Installation Summary
# =============================================================================

echo "🎉 [4/4] Installation Summary..."
echo ""
echo "✅ Successfully installed packages:"
echo "   📊 btop - Modern system resource monitor"
echo "   🌐 ET - Persistent SSH terminal sessions"
echo ""
echo "🧪 Quick start commands:"
echo "   • System monitoring: btop"
echo "   • Connect via ET: et user@hostname"
echo "   • View package versions: btop --version && et --version"
echo ""
echo "📝 Additional packages can be added to this script as needed."
echo "✨ Installation finished successfully!"
