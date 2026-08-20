#!/bin/sh
# 自訂 entrypoint：以 bind mount 覆蓋 image 內 /usr/local/bin/entrypoint.sh
# 與上游差異：(1) chromium 加 --disable-web-security  (2) 自動載入 /home/taoli/ext/* 底下的未打包插件
set -eu

VNC_PID=""
WEBSOCKIFY_PID=""
OPENBOX_PID=""
BROWSER_PID=""
TAILSCALED_PID=""
TAILSCALE_PID=""

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

# 掃 /home/taoli/ext 底下每個含 manifest.json 的資料夾，組成 --load-extension=a,b,c
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
chromium --display=$DISPLAY --enable-features=WebContentsForceDark --no-default-browser-check --no-first-run --disable-gpu --use-gl=disabled --disable-dev-shm-usage --start-fullscreen \
  --disable-web-security --disable-smooth-scrolling --animation-duration-scale=0 --renderer-process-limit=2 --lang=zh-TW --accept-lang=zh-TW,zh,en-US \
  $EXT_FLAG \
  --user-data-dir=$HOME/data https://taoli.tools &
BROWSER_PID=$!

tailscaled --tun=userspace-networking --socket=$HOME/tailscale.socket &
TAILSCALED_PID=$!

sleep 5

tailscale --socket=$HOME/tailscale.socket up --hostname=taoli-tools-container --qr &
TAILSCALE_PID=$!

wait $BROWSER_PID
