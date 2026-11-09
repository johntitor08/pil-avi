#!/bin/sh
# Otomatik testler: kurallar ve fizik, sonra gerçek ağ üzerinden sunucu + istemciler.
D="$(dirname "$(readlink -f "$0")")"
PORT=7816
G="flatpak run org.godotengine.Godot --headless --path $D"
TMP="$(mktemp -d)"
trap 'pkill -f "^/app/bin/godot-bin.*(--test-|--port=$PORT)"; rm -rf "$TMP"' EXIT
FILTER="^OK|^HATA|SONUÇ|\[yz\]|SCRIPT ERROR|Parse Error|   at: "

echo "--- Kurallar ve fizik ---"
timeout 280 flatpak run org.godotengine.Godot --headless --fixed-fps 60 --path "$D" -- --test-sim > "$TMP/sim.log" 2>&1
RC=$?
grep -E "$FILTER" "$TMP/sim.log"
if [ "$RC" -ne 0 ]; then
	echo "SONUÇ: kural testleri başarısız (çıkış $RC)"
	exit 1
fi

echo "--- Ağ ---"
$G -- --sunucu --port=$PORT --botsuz --ilk-muhendis > "$TMP/sunucu.log" 2>&1 &
sleep 3
timeout 40 $G -- --test-bot --rol=eski --port=$PORT > "$TMP/eski.log" 2>&1 &
P0=$!
timeout 40 $G -- --test-bot --rol=ilk --port=$PORT > "$TMP/ilk.log" 2>&1 &
P1=$!
sleep 1.5
timeout 40 $G -- --test-bot --rol=ikinci --port=$PORT --adres=ws://127.0.0.1:$((PORT+1)) > "$TMP/ikinci.log" 2>&1 &
P2=$!
FAIL=0
wait $P0 || FAIL=1
wait $P1 || FAIL=1
wait $P2 || FAIL=1
grep -hE "$FILTER" "$TMP/eski.log" "$TMP/ilk.log" "$TMP/ikinci.log"
grep -h "oda" "$TMP/sunucu.log"
grep -E "SCRIPT ERROR|Parse Error" "$TMP/sunucu.log"
if [ "$FAIL" -ne 0 ]; then
	echo "SONUÇ: ağ testi başarısız"
	exit 1
fi
echo "SONUÇ: ağ testi geçti"
