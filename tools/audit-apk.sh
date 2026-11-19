#!/usr/bin/env bash
# 对单个 APK 做结构级审计：manifest 权限/组件、dex 端点、可疑字符串。
# 依赖: apktool, unzip, python3（可选: jadx）
# 用法: bash audit-apk.sh <base.apk> [输出目录]
set -uo pipefail

APK="${1:?usage: audit-apk.sh <base.apk> [outdir]}"
NAME="$(basename "$APK" .apk)"
OUT="${2:-audit-$NAME}"
mkdir -p "$OUT"

echo "[0] 指纹"
sha256sum "$APK" | tee "$OUT/sha256.txt"
stat -c '%s bytes' "$APK" | tee -a "$OUT/sha256.txt"

echo "[1] 解包"
[ -d "$OUT/decoded" ] || apktool d -f -s -o "$OUT/decoded" "$APK" >/dev/null 2>&1

MAN="$OUT/decoded/AndroidManifest.xml"

echo "[2] manifest 编码判定（这一步不做对，后面全是错的）"
ENCODING=utf-8
if [ -f "$MAN" ] && head -c 64 "$MAN" | tr -d '\0' | grep -q .; then
  if python3 - "$MAN" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
sys.exit(0 if b.count(b'\x00') > len(b) // 4 else 1)
PY
  then ENCODING=utf-16-le; fi
fi
echo "detected: $ENCODING" | tee "$OUT/encoding.txt"

[ "$ENCODING" = utf-16-le ] && { iconv -f UTF-16LE -t UTF-8 "$MAN" > "$OUT/AndroidManifest.utf8.xml"; MAN="$OUT/AndroidManifest.utf8.xml"; }

echo "[3] 权限"
grep -oE 'android:name="android\.permission\.[A-Z_0-9]+"' "$MAN" 2>/dev/null \
  | cut -d'"' -f2 | sort -u > "$OUT/permissions.txt"
grep -oE 'android:name="[a-z]+\.[A-Za-z.]*permission[A-Za-z.]*"' "$MAN" 2>/dev/null \
  | cut -d'"' -f2 | sort -u >> "$OUT/permissions.txt"
sort -u -o "$OUT/permissions.txt" "$OUT/permissions.txt"
grep -qE 'android.permission.INTERNET$' "$OUT/permissions.txt" && echo "INTERNET: yes" || echo "INTERNET: no"
grep -qE 'android.permission.BIND_VPN_SERVICE$' "$OUT/permissions.txt" && echo "BIND_VPN_SERVICE: yes"

echo "[4] 组件与 sharedUserId"
grep -E 'sharedUserId|android:exported="true"|android:authorities' "$MAN" 2>/dev/null | sed 's/^ *//' > "$OUT/components.txt"

echo "[5] dex 端点提取"
unzip -o -q "$APK" 'classes*.dex' -d "$OUT/dex" 2>/dev/null
cat "$OUT"/dex/*.dex 2>/dev/null | strings -n 8 \
  | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' | sort -u > "$OUT/urls.txt"
cat "$OUT"/dex/*.dex 2>/dev/null | strings -n 6 \
  | grep -oE '\b([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+(com|cn|net|org|io|mi|tv)\b' | sort -u > "$OUT/domains.txt"
wc -l < "$OUT/urls.txt" | xargs echo "urls:"
wc -l < "$OUT/domains.txt" | xargs echo "domains:"

echo "[6] 可疑字符串（密钥/密码/上报字段）"
grep -iE 'api[_-]?key|secret|password|token|aes|encrypt|upload|report|iccid|imsi|imei|android_id|oaid' \
  "$OUT/urls.txt" "$OUT/domains.txt" 2>/dev/null | sort -u > "$OUT/interesting.txt" || true

echo "done -> $OUT"
echo "人工复核顺序: encoding.txt -> permissions.txt -> components.txt -> urls.txt -> interesting.txt"
