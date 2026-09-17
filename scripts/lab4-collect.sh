#!/usr/bin/env bash
# Lab 4 evidence collector — uses :18080 / :18443 to avoid Airflow on :8080
#   sudo -E bash /mnt/c/Users/Asus/Desktop/DevOps-Intro/scripts/lab4-collect.sh
set -euo pipefail

REPO="/mnt/c/Users/Asus/Desktop/DevOps-Intro"
OUT="$REPO/submissions/lab4-artifacts"
BIN="$OUT/bin"
APP="$REPO/app"
QN_PORT=18080
TLS_PORT=18443
export PATH="$BIN:${HOME}/.local/go/bin:/usr/local/go/bin:$PATH"
export ADDR=":${QN_PORT}"

mkdir -p "$OUT"
cd "$OUT"
chmod +x "$BIN/jq" "$BIN/caddy" "$BIN/dig" 2>/dev/null || true

echo "==> Note: avoiding :8080 (occupied by Airflow/gunicorn in this WSL). Using :${QN_PORT} / :${TLS_PORT}"

echo "==> Building QuickNotes"
cd "$APP"
if command -v go >/dev/null; then
  CGO_ENABLED=0 go build -o "$OUT/quicknotes" .
elif [[ -x "$APP/quicknotes-linux" ]]; then
  cp -f "$APP/quicknotes-linux" "$OUT/quicknotes"
  chmod +x "$OUT/quicknotes"
else
  echo "No go / quicknotes-linux" >&2
  exit 1
fi
cp -f "$APP/seed.json" "$OUT/seed.json" 2>/dev/null || true

pkill -f "$OUT/quicknotes" 2>/dev/null || true
pkill -x caddy 2>/dev/null || true
fuser -k "${QN_PORT}/tcp" 2>/dev/null || true
fuser -k "${TLS_PORT}/tcp" 2>/dev/null || true
sleep 1

############################
# Task 1
############################
echo "==> Task 1: start QuickNotes on :${QN_PORT}"
cd "$OUT"
rm -rf "$OUT/data"
ADDR=":${QN_PORT}" ./quicknotes >"$OUT/qn-task1.log" 2>&1 &
QN_PID=$!
sleep 1
# prove it's ours
curl -4 -s "http://127.0.0.1:${QN_PORT}/health" | tee "$OUT/health-check.txt"
echo

tcpdump -i lo -nn -s 0 -A "tcp port ${QN_PORT}" -w "$OUT/lab4-trace.pcap" &
TCPDUMP_PID=$!
sleep 1

curl -4 -v -X POST "http://127.0.0.1:${QN_PORT}/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"trace me","body":"in flight"}' \
  >"$OUT/curl-post.txt" 2>&1 || true

sleep 1
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true
tcpdump -r "$OUT/lab4-trace.pcap" -nn -A >"$OUT/lab4-trace.txt" 2>&1 || true

{
  echo "### Environment note"
  echo "WSL :8080 is owned by Airflow (gunicorn). Lab capture used ADDR=:${QN_PORT}."
  echo
  echo "### ss -tlnp | grep :${QN_PORT}"
  ss -tlnp | grep ":${QN_PORT}" || true
  echo
  echo "### ss -tlnp | grep :8080  (shows foreign service)"
  ss -tlnp | grep ":8080" || true
  echo
  echo "### ip route show"
  ip route show || true
  echo
  echo "### mtr -rwc 5 localhost (fallback: ping)"
  if command -v mtr >/dev/null; then
    mtr -rwc 5 localhost || true
  else
    echo "(mtr unavailable — apt mirrors unreachable from WSL; ping -c 5 localhost)"
    ping -c 5 localhost || true
  fi
  echo
  echo "### dig +short example.com @1.1.1.1"
  "$BIN/dig" +short example.com @1.1.1.1 2>&1 || true
  echo
  echo "### journalctl --user -u quicknotes -n 20 || true"
  journalctl --user -u quicknotes -n 20 || true
} >"$OUT/task1-debug-commands.txt" 2>&1

############################
# Task 2 — conflict on QN_PORT
############################
echo "==> Task 2: broken deploy (second bind on :${QN_PORT})"
# keep first instance running as PID1
PID1=$QN_PID
ADDR=":${QN_PORT}" ./quicknotes >"$OUT/qn-broken.log" 2>&1 &
PID2=$!
sleep 2

{
  echo "### ps after double bind"
  ps -ef | grep quicknotes | grep -v grep || true
  echo
  echo "### broken instance log"
  cat "$OUT/qn-broken.log" || true
  echo
  echo "### Outside-in chain"
  echo "# 1) is it running?"
  ps -ef | grep quicknotes | grep -v grep || true
  echo
  echo "# 2) is it listening?"
  ss -tlnp | grep ":${QN_PORT}" || true
  echo
  echo "# 3) reachable? (expect 200 from first instance)"
  curl -4 -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:${QN_PORT}/health" || true
  curl -4 -s "http://127.0.0.1:${QN_PORT}/health" || true
  echo
  echo "# 4) firewall?"
  iptables -L -n -v 2>/dev/null || nft list ruleset 2>/dev/null || echo "(no iptables/nft output)"
  echo
  echo "# 5) DNS?"
  "$BIN/dig" +short localhost 2>&1 || getent hosts localhost || true
} >"$OUT/task2-outside-in.txt" 2>&1

echo "==> Task 2: repair"
kill "$PID1" "$PID2" 2>/dev/null || true
sleep 1
fuser -k "${QN_PORT}/tcp" 2>/dev/null || true
sleep 1
ADDR=":${QN_PORT}" ./quicknotes >"$OUT/qn-repaired.log" 2>&1 &
PID_FIX=$!
sleep 1
{
  echo "### after repair"
  curl -4 -s "http://127.0.0.1:${QN_PORT}/health" || true
  echo
  ss -tlnp | grep ":${QN_PORT}" || true
} >"$OUT/task2-repaired.txt" 2>&1

############################
# Bonus TLS
############################
echo "==> Bonus: Caddy HTTPS on 127.0.0.1:${TLS_PORT}"
mkdir -p "$OUT/caddy"
cat >"$OUT/caddy/Caddyfile" <<EOF
{
  auto_https off
}
https://127.0.0.1:${TLS_PORT} {
  tls internal
  reverse_proxy 127.0.0.1:${QN_PORT}
}
EOF

fuser -k "${TLS_PORT}/tcp" 2>/dev/null || true
pkill -x caddy 2>/dev/null || true
sleep 1

"$BIN/caddy" run --config "$OUT/caddy/Caddyfile" --adapter caddyfile >"$OUT/caddy.log" 2>&1 &
CADDY_PID=$!
sleep 3

tcpdump -i lo -nn -s 0 -w "$OUT/lab4-tls.pcap" "tcp port ${TLS_PORT}" &
TLS_TCPDUMP_PID=$!
sleep 1

curl -4 -vk --http1.1 "https://127.0.0.1:${TLS_PORT}/health" >"$OUT/curl-tls-health.txt" 2>&1 || true
sleep 1

kill "$TLS_TCPDUMP_PID" 2>/dev/null || true
wait "$TLS_TCPDUMP_PID" 2>/dev/null || true

{
  echo "### openssl s_client cert chain"
  openssl s_client -connect "127.0.0.1:${TLS_PORT}" -servername localhost -showcerts </dev/null 2>&1 || true
} >"$OUT/openssl-showcerts.txt"

tcpdump -r "$OUT/lab4-tls.pcap" -nn 2>/dev/null | head -n 40 >"$OUT/tls-pcap-summary.txt" || true

kill "$CADDY_PID" "$PID_FIX" 2>/dev/null || true
pkill -x caddy 2>/dev/null || true
fuser -k "${QN_PORT}/tcp" 2>/dev/null || true
fuser -k "${TLS_PORT}/tcp" 2>/dev/null || true
rm -f "$OUT/quicknotes"
chown -R tem4ik:tem4ik "$OUT" 2>/dev/null || true

echo
echo "DONE"
ls -la "$OUT" | head -40
echo "--- health ---"; cat "$OUT/health-check.txt"; echo
echo "--- post head ---"; head -30 "$OUT/curl-post.txt"
echo "--- tls head ---"; head -25 "$OUT/curl-tls-health.txt"
