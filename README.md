---
desc: taoli.tools 官方容器的自訂一鍵安裝（Chromium 加 --disable-web-security + 側載插件目錄）
kind: 自動化
status: 開發中
stack: sh / docker swarm（沿用上游 image，不自建）
run: 全新 Linux VPS 以 root 執行 `curl -fsSL https://raw.githubusercontent.com/demon851113/taoli-container-custom/main/bootstrap.sh | sh`
risk: 碰真錢（signer 容器持有助記詞；keychain.toml 絕不進 repo）
---

# taoli-container-custom

上游：<https://github.com/aliez-ren/taoli-tools-container>（`curl -fsSL https://taoli.tools/setup | sh`）。
本 repo 沿用上游 image，只改三處：

1. `entrypoint.sh`：Chromium 多 `--disable-web-security`（官方文檔「命令行禁用跨域」），並自動載入 `/home/taoli/ext/*` 下每個含 `manifest.json` 的資料夾（`--load-extension=`）。
2. `compose.yml`：container 服務多三個 bind mount — 覆蓋 entrypoint、`/opt/taoli/ext`（插件，唯讀）、`/opt/taoli/share`（檔案交換，雙向）。
3. `setup.sh`：不下載上游 compose.yml，改用本 repo 的；其餘與上游逐行一致。

## 安裝（全新 VPS，root）

```sh
# 可選：先放 signer 的助記詞檔與私有插件
scp keychain.toml vps:/opt/taoli/
scp -r my-extension vps:/opt/taoli/ext/my-extension   # 資料夾內直接有 manifest.json

curl -fsSL https://raw.githubusercontent.com/demon851113/taoli-container-custom/main/bootstrap.sh | sh
```

裝完照上游流程：掃 Tailscale QR → 本機瀏覽器開 `https://<tailscale 內網 IP>` → 遠端 Chromium 應出現「不受支援的命令列標記」黃條。

## 傳檔 / 更新插件

- 插件：`scp -r` 到 `/opt/taoli/ext/<名>/`，然後 `docker service update --force taoli_tools_container` 重啟生效。
- 一般檔案：`/opt/taoli/share` ↔ 容器內 `/home/taoli/share`，即放即見。
- 驗證 entrypoint 有被覆蓋：`docker service logs taoli_tools_container | grep entrypoint`。

## 紅線

`keychain.toml`、含 API key 的插件、任何憑證 **絕不 commit**（.gitignore 已擋）。

## 效能調校（2026-08-20，不花錢的部分）

- `index.html` 覆蓋上游 noVNC 頁：`compressionLevel 9→2`、`qualityLevel 0→6`（2 vCPU 上編碼是瓶頸，用頻寬換 CPU）。
- Chromium 多 `--disable-smooth-scrolling --animation-duration-scale=0 --renderer-process-limit=2`。
- 使用者端：把 noVNC 視窗縮小（遠端桌面會跟著視窗尺寸走，Retina 全螢幕 = 編碼量 3–4 倍）。
- 主機：2G swap（`/swapfile`）；`/etc/sysctl.conf` ip_forward 必須為 1（騰訊雲鏡像預設 0，見 Obsidian 踩雷）。
