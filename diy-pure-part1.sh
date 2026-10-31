#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-pure-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update Feeds)
#               OpenWrt 精簡 + 性能優化版 — 只裝 TR3600 智能風扇插件
#
# 這一版刻意「什麼都不 clone」：
#   * 沒有任何商店 / 科學上網 / DNS / 主題 / 工具類第三方倉庫
#   * 唯一的套件來源是 feeds（OpenWrt 官方）+ vendor/（本倉庫內建風扇插件）
#   * 2026-10-13：iStore 的 linkease/istore feed 也拿掉了
#
# 為什麼不 clone：
#   上游作者（liangcanming）名下倉庫在 2026-10 全部 404，build #1 就是死在
#   「git clone 一個已經消失的倉庫」。第三方倉庫隨時可能消失，clone 得越多
#   越脆弱。純淨版直接把這個風險歸零。
#
# 風扇插件內建在 vendor/luci-app-tr3600-fan/（與 MichaelJiangg/luci-app-tr3600-fan
# 逐位元組相同），並在複製後強制把三個進入點改成 0755 —— 上游 git tree 把
# 它們存成 100644，OpenWrt 用 $(CP) = "cp -fpR" 複製時會保留該權限，結果
# /usr/sbin/tr3600-fan 上機是 0644，fs.exec_direct() EACCES，LuCI 風扇頁
# 顯示「未檢測到風扇」。這正是本套件最原始要修的症狀。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate the build-kit repo root. In GitHub Actions the workflow copies this
# script into the openwrt/ checkout and runs it from there, so the repo root
# is one level up. When run straight from the repo root (local testing) it is
# SCRIPT_DIR itself. Prefer whichever one actually contains patches/.
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
echo " TR3600 pure build: diy-pure-part1.sh"
echo " repo root : $REPO_ROOT"
echo "========================================================"

# =========================================================
# 第三方 feed（mosdns / ddns-go / webdav）
# =========================================================
# 這三個官方 feed 都沒有（實測：apk 索引 + 上游倉庫都查不到）：
#   mosdns     ← sbwml/luci-app-mosdns
#   ddns-go    ← sirpdboy/luci-app-ddns-go
#   webdav     ← 只有聚合 feed 有
#   （passwall2 已於 2026-10-31 依使用者要求移除，見 config）
#
# 這裡用中文圈最通用的 kenzok8 兩個 feed（openwrt-packages + small-package），
# 它們同時提供上面三個。用單一來源的理由：避免同一個套件被兩個 feed 重複
# 定義 —— 那會讓 make defconfig 直接報 duplicate package。
#
# ⚠️ 這是本建置線唯一的外部依賴。kenzok8 很活躍（2026-10-13 當天還有更新），
#    但第三方 feed 本質上會漂移 —— 之前 liangcanming 的風扇倉庫整個 404
#    就是這個風險。退路：把下面追加的兩行註解掉，並在 config 裡把
#    luci-app-mosdns / -ddns-go / -webdav 改成 not set。
FEEDS_CONF=feeds.conf.default
if [ ! -f "$FEEDS_CONF" ]; then
	echo "ERROR: 找不到 $FEEDS_CONF（cwd 應該在 openwrt 根目錄）"
	exit 1
fi

if grep -q 'kenzok8/small-package' "$FEEDS_CONF"; then
	echo "[tr3600-pure] 第三方 feed 已經在了，跳過"
else
	cat >> "$FEEDS_CONF" <<'EOF'

# ---- TR3600 build: 第三方 feed（mosdns / ddns-go / webdav）----
src-git kenzok8 https://github.com/kenzok8/openwrt-packages.git
src-git small https://github.com/kenzok8/small-package.git
EOF
	echo "[tr3600-pure] 已追加第三方 feed: kenzok8/openwrt-packages + kenzok8/small-package"
fi

if ! grep -q 'kenzok8/openwrt-packages' "$FEEDS_CONF"; then
	echo "ERROR: feeds.conf.default 沒有寫入第三方 feed"
	exit 1
fi
echo "[tr3600-pure] feeds.conf.default 第三方 feed 就位"

mkdir -p package/custom

# =========================================================
# TR3600 風扇控制插件（內建，不依賴任何第三方倉庫）
# =========================================================
VENDOR_FAN="$REPO_ROOT/vendor/luci-app-tr3600-fan"
FANPKG="package/custom/luci-app-tr3600-fan"

rm -rf "$FANPKG"
if [ -d "$VENDOR_FAN" ]; then
	echo "[tr3600-pure] 使用內建風扇套件: $VENDOR_FAN"
	cp -a "$VENDOR_FAN" "$FANPKG"
else
	# 理論上不會走到這裡（vendor/ 就在倉庫裡）。真的沒有就硬失敗，
	# 不要偷偷去 clone 一個可能已經消失的第三方倉庫。
	echo "ERROR: $VENDOR_FAN 不存在，無法編入風扇插件（純淨版不做第三方 clone 回退）"
	exit 1
fi

# --- 讓風扇 helper 與 init script 可執行 ---
for f in "$FANPKG/root/usr/sbin/tr3600-fan" "$FANPKG/root/etc/init.d/tr3600-fan" "$FANPKG/root/etc/uci-defaults/99-tr3600-fan"; do
	if [ -f "$f" ]; then
		chmod 0755 "$f"
		echo "[tr3600-pure] chmod 0755 $f"
	else
		echo "ERROR: $f not found"
		exit 1
	fi
done
# Belt and braces: make sure a later re-checkout cannot silently drop the bit.
chmod 0755 "$FANPKG/Makefile" 2>/dev/null || true

# --- LuCI 風扇頁補丁 ---
#   0003：5 秒輪詢不得覆蓋使用者尚未送出的輸入（滑桿彈回）。**保留**。
#
#   ⚠️ 0008「智能季節建議」已於 2026-10-13 **下線**。
#      它讓風扇頁長出 smart 模式 + 三條季節曲線 + 日曆判斷 + 待機基準建議，
#      但那些全是**內核 step_wise 已經在做的事**的第二次實作：DTS 的 trip 點
#      （68/78/88 → 0/50%/78%/100%）本來就會驅動風扇，用戶態每 10 秒再算一遍
#      只是多一層會壞的東西，還把 UI 弄得很難懂。現在風扇只有 auto / manual。
#      補丁留在 retired/0008-…（不再套用）。
#
# 0003 改成硬失敗，不再「打不上去就繼續」——半套的風扇頁比編譯失敗難查得多。
#
# -F 0 / --no-backup-if-mismatch 不是裝飾：
#   預設 fuzz=2，上游只要動到 hunk 邊界那幾行，patch 就會「模糊命中」
#   照樣 rc=0 並留下 .orig。加 -F 0 之後同樣的漂移會 rc=1 直接失敗。
apply_fan_patch() {
	local p="$1" name="$2"
	if [ ! -f "$p" ]; then
		echo "ERROR: $p 不存在"
		exit 1
	fi
	if ! ( cd "$FANPKG" && patch -p1 --dry-run --forward -s -F 0 --no-backup-if-mismatch < "$p" >/dev/null 2>&1 ); then
		echo "ERROR: $name 打不上去（dry-run 失敗）。"
		echo "       風扇套件是 vendor/luci-app-tr3600-fan 的副本，"
		echo "       若上游內容被改動、或順序被顛倒就會這樣。"
		exit 1
	fi
	( cd "$FANPKG" && patch -p1 --forward -s -F 0 --no-backup-if-mismatch < "$p" )
	echo "[tr3600-pure] applied $name"
}

apply_fan_patch "$PATCHDIR/0003-luci-tr3600-fan-keep-pending-input.patch" \
	0003-luci-tr3600-fan-keep-pending-input.patch
# 0008（智能季節建議）已下線，不再套用 —— 見上面註解。
# 想要更簡單的風扇頁就不要把 0008 加回來：它就是複雜度的來源。

# =========================================================
# iStore 應用商店 feed：2026-10-13 移除
#   原本這裡會執行：
#     echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default
#   現在不加這個 feed，config 也一併拿掉 luci-app-store / luci-lib-taskd /
#   luci-lib-xterm / xz-utils。加了 feed 卻不選套件會多抓一份索引，沒必要。
# =========================================================

# =========================================================
# rootfs overlay（files/）：軟體源鏡像 + sysctl 調校
# =========================================================
# OpenWrt 產出的 /etc/apk/repositories.d/distfeeds.list 預設指向
#   https://downloads.openwrt.org/releases/25.12-SNAPSHOT/...
# 這在中國大陸慢到不能用的程度。實測（2026-10-13，同一條 WAN）：
#
#   targets/mediatek/filogic/packages/packages.adb 只有 14 KB
#     downloads.openwrt.org  9.75 s   ≈ 1.5 KB/s   ← 預設值
#     mirror.sjtu.edu.cn     0.32 s                ← 快 ~30 倍
#   整份 apk update（7 個索引、約 1.4 MB）
#     上游 ≈ 70 s 以上  →  SJTU 4 s
#
# 為什麼只有 SJTU：25.12-SNAPSHOT 是「滾動快照」，TUNA / USTC / 阿里雲
# 只鏡像 releases/，對 SNAPSHOT 一律回 404（實測）。SJTU 是目前唯一
# 有完整 25.12-SNAPSHOT 的中國鏡像，7 條索引路徑全部 200。
#
# 同一個 overlay 也交付 /etc/sysctl.d/99-tr3600-pure.conf（fq+BBR、TCP 16 MB、
# conntrack）。為什麼不寫 /etc/sysctl.conf：那是 conffile，被 sysupgrade 保留，
# 舊機上的檔案會蓋掉新映像的版本 → 調校永遠不生效（實測 rmem_max 停在 208 KB）。
#
# 實作方式：OpenWrt 支援在原始碼樹根放一個 files/ 目錄當 rootfs overlay
# （include/image.mk:403 `$(call prepare_rootfs,$(dir),$(TOPDIR)/files)`），
# 它在套件安裝**之後**、postinst **之前**被複製進 rootfs，所以會蓋掉
# base-files 產生的那些檔案。
if [ -d "$REPO_ROOT/files" ]; then
	echo "[tr3600-pure] 安裝 rootfs overlay: $REPO_ROOT/files"
	cp -a "$REPO_ROOT/files" ./files
	if [ ! -f ./files/etc/apk/repositories.d/distfeeds.list ]; then
		echo "ERROR: files/ 裡沒有 distfeeds.list，鏡像不會生效"
		exit 1
	fi
	if ! grep -q "mirror.sjtu.edu.cn" ./files/etc/apk/repositories.d/distfeeds.list; then
		echo "ERROR: distfeeds.list 沒有指向 SJTU 鏡像"
		exit 1
	fi
	echo "[tr3600-pure] distfeeds.list → mirror.sjtu.edu.cn（$(grep -c . ./files/etc/apk/repositories.d/distfeeds.list) 條）"
	if [ ! -f ./files/etc/sysctl.d/99-tr3600-pure.conf ]; then
		echo "ERROR: files/ 裡沒有 etc/sysctl.d/99-tr3600-pure.conf，sysctl 調校不會生效"
		exit 1
	fi
	if ! grep -q "default_qdisc=fq" ./files/etc/sysctl.d/99-tr3600-pure.conf; then
		echo "ERROR: sysctl.d/99-tr3600-pure.conf 裡沒有 default_qdisc=fq"
		exit 1
	fi
	if ! grep -q "rmem_max=16777216" ./files/etc/sysctl.d/99-tr3600-pure.conf; then
		echo "ERROR: sysctl.d/99-tr3600-pure.conf 裡沒有 16 MB 緩衝區設定"
		exit 1
	fi
	echo "[tr3600-pure] sysctl.d/99-tr3600-pure.conf → fq + BBR + 16 MB 緩衝區"
else
	echo "ERROR: $REPO_ROOT/files 不存在，軟體源會退回慢速的 downloads.openwrt.org"
	exit 1
fi

echo "========================================================"
echo " TR3600 build: part1 done (只裝了風扇插件，無 iStore)"
echo "========================================================"
