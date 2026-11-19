#!/usr/bin/env bash
# 采集设备上的预装组件清单：包名、版本、uid、APK 路径、危险权限。
# 用法: bash collect-inventory.sh <serial> [输出目录]
set -uo pipefail

SERIAL="${1:?usage: collect-inventory.sh <serial> [outdir]}"
OUT="${2:-inventory-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

ADB="adb -s $SERIAL"

echo "[1/5] 设备信息"
$ADB shell getprop ro.product.model          >  "$OUT/device.txt"
$ADB shell getprop ro.build.version.release >> "$OUT/device.txt"
$ADB shell getprop ro.build.display.id      >> "$OUT/device.txt"
$ADB shell getprop ro.build.version.security_patch >> "$OUT/device.txt"

echo "[2/5] 包清单（user 0）"
$ADB shell pm list packages --user 0 | sed 's/^package://' | sort > "$OUT/packages.txt"

echo "[3/5] 逐包详情（uid / apk 路径 / 版本）"
: > "$OUT/packages-detail.txt"
while read -r p; do
  [ -z "$p" ] && continue
  # 用 dumpsys 拿 uid、codePath、versionName，一次 shell 往返
  $ADB shell "dumpsys package $p | grep -E 'versionName=|codePath=|userId=|sharedUser=' | sed 's/^ *//'" \
    | sed "s|^|$p\t|" >> "$OUT/packages-detail.txt"
done < "$OUT/packages.txt"

echo "[4/5] 危险权限持有者"
$ADB shell "dumpsys package | grep -E '^\s+(android\.permission\.(INTERNET|RECORD_AUDIO|READ_SMS|SEND_SMS|READ_CONTACTS|READ_CALL_LOG|ACCESS_FINE_LOCATION|BIND_VPN_SERVICE|PACKAGE_USAGE_STATS|GET_TASKS|READ_PRIVILEGED_PHONE_STATE))'" \
  > "$OUT/perm-lines.txt"

echo "[5/5] VPN 与代理状态"
$ADB shell settings get secure always_on_vpn_app > "$OUT/vpn.txt"
$ADB shell settings get global http_proxy        >> "$OUT/vpn.txt"
$ADB shell ip link                               >> "$OUT/vpn.txt"

echo "done -> $OUT"
echo "下一步: 对每个 codePath 的 base.apk 执行 tools/audit-apk.sh"
