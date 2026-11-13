#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-pure-part2.sh
# Description: OpenWrt DIY script part 2 (After Update Feeds)
#              純淨基礎 + 性能優化版
#
# 這個腳本做三件事：
#   1. 預設 IP / 語言 / 主題（bootstrap，OpenWrt 原生）
#   2. 板級 DTS 修正 0001 / 0004 / 0005 / 0006 / 0007 / 0008 / 0009（風扇 + LED +
#      WiFi MAC + USB 穩定 + pci=noaer/ramoops）
#   3. mt76 backport 0002（STA_REC 先於 VoW，修 wifi down/up 後連不上）
#   ＋ uci-defaults 兜底（語言 / 主題 / HWNAT 硬體流量卸載）
#
# 註：sysctl 性能調校（fq + BBR、TCP 16 MB 緩衝區、conntrack）**已經不在這裡**。
#     以前 append 到 package/base-files/files/etc/sysctl.conf，但那個檔案是 conffile，
#     被 /lib/upgrade/keep.d/base-files-essential 保留 → sysupgrade 後舊機上的檔案
#     會蓋掉新映像的版本，調校等於永遠不生效（實測 rmem_max 一直停在 208 KB）。
#     現在改由倉庫的 files/etc/sysctl.d/99-tr3600-pure.conf 交付（files/ 是 rootfs
#     overlay，而 /etc/sysctl.d/ 不被 sysupgrade 保留）。見 diy-pure-part1.sh。
#
# 每個 DTS patch 都先 --dry-run 再套用，套用後複查標記字串；任何一個沒生效
# 就 exit 1，絕不產出「看起來編過了但其實沒修」的固件。
#
# 註：0006 與 0007 都會動同一段，順序不能顛倒（0007 改的是 0006 放進去的值）。
#     0006 的偵測標記刻意用 `cpu_trip_active_low: active-low {`，
#     因為 0007 會把 0006 的 `cooling-levels = <0 64 160 255>` 改掉，
#     用那個當標記會讓「重跑」誤判成沒套用。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/patches" ]; then
	REPO_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../patches" ]; then
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
	echo "[tr3600-pure] WARNING: no patches/ directory found near $SCRIPT_DIR"
fi
PATCHDIR="$REPO_ROOT/patches"

echo "========================================================"
echo " TR3600 pure build: diy-pure-part2.sh"
echo " repo root : $REPO_ROOT"
echo " patch dir : $PATCHDIR"
echo "========================================================"

# =========================================================
# 1. 預設 IP / 語言 / 主題
# =========================================================

# 預設 IP 從 192.168.1.1 改為 10.0.0.1
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 主題：OpenWrt 原生 bootstrap。
# config 裡已經有 CONFIG_DEFAULT_THEME=bootstrap + CONFIG_PACKAGE_default-settings，
# 這裡再放一份 uci-defaults 兜底。注意 openwrt-25.12 的 base-files 已經沒有
# etc/config/luci，對它 sed 會在 `set -e` 下直接打死編譯，所以一定要先判斷。
LUCI_CFG=package/base-files/files/etc/config/luci
if [ -f "$LUCI_CFG" ]; then
	sed -i 's/luci.main.theme=argon/luci.main.theme=bootstrap/' "$LUCI_CFG"
	echo "[tr3600-pure] patched $LUCI_CFG -> bootstrap"
else
	echo "[tr3600-pure] $LUCI_CFG 不存在（openwrt-25.12 已移除），改用 uci-defaults"
fi

# =========================================================
# 2. 性能優化（sysctl）—— 已搬到 files/etc/sysctl.d/99-tr3600-pure.conf
# =========================================================
# 這裡以前會 append 到 package/base-files/files/etc/sysctl.conf。
# 那個做法有兩個問題，所以整段拿掉了：
#   1. /etc/sysctl.conf 是 conffile，被 sysupgrade 保留 → 新映像的版本被舊檔蓋掉。
#   2. /etc/init.d/sysctl 讀取順序是 sysctl.d/*.conf 先、sysctl.conf 後，
#      所以 sysctl.conf 反而會覆蓋 sysctl.d。
# 現在統一由 files/ overlay 交付（files/ 由 include/image.mk 的 prepare_rootfs
# 蓋進 rootfs；/etc/sysctl.d/ 不被保留 → 永遠用新映像的）。
# files/ 的複製與守門在 diy-pure-part1.sh。

# =========================================================
# 3. uci-defaults：語言 / 主題 / 硬體流量卸載
# =========================================================
THEME_UCI=package/base-files/files/etc/uci-defaults/99-tr3600-pure-defaults
mkdir -p "$(dirname "$THEME_UCI")"
cat > "$THEME_UCI" <<'EOS'
#!/bin/sh
# TR3600 pure build: 首次開機預設值 + 性能優化
# 這個檔案由 /etc/init.d/boot 執行一次，成功後會自我刪除。

# --- LuCI 預設語言 / 主題（OpenWrt 原生 bootstrap）---
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.theme='bootstrap'
uci -q commit luci

# --- 硬體流量卸載（HWNAT）---
# MediaTek filogic 的硬體 NAT：轉發幾乎不吃 CPU，2.5G 才跑得滿。
# 需要 kmod-mediatek_hnat + kmod-nf-flow（config 裡都有）。
# 若之後要用 SQM / 流量整形，記得把這兩項關掉。
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'
uci -q commit firewall

exit 0
EOS
chmod 0755 "$THEME_UCI"
echo "[tr3600-pure] installed $THEME_UCI"

# =========================================================
# 4. 板級 DTS 修正
# =========================================================
DTS=target/linux/mediatek/dts/mt7987b-cudy-tr3600-v1.dts

echo "--------------------------------------------------------"
echo "[1/2] board DTS fixes -> $DTS"
if [ ! -f "$DTS" ]; then
	echo "ERROR: $DTS not found. Is REPO_BRANCH still agent/cudy-tr3600-v1-6.12 ?"
	exit 1
fi

# apply_dts_patch <patch-basename> <marker-string>
#   applies patches/<basename>.patch with -p1, is idempotent, and aborts the
#   build if the patch neither applies nor lands.  Never ship a silently
#   broken DTS.
apply_dts_patch() {
	local name="$1" marker="$2"
	if grep -qF "$marker" "$DTS"; then
		echo "  $name: already applied, skipping"
	else
		patch -p1 --dry-run --forward -s < "$PATCHDIR/$name.patch" \
			|| { echo "ERROR: $name does not apply"; exit 1; }
		patch -p1 --forward -s < "$PATCHDIR/$name.patch"
		echo "  $name: applied"
	fi
	grep -qF "$marker" "$DTS" || { echo "ERROR: $name did not take effect"; exit 1; }
}

# 1. fan on PWM0 (PIN13) instead of PWM1; pinctrl-0 -> pwm_pins
apply_dts_patch 0001-tr3600-fan-pwm0          'pwms = <&pwm 0 50000 0>;'
# 2. GPIO48 = white, GPIO46 = red (there is no blue LED on this board)
apply_dts_patch 0004-tr3600-led-colours       'led_status_white: led-0 {'
# 3. 2.4 GHz = base + 0x00, 5 GHz = base + 0x10 (vendor layout)
apply_dts_patch 0005-tr3600-wifi-mac-layout   'nvmem-cells = <&macaddr_bdinfo_de00 16>;'
# 4. 風扇溫控曲線：待機停轉，65/75/85 C 三段
#    標記用節點名而不是數值 —— 0007 會把數值改掉。
apply_dts_patch 0006-tr3600-fan-thermal-curve 'cpu_trip_active_low: active-low {'
# 5. 風扇曲線調校：拿掉無效的 25% 段，改成 50/78/100%，
#    整條曲線上移到 68/78/88 C，讓 64 C 的待機溫度真的落在停轉區
apply_dts_patch 0007-tr3600-fan-curve-tune    'cooling-levels = <0 128 200 255>;'
# 6. USB 穩定性：對齊原廠 Cudy DTB —— 屏蔽 u3 口（u3p-dis-msk=0x1）、
#    啟用 USB2 PHY、禁用 SoC USB3 PHY（tphyu3port0）。soapmancn 錯誤啟用
#    USB3 PHY 是 CMIOT ML307R 反復掉線/重枚舉的根因。marker 用 u3p-dis-msk。
apply_dts_patch 0008-tr3600-usb-stability    'mediatek,u3p-dis-msk = <0x1>;'
# 7. 可診斷性 + 關 AER：bootargs 加 pci=noaer（MT7990 PCIe 的 AER abort
#    風暴會一路走到 panic，報告沒有意義）；並在 DRAM 末端留 1 MiB ramoops，
#    讓 /sys/fs/pstore 真的能留下上一次 panic 的 console（以前永遠是空的）。
apply_dts_patch 0009-tr3600-noaer-ramoops     'pci=noaer'

grep -qF 'pinctrl-0 = <&pwm_pins>;' "$DTS" || { echo "ERROR: pinctrl not fixed"; exit 1; }
grep -qF 'temperature = <68000>;' "$DTS"   || { echo "ERROR: fan curve 0007 did not land"; exit 1; }
grep -qF 'mediatek,u3p-dis-msk = <0x1>;' "$DTS" || { echo "ERROR: USB stability 0008 did not land"; exit 1; }
grep -qF '&tphyu3port0' "$DTS" && grep -A2 '&tphyu3port0' "$DTS" | grep -qF 'status = "disabled";' \
	|| { echo "ERROR: USB3 PHY 0008 not disabled"; exit 1; }
grep -qF 'compatible = "ramoops";' "$DTS" || { echo "ERROR: ramoops 0009 did not land"; exit 1; }
grep -qF 'pci=noaer' "$DTS" || { echo "ERROR: pci=noaer 0009 did not land"; exit 1; }
echo "  OK: PWM0 fan / white+red LEDs / vendor MAC layout / 68-78-88 C fan curve / USB stability (u3 masked, USB3 PHY off) / noaer + ramoops"

# =========================================================
# 5. mt76 backports (STA_REC/VoW 顺序 + PCIe 复位保护)
# =========================================================
P2="$PATCHDIR/0002-mt76-mt7996-sta-rec-before-vow.patch"
P10="$PATCHDIR/0010-mt7996-guard-pcie-recovery.patch"
MT76PATCHDIR=package/kernel/mt76/patches

echo "--------------------------------------------------------"
echo "[2/3] mt76 backport STA_REC/VoW -> $MT76PATCHDIR/"
if [ ! -f "$P2" ]; then
	echo "ERROR: $P2 not found"
	exit 1
fi

MT76_SHA=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' package/kernel/mt76/Makefile | tr -d ' ')
echo "  mt76 PKG_SOURCE_VERSION = $MT76_SHA"
if [ "$MT76_SHA" != "39c960c3ada558b4c2e7915772483d3731573d09" ]; then
	echo "  WARNING: mt76 was bumped upstream. The backport was verified against"
	echo "           39c960c3ada558b4c2e7915772483d3731573d09 only."
	echo "           The patch may still apply - the build will fail loudly if not."
fi

mkdir -p "$MT76PATCHDIR"
cp "$P2" "$MT76PATCHDIR/0202-wifi-mt76-mt7996-send-the-STA_REC-before-the-per-station-VoW-setup.patch"
echo "  installed: $(basename "$MT76PATCHDIR"/0202-*.patch)"

echo "--------------------------------------------------------"
echo "[3/3] mt76 backport PCIe 复位保护 -> $MT76PATCHDIR/"
if [ ! -f "$P10" ]; then
	echo "ERROR: $P10 not found"
	exit 1
fi
cp "$P10" "$MT76PATCHDIR/0203-wifi-mt76-mt7996-guard-L1-SER-recovery-against-dead-pcie.patch"
echo "  installed: $(basename "$MT76PATCHDIR"/0203-*.patch)"

echo "========================================================"
echo " TR3600 pure build: part2 done (DTS + mt76 + 性能優化)"
echo "========================================================"
