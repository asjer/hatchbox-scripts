#!/usr/bin/env bash
set -e

echo "🚀 === Installing ET (Eternal Terminal) ==="
echo "👤 Running as: $(whoami)"
echo "📅 Date: $(date)"
echo ""

echo "📦 Adding ET PPA repository..."
add-apt-repository ppa:jgmath2000/et -y
echo "✅ PPA repository added successfully!"

echo ""
echo "🔄 Updating package lists..."
apt-get update
echo "✅ Package lists updated!"

echo ""
echo "⬇️ Installing ET..."
apt-get install et -y
echo "✅ ET installed successfully!"

echo ""
echo "🎉 === ET Installation Complete! ==="
echo "🌐 You can now use ET to connect to this server."
echo "🔌 Default ET port: 2022"
echo "✨ Installation finished successfully!"
