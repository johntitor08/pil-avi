#!/bin/bash
# Tarayıcı sürümü tünelini kullanıcı servisi olarak kurar ve başlatır.
# Kaldırmak için: systemctl --user disable --now pil-avi-web-tunel
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 web-tunel.sh "$HOME/.local/bin/pil-avi-web-tunel.sh"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/pil-avi-web-tunel.service" <<UNIT
[Unit]
Description=Pil Avi tarayici tuneli
After=network-online.target

[Service]
ExecStart=%h/.local/bin/pil-avi-web-tunel.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable pil-avi-web-tunel.service
systemctl --user restart pil-avi-web-tunel.service
echo "== Tünel adresi bekleniyor"
sleep 20
systemctl --user is-active pil-avi-web-tunel
grep -E "adres yayınlandı|UYARI" "$HOME/.local/state/pil-avi-web-tunel.log" | tail -2
