#!/bin/bash
# Pil Avı sunucusunu bu bilgisayara systemd kullanıcı servisi olarak kurar ya da günceller.
# Kullanım: ./deploy/kur.sh [port]   (varsayılan 7810/UDP)
set -euo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-7810}"
HEDEF="$HOME/.local/share/pil-avi-sunucu"
SERVIS="pil-avi-sunucu"

echo "== Linux sürümü derleniyor"
mkdir -p "$D/build/linux"
LOG="$(mktemp)"
if ! flatpak run org.godotengine.Godot --headless --path "$D" --export-release "Linux" "$D/build/linux/PilAvi.x86_64" > "$LOG" 2>&1; then
	echo "HATA: derleme başarısız. Çıktı:"
	cat "$LOG"
	rm -f "$LOG"
	exit 1
fi
rm -f "$LOG"

if systemctl --user is-active --quiet "$SERVIS"; then
	echo "== Çalışan servis durduruluyor (süren turlar biter)"
	systemctl --user stop "$SERVIS"
fi

# Elle ya da sunucu.sh ile açılmış kopya portu tutuyorsa servis başlayamaz.
if pkill -f "^/app/bin/godot-bin.*--sunucu --port=$PORT\$"; then
	echo "== Elle açılmış sunucu kapatıldı"
	sleep 2
fi

mkdir -p "$HEDEF" "$HOME/.config/systemd/user"
cp "$D/build/linux/PilAvi.x86_64" "$HEDEF/"
cat > "$HOME/.config/systemd/user/$SERVIS.service" <<UNIT
[Unit]
Description=Pil Avi oyun sunucusu
After=network-online.target

[Service]
WorkingDirectory=%h/.local/share/pil-avi-sunucu
ExecStart=/usr/bin/stdbuf -oL -eL %h/.local/share/pil-avi-sunucu/PilAvi.x86_64 --headless -- --sunucu --port=$PORT
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now "$SERVIS"
sleep 3
systemctl --user --no-pager status "$SERVIS" | head -5
ss -ulnp | grep ":$PORT " || echo "UYARI: $PORT/UDP dinlenmiyor, logu kontrol et: journalctl --user -u $SERVIS"

echo "== Tarayıcı tüneli kuruluyor"
"$D/deploy/web-tunel-kur.sh"
