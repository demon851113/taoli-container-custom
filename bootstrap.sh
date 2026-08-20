#!/bin/sh
# 一鍵安裝入口：curl -fsSL https://raw.githubusercontent.com/demon851113/taoli-container-custom/main/bootstrap.sh | sh
# 只拉公開的三個檔；keychain.toml 與私有插件請自行先放到 /opt/taoli/ 與 /opt/taoli/ext/
set -eu
BASE=https://raw.githubusercontent.com/demon851113/taoli-container-custom/main
mkdir -p /opt/taoli/ext /opt/taoli/share
cd /opt/taoli
for f in setup.sh entrypoint.sh compose.yml; do
  curl -fsSL "$BASE/$f" -o "$f"
done
chmod +x setup.sh entrypoint.sh
exec sh ./setup.sh
