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
chmod 755 ext share
chmod 777 share   # 容器內使用者 taoli(非root) 也要能寫

mkdir -p /etc/docker
echo "{\"seccomp-profile\": \"/etc/docker/seccomp.json\"}" > /etc/docker/daemon.json
curl -fsSL https://github.com/aliez-ren/taoli-tools-container/raw/refs/heads/main/seccomp.json > /etc/docker/seccomp.json

curl -fsSL https://get.docker.com | sh

# CUSTOM：不再下載上游 compose.yml，用 /opt/taoli/compose.yml
# CUSTOM：signer image 改 ghcr.io/taoli-tools/（上游 repo 已轉組織，舊路徑 aliez-ren/ 拉取 unauthorized，2026-08-20 實測）

openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -subj /CN=signer -addext 'subjectAltName=DNS:signer,IP:127.0.0.1' -out CERT.pem -keyout KEY.pem

if [ ! -f keychain.toml ]; then
  echo " " > keychain.toml
fi

docker info --format "{{.Swarm.LocalNodeState}}" | grep -q active || docker swarm init   # CUSTOM 可重跑

docker pull ghcr.io/aliez-ren/taoli-tools-container:latest
docker pull ghcr.io/taoli-tools/taoli-tools-signer:latest

docker stack deploy -c compose.yml -d taoli_tools

rm -f keychain.toml KEY.pem
mv CERT.pem /mnt/

docker service logs -f taoli_tools_container
