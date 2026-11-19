# 预装审计 · Preload Audit

国产手机预装组件的**联网上报与录制行为**审计。两台小米手机实机（HyperOS 3 / Android 16、MIUI 13 / Android 12，均已 root），逐个组件做权限核查、端点提取、反编译、设备端抓包、卸载与恢复验证。

目标不是罗列权限，而是回答四个问题：

1. 这个组件**在什么情况下**会主动对外发数据；
2. 发的是**什么内容**，能不能被看见；
3. 有没有**录制**能力，是持续录还是触发式录；
4. 关掉它之后**系统会不会坏**，能不能恢复。

---

## 一句话结论

被审计的 15 个预装组件中，具备联网上报结构的有 6 个，**真正抓到完整报文的只有 1 个**——运营商定制服务 `com.mobiletools.systemhelper`，开机 4 分钟后以**明文 HTTP** 向 `dm.wo.com.cn:18080` 发出 SIM 卡 ICCID、街道级定位、应用列表等 40 余项信息，报文体内层加密、外层明文。

「系统会录屏录音」这个说法成立，但主体不是安全中心，而是 `com.miui.guardprovider`（系统安全组件）：它**不常驻录制**，只在通话中按语音/视频两种场景各录一小段，用于 AI 反诈判定后上传云端比对。

---

## 结论速览

| 组件 | 包名 | 能外传 | 实测外传 | 采集范围 | 风险 |
|---|---|---|---|---|---|
| 手机管家 / 安全中心 | `com.miui.securitycenter` | 是 | 未观测到 | 短信、通话记录、联系人、麦克风、OAID、本地敏感词检测、日志导出 | 高 |
| 系统安全组件 | `com.miui.guardprovider` | 是 | 未观测到 | 应用清单、设备 ID、通话音频、屏幕与视频帧 | 高 |
| SystemHelper（运营商） | `com.mobiletools.systemhelper` | 是 | **抓到完整报文** | SIM ICCID、精确定位与街道地址、应用列表、信号、WiFi | 高 |
| 安全组件（插件） | `com.miui.securityadd` | 是，含 VpnService | 未观测到 | 短信收发、摄像头、高德定位采集、热更新 | 高 |
| AutoRegistration（电信） | `com.qualcomm.qti.autoregistration` | 是 | 未触发 | IMEI、MEID、IMSI、ICCID、WiFi MAC、系统指纹 | 中高 |
| RegService（移动） | `com.miui.dmregservice` | 是 | 未观测到 | 基站、SIM 卡、电池、蓝牙、WiFi 列表、屏幕快照开关 | 中高 |
| 小米自注册（联通/广电） | `com.xiaomi.registration` | 是 | 未观测到 | IMEI、ICCID、IMSI、机型、系统版本 | 中 |
| QMS Telemetry | `com.qualcomm.qti.qms.service.telemetry` | 是 | 未观测到 | MCC、MNC、机型、使用统计 | 中 |
| 安全数据上报服务 | `com.xiaomi.security.onetrack` | 间接 | 无网络权限 | 安全类事件，转交 `com.miui.analytics` | 中 |
| Device Info | `com.qti.qualcomm.deviceinfo` | 视版本 | 无 | 本地展示 IMEI / MEID / ICCID | 低 |
| Device Statistics | `com.qualcomm.qti.devicestatisticsservice` | 无 | 无 | 本地统计 | 低 |
| System Helper Service | `com.qualcomm.qti.services.systemhelper` | 无 | 无 | 无网络权限 | 低 |
| Log generator | `com.bsp.catchlog` | 无 | 无 | 本地日志文件 | 低 |

完整字段、权限、端点见 [`data/components.csv`](data/components.csv) 与 [`data/endpoints.csv`](data/endpoints.csv)。

---

## 三个可以直接用的结果

### 1. 抓到的那一次上传

```
POST /register?ver=5.0&model=24117RK2CC&manuf=Xiaomi&sign=... HTTP/1.1
Host: dm.wo.com.cn:18080
Content-Type: application/encrypted-json
Content-Length: 1056
```

- 触发条件：开机 +4 分钟，或 SIM 变更、信号/应用变化；
- 明文 HTTP，公网可读报文头，`sign` 参数泄露机型与厂商；
- 上报字段 40+：`IMEI1/2`、`ICCID1/2`、`IMSI1/2`、`TAC/CID/PCI`、`BSSID/RSSI/LinkSpeed`、`VolteEnabled/5GEnabled/VoNREnable`、`Esim`、`AppInfo` 等；
- 原始报文：[`evidence/pcap/zorn-systemhelper-dm.wo.com.cn.pcap`](evidence/pcap/)（已剔除 ICCID、IMSI、IMEI、GPS）。

### 2. 录制的真实触发条件

| 场景 | 录什么 |
|---|---|
| 普通语音通话 | 只录声音 |
| 视频通话 | 录屏幕 + 声音 |
| 不在通话中 / 开关关闭 / 权限被收回 / 未知指令 | 不录，服务自行停止 |

三个前提缺一不可：「AI 通话防诈」开关打开、麦克风或录屏已授权、当前确实在通话。录制期间是**前台服务，通知栏有常驻通知**，权限弹窗可以点「拒绝」。上传的是判定用的短片段 `clip.mp4`，不是完整通话录像。

### 3. 卸载与一键恢复

全部采用 `pm uninstall -k --user 0`：只对当前用户卸载，**不动系统分区 APK**，数据保留，`cmd package install-existing --user 0` 原样恢复。

```powershell
# 恢复单台设备上被卸载的全部组件（自动跳过本机不存在的包）
powershell -ExecutionPolicy Bypass -File .\tools\restore-security-packages.ps1 -Serial <设备序列号>
```

详见 [`docs/05-卸载与恢复.md`](docs/05-卸载与恢复.md)。

---

## 仓库结构

```
.
├── README.md                     本文件：结论与导览
├── docs/
│   ├── 00-方法与证据等级.md        怎么做的、证据怎么定级、边界在哪
│   ├── 01-基础审计.md             章一~十一：对象、方法、风险表、逐组件、抓包、加固建议
│   ├── 02-逆向与行为结论.md        章十二~十四：反编译结果、代码级问题清单、行为模型
│   ├── 03-敏感词表提取.md          章十五：本地敏感词表的格式、解密链路、受阻原因
│   ├── 04-运营商与安全中心补审计.md 章十六~十八：RegService、安全中心定向逆向、AI 防诈录制
│   └── 05-卸载与恢复.md           处置记录与恢复方法
├── data/
│   ├── components.csv            组件总表：版本、SHA-256、权限、采集范围、风险、处置
│   ├── endpoints.csv             有据可查的外传端点
│   └── uninstalled.csv           两台设备的卸载明细
├── tools/
│   ├── restore-security-packages.ps1  一键恢复
│   ├── collect-inventory.sh      在设备上采集包清单、权限、端点
│   └── audit-apk.sh              对单个 APK 做 manifest 解析与端点提取
└── evidence/
    ├── README.md                 证据说明与脱敏规则
    ├── apk-sha256.txt            被审计 APK 的 SHA-256 与体积（不含 APK 本体）
    └── pcap/                     设备端抓包原始文件
```

APK 本体不入库（累计约 400 MB，且属厂商版权物）。凭 `evidence/apk-sha256.txt` 里的哈希可以在自己机器上核对到同一版本。

---

## 证据等级

全文结论按三档标注，读者可以据此判断可信度：

| 标记 | 含义 |
|---|---|
| 【实测】 | 在设备上实际观察到：抓到的报文、`dumpsys` 输出、执行过的命令回显 |
| 【静态】 | 从 APK 反编译／manifest／字符串中读到的结构与代码，未经运行验证 |
| 【推断】 | 由前两者推出的行为判断，未取到直接证据 |

只写了【静态】的地方，不代表行为一定发生；写了【实测】的地方，有可复现的命令和原始文件。

---

## 复现路径

需要：一台已 root 的 Android 设备、`adb`、`apktool`、`jadx`（可选）、设备端 `tcpdump`。

```bash
adb shell pm list packages -3 > packages.txt          # 第三方与预装分布
bash tools/collect-inventory.sh <序列号>               # 采集权限与端点
bash tools/audit-apk.sh base.apk                       # 单包解析
adb shell su -c "tcpdump -i any -s 0 -w /sdcard/cap.pcap"   # 抓包
```

完整流程与踩过的坑见 [`docs/00-方法与证据等级.md`](docs/00-方法与证据等级.md) 与 [`docs/01-基础审计.md`](docs/01-基础审计.md) 第二、六节。

---

## 尚未完成

诚实标注，避免过度解读：

- `securitycenter` 反编译出 12674 个类，实际逐类读过 3 个；`securityadd` 16510 个类，只读了模型与 SDK 列表；`guardprovider` 5596 个类，只读了 AI 防诈子集。
- 本地敏感词表（`securitycenter` 的 `SensitiveWordDetectProvider`）已解出白名单与解密链路，词表本体未取到，原因与后续路径写在 [`docs/03-敏感词表提取.md`](docs/03-敏感词表提取.md)。
- 「究竟是哪个组件发出 AI 防诈的开始录制指令」未追到具体调用方，只能由命令值（1=语音、2=视频）反推场景。
- 无任何组件持有全量流量采集实现；唯一持有 `BIND_VPN_SERVICE` 的 `securityadd` 在两台设备上都未启用过 VPN 通道。

---

## 免责

- 所有设备均为作者本人所有，操作前已备份、操作后可回滚；
- 报告中不含任何人的 ICCID、IMSI、IMEI、手机号、精确坐标与住址，抓包文件已按 [`evidence/README.md`](evidence/README.md) 的规则剔除；
- 厂商名称、包名、端点均为客观事实描述，用于安全研究与用户知情，不构成对任何主体的指控；
- 卸载系统组件有风险，照做前请确认自己能恢复。仓库内脚本只做 `--user 0` 卸载与反向恢复，不做分区改写。

---

## 命名

仓库名 `android-preload-audit`，中文名「预装审计」。范围不限于小米，其它厂商的预装组件审计可以按同样结构并入 `docs/` 与 `data/`。

## 许可

[GPL-3.0](LICENSE)。文档、数据表、脚本、证据文件统一采用同一许可：可自由使用、修改、再分发，衍生作品需同样以 GPL-3.0 开放。

厂商名称、商标、包名为客观标识，不随本许可授权。
