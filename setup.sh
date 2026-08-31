#!/bin/sh
# 自訂版 taoli.tools 安裝腳本（對照上游 https://taoli.tools/setup，差異見 # CUSTOM）
# 由 bootstrap.sh 呼叫；也可手動：把本目錄檔案放到 /opt/taoli/ 後 sh setup.sh
set -eu
cd /opt/taoli

# CUSTOM：前置檢查，缺檔就停，不半做
for f in entrypoint.sh compose.yml index.html; do
  [ -f "$f" ] || { echo "缺 /opt/taoli/$f"; exit 1; }
done
chmod +x entrypoint.sh
mkdir -p ext share

# CUSTOM：騰訊雲鏡像預設 ip_forward=0，重載 sysctl 或重開機會讓容器斷網
sed -i "s/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/" /etc/sysctl.conf 2>/dev/null || true
chmod 755 ext share
chmod 777 share   # 容器內使用者 taoli(非root) 也要能寫

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DJ'
{
  "seccomp-profile": "/etc/docker/seccomp.json",
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65535, "Soft": 65535 }
  }
}
DJ
curl -fsSL https://github.com/aliez-ren/taoli-tools-container/raw/refs/heads/main/seccomp.json > /etc/docker/seccomp.json

curl -fsSL https://get.docker.com | sh

# CUSTOM：不再下載上游 compose.yml，用 /opt/taoli/compose.yml
# CUSTOM：signer image 改 ghcr.io/taoli-tools/（上游 repo 已轉組織，舊路徑 aliez-ren/ 拉取 unauthorized，2026-08-20 實測）

openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -subj /CN=signer -addext 'subjectAltName=DNS:signer,IP:127.0.0.1' -out CERT.pem -keyout KEY.pem

if [ ! -f keychain.toml ]; then
  echo " " > keychain.toml
fi

docker info --format "{{.Swarm.LocalNodeState}}" | grep -q active || docker swarm init   # CUSTOM 可重跑


# CUSTOM：抽取與 image 同版本的 Chromium 繁中/簡中語言包（容器非 root 無法 apk add）
mkdir -p /opt/taoli/locales
docker pull -q ghcr.io/aliez-ren/taoli-tools-container:latest >/dev/null
CHROMIUM_VER=$(docker run --rm --entrypoint sh ghcr.io/aliez-ren/taoli-tools-container:latest -c 'apk list -I chromium 2>/dev/null | head -1' | grep -o '[0-9][0-9.]*-r[0-9]*')
docker run --rm -v /opt/taoli/locales:/out alpine:3.22 sh -c "apk update -q && cd /tmp && (apk fetch -q chromium-lang=$CHROMIUM_VER 2>/dev/null || apk fetch -q chromium-lang) && tar -xzf chromium-lang-*.apk usr/lib/chromium/locales/zh-TW.pak usr/lib/chromium/locales/zh-CN.pak && cp usr/lib/chromium/locales/zh-*.pak /out/"
chmod 644 /opt/taoli/locales/*.pak

docker pull ghcr.io/aliez-ren/taoli-tools-container:latest
docker pull ghcr.io/taoli-tools/taoli-tools-signer:latest

docker stack deploy -c compose.yml -d taoli_tools

rm -f keychain.toml KEY.pem
mv CERT.pem /mnt/

docker service logs -f taoli_tools_container
