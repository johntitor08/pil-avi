#!/bin/sh
# Adanmış sunucuyu başlatır. Kullanım: ./sunucu.sh [port]  (varsayılan 7810/UDP)
D="$(dirname "$(readlink -f "$0")")"
exec flatpak run org.godotengine.Godot --headless --path "$D" -- --sunucu --port="${1:-7810}"
