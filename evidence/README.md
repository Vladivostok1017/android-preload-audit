# 证据文件说明

## 一、文件清单

| 文件 | 内容 |
|---|---|
| `apk-sha256.txt` | 23 个被审计 APK 的 SHA-256、体积、原始路径（已去除设备序列号），用于核对版本一致性 |
| `pcap/zorn-systemhelper-dm.wo.com.cn.pcap` | `com.mobiletools.systemhelper` 向 `dm.wo.com.cn:18080` 的明文 HTTP POST，含 1056 与 1040 字节两次请求及服务端 429 回包 |
| `pcap/vangogh-securitycenter-round2.pcap` | 安全中心在设备 B 安装态下的对外连接，第一轮 |
| `pcap/vangogh-securitycenter-round3.pcap` | 同上，第二轮，观测窗口更长 |
| `pcap/cap1.pcap`、`cap2.pcap` | 设备 B 无卡状态下的空白对照，130 秒内无目标流量 |

抓包方式：设备端 `/system/bin/tcpdump -i any -s 0 -w /sdcard/x.pcap`，抓取完成后 `adb pull` 回本地，未执行重放或注入。

## 二、脱敏规则

入库前对文本与抓包执行以下处理，逐项列明以便复核。

| 数据 | 处理 |
|---|---|
| ICCID | 保留前 6 位运营商前缀，其余替换为 `x` |
| IMSI / IMEI / MEID | 文本中不出现；抓包文件实测 0 处命中（报文体为加密 JSON） |
| 手机号 | 文本中不出现；抓包文件实测 0 处命中 |
| GPS 坐标 | 保留两位小数位，其余替换为 `x` |
| 街道级地址 | 区、路、街道替换为占位符，仅保留省市级与行政区划码前缀 |
| WiFi MAC / BSSID | 不出现 |
| 设备序列号 | 替换为 `<K80_SERIAL>` / `<VANGOGH_SERIAL>`，目录名中的序列号已去除 |
| 账号、Cookie、令牌 | 未采集、未保存 |

复核命令，正常情况应返回空：

```bash
grep -rnE '8986[0-9]{10}|([0-9a-f]{2}:){5}[0-9a-f]{2}' .

python3 - <<'PY'
import glob, re
pats = {'iccid': rb'8986[0-9]{15,17}', 'imsi': rb'460[0-9]{2}[0-9]{10,12}', 'imei': rb'\b[0-9]{15}\b'}
for f in glob.glob('pcap/*.pcap'):
    b = open(f, 'rb').read()
    for name, p in pats.items():
        print(f, name, len(re.findall(p, b)))
PY
```

## 三、APK 未入库的原因

23 个 APK 累计约 400 MB，且属厂商版权物。复现时可在自有设备上从 `/data/app` 或 `/vendor/app` 拉取，以 `apk-sha256.txt` 核对是否为同一版本；哈希一致时，本仓库的静态结论可直接对应。

## 四、抓包读取

Wireshark 或 tshark 均可。明文 HTTP 可直接跟随流查看：

```bash
tshark -r pcap/zorn-systemhelper-dm.wo.com.cn.pcap -Y http.request -T fields \
  -e http.request.method -e http.host -e http.request.uri
```

报文体为 `Content-Type: application/encrypted-json`，内层加密。本仓库仅分析外层与头部参数，未尝试解密。
