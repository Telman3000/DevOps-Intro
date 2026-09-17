#!/usr/bin/env bash
# Bonus-only TLS capture (Task 1/2 already good). Uses local tlsproxy + openssl certs.
#   sudo -E bash /mnt/c/Users/Asus/Desktop/DevOps-Intro/scripts/lab4-bonus-tls.sh
set -euo pipefail

REPO="/mnt/c/Users/Asus/Desktop/DevOps-Intro"
OUT="$REPO/submissions/lab4-artifacts"
BIN="$OUT/bin"
QN_PORT=18080
TLS_PORT=18443
export PATH="$BIN:${HOME}/.local/go/bin:$PATH"

chmod +x "$BIN/tlsproxy" "$BIN/caddy" 2>/dev/null || true
cd "$OUT"

pkill -f "$OUT/quicknotes" 2>/dev/null || true
pkill -f "$BIN/tlsproxy" 2>/dev/null || true
pkill -x caddy 2>/dev/null || true
fuser -k "${QN_PORT}/tcp" 2>/dev/null || true
fuser -k "${TLS_PORT}/tcp" 2>/dev/null || true
sleep 1

# rebuild quicknotes if needed
if [[ ! -x "$OUT/quicknotes" ]]; then
  if command -v go >/dev/null; then
    (cd "$REPO/app" && CGO_ENABLED=0 go build -o "$OUT/quicknotes" .)
  else
    cp -f "$REPO/app/quicknotes-linux" "$OUT/quicknotes"
    chmod +x "$OUT/quicknotes"
  fi
fi

echo "==> QuickNotes :${QN_PORT}"
ADDR=":${QN_PORT}" ./quicknotes >"$OUT/qn-bonus.log" 2>&1 &
QN_PID=$!
sleep 1
curl -4 -s "http://127.0.0.1:${QN_PORT}/health"

echo
echo "==> TLS proxy :${TLS_PORT}"
rm -f "$OUT/tls-cert.pem" "$OUT/tls-key.pem"
LISTEN="127.0.0.1:${TLS_PORT}" TARGET="http://127.0.0.1:${QN_PORT}" \
  CERT="$OUT/tls-cert.pem" KEY="$OUT/tls-key.pem" \
  "$BIN/tlsproxy" >"$OUT/tlsproxy.log" 2>&1 &
PROXY_PID=$!
sleep 2
if ! kill -0 "$PROXY_PID" 2>/dev/null; then
  echo "tlsproxy died — log:" >&2
  cat "$OUT/tlsproxy.log" >&2 || true
  exit 1
fi
ss -tln | grep "${TLS_PORT}" || { echo "not listening on ${TLS_PORT}"; cat "$OUT/tlsproxy.log"; exit 1; }

tcpdump -i lo -nn -s 0 -w "$OUT/lab4-tls.pcap" "tcp port ${TLS_PORT}" &
TCPDUMP_PID=$!
sleep 1

echo "==> curl HTTPS"
curl -4 -vk --http1.1 "https://127.0.0.1:${TLS_PORT}/health" >"$OUT/curl-tls-health.txt" 2>&1 || true

sleep 1
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

echo "==> openssl showcerts"
openssl s_client -connect "127.0.0.1:${TLS_PORT}" -servername localhost -showcerts </dev/null \
  >"$OUT/openssl-showcerts.txt" 2>&1 || true

# Extract ClientHello / ServerHello lines from curl -v for submission
{
  echo "### From curl -vk (handshake lines)"
  grep -E 'TLS|SSL|hello|Hello|cipher|Cipher|subject|issuer|Connected' "$OUT/curl-tls-health.txt" || true
  echo
  echo "### tcpdump summary"
  tcpdump -r "$OUT/lab4-tls.pcap" -nn 2>/dev/null | head -n 30 || true
} >"$OUT/tls-handshake-notes.txt"

kill "$PROXY_PID" "$QN_PID" 2>/dev/null || true
fuser -k "${QN_PORT}/tcp" 2>/dev/null || true
fuser -k "${TLS_PORT}/tcp" 2>/dev/null || true
chown -R tem4ik:tem4ik "$OUT" 2>/dev/null || true

echo
echo "DONE bonus"
tail -20 "$OUT/curl-tls-health.txt"
echo "----"
head -40 "$OUT/openssl-showcerts.txt"
