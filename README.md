# Cudy TR3600 v1 — OpenWrt 自建固件（GitHub Actions）

編譯 Cudy TR3600 v1（MT7987B + MT7990，Wi-Fi 7）的 OpenWrt 固件，
一次修好**風扇 / LED / WiFi MAC / 無線 STA_REC** 四個硬體描述問題。

- **建置 HEAD**：`046aec0dccd9`（2026-08-11，「mediatek: add support for Cudy TR3600 v1」），
  即當前固件版本來源（`DISTRIB_REVISION = r0-046aec0`）
- **基底**：`openwrt-25.12` + TR3600 v1 板級支援（上游 PR #24596，**尚未合併**）

## 版本線

**2026-10-13 起只剩一條線。** iStore 版（`build-openwrt-iStore.yml`）已退休，
連同 iStore 應用商店本身（`luci-app-store` + `linkease/istore` feed）一起移除，
第三方主題（Argon / Aurora / Kucat）也一併清掉。

| | **功能性能版** |
|---|---|
| Workflow | `Build Cudy TR3600 OpenWrt Pure` |
| 設定檔 | `mt7987-cudy-tr3600-pure.config` |
| DIY | `diy-pure-part1/2.sh` |
| 外掛 | 智能風扇（LuCI 模組名就叫「智能風扇」，中英文模式一致）＋ **VPN / 組網 / 代理 / 下載 / 共享 / DDNS**（見下方「第二輪」那節） |
| 主題 | **OpenWrt 原生 bootstrap** |
| Patch | 0001–**0007**（0008 已下線） |
| Tag | `Cudy-TR3600-Pure-<時間>` |

另外做**性能優化**：`fq` + **BBR**、TCP 緩衝 16 MB、**HWNAT 硬體流量卸載**
（`flow_offloading` + `flow_offloading_hw`）、WED 無線卸載、zram。
Release 保留最近 10 個。

## 修了什麼

| Patch | 症狀 | 修法 |
|---|---|---|
| `0001-tr3600-fan-pwm0` | 風扇全速轉、LuCI 顯示「未檢測到」 | DTS 把 pwm-fan 從 PWM 通道 1 改回**通道 0**（硬體風扇實際接在 PWM0@PIN13） |
| `0002-mt76-mt7996-sta-rec-before-vow` | 改過 Wi-Fi MAC 過濾後客戶端再也連不上，**只有重開機能救** | mt76 `mt7996_mcu_add_sta()` 改成**先送 STA_REC 再送 VoW**（backport 上游 `da2c90d2`） |
| `0003-luci-tr3600-fan-keep-pending-input` | LuCI 風扇頁每 5 秒輪詢會蓋掉還沒按 Apply 的值 | 加 dirty flag（外觀，非致命） |
| `0004-tr3600-led-colours` | 狀態燈顏色與機身不符 | `led-0` = **白**@GPIO48、`led-1` = **紅**@GPIO46（上游誤標成 blue/white，**本板無藍燈**） |
| `0005-tr3600-wifi-mac-layout` | 2.4G / 5G 的 MAC 位址對不上 | 2.4 GHz = **base+0**（與 LAN 相同）、5 GHz = **base+0x10** |
| `0006-tr3600-fan-thermal-curve` | 待機時風扇持續低鳴 | 60 °C 以下**停轉**、65/75/85 °C 三段（上游 40 °C 就鎖 50 %） |
| `0007-tr3600-fan-curve-tune` | 0006 的 65 °C 那段是 25 % PWM，**實測完全沒有降溫效果**；本板待機剛好 64 °C，卡在門檻上 | 改成 **50 / 78 / 100 %**，曲線整條上移到 **68 / 78 / 88 °C**——待機真的停轉，要降溫時每一段都有用 |

> ⚠️ **0007 才是最終值**：`cooling-levels = 0 128 200 255`、trip `68000 / 78000 / 88000`。
> 拿 0006 的 `0 64 160 255` / 65000 去比，會誤判成「patch 沒生效」。

`0008-luci-tr3600-fan-smart-suggestions`（風扇頁智能季節建議）已於 **2026-10-13 下線**：
那三條季節曲線 + 日曆 + 待機基準，全是內核 `step_wise` 的**第二次實作**，只多一層會壞的
東西。補丁留在 build kit 的 `retired/patches/`，**本倉庫不含**。

`diy-pure-part1.sh` 另外把 `luci-app-tr3600-fan` 的腳本 `chmod 0755`
（上游 git 樹全是 100644，上機後 0644 → `exec_direct` EACCES → LuCI 空狀態）。

風扇插件已內建在本倉庫 `vendor/luci-app-tr3600-fan/`，`diy-pure-part1.sh` 以
`cp -a` 安裝，**不依賴任何第三方倉庫**（連「找不到就 clone 上游」的回退都沒有，
直接失敗——第三方倉庫已經消失過一次了）。

## 目錄結構

```
.
├── .github/workflows/
│   └── build-openwrt-pure.yml          # 唯一的建置線（功能性能版）
├── diy-pure-part1.sh        # feeds 之前：裝風扇插件 + 0003 + 複製 files/ overlay
├── diy-pure-part2.sh        # feeds 之後：0001~0007 + 0002 + HWNAT（sysctl 已移出）
├── diy-partX.sh             # 關掉 Ruby YJIT，避免 Rust 長編譯
├── mt7987-cudy-tr3600-pure.config                    # 設定檔
├── files/                   # rootfs overlay（由 include/image.mk 蓋進固件）
│   └── etc/
│       ├── apk/repositories.d/distfeeds.list  # apk 源 → SJTU 鏡像
│       └── sysctl.d/99-tr3600-pure.conf       # fq+BBR、TCP 16 MB、conntrack
├── patches/
│   ├── 0001-tr3600-fan-pwm0.patch
│   ├── 0002-mt76-mt7996-sta-rec-before-vow.patch
│   ├── 0003-luci-tr3600-fan-keep-pending-input.patch
│   ├── 0004-tr3600-led-colours.patch
│   ├── 0005-tr3600-wifi-mac-layout.patch
│   ├── 0006-tr3600-fan-thermal-curve.patch
│   └── 0007-tr3600-fan-curve-tune.patch
└── vendor/
    └── luci-app-tr3600-fan/  # 內建的風扇插件（10 個檔案）
```

`0006` 與 `0007` 動同一段 DTS，**順序不能顛倒**（0007 改的是 0006 放進去的值）。
`diy-pure-part2.sh` 對 0006 的偵測標記刻意用節點名 `cpu_trip_active_low: active-low {`
而不是 `cooling-levels` 的數值，否則 0007 改完之後會被誤判成「沒套用」。

`0003` 是唯一動 LuCI 風扇頁的補丁（0008 下線後），**必須套而且必須成功**。
`part1` 對它是**硬失敗**（不再「打不上去就繼續」），並且加 `-F 0` 關掉 fuzz——
預設 fuzz=2 會讓 patch 在上游漂移時「模糊命中」照樣回 rc=0。

## 風扇控制：只有 auto / manual

風扇頁（**系統 → 智能風扇**）只有兩種模式：

| 模式 | 行為 |
|---|---|
| **自動**（預設） | 交給內核 `step_wise` governor，按板級 DTS 曲線調速 |
| **手動** | 固定 0–3 檔；100 °C 會被強制拉滿，110 °C 交還自動（保命線） |

DTS 曲線（patch 0006 + **0007**，**0007 才是最終值**）：

| trip | PWM 檔位 |
|---|---|
| 68 °C | 50 % |
| 78 °C | 78 % |
| 88 °C | 100 % |
| < 68 °C | 停轉 |

實測（**無線關閉**）：待機約 **59 °C**；4 核 `yes` 滿載 100 秒只爬到 **66 °C**。
兩個都還在 68 °C 第一段之下，所以**這條曲線實務上風扇幾乎不會轉**（無線開著會再
高一些）。要讓風扇真的參與散熱就得把第一段往下調，但那就是待機噪音的取捨。

設定檔在 `/etc/config/tr3600-fan`（只有 `mode` / `level`），預設 `mode 'auto'`。
指令列：`/usr/sbin/tr3600-fan set auto`、`set manual 0-3`、`get`。

### `set auto` 會清掉手動模式留下的檔位（2026-10-13 修）

內核 `step_wise` governor **只在 trip 跨越門檻時才會動作**。實測：
把 `trip_point_N_temp` 改一下（造成一次跨越）風扇會立刻反應；溫度穩定停在
trip 之下時，governor 完全不會被叫到。

所以手動模式（走 `user_space`）留下的 `cur_state`，在溫度已經落回所有 trip 之下
時不會被清掉——沒有跨越事件——風扇就一直停在手動檔位，正是「待機低鳴」。

重現：`set manual 1` 之後 `set auto`，SoC 59 °C（比第一個 trip 低 9 °C），
風扇在檔位 1 卡住 60 秒不動。

修法：`set_auto` 切回 `step_wise` 之後，**只在溫度低於最低的 active trip 時**
明確把 `cur_state` 歸零。這個條件下關風扇一定正確；門檻是從
`/sys/class/thermal/thermal_zone0/trip_point_*_temp` 讀的，不是把曲線再寫一份在
用戶態（所以沒有 0008 那種漂移問題）。溫度在 trip 之上時完全不動它——
**永遠不會在高溫時降轉速**。

### ⚠️ 0008「智能季節建議」已於 2026-10-13 下線

它曾經加上第三種模式 `smart`、三條季節曲線（winter 68/78/88、mild 66/76/86、
summer 58/68/78）、日曆判斷、待機基準建議與季節覆寫。

**拿掉的理由：那些全是內核 `step_wise` 已經在做的事的第二次實作。**
DTS 的 trip 點本來就會驅動風扇，用戶態每 10 秒再用 shell 重算一遍同樣的曲線，
只是多一層會壞的東西——它得自己維護 hysteresis、自己的待機基準啟發式、一套日曆，
而且會跟 DTS 的數值漂移（mild 用 66/76/86，DTS 是 68/78/88）。拿掉之後風扇行為
不變，可壞的東西少一大半，UI 回到一眼看得懂。

- 補丁留在 build kit 的 `retired/patches/0008-…`（**本倉庫不含，也不再套用**）
- 編譯守門改成**反向斷言**：`season_trips` / `set_smart` / `SEASON_TRIPS` /
  `Smart suggestion` / `option season` 只要出現在固件裡就 `exit 1`

## 模組名：智能風扇

LuCI 選單與頁面標題都是 **智能風扇**，**中英文模式都一樣**。

做法是讓 menu.d 的 `title` 與頁面 `h2` 用同一個字面量，`po/zh_Hans` 裡也放同名條目
（`msgid == msgstr`）。中文模式查到條目回傳自身；英文模式沒有 en 目錄，回退到 msgid
也是自身——兩邊都穩定顯示「智能風扇」，不會退回 `TR3600 Fan Control`。編譯守門會斷言這件事。

## 軟體源鏡像：SJTU（2026-10-13）

OpenWrt 出廠的 `/etc/apk/repositories.d/distfeeds.list` 指向
`https://downloads.openwrt.org/releases/25.12-SNAPSHOT/...`。這在國內**慢到不能用**：

| 來源 | `targets/mediatek/filogic/packages/packages.adb`（14 KB） | 整份 `apk update`（7 個索引，約 1.4 MB） |
|---|---|---|
| `downloads.openwrt.org`（預設） | **9.75 s**（≈ 1.5 KB/s） | 70 s 以上 |
| `mirror.sjtu.edu.cn` | **0.32 s** | **4 s** |

換成 SJTU 之後 `apk update` **快約 30 倍**，而且依賴解析完全正常
（實測 `apk add --simulate luci-app-ttyd` 正確解析出 5 個套件，LuCI 版本號
`26.284.22350~8125d12` 與機上完全一致）。

**為什麼只有 SJTU**：25.12-SNAPSHOT 是滾動快照，TUNA / USTC / 阿里雲只鏡像
`releases/`，對 `SNAPSHOT` 一律回 **404**（實測）。SJTU 是目前唯一有完整
25.12-SNAPSHOT 的國內鏡像，7 條索引路徑全部 **200**。

**實作**：倉庫根目錄的 `files/` 是 OpenWrt 的 rootfs overlay ——
`include/image.mk:403` 有 `$(call prepare_rootfs,$(mkfs_cur_target_dir),$(TOPDIR)/files)`，
它在套件安裝**之後**、postinst **之前**把 `files/` 複製進 rootfs，所以會蓋掉
`base-files` 產生的那份 `distfeeds.list`。`diy-pure-part1.sh` 負責把倉庫的 `files/`
複製成 `openwrt/files/`。

**兩道守門**：`part1` 之後確認 `files/etc/apk/repositories.d/distfeeds.list` 存在且
指向 SJTU；編譯後再從 `build_dir/*/root-*/etc/apk/repositories.d/distfeeds.list`
（真正進固件的那份）複查，不是 SJTU 就 `exit 1`。

> ⚠️ 這是**刻意的地區性優化**。若 SJTU 哪天停止鏡像 SNAPSHOT，`apk update` 會失敗。
> 退路：把 `files/etc/apk/repositories.d/distfeeds.list` 改回 `downloads.openwrt.org`
> 或刪掉整個 `files/`（機上原本那份備份在 `/root/feed-mirror-backup-20261013/`）。

## sysctl 調校：`files/etc/sysctl.d/`（2026-10-13）

TCP 16 MB 緩衝區以前寫在 `package/base-files/files/etc/sysctl.conf`，但**從來沒生效**——
實機量到的是 **212992（208 KB）**。因為 `/etc/sysctl.conf` 是 conffile，列在
`/lib/upgrade/keep.d/base-files-essential` 裡，**`sysupgrade` 保留舊機上的那份，把新映像
的蓋掉**。而且 `/etc/init.d/sysctl` 的讀取順序是 `sysctl.d/*.conf` 先、`sysctl.conf` 後，
所以 `sysctl.conf` 反而會覆蓋 `sysctl.d`。

改成 `files/etc/sysctl.d/99-tr3600-pure.conf`（`/etc/sysctl.d/` 不在任何 keep.d 裡 → 永遠
用新映像的；`99-` 排在內建 `10/11/12-` 之後）：

| 項目 | 舊值 | 新值 |
|---|---|---|
| `net.core.default_qdisc` | `fq_codel` | **`fq`** |
| `net.core.rmem_max` / `wmem_max` | 212992 | **16777216** |
| `net.core.netdev_max_backlog` | 1000 | 2048 |
| `net.netfilter.nf_conntrack_max` | 31232 | 65536 |

`default_qdisc=fq` 以前也是**靜默失敗**（`write error: No such file or directory`），因為
**`sch_fq` 在 `kmod-sched` 而不是 `kmod-sched-core`**。config 已加
`CONFIG_PACKAGE_kmod-sched=y`，它的 `AUTOLOAD` 用前綴 73 載入 `sch_fq`。

開機順序已實證：`S10boot`（kmodloader 讀 `/etc/modules.d/`）早於 `S11sysctl`——
證據是機上 `nf_conntrack_acct = 1`，這個值只由 `/etc/sysctl.d/11-nf-conntrack.conf` 設定，
而它需要 `nf_conntrack` 模組已在。

## USB：儲存 / 網卡 / 共享（2026-10-13）

這台有 USB 3.0 埠（DTS `usb@11200000` = `okay`、`xhci_mtk_hcd` 已載入、兩個 root hub
都在），但**沒有任何儲存或網路類驅動** → 插隨身碟、插網卡都不會有反應。而 feed 裡
**一個 kmod 都沒有**（9977 個套件只有 1 個 `kmod-*`），事後 `apk add` 補不了，
只能編進固件。config 已加：

- **儲存**：`kmod-usb-storage`、`kmod-usb-storage-uas`、`kmod-fs-ext4`、`kmod-fs-exfat`、`block-mount`
- **USB 網卡**：`kmod-usb-net` + `rtl8152` / `asix-ax88179` / `asix` / `aqc111` /
  `lan78xx` / `smsc95xx` / `rtl8150` / `mcs7830` / `dm9601-ether` / `sr9700` / `pegasus`
- **USB 共享（tethering）**：`rndis`（Android/Windows）、`cdc-ncm`（iPhone/4G 網卡）、
  `cdc-ether`、`cdc-eem`、`cdc-subset`、`ipheth`（iPhone）
- **WWAN 模組**：`kmod-usb-wdm`、`qmi-wwan`、`cdc-mbim`、`kmod-usb-serial*`、
  `usb-modeswitch`、`uqmi`、`umbim`、`luci-proto-qmi` / `-mbim`
- **序列埠**：`ch341` / `cp210x` / `pl2303` / `ftdi`

編譯守門會在 `oldconfig` 之後斷言這些套件仍為 `=y`，並確認
`wpad-basic-mbedtls` 已被換成 `wpad-mbedtls`（前者缺 802.11r/k/v 快速漫遊與 WPS）。

## 功能外掛：VPN / 組網 / 代理 / 下載 / 共享 / DDNS（2026-10-13 第二輪）

| 需求 | 套件 | 來源 |
|---|---|---|
| zerotier | `zerotier` | 官方（⚠️ 只有命令列，**沒有 LuCI 頁**） |
| wireguard | `kmod-wireguard` + `wireguard-tools` + `luci-proto-wireguard` | 官方 |
| tailscale | `tailscale` + `luci-app-tailscale-community` | 官方 |
| openvpn | `openvpn-openssl` + `luci-app-openvpn` + `openvpn-easy-rsa` | 官方 |
| aria2 | `aria2` + `luci-app-aria2` | 官方 |
| samba4 | `samba4-server` + `luci-app-samba4` | 官方 |
| webdav | `luci-app-webdav` | **第三方** |
| luci-app-ddns | `luci-app-ddns` + `ddns-scripts` | 官方 |
| ddns-go | `luci-app-ddns-go` | **第三方** |
| mosdns | `luci-app-mosdns` | **第三方** |

### 第三方 feed

`mosdns / ddns-go / webdav` 官方 feed 都沒有（實測 apk 索引 + 上游倉庫）。
`diy-pure-part1.sh` 會把這兩個 feed 追加到 `feeds.conf.default`：

```
src-git kenzok8 https://github.com/kenzok8/openwrt-packages.git
src-git small   https://github.com/kenzok8/small-package.git
```

用**單一來源**是刻意的：同一個套件被兩個 feed 重複定義會讓 `make defconfig` 直接報
duplicate package。kenzok8 的聚合 feed 跟官方 feed 撞名的套件（例如 `aria2`），
`scripts/feeds install -a` 會自己跳過並印 WARNING，那是預期行為。

> ⚠️ 這是本建置線**唯一的外部依賴**。第三方 feed 會漂移 —— 2026-10-31 起
> passwall2 已依使用者要求移除（該作者倉庫一度 404 搬到 `Openwrt-Passwall`），
> 當年 `liangcanming/luci-app-tr3600-fan` 更是整個消失。退路：把 part1 裡那兩行
> 註解掉，並在 config 把那幾個 `luci-app-*` 改成 `not set`。

### zerotier 沒有 LuCI 頁

`luci-app-zerotier` 在 25.12 官方 feed 已不存在（`apk list --available | grep zerotier`
只有 `zerotier-1.16.2-r1`；上游 `openwrt/luci` 也查不到）。用命令列：

```sh
uci set zerotier.global.enabled=1; uci commit zerotier
/etc/init.d/zerotier start
zerotier-cli join <network-id>
```

### dnsmasq → dnsmasq-full

passwall2 的 nftables 透明代理 select `dnsmasq-full`。它與 `dnsmasq` 是**同一套件的
不同 variant**（`PROVIDES:=dnsmasq`，不是 CONFLICTS），所以只是換版本，依賴
`dnsmasq` 的套件照常滿足。多了 DNSSEC / DHCPv6 / ipset / nftset。

## 刷機前必讀

> **不要刷 U-Boot。** 本機沒有可用的第三方 U-Boot（OpenWrt `uboot-mediatek` 無
> `cudy_tr3600`；`hanwckf/bl-mt798x` 只支援 MT7981/MT7986）。刷 U-Boot 會覆蓋
> `mtd0 BL2` + `mtd4 FIP`，等於**拆掉現有的救援網**。

刷機前先做**全分區備份**（唯讀、零風險，約 60 秒）——逐個 `mtd` 分區 `dd` 出來即可：

| 分區 | 內容 | 大小 |
|---|---|---|
| `mtd0` | BL2 | 1 MiB |
| `mtd1` | backup | 512 KiB |
| `mtd2` | Factory | 4 MiB |
| `mtd3` | bdinfo | 256 KiB |
| `mtd4` | FIP（ATF + U-Boot） | 2 MiB |
| `mtd5` | ubi（系統，slot A/B） | 232 MiB |

這台有 **A/B 雙開機槽** + `mtk-wdt` watchdog，sysupgrade 寫到另一個槽，
新固件開不起來會**自動回退舊槽**，所以刷機風險低。

## 參考

- 上游 PR #24596（TR3600 支援，base `openwrt-25.12`，**未合併**）：
  <https://github.com/openwrt/openwrt/pull/24596>

