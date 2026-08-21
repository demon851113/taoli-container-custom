# 安裝腳本優化紀錄與建議

> 對象：`bootstrap.sh` → `setup.sh`（+ `entrypoint.sh` / `compose.yml` / `index.html`）。
> 基準：上游 `curl -fsSL https://taoli.tools/setup | sh`（31 行）。
> 原則：**不自建 image**，所有差異靠 bind mount / env / compose 達成；上游更新只要 `docker pull` + `service update --force`。

---

## 一、已完成（2026-08-20，已在 taoli-vps 實機驗證）

| # | 項目 | 做法 | 為什麼 | 驗證方式 |
|---|---|---|---|---|
| 1 | 修上游壞掉的 signer image 路徑 | `ghcr.io/aliez-ren/…-signer` → `ghcr.io/taoli-tools/…-signer` | 上游 repo 轉組織，ghcr package 不跟著轉；官方一鍵裝目前在 `docker pull signer` 就 unauthorized | `docker manifest inspect` 兩路徑對照；實機 pull 成功 |
| 2 | `swarm init` 可重跑 | `docker info … Swarm.LocalNodeState \| grep -q active \|\| docker swarm init` | 上游第二次執行必死在 "already part of a swarm" | 重跑 setup 不中止 |
| 3 | 前置檢查 | 缺 `entrypoint.sh / compose.yml / index.html` 即 `exit 1` | 半裝比不裝糟 | — |
| 4 | Chromium 解除跨域 | entrypoint 加 `--disable-web-security` | 官方「命令行禁用跨域」文檔；免在遠端裝插件 | 容器內 `/proc/*/cmdline` 含該 flag；畫面出現黃條 |
| 5 | 插件側載 | entrypoint 掃 `/home/taoli/ext/*/manifest.json` 組 `--load-extension=` | 自寫插件不經商店 | `scp -r` 後容器即見（實測） |
| 6 | 繁中介面 | compose `environment: LANG=zh_TW.UTF-8` + 掛同版本 `zh-TW.pak / zh-CN.pak` | **Alpine Chromium 142 忽略 `--lang`，只認 LANG**；語言包不在 image 內，容器非 root 無法 apk add | headless 對照實驗 `<html lang>`；主進程 maps 載入 `zh-TW.pak` |
| 7 | 語言包自動抽取 | setup.sh 用臨時 alpine 容器 `apk fetch chromium-lang=<同版本>` 解出 pak 到 `/opt/taoli/locales/` | 版本須與 image 內 Chromium 一致，否則 Chromium 拒載退回英文 | 倉庫版本 142.0.7444.59 = 容器版本 |
| 8 | noVNC 編碼調校 | 覆蓋 `index.html`：`compressionLevel 9→2`、`qualityLevel 0→6` | 2 vCPU 上影像編碼是瓶頸；東京直連 55 ms 頻寬充裕，用頻寬換 CPU | 容器內 `/usr/share/novnc/index.html` 內容 |
| 9 | Chromium 省力參數 | `--disable-smooth-scrolling --animation-duration-scale=0 --renderer-process-limit=2 --accept-lang=zh-TW,zh,en-US` | 減少每幀變動區域；限制渲染進程數 | cmdline |
| 10 | 更新策略 `stop-first` | container 服務 `update_config.order: stop-first` | 上游 `start-first` 讓新舊兩個 Chromium 同時開同一 profile → "Profile error / didn't shut down correctly" | `service inspect … UpdateConfig.Order` |
| 11 | 檔案交換區 | 掛 `/opt/taoli/share`（rw）、`/opt/taoli/ext`（ro） | 上游只有 `/mnt`（沒文件化） | 雙向寫入實測 |
| 12 | 裝後變更流程文件化 | README「裝完之後改東西怎麼生效」 | `stack deploy` 重跑需要 keychain/KEY.pem（裝完已刪）→ 必失敗；正解是 `service update --force / --mount-add / --env-add` | 實機踩過 |

---

## 二、建議再做（按價值排序；未做）

### A. 可靠性

| # | 項目 | 做法 | 價值 | 取捨 |
|---|---|---|---|---|
| A1 | **裝完自動驗證** | setup.sh 末尾取代 `logs -f`：等服務 1/1 → 檢查 entrypoint log 有 `[entrypoint]` 行 → cmdline 含 `--disable-web-security` → 印 Tailscale 登入 URL → 才 `logs -f` | 現在「裝完」只代表 deploy 指令送出，沒人確認容器真的起來；上游也一樣 | 多 ~30 行 |
| A2 | **`/etc/sysctl.conf` ip_forward 改 1** | setup.sh 加一行 `sed -i 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf` | 騰訊雲鏡像預設 0；任何 `sysctl --system` 或重開機後容器全斷網（踩過，見 Obsidian 踩雷） | 騰訊雲以外的鏡像無此行，sed 無副作用 |
| A3 | **Docker 安裝冪等** | `command -v docker >/dev/null \|\| curl get.docker.com \| sh` | 重跑時 get.docker.com 會重跑 apt、印一堆警告、有機會升版重啟 daemon 把容器踢一次 | 要升 Docker 時手動 |
| A4 | **daemon.json 合併而非覆寫** | 存在就備份到 `daemon.json.bak.<date>` 再寫 | 上游直接 `>` 覆寫；全新機無所謂，但違反「刪改核對」 | 幾行 |
| A5 | **憑證/secret 重跑處理** | 若 `docker secret ls` 已有三個 secret → 跳過 openssl 與 secret 建立，改走 `service update` 路徑 | 現在重跑 setup 到 `stack deploy` 必死（secret 檔已刪） | 等於把「首裝」與「更新」分成兩條路徑 |
| A6 | **bootstrap 固定 commit** | bootstrap 用 `git rev-parse` 不可行（無 git）；改為 bootstrap 先抓 `https://api.github.com/repos/…/commits/main` 取 SHA，再以 SHA 路徑拉檔 | 繞過 raw CDN ~5 分鐘快取；剛推的修正立即可裝 | 多一次 API 呼叫（匿名 60 次/小時夠用） |

### B. 安全

| # | 項目 | 做法 | 價值 | 取捨 |
|---|---|---|---|---|
| B1 | **上游 seccomp.json 釘 SHA256** | 下載後 `sha256sum -c`，不符即停 | 目前是 `curl \| >` 盲信上游 GitHub；seccomp 是容器的 syscall 白名單，被動過 = 沙箱形同虛設 | 上游更新時要手動更新 hash（這正是目的） |
| B2 | **image 釘 digest** | compose 用 `image@sha256:…` 而非 `:latest` | `:latest` 可被上游（或被盜的上游帳號）靜默換掉；signer 持有助記詞，值得釘 | 升級要手動改 digest（可寫 `update.sh` 自動查最新 digest 並提示差異） |
| B3 | 主機加固併入可選腳本 `harden.sh` | SSH 僅金鑰 / fail2ban / unattended-upgrades / BBR / swap，全部冪等 | 今天手動做的五件事，下一台要重做 | 與 setup.sh 分開，保持 setup 只管容器 |
| B4 | keychain 權限檢查 | 存在時要求 `chmod 600` 且 owner root，否則停 | 助記詞檔被 644 放在 /opt 幾秒也不該 | 一行 |

### C. 可維護性

| # | 項目 | 做法 | 價值 | 取捨 |
|---|---|---|---|---|
| C1 | **上游漂移偵測** `check-upstream.sh` | 抓上游 `setup.sh / compose.yml / entrypoint.sh`（從 image 內 `docker cp` 出來）與本 repo diff，列出上游新增的行 | 我們覆蓋了 entrypoint，上游若加了新步驟（例如換 VNC 參數）我們不會自動得到 | 只做提示，不自動合併 |
| C2 | 語言包抽取抽成 `fetch-locales.sh` | setup.sh 與日後升級都呼叫同一支 | 目前那段 inline 在 setup.sh，升級 image 時要手動複製來跑 | — |
| C3 | `update.sh` | `docker pull` 兩個 image → 若 Chromium 版本變則重抽語言包 → `service update --force` 兩個服務 → 跑 A1 的驗證 | 把 README 那段「更新」變成一行 | — |
| C4 | 移除 `--lang=zh-TW` | 實測無效，留著誤導下一個人 | 乾淨 | 無 |

### D. 不建議做的

| 項目 | 為什麼不做 |
|---|---|
| 自建 image（fork dockerfile 改 entrypoint/加語言包） | 得到的只是少兩個 bind mount；代價是要維護 build/push 流程、失去「上游 pull 即更新」。目前覆蓋法已足夠 |
| 把 noVNC 443 發佈到主機 / 公網 | 上游設計靠 Tailscale 作唯一入口；VNC 無密碼，發佈出去 = 裸奔 |
| 再調 sysctl（fd 上限、TCP 參數、conntrack） | 工作負載是「一個人一個瀏覽器」，與伺服器調參的情境差三個數量級；已驗 BBR 對此場景無感 |
| 在同一台加裝其他服務 | setup.sh 會覆寫 daemon.json、開 swarm；專用機原則 |

---

## 三、執行順序建議

1. **A2 + A1 + C4**（一次 commit：防斷網、裝完自驗、去死參數）——最小、最有價值。
2. **B1 + B2**（釘 hash/digest）——在放入真 keychain 之前做完。
3. **A5 + C3**（首裝/更新分流 + update.sh）。
4. **B3 harden.sh**（下一台機器前）。
5. A3 / A4 / A6 / C1 / C2 視情況。

每步都要在 taoli-vps 實機重跑一次並跑 A1 的驗證，不以「腳本語法通過」當完成。
