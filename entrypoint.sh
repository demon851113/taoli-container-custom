#!/bin/sh
# 自訂 entrypoint（基底 = 上游 main 2026-08-26 94b35bc）。與上游差異：
# (1) 掃 /home/taoli/ext/* 側載插件  (2) chromium 加省力參數與 accept-lang
# （--disable-web-security 上游已內建；介面語言由 compose 的 LANG=zh_TW.UTF-8 決定）
set -eu

VNC_PID=""
WEBSOCKIFY_PID=""
OPENBOX_PID=""
BROWSER_PID=""
TAILSCALED_PID=""
TAILSCALE_PID=""

CHROMIUM_NOFILE_LIMIT="${CHROMIUM_NOFILE_LIMIT:-65535}"

cleanup() {
  for pid in "$VNC_PID" "$WEBSOCKIFY_PID" "$OPENBOX_PID" "$BROWSER_PID" "$TAILSCALED_PID" "$TAILSCALE_PID"; do
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup INT TERM

Xvnc $DISPLAY -rfbport $VNC_PORT -localhost -AlwaysShared -SecurityTypes None -depth 16 &
VNC_PID=$!

mkdir -p $HOME/websockify
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -subj /CN=localhost -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -out $HOME/websockify/CERT.pem -keyout $HOME/websockify/KEY.pem
websockify --web /usr/share/novnc/ --cert $HOME/websockify/CERT.pem --key $HOME/websockify/KEY.pem 127.0.0.1:$NOVNC_PORT 127.0.0.1:$VNC_PORT &
WEBSOCKIFY_PID=$!

openbox-session &
OPENBOX_PID=$!

# CUSTOM：掃插件目錄
EXT_FLAG=""
EXT_LIST=""
for d in $HOME/ext/*/; do
  [ -f "${d}manifest.json" ] || continue
  d=${d%/}
  EXT_LIST="${EXT_LIST:+$EXT_LIST,}$d"
done
if [ -n "$EXT_LIST" ]; then
  EXT_FLAG="--load-extension=$EXT_LIST"
  echo "[entrypoint] loading extensions: $EXT_LIST"
else
  echo "[entrypoint] no extensions found in $HOME/ext"
fi

rm -f $HOME/data/SingletonLock

case "$CHROMIUM_NOFILE_LIMIT" in
  ''|*[!0-9]*)
    echo "CHROMIUM_NOFILE_LIMIT must be a positive integer" >&2
    exit 1
    ;;
esac

NOFILE_HARD_LIMIT="$(ulimit -Hn)"
if [ "$NOFILE_HARD_LIMIT" != "unlimited" ] && [ "$CHROMIUM_NOFILE_LIMIT" -gt "$NOFILE_HARD_LIMIT" ]; then
  CHROMIUM_NOFILE_LIMIT="$NOFILE_HARD_LIMIT"
fi
ulimit -Sn "$CHROMIUM_NOFILE_LIMIT"
echo "Starting Chromium with a nofile soft limit of $(ulimit -Sn)"

chromium --display=$DISPLAY --enable-features=WebContentsForceDark --no-default-browser-check --no-first-run --disable-gpu --use-gl=disabled --disable-dev-shm-usage --disable-web-security --disable-smooth-scrolling --animation-duration-scale=0 --renderer-process-limit=2 --accept-lang=zh-TW,zh,en-US $EXT_FLAG --start-fullscreen --user-data-dir=$HOME/data https://taoli.tools &
BROWSER_PID=$!

tailscaled --tun=userspace-networking --socket=$HOME/tailscale.socket &
TAILSCALED_PID=$!

sleep 5

tailscale --socket=$HOME/tailscale.socket up --hostname=taoli-tools-container --qr &
TAILSCALE_PID=$!

wait $BROWSER_PID
