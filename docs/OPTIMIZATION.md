# 安裝腳本待辦（只列必要）

| # | 項目 | 時機 | 原因 |
|---|---|---|---|
| 1 | setup.sh 加一行：`sed -i 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf` | ✅ 已做（2026-08-21） | 騰訊雲鏡像預設 0；任何 sysctl 重載或重開機後容器全斷網（2026-08-20 踩過） |
| 2 | entrypoint.sh 移除 `--lang=zh-TW` | ✅ 已做 | 實測無效（介面語言由 `LANG` 決定），留著誤導 |
| 3 | compose.yml 的 signer image 改釘 digest（`image@sha256:…`） | **放入真 keychain 之前** | signer 持有助記詞；`:latest` 等於信任上游帳號永不被盜 |

其餘（自動驗證、update.sh、harden.sh、釘 seccomp hash、冪等安裝…）在只有一台機器、裝一次的前提下不做；開第二台時再評估。
