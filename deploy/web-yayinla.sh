#!/bin/bash
# Pil Avı ve Nakavt Online'ı web'e çıkarır: GitHub'a yükler, tarayıcı sürümlerini derler,
# itch.io html5 kanalına gönderir, sunucuları ve wss tünellerini kurar/günceller.
# Kullanım: ~/pil-avi/deploy/web-yayinla.sh
# Pil Avı için önce itch.io'da "pil-avi" adresli proje sayfası açılmış olmalı.
set -uo pipefail
PIL="$HOME/pil-avi"
NAKAVT="$HOME/nakavt-online"
ITCH="johntitortheprog"
ID_DOSYA="$HOME/.config/oyun-web-gist-id"
EKSIK=()

echo "== 1/5 Adres gist'i"
if [ ! -s "$ID_DOSYA" ]; then
	TMP="$(mktemp -d)"
	echo '{"wss": ""}' > "$TMP/pil-avi.json"
	echo '{"wss": ""}' > "$TMP/nakavt.json"
	URL="$(gh gist create -d "Pil Avi ve Nakavt Online tarayici surumu sunucu adresleri" "$TMP/pil-avi.json" "$TMP/nakavt.json" | tail -1)"
	rm -rf "$TMP"
	if [ -z "$URL" ]; then
		echo "HATA: gist oluşturulamadı"
		exit 1
	fi
	mkdir -p "$(dirname "$ID_DOSYA")"
	echo "${URL##*/}" > "$ID_DOSYA"
fi
GIST="$(cat "$ID_DOSYA")"
echo "gist: $GIST"
sed -i "s/^const GIST_ID := .*/const GIST_ID := \"$GIST\"/" "$PIL/scripts/web_address.gd" "$NAKAVT/scripts/web_address.gd"

MESAJ_SON=$'\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'

echo "== 2/5 GitHub"
cd "$PIL" || exit 1
if [ ! -d .git ]; then
	git init -q -b main
fi
git add -A
git diff --cached --quiet || git commit -q -m "Pil Avı: Godot 4.6 ile online fizik platform oyunu ve web sürümü$MESAJ_SON"
if git remote get-url origin >/dev/null 2>&1; then
	git push -u origin main || EKSIK+=("pil-avi GitHub")
else
	gh repo create johntitor08/pil-avi --private --source=. --remote=origin --push || EKSIK+=("pil-avi GitHub")
fi
cd "$NAKAVT" || exit 1
git add -A
git diff --cached --quiet || git commit -q -m "Web sürümü: WebSocket desteği ve wss tüneli$MESAJ_SON"
git push origin main || EKSIK+=("nakavt GitHub")

web_derle() {
	mkdir -p "$1/build/web"
	if ! flatpak run org.godotengine.Godot --headless --path "$1" --export-release "Web" "$1/build/web/index.html" > /dev/null 2>&1 || [ ! -s "$1/build/web/index.wasm" ]; then
		echo "HATA: $1 web derlemesi başarısız"
		return 1
	fi
}

echo "== 3/5 Web derlemeleri"
web_derle "$PIL" || EKSIK+=("pil-avi web derlemesi")
web_derle "$NAKAVT" || EKSIK+=("nakavt web derlemesi")

echo "== 4/5 itch.io"
butler push "$PIL/build/web" "$ITCH/pil-avi:html5" --userversion 1.0.0 || EKSIK+=("pil-avi itch.io (sayfa açık mı?)")
butler push "$NAKAVT/build/web" "$ITCH/nakavt-online:html5" --userversion 1.0.0 || EKSIK+=("nakavt itch.io")

echo "== 5/5 Sunucular ve tüneller"
"$PIL/deploy/kur.sh" || EKSIK+=("pil-avi sunucu kurulumu")
"$NAKAVT/deploy/kur.sh" || EKSIK+=("nakavt sunucu kurulumu")

echo
if [ "${#EKSIK[@]}" -eq 0 ]; then
	echo "TAMAM: tüm adımlar bitti."
else
	echo "EKSİK KALANLAR:"
	printf ' - %s\n' "${EKSIK[@]}"
	exit 1
fi
