# 切换到 OpenWrt 官方主线（摆脱 soapmancn 依赖，内核自由）

> 目标：把 TR3600 支持**完全移入本仓库**，构建源从 `soapmancn/openwrt`
> 切到 `openwrt/openwrt`（官方主线，内核 6.18）。完成后不再依赖
> soapmancn 的源码树/DTS，升级内核跟随官方主线（自由）。

## 为什么现在切

- 当前构建源 `soapmancn/openwrt` 分支 `agent/cudy-tr3600-v1-6.12`（内核 6.12）
  是第三方为 TR3600 定制的，**锁死内核版本**（soapmancn 不出新分支就无法升级）。
- OpenWrt **官方主线完整支持 mt7987**（mt7987b.dtsi 存在、filogic 镜像定义、
  内核 6.18），且官方 mt7987.dtsi 与 soapmancn **仅 8 行差异**（下方验证）。
- 我们的 `patches/0008`（USB 稳定性）与官方 USB 节点**逐字节一致**，直接兼容。

## 已验证的兼容性（2026-11-01）

| 检查项 | 结果 |
|--------|------|
| 官方 `mt7987.dtsi` 存在 | ✅ |
| 官方 `mt7987b.dtsi`（TR3600 是 mt7987b 双核） | ✅ |
| 官方 vs soapmancn `mt7987.dtsi` 差异 | 仅 8 行（官方新增 `#pcs-cells`、spi `#address-cells`），不影响 |
| 官方 USB 节点（`ssusb`/`tphyu2port0`/`tphyu3port0`/`u3p-dis-msk`/`usb2-lpm-disable`） | 与 soapmancn **逐字节一致** |
| `patches/0008` 在官方 USB 段兼容 | ✅（引用同一批 label） |
| TR3600 DTS 引用的 label（`spi0`/`eth`/`fan`/`pwm`/`pcie0`/`gmac0`/`gmac1`/`uart0`/`i2p5gbe_led0_pins`/`tphyu*`/`ssusb`） | 官方 `mt7987.dtsi` 全部存在 ✅ |
| 官方 `image/filogic.mk` 有 mt7987 设备（bananapi_bpi-r4-lite，sysupgrade.itb + UBI） | ✅ 作为 TR3600 镜像定义参考 |
| 完整独立 TR3600 DTS（soapmancn 内容 + 0008 修正） | 本目录 `mt7987b-cudy-tr3600-v1.dts`（288 行） |

## 需要的改动（切官方主线时执行）

1. **构建源**：`.github/workflows/build-openwrt-pure.yml`
   - `REPO_URL` → `https://github.com/openwrt/openwrt`
   - `REPO_BRANCH` → `main`（或 `openwrt-24.10`）
2. **TR3600 DTS**：官方无此文件，把本目录 `mt7987b-cudy-tr3600-v1.dts`
   复制到 `target/linux/mediatek/dts/`（作为 patch，或加到 CI 的 copy 步骤）。
3. **镜像定义**：`target/linux/mediatek/image/filogic.mk` 加
   `define Device/cudy_tr3600-v1`（参考 `bananapi_bpi-r4-lite`）：
   - `DEVICE_DTS := mt7987b-cudy-tr3600-v1`
   - `KERNEL_IN_UBI := 1`、`UBOOTENV_IN_UBI := 1`
   - `KERNEL_LOADADDR := 0x40000000`
   - `IMAGES := sysupgrade.itb`、`IMAGE/sysupgrade.itb := append-kernel | fit gzip ... external-with-rootfs | pad-rootfs | append-metadata`
   - TR3600 用 spi-nand + UBI（分区见 DTS `partition@...`）
4. **base-files**：`target/linux/mediatek/filogic/base-files/` 加 TR3600
   - `etc/board.d/02_network`（eth0=wan、eth1=lan、br-lan）
   - `etc/board.d/01_leds`、`etc/diag.sh`（LED 映射）
   - `etc/board.d/*` 的 sysupgrade 支持（UBI）
5. **内核 config**：`target/linux/mediatek/filogic/config-6.18` 确认 mt7987
   相关 + TR3600 特有（fan、WiFi mt76、USB 驱动）。
6. **patch 适配**：`patches/0001-0008` 应用到官方 6.18（DTS 兼容已验证；
   `0002` mt76 backport、`0001/0006/0007` fan 需确认官方 6.18 内核 API）。

## 风险

- 官方 6.18 内核与 soapmancn 6.12 的驱动差异（mt76、mediatek 网络、fan
  PWM）——`0001-0007` 需逐个验证能否干净 apply / 编译。
- TR3600 的 uboot/分区（BL2/FIP/UBI）需与官方 `Build/mt7987-bl2`/`bl31-uboot`
  兼容（bananapi r4 lite 用同款，应该一致）。
- WiFi（mt7996）在官方 6.18 的支持状态需确认（soapmancn 可能有 backport）。

## 建议执行顺序（等当前构建 41257484480 验证 USB 基础后再动）

1. 先拉官方源码，**用官方 + 我们的 DTS 试构建**（不改 CI，本地/临时 workflow）。
2. 确认能构建出 sysupgrade.itb + WiFi/网络驱动就位。
3. 通过后切 `REPO_URL`/`REPO_BRANCH` 到官方，触发正式构建。
4. 保持 `patches/0008`（USB 稳定）+ 完整 DTS 为权威。
