# 证据目录

## 内容

| 文件 | 内容 |
|---|---|
| `apk-sha256.txt` | 23 个被审计 APK 的 SHA-256、体积、原始路径（已去掉设备序列号）。凭哈希可核对版本一致性 |
| `pcap/zorn-systemhelper-dm.wo.com.cn.pcap` | **关键证据**：`com.mobiletools.systemhelper` 向 `dm.wo.com.cn:18080` 的明文 HTTP POST，含 1056 / 1040 字节两次请求与服务端 429 回包 |
| `pcap/vangogh-securitycenter-round2.pcap` | 安全中心在设备 B 上的对外连接（安装态） |
| `pcap/vangogh-securitycenter-round3.pcap` | 同上，第二轮，更长窗口 |
| `pcap/cap1.pcap`、`cap2.pcap` | 设备 B 无卡状态下的空白对照：130 秒内零目标流量 |

抓包方式：设备端 `/system/bin/tcpdump -i any -s 0 -w /sdcard/x.pcap`，抓完 `adb pull` 回本地，未做任何重放或注入。

## 脱敏规则

入库前对全部文本与抓包做过如下处理，逐项列明以便复核：

| 数据 | 处理 |
|---|---|
| ICCID（SIM 卡序列号） | 保留前 6 位运营商前缀，其余替换为 `x`（如 `898601xxxxxxxxxxxx`） |
| IMSI / IMEI / MEID | 不出现于文本；抓包文件内实测 0 处命中（报文体为加密 JSON） |
| 手机号 | 不出现；抓包内实测 0 处命中 |
| GPS 坐标 | 保留两位小数位示意，其余替换（如 `116.9xxxx\|36.7xxxx`） |
| 街道级地址 | 区、路、街道替换为占位符，仅保留省市级与行政区划码前缀 |
| WiFi MAC / BSSID | 不出现 |
| 设备序列号 | 替换为 `<K80_SERIAL>` / `<VANGOGH_SERIAL>`，目录名中的序列号已去掉 |
| 账号、Cookie、令牌 | 不采集、不保存 |

复核命令（应返回空）：

```bash
grep -rnE '8986[0-9]{10}|[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}' .
python3 - <<'PY'
import glob, re
for f in glob.glob('pcap/*.pcap'):
    b = open(f, 'rb').read()
    for name, p in {'iccid': rb'8986[0-9]{15,17}', 'imsi': rb'460[0-9]{2}[0-9]{10,12}',
                    'imei': rb'\b[0-9]{15}\b'}.items():
        print(f, name, len(p.findall(b) if hasattr(p, 'findall') else re.findall(p, b)))
PY
```

## 为什么库内没有 APK

累计约 400 MB，且属厂商版权物。需要复现时在自有设备上从 `/data/app` 或 `/vendor/app` 拉取，用 `apk-sha256.txt` 核对是否同一版本；哈希一致则本文所有静态结论可直接对应。

## 看抓包的工具

Wireshark / tshark 均可，明文 HTTP 直接跟流看：

```bash
tshark -r pcap/zorn-systemhelper-dm.wo.com.cn.pcap -Y http.request -T fields \
  -e http.request.method -e http.host -e http.request.uri
```

报文体是 `Content-Type: application/encrypted-json`，内层加密，本仓库只分析外层与头部参数，未尝试解密。
